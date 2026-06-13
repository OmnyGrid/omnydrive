import '../domain/contracts/drive_endpoint.dart';
import '../domain/contracts/drive_hub.dart';
import '../domain/entities/drive.dart';
import '../domain/entities/drive_registration.dart';
import '../domain/entities/endpoint_identity.dart';
import '../domain/entities/mount_info.dart';
import '../domain/entities/sync_result.dart';
import '../domain/entities/sync_state.dart';
import '../domain/enums/access_mode.dart';
import '../domain/enums/mount_type.dart';
import '../domain/enums/provider_type.dart';
import '../domain/enums/sync_status.dart';
import '../domain/repositories/drive_registry.dart';
import '../domain/repositories/mount_registry.dart';
import '../domain/repositories/sync_state_store.dart';
import '../domain/services/capability_negotiator.dart';
import '../domain/services/conflict_detector.dart';
import '../domain/value_objects/capability.dart';
import '../domain/value_objects/drive_id.dart';
import '../domain/value_objects/local_path.dart';
import '../domain/value_objects/mount_id.dart';
import '../domain/value_objects/origin_uri.dart';
import '../domain/value_objects/path_filter.dart';
import '../infrastructure/persistence/in_memory_drive_registry.dart';
import '../infrastructure/persistence/in_memory_mount_registry.dart';
import '../infrastructure/persistence/in_memory_sync_state_store.dart';
import '../shared/errors/domain_exception.dart';
import '../shared/errors/error_codes.dart';
import '../shared/observability/progress.dart';
import '../shared/utils/clock.dart';
import '../shared/utils/id_generator.dart';
import '../domain/entities/sync_plan.dart';
import 'provider_registry.dart';

/// Builds the URL peers should use to fetch a published drive's content.
typedef ServeUrlBuilder = String Function(EndpointIdentity self, Drive drive);

/// In-process [DriveEndpoint]: the device-side orchestration that ties the
/// provider registry, the local mount/sync stores and a [DriveHub] together.
///
/// All transport (HTTP) lives outside this class — it talks to providers and a
/// [DriveHub] through their interfaces, so the same logic drives an in-memory
/// test, a single-process demo, or a networked deployment.
class LocalDriveEndpoint implements DriveEndpoint {
  @override
  final EndpointIdentity identity;

  final DriveHub hub;
  final ProviderRegistry providers;

  /// Drives this endpoint has published (so a content server can serve them).
  final DriveRegistry published;
  final MountRegistry mounts;
  final SyncStateStore syncStates;

  final IdGenerator _ids;
  final Clock _clock;
  final CapabilityNegotiator _negotiator;
  final ConflictDetector _detector;
  final ServeUrlBuilder _serveUrl;

  LocalDriveEndpoint({
    required this.identity,
    required this.hub,
    ProviderRegistry? providers,
    DriveRegistry? published,
    MountRegistry? mounts,
    SyncStateStore? syncStates,
    IdGenerator? idGenerator,
    Clock? clock,
    CapabilityNegotiator negotiator = const CapabilityNegotiator(),
    ConflictDetector detector = const ConflictDetector(),
    ServeUrlBuilder? serveUrl,
  }) : providers = providers ?? ProviderRegistry.local(endpoint: identity.id),
       published = published ?? InMemoryDriveRegistry(),
       mounts = mounts ?? InMemoryMountRegistry(),
       syncStates = syncStates ?? InMemorySyncStateStore(),
       _ids = idGenerator ?? RandomIdGenerator(),
       _clock = clock ?? SystemClock(),
       _negotiator = negotiator,
       _detector = detector,
       _serveUrl = serveUrl ?? _defaultServeUrl;

  static String _defaultServeUrl(EndpointIdentity self, Drive drive) {
    final base = self.baseUrl.endsWith('/')
        ? self.baseUrl.substring(0, self.baseUrl.length - 1)
        : self.baseUrl;
    return '$base/drives/${drive.id.value}';
  }

  // --- Publishing -----------------------------------------------------------

