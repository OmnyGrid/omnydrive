/// How two git references have diverged, as reported by
/// `git rev-list --left-right --count base...head`.
class GitDivergence {
  /// Commits on the local side not present on the base.
  final int ahead;

  /// Commits on the base not present locally.
  final int behind;

  final String baseSha;
  final String headSha;

  const GitDivergence({
    required this.ahead,
    required this.behind,
    required this.baseSha,
    required this.headSha,
  });

  /// Both sides moved relative to the merge base.
  bool get isDiverged => ahead > 0 && behind > 0;

  /// The local side can fast-forward the base (no remote-only commits).
  bool get isFastForward => behind == 0;

  Map<String, dynamic> toJson() => {
    'ahead': ahead,
    'behind': behind,
    'baseSha': baseSha,
    'headSha': headSha,
  };
}
