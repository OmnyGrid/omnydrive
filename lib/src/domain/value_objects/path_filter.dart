import '../../shared/errors/domain_exception.dart';

/// A sub-path filter applied to a directory drive's [FileManifest].
///
/// Patterns are gitignore-style globs matched against each file's forward-slash
/// relative path:
///
/// - `*` matches any run of characters except `/`.
/// - `**` matches any run of characters, including `/`.
/// - `?` matches a single character except `/`.
/// - A trailing `/` (e.g. `build/`) — or a bare token with no `/` and no
///   wildcard (e.g. `build`) — matches the directory itself and everything
///   under it (expanded to `build/**`).
/// - A leading `/` anchors to the root and is otherwise insignificant.
///
/// Semantics, evaluated per path:
///
/// 1. if any [exclude] pattern matches, the path is **dropped** (exclude wins);
/// 2. otherwise, when [include] is non-empty, the path is kept only if at least
///    one include pattern matches (include acts as a whitelist);
/// 3. otherwise the path is kept.
///
/// An [empty] filter (no patterns) keeps everything.
class PathFilter {
  /// Whitelist globs. When empty, every non-excluded path is kept.
  final List<String> include;

  /// Blacklist globs. A match drops the path regardless of [include].
  final List<String> exclude;

  final List<RegExp> _includeRe;
  final List<RegExp> _excludeRe;

  PathFilter._(this.include, this.exclude, this._includeRe, this._excludeRe);

  /// Builds a filter from raw [include]/[exclude] glob patterns.
  factory PathFilter({
    List<String> include = const [],
    List<String> exclude = const [],
  }) {
    final inc = List<String>.unmodifiable(include);
    final exc = List<String>.unmodifiable(exclude);
    return PathFilter._(
      inc,
      exc,
      [for (final pattern in inc) _compile(pattern)],
      [for (final pattern in exc) _compile(pattern)],
    );
  }

  /// A filter that keeps every path.
  static final PathFilter empty = PathFilter();

  /// Whether this filter has no patterns and therefore keeps everything.
  bool get isEmpty => include.isEmpty && exclude.isEmpty;

  /// Whether [relativePath] (forward-slash, relative to the drive root) survives
  /// the filter.
  bool matches(String relativePath) {
    final path = _normalizePath(relativePath);
    for (final re in _excludeRe) {
      if (re.hasMatch(path)) return false;
    }
    if (_includeRe.isEmpty) return true;
    for (final re in _includeRe) {
      if (re.hasMatch(path)) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    if (include.isNotEmpty) 'include': include,
    if (exclude.isNotEmpty) 'exclude': exclude,
  };

  factory PathFilter.fromJson(Map<String, dynamic> json) => PathFilter(
    include: (json['include'] as List?)?.cast<String>() ?? const [],
    exclude: (json['exclude'] as List?)?.cast<String>() ?? const [],
  );

  /// Normalizes a path to the form patterns are matched against: forward slashes
  /// and no leading/trailing `/`.
  static String _normalizePath(String path) =>
      path.replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');

  /// Translates a glob [pattern] into an anchored [RegExp].
  static RegExp _compile(String pattern) {
    final trimmed = pattern.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Filter pattern must not be empty');
    }

    // A directory pattern (`build/` or a bare `build`) matches the subtree.
    var glob = trimmed.replaceAll(RegExp(r'^/+|/+$'), '');
    final isDirToken =
        trimmed.endsWith('/') ||
        (!trimmed.contains('/') &&
            !trimmed.contains('*') &&
            !trimmed.contains('?'));
    if (isDirToken) glob = '$glob/**';

    final buffer = StringBuffer('^');
    for (var i = 0; i < glob.length; i++) {
      final char = glob[i];
      switch (char) {
        case '*':
          if (i + 1 < glob.length && glob[i + 1] == '*') {
            if (i + 2 < glob.length && glob[i + 2] == '/') {
              // `**/` matches zero or more leading/intermediate directories, so
              // `**/foo` also matches `foo` at the root (gitignore semantics).
              buffer.write('(?:.*/)?');
              i += 2; // consume the second star and the slash
            } else {
              buffer.write('.*');
              i++; // consume the second star
            }
          } else {
            buffer.write('[^/]*');
          }
        case '?':
          buffer.write('[^/]');
        default:
          // Escape any regex metacharacter so the rest is matched literally.
          if (RegExp(r'[.\\+(){}\[\]^$|]').hasMatch(char)) buffer.write('\\');
          buffer.write(char);
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }

  @override
  bool operator ==(Object other) =>
      other is PathFilter &&
      _listEquals(other.include, include) &&
      _listEquals(other.exclude, exclude);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(include), Object.hashAll(exclude));

  @override
  String toString() => 'PathFilter(include: $include, exclude: $exclude)';

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