  @override
  Future<Drive> publishDirectory({
    required String path,
    String? name,
    bool readOnly = false,
    PathFilter? filter,
  }) => _publish(
    origin: OriginUri(path),
    provider: ProviderType.directory,
    name: name,
    readOnly: readOnly,
    filter: filter,
  );

  @override
  Future<Drive> publishGit({
    required String url,
    String? name,
    bool bare = false,
    bool readOnly = false,
  }) => _publish(
    origin: OriginUri(url),
    provider: ProviderType.git,
    name: name,
    readOnly: readOnly,
  );

  Future<Drive> _publish({
    required OriginUri origin,
    required ProviderType provider,
    required String? name,
    required bool readOnly,
    PathFilter? filter,
  }) async {
    final accessMode = readOnly ? AccessMode.readOnly : AccessMode.readWrite;
    final described = await providers
        .forType(provider)
        .describe(origin, accessMode: accessMode, filter: filter);
    final drive = name == null ? described : _rename(described, name);

    // Git drives are fetched directly from their URL; directory drives are
    // streamed from this endpoint's content server.
    final serveUrl = provider == ProviderType.git
        ? drive.originUri.value
        : _serveUrl(identity, drive);

    final registration = DriveRegistration(
      drive: drive,
      servingEndpoint: identity.id,
      serveUrl: serveUrl,
      registeredAt: _clock.now(),
    );
    await published.save(registration);
    await hub.registerDrive(registration);
    return drive;
  }

  Drive _rename(Drive drive, String name) => Drive(
    id: DriveId.scoped(endpoint: identity.id, name: name),
    name: name,
    provider: drive.provider,
    originEndpoint: drive.originEndpoint,
    originUri: drive.originUri,
    accessMode: drive.accessMode,
    capabilities: drive.capabilities,
    filter: drive.filter,
    createdAt: drive.createdAt,
  );

  // --- Cloning --------------------------------------------------------------

  @override
  Future<MountInfo> cloneDrive({
    required String driveId,
    required String dest,
    bool readOnly = false,
  }) async {
    final id = DriveId(driveId);
    final registration = await hub.getDrive(id);
    final route = await hub.routeSync(id, requester: identity.id);

    final accessMode = _grantAccess(registration, readOnly: readOnly);
    final cloneDrive = _retarget(
      registration.drive,
      origin: OriginUri(route.serveUrl),
      accessMode: accessMode,
    );

    final mounted = await providers
        .forType(cloneDrive.provider)
        .materialize(
          drive: cloneDrive,
          dest: LocalPath(dest),
          mountType: MountType.mirror,
        );

    final mountId = MountId(_ids.next('mount'));
    final info = _assignId(mounted.info, mountId);
    await mounts.save(info);
    await syncStates.save(mountId, info.syncState);
    return info;
  }

  /// Resolves the access mode a clone is actually granted: never wider than what
  /// the drive supports, and downgraded to read-only when write is not allowed.
  AccessMode _grantAccess(DriveRegistration reg, {required bool readOnly}) {
    if (readOnly || reg.drive.accessMode.isReadOnly) return AccessMode.readOnly;
    final granted = _negotiator.negotiate(
      supported: reg.drive.capabilities.toSet(),
      requested: AccessMode.readWrite,
    );
    return granted.has(Capability.write)
        ? AccessMode.readWrite
        : AccessMode.readOnly;
  }

  // --- Synchronizing --------------------------------------------------------

