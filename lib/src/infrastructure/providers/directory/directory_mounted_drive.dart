import '../../../domain/contracts/content_source.dart';
import '../../../domain/contracts/mounted_drive.dart';
import '../../../domain/entities/file_manifest.dart';
import '../../../domain/entities/mount_info.dart';
import '../../../domain/entities/sync_plan.dart';
import '../../../domain/services/manifest_differ.dart';
import '../../../domain/value_objects/sync_ref.dart';
import '../../../shared/observability/progress.dart';

/// A directory drive materialized at a local path. Holds the local working-copy
/// source plus the origin source so pulls can be applied.
class DirectoryMountedDrive implements MountedDrive {
  @override
  final MountInfo info;

  final ContentSource local;
  final ContentSource origin;
  final ManifestDiffer _differ;

  DirectoryMountedDrive({
    required this.info,
    required this.local,
    required this.origin,
    ManifestDiffer differ = const ManifestDiffer(),
  }) : _differ = differ;

  @override
  Future<SyncRef> localRef() async => (await local.manifest()).hash();

  @override
  Future<FileManifest> localManifest() => local.manifest();

  @override
  Future<void> applyRemote(SyncPlan plan, {ProgressReporter? progress}) async {
    final base = await local.manifest();
    final target = await origin.manifest();
    final diff = _differ.diff(base, target);

    progress?.report(
      ProgressEvent(
        phase: ProgressPhase.transferring,
        total: diff.allPaths.length,
        completed: 0,
        message: 'Applying ${diff.allPaths.length} change(s)',
      ),
    );

    var done = 0;
    for (final path in [...diff.added, ...diff.modified]) {
      await local.writeBytes(path, await origin.readBytes(path));
      done++;
      progress?.report(
        ProgressEvent(
          phase: ProgressPhase.transferring,
          total: diff.allPaths.length,
          completed: done,
        ),
      );
    }
    for (final path in diff.removed) {
      await local.delete(path);
      done++;
    }
  }
}
