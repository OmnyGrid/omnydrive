import '../../../domain/contracts/mounted_drive.dart';
import '../../../domain/entities/file_manifest.dart';
import '../../../domain/entities/mount_info.dart';
import '../../../domain/entities/sync_plan.dart';
import '../../../domain/value_objects/sync_ref.dart';
import '../../../shared/observability/progress.dart';
import '../directory/manifest_builder.dart';
import 'git_cli.dart';

/// A git drive cloned to a local path.
class GitMountedDrive implements MountedDrive {
  @override
  final MountInfo info;

  final GitCli git;
  final ManifestBuilder _builder;

  GitMountedDrive({
    required this.info,
    required this.git,
    ManifestBuilder builder = const ManifestBuilder(),
  }) : _builder = builder;

  String get _path => info.localPath.value;

  @override
  Future<SyncRef> localRef() async => SyncRef.git(await git.revParse(_path));

  @override
  Future<FileManifest> localManifest() => _builder.build(_path);

  @override
  Future<void> applyRemote(SyncPlan plan, {ProgressReporter? progress}) async {
    progress?.phase(ProgressPhase.transferring, 'Fetching');
    await git.fetch(_path);
    final branch = await git.currentBranch(_path);
    await git.mergeFastForward(_path, 'origin/$branch');
    progress?.phase(ProgressPhase.done, 'Pulled');
  }
}
