/// Decides whether a git-drive push publishes the checked-out branch directly,
/// or routes it through a fresh feature branch so the branch is never moved by a
/// drive push.
///
/// Injected into `GitProvider`; the git synchronizer consults it on every push.
/// This lets an embedder express which branches are protected (e.g. `main`,
/// `master`, or the branch a drive was mounted to track) while branches the node
/// created — or branches not yet on the origin — are pushed to directly.
abstract class GitPushPolicy {
  /// Whether [branch] (the node's checked-out branch) must be **protected** —
  /// pushed via a fresh feature branch rather than updated directly. [onOrigin]
  /// indicates whether the branch already exists on the origin.
  bool isProtected({required String branch, required bool onOrigin});
}

/// Protects a fixed set of branch names (defaulting to `main`/`master`); every
/// other branch is pushed to directly.
///
/// Embedders can protect more branches by passing [protectedBranches] — e.g.
/// omnyshell adds the branch a drive was mounted to track, so a drive push never
/// moves the mounted branch or the conventional default branches, while a
/// working branch the node created is pushed to as-is.
class DefaultGitPushPolicy implements GitPushPolicy {
  /// The protected branch names.
  final Set<String> protectedBranches;

  const DefaultGitPushPolicy({
    this.protectedBranches = const {'main', 'master'},
  });

  @override
  bool isProtected({required String branch, required bool onOrigin}) =>
      protectedBranches.contains(branch);
}
