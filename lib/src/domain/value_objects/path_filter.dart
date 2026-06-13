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
/// - A pattern with a leading or internal `/` (e.g. `/build`, `a/b`) is
///   **anchored** to the drive root; a slash-less pattern (e.g. `*.tmp`,
///   `build`) matches at **any depth** below the root (gitignore semantics).
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

  /// Rewrites raw [patterns] (e.g. from a nested `.omnyignore`) so they apply
  /// relative to the subtree [prefix] (forward-slash, relative to the drive
  /// root). Anchored patterns bind to `<prefix>/…`; slash-less patterns keep
  /// their match-at-any-depth meaning *within* the subtree (`<prefix>/**/…`),
  /// mirroring how git applies a nested `.gitignore`.
  static List<String> scope(String prefix, List<String> patterns) {
    final base = prefix
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^/+|/+$'), '');
    return [
      for (final pattern in patterns)
        _isAnchored(pattern)
            ? '$base/${pattern.replaceAll(RegExp(r'^/+'), '')}'
            : '$base/**/$pattern',
    ];
  }

  /// Normalizes a path to the form patterns are matched against: forward slashes
  /// and no leading/trailing `/`.
  static String _normalizePath(String path) =>
      path.replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');

  /// Whether [pattern] is anchored to the drive root, i.e. it carries a leading
  /// or internal `/` (a lone trailing `/` is a directory marker, not anchoring).
  /// Slash-less patterns are unanchored and match at any depth.
  static bool _isAnchored(String pattern) {
    final trimmed = pattern.trim();
    final core = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    return core.contains('/');
  }

  /// Translates a glob [pattern] into an anchored [RegExp].
  static RegExp _compile(String pattern) {
    final trimmed = pattern.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Filter pattern must not be empty');
    }

    // A slash-less pattern is not bound to the root: it matches at any depth.
    final anchored = _isAnchored(trimmed);

    // A directory pattern (`build/` or a bare `build`) matches the subtree.
    var glob = trimmed.replaceAll(RegExp(r'^/+|/+$'), '');
    final isDirToken =
        trimmed.endsWith('/') ||
        (!trimmed.contains('/') &&
            !trimmed.contains('*') &&
            !trimmed.contains('?'));
    if (isDirToken) glob = '$glob/**';

    final buffer = StringBuffer('^');
    // Unanchored patterns may start at any directory level below the root.
    if (!anchored) buffer.write('(?:.*/)?');
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
