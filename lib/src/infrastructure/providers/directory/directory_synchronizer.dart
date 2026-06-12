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
import '../../../domain/value_objects/content_hash.dart';
import '../../../domain/value_objects/sync_ref.dart';
import '../../../shared/errors/domain_exception.dart';
import '../../../shared/observability/metrics.dart';
import '../../../shared/observability/progress.dart';
import '../../../shared/utils/concurrent.dart';

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

  /// Maximum number of file transfers kept in flight at once during [apply].
  final int transferConcurrency;

  DirectorySynchronizer({
    required this.drive,
    required this.resolveOrigin,
    required this.resolveLocal,
    ManifestDiffer differ = const ManifestDiffer(),
    ConflictDetector detector = const ConflictDetector(),
    this.transferConcurrency = 8,
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

    int bytes;
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
      bytes = await _transfer(
        diff: diff,
        source: local,
        dest: origin,
        sourceManifest: localManifest,
        destManifest: originManifest,
        progress: progress,
      );
      applied = diff.allPaths.length;
      newRef = (await origin.manifest()).hash();
    } else {
      final diff = _differ.diff(localManifest, originManifest);
      bytes = await _transfer(
        diff: diff,
        source: origin,
        dest: local,
        sourceManifest: originManifest,
        destManifest: localManifest,
        progress: progress,
      );
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

  /// Copies [diff] from [source] to [dest], transferring up to
  /// [transferConcurrency] files at once instead of one at a time. Returns the
  /// total number of bytes written. Writes (added + modified) run first, then
  /// deletes; per-file progress is reported as each operation settles.
  ///
  /// When the destination supports an in-place [ContentSource.copy], writes
  /// whose content hash is already present at the destination — or is about to
  /// be written this run — are deduplicated: the bytes are sent once and the
  /// destination copies them to the remaining paths. [sourceManifest] supplies
  /// each write path's expected hash; [destManifest] is the destination's
  /// existing content. Only the bytes actually sent over the wire are counted,
  /// so the return value reflects the saved traffic.
  Future<int> _transfer({
    required ManifestDiff diff,
    required ContentSource source,
    required ContentSource dest,
    required FileManifest sourceManifest,
    required FileManifest destManifest,
    ProgressReporter? progress,
  }) async {
    final total = diff.allPaths.length;
    var done = 0;
    var bytes = 0;
    progress?.report(
      ProgressEvent(
        phase: ProgressPhase.transferring,
        total: total,
        completed: 0,
      ),
    );

    // Counters below are mutated from concurrent worker callbacks; this is safe
    // because Dart's event loop runs them on a single thread without preemption.
    void reportDone(String path) {
      done++;
      progress?.report(
        ProgressEvent(
          phase: ProgressPhase.transferring,
          total: total,
          completed: done,
          bytes: bytes,
          message: path,
        ),
      );
    }

    final writes = [...diff.added, ...diff.modified];

    // Split writes into byte transfers and in-place copies. A copy reuses
    // content already at the destination — either a pre-existing file or the
    // first file of the same content hash sent this run (its representative).
    final transfers = <String>[];
    final copies = <({String from, String to, ContentHash hash})>[];

    if (dest.isWritable && await dest.supportsCopy()) {
      final existingByHash = <String, String>{};
      for (final path in destManifest.sortedPaths) {
        existingByHash.putIfAbsent(
          destManifest.entries[path]!.hash.value,
          () => path,
        );
      }
      final repByHash = <String, String>{};
      for (final path in writes) {
        final hash = sourceManifest.entries[path]!.hash;
        final reuse = existingByHash[hash.value] ?? repByHash[hash.value];
        if (reuse != null) {
          copies.add((from: reuse, to: path, hash: hash));
        } else {
          repByHash[hash.value] = path;
          transfers.add(path);
        }
      }
    } else {
      transfers.addAll(writes);
    }

    // Phase 1: send the representative byte payloads. These must all settle
    // before phase 2 so every copy's source is guaranteed present at the dest.
    await forEachConcurrent(transfers, (path) async {
      final data = await source.readBytes(path);
      await dest.writeBytes(path, data);
      bytes += data.length;
      reportDone(path);
    }, concurrency: transferConcurrency);

    // Phase 2: reuse content already at the dest. A false result means the
    // source drifted or vanished, so fall back to a full transfer for that path.
    await forEachConcurrent(copies, (op) async {
      final copied = await dest.copy(op.from, op.to, op.hash);
      if (!copied) {
        final data = await source.readBytes(op.to);
        await dest.writeBytes(op.to, data);
        bytes += data.length;
      }
      reportDone(op.to);
    }, concurrency: transferConcurrency);

    await forEachConcurrent(diff.removed, (path) async {
      await dest.delete(path);
      reportDone(path);
    }, concurrency: transferConcurrency);

    return bytes;
  }
}
