import '../../shared/errors/domain_exception.dart';

/// A git branch name with validation and protected-branch awareness.
class BranchName {
  /// Branch names that must never be pushed to directly by automation.
  static const defaultProtected = {'main', 'master', 'develop'};

  static final RegExp _invalid = RegExp(r'[\s~^:?*\[\\]');

  final String value;

  BranchName(String input) : value = input.trim() {
    if (value.isEmpty) {
      throw const ValidationException('Branch name is required');
    }
    if (_invalid.hasMatch(value) ||
        value.startsWith('/') ||
        value.endsWith('/') ||
        value.contains('..') ||
        value.endsWith('.lock')) {
      throw ValidationException('Invalid branch name: "$value"');
    }
  }

  /// The conventional default branch.
  static BranchName get main => BranchName('main');

  /// Whether this branch is protected against direct automated pushes.
  bool isProtected({Set<String> protected = defaultProtected}) =>
      protected.contains(value);

  @override
  bool operator ==(Object other) => other is BranchName && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