  @override
  Future<SyncResult> syncMount(
    String mountId, {
    ProgressReporter? progress,
  }) async {
    final mid = MountId(mountId);
    final info = await mounts.findById(mid);
    if (info == null) {
      throw NotFoundException(
        code: ErrorCodes.mountNotFound,
        message: 'Mount "$mountId" not found',
      );
    }
    final state = await syncStates.load(mid) ?? info.syncState;

    final registration = await hub.getDrive(info.driveId);
    final route = await hub.routeSync(info.driveId, requester: identity.id);
    final syncDrive = _retarget(
      registration.drive,
      origin: OriginUri(route.serveUrl),
      accessMode: info.accessMode,
    );
    final provider = providers.forType(syncDrive.provider);
    final synchronizer = provider.synchronizer(syncDrive);
    final baseline = state.baselineRef;

    // Decide direction from where each side sits relative to the baseline,
    // using the provider's own notion of a reference so the logic is identical
    // for directory (manifest hash) and git (commit sha) drives.
    final localRef = await provider.currentRef(
      OriginUri(info.localPath.value),
      filter: syncDrive.filter,
    );
    final originRef = await provider.currentRef(
      syncDrive.originUri,
      filter: syncDrive.filter,
    );
    final localChanged = localRef != baseline;
    final originChanged = originRef != baseline;

    if (!localChanged && !originChanged) {
      final clean = state.copyWith(
        status: SyncStatus.clean,
        currentRef: localRef,
        lastSyncedAt: _clock.now(),
        clearError: true,
      );
      await syncStates.save(mid, clean);
      await mounts.save(info.copyWith(syncState: clean));
      return SyncResult(
        newRef: baseline,
        appliedChanges: 0,
        status: SyncStatus.clean,
      );
    }

    // A read-write mirror with local-only edits publishes them; an unchanged
    // mirror pulls the origin's changes down. Any other combination — the local
    // copy diverged but cannot be pushed (read-only), or both sides moved —
    // would lose work if we pulled (deleting/overwriting local files) or pushed
    // (clobbering the origin), so we refuse and surface a conflict.
    final canPush =
        info.accessMode.isReadWrite && localChanged && !originChanged;
    final direction = canPush ? SyncDirection.push : SyncDirection.pull;

    if (direction == SyncDirection.pull && localChanged) {
      final conflict = _detector.detectForPull(
        driveId: syncDrive.id,
        baseline: baseline,
        local: localRef,
        origin: originRef,
      );
      if (conflict != null) {
        await syncStates.save(
          mid,
          state.copyWith(
            status: SyncStatus.conflicted,
            lastSyncedAt: _clock.now(),
          ),
        );
        throw ConflictDetectedException(conflict);
      }
    }

    final plan = await synchronizer.plan(
      mount: info,
      baseline: baseline,
      direction: direction,
    );

    final SyncResult result;
    try {
      result = await synchronizer.apply(
        mount: info,
        plan: plan,
        baseline: baseline,
        progress: progress,
      );
    } on ConflictDetectedException {
      await syncStates.save(
        mid,
        state.copyWith(
          status: SyncStatus.conflicted,
          lastSyncedAt: _clock.now(),
        ),
      );
      rethrow;
    }

    final newState = SyncState(
      baselineRef: result.newRef,
      currentRef: result.newRef,
      status: SyncStatus.clean,
      lastSyncedAt: _clock.now(),
    );
    await syncStates.save(mid, newState);
    await mounts.save(info.copyWith(syncState: newState));
    return result;
  }

  // --- Helpers --------------------------------------------------------------

  /// Re-points [drive] at a network [origin] under a (possibly narrower)
  /// [accessMode], preserving its identity and capabilities.
  Drive _retarget(
    Drive drive, {
    required OriginUri origin,
    required AccessMode accessMode,
  }) => Drive(
    id: drive.id,
    name: drive.name,
    provider: drive.provider,
    originEndpoint: drive.originEndpoint,
    originUri: origin,
    accessMode: accessMode,
    capabilities: drive.capabilities,
    filter: drive.filter,
    createdAt: drive.createdAt,
  );

  /// Providers materialize mounts with a placeholder id; the endpoint owns id
  /// assignment so ids stay unique within its registry.
  MountInfo _assignId(MountInfo info, MountId id) => MountInfo(
    id: id,
    driveId: info.driveId,
    localPath: info.localPath,
    accessMode: info.accessMode,
    mountType: info.mountType,
    mountedAt: info.mountedAt,
    syncState: info.syncState,
  );
}
