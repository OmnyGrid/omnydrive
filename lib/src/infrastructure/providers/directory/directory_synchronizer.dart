import '../../../domain/contracts/content_source.dart';
import '../../../domain/contracts/synchronizer.dart';
import '../../../domain/entities/drive.dart';
import '../../../domain/entities/file_manifest.dart';
import '../../../domain/entities/mount_info.dart';
import '../../../domain/entities/sync_plan.dart';
import '../../../domain/entities/sync_result.dart';
import '../../../domain/enums/sync_status.dart';
import '../../../domain/services/conflict_detector.dart';
import '../../../domain/services/manifest_differ.dart';
import '../../../domain/value_objects/sync_ref.dart';
import '../../../shared/errors/domain_exception.dart';
import '../../../shared/observability/metrics.dart';
import '../../../shared/observability/progress.dart';

/// Synchronizes a directory drive using manifest-hash references.
///
/// The baseline is the manifest hash the local copy was reconciled against. A
/// push only proceeds when the origin still hashes to that baseline; otherwise
/// a [ConflictDetectedException] is thrown.
class DirectorySynchronizer implements Synchronizer {
  final Drive drive;

  /// Resolves the origin content source. [writable] is true for pushes.
  final ContentSource Function({required bool writable}) resolveOrigin;

  /// Builds the local working-copy source for a mount path.
  final ContentSource Function(String localPath) resolveLocal;

  final ManifestDiffer _differ;
  final ConflictDetector _detector;

  DirectorySynchronizer({
    required this.drive,
    required this.resolveOrigin,
    required this.resolveLocal,
    ManifestDiffer differ = const ManifestDiffer(),
    ConflictDetector detector = const ConflictDetector(),
  }) : _differ = differ,
       _detector = detector;

  @override
  Future<SyncPlan> plan({
    required MountInfo mount,
    required SyncRef baseline,
    required SyncDirection direction,
  }) async {
    final local = resolveLocal(mount.localPath.value);
    final origin = resolveOrigin(writable: false);
    final localManifest = await local.manifest();
    final originManifest = await origin.manifest();

    final FileManifest base;
    final FileManifest target;
    final SyncRef targetRef;
    if (direction == SyncDirection.pull) {
      base = localManifest;
      target = originManifest;
      targetRef = originManifest.hash();
    } else {
      base = originManifest;
      target = localManifest;
      targetRef = localManifest.hash();
    }

    final diff = _differ.diff(base, target);
    final requiresResolution =
        direction == SyncDirection.push && originManifest.hash() != baseline;

    return SyncPlan(
      direction: direction,
      baselineRef: baseline,
      targetRef: targetRef,
      changedPaths: diff.allPaths,
      requiresConflictResolution: requiresResolution,
    );
  }

  @override
  Future<SyncResult> apply({
    required MountInfo mount,
    required SyncPlan plan,
    required SyncRef baseline,
    ProgressReporter? progress,
  }) async {
    final stopwatch = Stopwatch()..start();
    final local = resolveLocal(mount.localPath.value);
    final origin = resolveOrigin(
      writable: plan.direction == SyncDirection.push,
    );

    final localManifest = await local.manifest();
    final originManifest = await origin.manifest();

    var bytes = 0;
    int applied;
    SyncRef newRef;

    if (plan.direction == SyncDirection.push) {
      // The heart of the conflict model: refuse to publish if the origin moved.
      final conflict = _detector.detectForPush(
        driveId: drive.id,
        baseline: baseline,
        origin: originManifest.hash(),
      );
      if (conflict != null) throw ConflictDetectedException(conflict);

      final diff = _differ.diff(originManifest, localManifest);
      progress?.report(
        ProgressEvent(
          phase: ProgressPhase.transferring,
          total: diff.allPaths.length,
          completed: 0,
        ),
      );
      for (final path in [...diff.added, ...diff.modified]) {
        final data = await local.readBytes(path);
        await origin.writeBytes(path, data);
        bytes += data.length;
      }
      for (final path in diff.removed) {
        await origin.delete(path);
      }
      applied = diff.allPaths.length;
      newRef = (await origin.manifest()).hash();
    } else {
      final diff = _differ.diff(localManifest, originManifest);
      progress?.report(
        ProgressEvent(
          phase: ProgressPhase.transferring,
          total: diff.allPaths.length,
          completed: 0,
        ),
      );
      for (final path in [...diff.added, ...diff.modified]) {
        final data = await origin.readBytes(path);
        await local.writeBytes(path, data);
        bytes += data.length;
      }
      for (final path in diff.removed) {
        await local.delete(path);
      }
      applied = diff.allPaths.length;
      newRef = (await local.manifest()).hash();
    }

    stopwatch.stop();
    progress?.phase(ProgressPhase.done, 'Synchronized');
    return SyncResult(
      newRef: newRef,
      appliedChanges: applied,
      status: SyncStatus.clean,
      metrics: SyncMetrics(
        duration: stopwatch.elapsed,
        filesChanged: applied,
        bytesTransferred: bytes,
      ),
    );
  }
}
