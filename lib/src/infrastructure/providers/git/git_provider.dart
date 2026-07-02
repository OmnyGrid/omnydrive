import '../../../domain/contracts/drive_provider.dart';
import '../../../domain/contracts/git_credential_resolver.dart';
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
import '../../../domain/services/branch_naming_strategy.dart';
import '../../../domain/services/git_push_policy.dart';
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
import 'git_cli.dart';
import 'git_mounted_drive.dart';
import 'git_synchronizer.dart';

/// [DriveProvider] for Git repositories — regular or bare, local path or remote
/// URL. All git interaction is delegated to [GitCli].
class GitProvider implements DriveProvider {
  final EndpointId endpoint;
  final GitCli git;
  final BranchNamingStrategy branchNaming;

  /// Decides whether a push targets the checked-out branch or a fresh feature
  /// branch. Defaults to protecting `main`/`master`.
  final GitPushPolicy pushPolicy;

  /// Resolves the credential (if any) for a remote origin. Null means git falls
  /// back to the host's own configuration.
  final GitCredentialResolver? credentials;

  final Clock _clock;

  GitProvider({
    required this.endpoint,
    this.git = const GitCli(),
    this.credentials,
    BranchNamingStrategy? branchNaming,
    GitPushPolicy? pushPolicy,
    Clock? clock,
  }) : branchNaming = branchNaming ?? DefaultBranchNamingStrategy(),
       pushPolicy = pushPolicy ?? const DefaultGitPushPolicy(),
       _clock = clock ?? SystemClock();

  @override
  ProviderType get type => ProviderType.git;

  @override
  Future<Drive> describe(
    OriginUri origin, {
    required AccessMode accessMode,
    PathFilter? filter, // sub-path filtering is a directory-drive feature
  }) async {
    final name = _nameFrom(origin);
    return Drive(
      id: DriveId.scoped(endpoint: endpoint, name: name),
      name: name,
      provider: ProviderType.git,
      originEndpoint: endpoint,
      originUri: origin,
      accessMode: accessMode,
      capabilities: DriveCapabilities.forProvider(ProviderType.git, accessMode),
      createdAt: _clock.now(),
    );
  }

  @override
  Future<SyncRef> currentRef(OriginUri origin, {PathFilter? filter}) async {
    final sha = await git.lsRemote(
      _url(origin),
      'HEAD',
      credential: credentials?.resolve(origin),
    );
    if (sha == null) {
      throw ProviderException('Could not resolve HEAD of ${origin.value}');
    }
    return SyncRef.git(sha);
  }

  @override
  Future<MountedDrive> materialize({
    required Drive drive,
    required LocalPath dest,
    required MountType mountType,
    ProgressReporter? progress,
  }) async {
    final credential = credentials?.resolve(drive.originUri);
    progress?.phase(ProgressPhase.transferring, 'Cloning ${drive.name}');
    await git.clone(
      _url(drive.originUri),
      dest.value,
      // Read-only mounts only need a shallow snapshot (CI workflow).
      depth: drive.accessMode.isReadOnly ? 1 : null,
      credential: credential,
    );
    final headSha = await git.revParse(dest.value);
    progress?.phase(ProgressPhase.done, 'Cloned');

    return GitMountedDrive(
      git: git,
      credential: credential,
      info: MountInfo(
        id: MountId('pending'),
        driveId: drive.id,
        localPath: dest,
        accessMode: drive.accessMode,
        mountType: mountType,
        mountedAt: _clock.now(),
        syncState: SyncState(
          baselineRef: SyncRef.git(headSha),
          status: SyncStatus.clean,
        ),
      ),
    );
  }

  @override
  Synchronizer synchronizer(Drive drive) => GitSynchronizer(
    drive: drive,
    git: git,
    branchNaming: branchNaming,
    pushPolicy: pushPolicy,
    credential: credentials?.resolve(drive.originUri),
  );

  String _url(OriginUri origin) => origin.scheme == OriginUriScheme.file
      ? Uri.parse(origin.value).toFilePath()
      : origin.value;

  String _nameFrom(OriginUri origin) {
    var raw = origin.value;
    if (raw.endsWith('/')) raw = raw.substring(0, raw.length - 1);
    if (raw.endsWith('.git')) raw = raw.substring(0, raw.length - 4);
    final seg = raw.split(RegExp(r'[\\/:]')).last;
    return seg.isEmpty ? 'repo' : seg;
  }
}
