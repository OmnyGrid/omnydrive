import '../../../domain/contracts/synchronizer.dart';
import '../../../domain/entities/drive.dart';
import '../../../domain/entities/mount_info.dart';
import '../../../domain/entities/sync_plan.dart';
import '../../../domain/entities/sync_result.dart';
import '../../../domain/enums/sync_status.dart';
import '../../../domain/services/branch_naming_strategy.dart';
import '../../../domain/services/conflict_detector.dart';
import '../../../domain/value_objects/git_credential.dart';
import '../../../domain/value_objects/origin_uri.dart';
import '../../../domain/value_objects/sync_ref.dart';
import '../../../shared/errors/domain_exception.dart';
import '../../../shared/observability/metrics.dart';
import '../../../shared/observability/progress.dart';
import 'git_cli.dart';

/// Synchronizes a git drive using commit-SHA references.
///
/// Read-write pushes never target a protected branch: a feature branch is
/// created automatically via the [BranchNamingStrategy]. Before publishing, the
/// origin's tracked branch must still point at the baseline SHA, otherwise a
/// [ConflictDetectedException] is raised.
class GitSynchronizer implements Synchronizer {
  final Drive drive;
  final GitCli git;
  final BranchNamingStrategy branchNaming;

  /// Credential for the origin remote, or null to use the host's git config.
  final GitCredential? credential;

  final ConflictDetector _detector;

  GitSynchronizer({
    required this.drive,
    required this.git,
    required this.branchNaming,
    this.credential,
    ConflictDetector detector = const ConflictDetector(),
  }) : _detector = detector;

  @override
  Future<SyncPlan> plan({
    required MountInfo mount,
    required SyncRef baseline,
    required SyncDirection direction,
  }) async {
    final path = mount.localPath.value;
    final branch = await git.currentBranch(path);
    final originSha = await _originBranchSha(branch);
    final localSha = await git.revParse(path);

    if (direction == SyncDirection.push) {
      final changed = await git.changedFiles(
        path,
        from: baseline.value,
        to: localSha,
      );
      return SyncPlan(
        direction: direction,
        baselineRef: baseline,
        targetRef: SyncRef.git(localSha),
        changedPaths: changed,
        requiresConflictResolution:
            originSha != null && originSha != baseline.value,
      );
    }

    return SyncPlan(
      direction: direction,
      baselineRef: baseline,
      targetRef: SyncRef.git(originSha ?? localSha),
      changedPaths: const [],
      requiresConflictResolution: false,
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
    final path = mount.localPath.value;

    if (plan.direction == SyncDirection.pull) {
      final branch = await git.currentBranch(path);
      // A branch that exists only locally (never pushed to the origin) has
      // nothing to pull — treat it as a clean no-op instead of failing on a
      // fetch/merge of a ref the origin doesn't have.
      final originSha = await _originBranchSha(branch);
      if (originSha == null) {
        stopwatch.stop();
        return SyncResult(
          newRef: SyncRef.git(await git.revParse(path)),
          appliedChanges: 0,
          status: SyncStatus.clean,
          metrics: SyncMetrics(duration: stopwatch.elapsed),
        );
      }
      progress?.phase(ProgressPhase.transferring, 'Fetching');
      // Fetch the checked-out branch by name and fast-forward to FETCH_HEAD, so
      // a pull works even when `origin/<branch>` is not a local remote-tracking
      // ref (e.g. a shallow/single-branch clone, or a branch fetched by name).
      await git.fetch(path, branch: branch, credential: credential);
      await git.mergeFastForward(path, 'FETCH_HEAD');
      final newSha = await git.revParse(path);
      stopwatch.stop();
      return SyncResult(
        newRef: SyncRef.git(newSha),
        appliedChanges: plan.changedPaths.length,
        status: SyncStatus.clean,
        metrics: SyncMetrics(duration: stopwatch.elapsed),
      );
    }

    // Push: verify the origin still points at the baseline.
    final baseBranch = await git.currentBranch(path);
    final originSha = await _originBranchSha(baseBranch);
    if (originSha != null) {
      final conflict = _detector.detectForPush(
        driveId: drive.id,
        baseline: baseline,
        origin: SyncRef.git(originSha),
      );
      if (conflict != null) throw ConflictDetectedException(conflict);
    }

    // Always publish to a fresh feature branch, never a protected one.
    final feature = branchNaming.nextBranch();
    progress?.phase(ProgressPhase.transferring, 'Creating ${feature.value}');
    await git.checkoutNewBranch(path, feature.value);
    if (await git.hasChanges(path)) {
      await git.addAll(path);
      await git.commit(path, 'OmnyDrive sync');
    }
    await git.push(path, feature.value, credential: credential);
    final newSha = await git.revParse(path);

    stopwatch.stop();
    progress?.phase(ProgressPhase.done, 'Pushed ${feature.value}');
    return SyncResult(
      newRef: SyncRef.git(newSha),
      appliedChanges: plan.changedPaths.isEmpty ? 1 : plan.changedPaths.length,
      status: SyncStatus.clean,
      metrics: SyncMetrics(duration: stopwatch.elapsed),
      publishedBranch: feature.value,
    );
  }

  Future<String?> _originBranchSha(String branch) async {
    if (drive.originUri.isRemote) {
      return git.lsRemote(
        drive.originUri.value,
        'refs/heads/$branch',
        credential: credential,
      );
    }
    final path = _localOriginPath(drive.originUri);
    return git.branchSha(path, branch);
  }

  static String _localOriginPath(OriginUri origin) =>
      origin.scheme == OriginUriScheme.file
      ? Uri.parse(origin.value).toFilePath()
      : origin.value;
}
