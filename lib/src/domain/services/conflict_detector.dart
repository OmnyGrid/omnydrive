import '../entities/conflict.dart';
import '../enums/conflict_kind.dart';
import '../value_objects/drive_id.dart';
import '../value_objects/sync_ref.dart';

/// Pure conflict-detection logic shared by all synchronizers. No I/O.
///
/// The core rule of OmnyDrive's synchronization model: a push may only proceed
/// when the origin still points at the baseline the caller synchronized
/// against. If the origin moved, publishing would clobber that work, so a
/// [Conflict] is produced and the caller must resolve it explicitly.
class ConflictDetector {
  const ConflictDetector();

  /// Returns a [Conflict] if pushing local changes against [origin] would be
  /// unsafe, or null when it is safe to publish.
  ///
  /// [baseline] is the reference the local copy was synced from; [origin] is
  /// the reference the source points at right now.
  Conflict? detectForPush({
    required DriveId driveId,
    required SyncRef baseline,
    required SyncRef origin,
  }) {
    if (origin == baseline) return null;
    return Conflict(
      kind: ConflictKind.refMoved,
      driveId: driveId,
      expectedRef: baseline,
      actualRef: origin,
      message:
          'Source moved from ${baseline.value} to ${origin.value}; '
          'resolve the conflict before publishing.',
    );
  }

  /// Returns a [Conflict] when a pull would be destructive, or null when it is
  /// safe to apply the origin onto the local copy.
  ///
  /// A pull overwrites/deletes local files to match the origin. That is only
  /// safe while the local copy still matches [baseline]; once it has diverged
  /// ([local] != [baseline]) the pull would silently discard local work, so a
  /// conflict is raised instead. When the origin also moved this is a genuine
  /// two-sided divergence; otherwise the local copy simply cannot be published
  /// (e.g. a read-only mount).
  Conflict? detectForPull({
    required DriveId driveId,
    required SyncRef baseline,
    required SyncRef local,
    required SyncRef origin,
  }) {
    if (local == baseline) return null;
    final originMoved = origin != baseline;
    return Conflict(
      kind: originMoved
          ? ConflictKind.contentDivergence
          : ConflictKind.localDivergence,
      driveId: driveId,
      expectedRef: baseline,
      actualRef: local,
      message: originMoved
          ? 'Both the local copy (${local.value}) and the origin '
                '(${origin.value}) changed since ${baseline.value}; resolve the '
                'conflict before syncing.'
          : 'The local copy changed to ${local.value} since ${baseline.value} '
                'but the mount cannot publish it; refusing to discard local '
                'changes by pulling.',
    );
  }

  /// Builds a protected-branch conflict for a git push that targeted a branch
  /// it must not write to directly.
  Conflict protectedBranch({
    required DriveId driveId,
    required SyncRef baseline,
    required String branch,
  }) => Conflict(
    kind: ConflictKind.protectedBranch,
    driveId: driveId,
    expectedRef: baseline,
    message:
        'Refusing to push directly to protected branch "$branch"; '
        'a feature branch is created automatically instead.',
  );
}
