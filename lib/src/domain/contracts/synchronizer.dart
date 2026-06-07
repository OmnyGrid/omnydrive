import '../entities/mount_info.dart';
import '../entities/sync_plan.dart';
import '../entities/sync_result.dart';
import '../value_objects/sync_ref.dart';
import '../../shared/observability/progress.dart';

/// Computes and applies synchronization for a specific provider.
///
/// Implementations encapsulate the provider-specific notion of a reference and
/// of "changed content" (git commits vs directory manifests), but all share the
/// same contract: [apply] must throw [ConflictDetectedException] when the origin
/// has moved away from [baseline] before publishing.
abstract interface class Synchronizer {
  /// Builds a [SyncPlan] describing the work needed to move [mount] in
  /// [direction] from [baseline] to the current target reference.
  Future<SyncPlan> plan({
    required MountInfo mount,
    required SyncRef baseline,
    required SyncDirection direction,
  });

  /// Executes [plan]. For pushes, verifies the origin still points at
  /// [baseline] and throws `ConflictDetectedException` otherwise. Returns the
  /// new reference and applied-change count on success.
  Future<SyncResult> apply({
    required MountInfo mount,
    required SyncPlan plan,
    required SyncRef baseline,
    ProgressReporter? progress,
  });
}
