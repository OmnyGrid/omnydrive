import 'dart:io';

import '../../../domain/contracts/content_source.dart';
import '../../../domain/contracts/drive_provider.dart';
import '../../../domain/contracts/mounted_drive.dart';
import '../../../domain/contracts/synchronizer.dart';
import '../../../domain/entities/drive.dart';
import '../../../domain/entities/drive_capabilities.dart';
import '../../../domain/entities/mount_info.dart';
import '../../../domain/entities/sync_state.dart';
import '../../../domain/enums/access_mode.dart';
import '../../../domain/enums/mount_type.dart';
import '../../../domain/enums/provider_type.dart';
import '../../../domain/enums/sync_status.dart';
import '../../../domain/value_objects/drive_id.dart';
import '../../../domain/value_objects/endpoint_id.dart';
import '../../../domain/value_objects/local_path.dart';
import '../../../domain/value_objects/mount_id.dart';
import '../../../domain/value_objects/origin_uri.dart';
import '../../../domain/value_objects/path_filter.dart';
import '../../../domain/value_objects/sync_ref.dart';
import '../../../shared/errors/domain_exception.dart';
import '../../../shared/observability/progress.dart';
import '../../../shared/utils/clock.dart';
import 'directory_mounted_drive.dart';
import 'directory_synchronizer.dart';
import 'local_content_source.dart';

/// Resolves an [OriginUri] (and write intent) to a [ContentSource]. The local
/// resolver handles `dir`/`file` origins; an HTTP resolver is supplied for
/// remote drives served by an endpoint content server.
typedef ContentSourceResolver =
    ContentSource Function(
      OriginUri origin, {
      required bool writable,
      PathFilter? filter,
    });

/// [DriveProvider] for filesystem directories, local or remote.
///
/// The provider is transport-agnostic: it talks to origins through a
/// [ContentSourceResolver], so the same logic serves a local directory or a
/// directory mirrored over HTTP.
class DirectoryProvider implements DriveProvider {
  final EndpointId endpoint;
  final ContentSourceResolver resolveSource;
  final Clock _clock;

  DirectoryProvider({
    required this.endpoint,
    ContentSourceResolver? resolveSource,
    Clock clock = const _ConstSystemClock(),
  }) : resolveSource = resolveSource ?? localDirectoryResolver,
       _clock = clock;

  @override
  ProviderType get type => ProviderType.directory;

  /// Default resolver for local `dir`/`file` origins.
  static ContentSource localDirectoryResolver(
    OriginUri origin, {
    required bool writable,
    PathFilter? filter,
  }) {
    final String path;
    switch (origin.scheme) {
      case OriginUriScheme.dir:
        path = origin.value;
      case OriginUriScheme.file:
        path = Uri.parse(origin.value).toFilePath();
      default:
        throw ProviderException(
          'DirectoryProvider cannot resolve origin "${origin.value}"',
        );
    }
    return LocalContentSource(path, isWritable: writable, filter: filter);
  }

  @override
  Future<Drive> describe(
    OriginUri origin, {
    required AccessMode accessMode,
    PathFilter? filter,
  }) async {
    final name = _nameFrom(origin);
    return Drive(
      id: DriveId.scoped(endpoint: endpoint, name: name),
      name: name,
      provider: ProviderType.directory,
      originEndpoint: endpoint,
      originUri: origin,
      accessMode: accessMode,
      capabilities: DriveCapabilities.forProvider(
        ProviderType.directory,
        accessMode,
      ),
      filter: filter,
      createdAt: _clock.now(),
    );
  }

  @override
  Future<SyncRef> currentRef(OriginUri origin, {PathFilter? filter}) async {
    final source = resolveSource(origin, writable: false, filter: filter);
    return (await source.manifest()).hash();
  }

  @override
  Future<MountedDrive> materialize({
    required Drive drive,
    required LocalPath dest,
    required MountType mountType,
    ProgressReporter? progress,
  }) async {
    final origin = resolveSource(
      drive.originUri,
      writable: false,
      filter: drive.filter,
    );

    if (mountType == MountType.mirror) {
      await Directory(dest.value).create(recursive: true);
      final localWritable = LocalContentSource(dest.value, isWritable: true);
      final manifest = await origin.manifest();
      progress?.report(
        ProgressEvent(
          phase: ProgressPhase.transferring,
          total: manifest.entries.length,
          completed: 0,
          message: 'Mirroring ${manifest.entries.length} file(s)',
        ),
      );
      var done = 0;
      for (final path in manifest.sortedPaths) {
        await localWritable.writeBytes(path, await origin.readBytes(path));
        done++;
        progress?.report(
          ProgressEvent(
            phase: ProgressPhase.transferring,
            total: manifest.entries.length,
            completed: done,
          ),
        );
      }
    }

    progress?.phase(ProgressPhase.done, 'Materialized');
    final localSource = LocalContentSource(
      dest.value,
      isWritable: drive.accessMode.isReadWrite,
    );
    final baselineRef = (await origin.manifest()).hash();
    return DirectoryMountedDrive(
      info: MountInfo(
        id: MountId('pending'),
        driveId: drive.id,
        localPath: dest,
        accessMode: drive.accessMode,
        mountType: mountType,
        mountedAt: _clock.now(),
        syncState: SyncState(
          baselineRef: baselineRef,
          status: SyncStatus.clean,
        ),
      ),
      local: localSource,
      origin: origin,
    );
  }

  @override
  Synchronizer synchronizer(Drive drive) => DirectorySynchronizer(
    drive: drive,
    resolveOrigin: ({required bool writable}) => resolveSource(
      drive.originUri,
      writable: writable,
      filter: drive.filter,
    ),
    resolveLocal: (localPath) =>
        LocalContentSource(localPath, isWritable: true, filter: drive.filter),
  );

  String _nameFrom(OriginUri origin) {
    final raw = origin.value
        .replaceAll(RegExp(r'[\\/]+$'), '')
        .split(RegExp(r'[\\/]'))
        .last;
    return raw.isEmpty ? 'drive' : raw;
  }
}

/// A const-constructible [SystemClock] wrapper so [DirectoryProvider] can have a
/// const default while still using wall-clock time.
class _ConstSystemClock implements Clock {
  const _ConstSystemClock();
  @override
  DateTime now() => DateTime.now().toUtc();
}
