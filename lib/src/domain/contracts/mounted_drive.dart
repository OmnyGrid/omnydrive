import '../entities/file_manifest.dart';
import '../entities/mount_info.dart';
import '../entities/sync_plan.dart';
import '../value_objects/sync_ref.dart';
import '../../shared/observability/progress.dart';

/// A drive that has been materialized at a local path. Provides access to the
/// local working copy's state and the ability to apply remote changes.
abstract interface class MountedDrive {
  /// Metadata about this mount.
  MountInfo get info;

  /// Computes the reference the local working copy currently represents.
  Future<SyncRef> localRef();

  /// Builds the manifest of the local working copy (directory drives).
  Future<FileManifest> localManifest();

  /// Applies a pull [plan] to the local working copy.
  Future<void> applyRemote(SyncPlan plan, {ProgressReporter? progress});
}
