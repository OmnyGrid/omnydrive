import 'package:path/path.dart' as p;

import '../../shared/errors/domain_exception.dart';

/// An absolute, normalized local filesystem path.
class LocalPath {
  final String value;

  LocalPath._(this.value);

  /// Creates a [LocalPath], requiring [input] to be absolute. The stored value
  /// is normalized (`.`/`..` collapsed, redundant separators removed).
  factory LocalPath(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Local path is required');
    }
    if (!p.isAbsolute(trimmed)) {
      throw ValidationException('Local path must be absolute: "$input"');
    }
    return LocalPath._(p.normalize(trimmed));
  }

  /// Joins this path with [parts], returning a new [LocalPath].
  LocalPath join(String part, [String? part2, String? part3]) =>
      LocalPath(p.join(value, part, part2, part3));

  /// The final path segment.
  String get basename => p.basename(value);

  @override
  bool operator ==(Object other) => other is LocalPath && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
