import '../value_objects/branch_name.dart';

/// Decides the branch name automation pushes to, so changes never land directly
/// on a protected branch.
abstract interface class BranchNamingStrategy {
  /// Produces a branch name for a change. [label] is an optional caller hint
  /// (e.g. a job or update id).
  BranchName nextBranch({String? label});
}

/// Default strategy producing names like `omnydrive/update-<n>` or, when a
/// label is supplied, `omnydrive/<label>`.
class DefaultBranchNamingStrategy implements BranchNamingStrategy {
  final String prefix;
  int _counter = 0;

  DefaultBranchNamingStrategy({this.prefix = 'omnydrive'});

  @override
  BranchName nextBranch({String? label}) {
    if (label != null && label.trim().isNotEmpty) {
      return BranchName('$prefix/${_slug(label)}');
    }
    _counter++;
    return BranchName('$prefix/update-$_counter');
  }

  static String _slug(String input) => input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
