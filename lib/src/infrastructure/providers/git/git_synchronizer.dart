import '../../../domain/contracts/synchronizer.dart';
import '../../../domain/entities/drive.dart';
import '../../../domain/entities/mount_info.dart';
import '../../../domain/entities/sync_plan.dart';
import '../../../domain/entities/sync_result.dart';
import '../../../domain/enums/sync_status.dart';
import '../../../domain/services/branch_naming_strategy.dart';
import '../../../domain/services/conflict_detector.dart';
import '../../../domain/services/git_push_policy.dart';
import '../../../domain/value_objects/git_credential.dart';
import '../../../domain/value_objects/origin_uri.dart';
import '../../../domain/value_objects/sync_ref.dart';
import '../../../shared/errors/domain_exception.dart';
import '../../../shared/observability/metrics.dart';
import '../../../shared/observability/progress.dart';
import 'git_cli.dart';

/// Synchronizes a git drive using commit-SHA references.
///
/// A push publishes the checked-out branch. Whether it goes to that branch
/// directly or to a fresh feature branch (via [BranchNamingStrategy]) is decided
/// by the [GitPushPolicy] — protected branches (e.g. `main`/`master` or a
/// mounted branch) get a feature branch so they are never moved by a push.
/// Before publishing, the origin's branch must still point at the baseline SHA,
/// otherwise a [ConflictDetectedException] is raised (a push never force-writes).
class GitSynchronizer implements Synchronizer {
  final Drive drive;
  final GitCli git;
  final BranchNamingStrategy branchNaming;

  /// Decides whether a push targets the checked-out branch or a feature branch.
  final GitPushPolicy pushPolicy;

  /// Credential for the origin remote, or null to use the host's git config.
  final GitCredential? credential;

  final ConflictDetector _detector;

  GitSynchronizer({
    required this.drive,
    required this.git,
    required this.branchNaming,
    this.pushPolicy = const DefaultGitPushPolicy(),
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

    // Push. The origin's copy of the checked-out branch (if any) must still be
    // at the baseline, else the push wouldn't fast-forward — surface a conflict
    // rather than force-writing.
    final branch = await git.currentBranch(path);
    final originSha = await _originBranchSha(branch);
    if (originSha != null) {
      final conflict = _detector.detectForPush(
        driveId: drive.id,
        baseline: baseline,
        origin: SyncRef.git(originSha),
      );
      if (conflict != null) throw ConflictDetectedException(conflict);
    }

    // Include any uncommitted working-tree changes in the push.
    if (await git.hasChanges(path)) {
      await git.addAll(path);
      await git.commit(path, 'OmnyDrive sync');
    }

    // A protected branch is published to a fresh feature branch (so it is never
    // moved by a drive push); any other branch is pushed to directly, creating
    // it on the origin when absent.
    final protected = pushPolicy.isProtected(
      branch: branch,
      onOrigin: originSha != null,
    );
    final String target;
    if (protected) {
      target = branchNaming.nextBranch().value;
      await git.checkoutNewBranch(path, target);
    } else {
      target = branch;
    }
    progress?.phase(ProgressPhase.transferring, 'Pushing $target');
    await git.push(path, target, credential: credential);
    final newSha = await git.revParse(path);

    stopwatch.stop();
    progress?.phase(ProgressPhase.done, 'Pushed $target');
    return SyncResult(
      newRef: SyncRef.git(newSha),
      appliedChanges: plan.changedPaths.isEmpty ? 1 : plan.changedPaths.length,
      status: SyncStatus.clean,
      metrics: SyncMetrics(duration: stopwatch.elapsed),
      publishedBranch: target,
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
