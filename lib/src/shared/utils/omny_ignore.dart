import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The conventional file name, placed at a directory's root, that lists
/// gitignore-style glob patterns to exclude from a published drive by default.
///
/// It is consulted only when `omnydrive publish <dir>` is run without explicit
/// `--include`/`--exclude` flags; the patterns become the drive's default
/// `exclude` set (see [PathFilter]). Explicit flags override the file entirely.
const String omnyIgnoreFileName = '.omnyignore';

/// Parses the textual [content] of a [omnyIgnoreFileName] file into a list of
/// `exclude` glob patterns suitable for `PathFilter(exclude: ...)`.
///
/// - Each line is trimmed; blank lines and `#` comments are skipped.
/// - The original order is preserved.
/// - Negation lines (`!pattern`) are **not supported** and are skipped:
///   `PathFilter` semantics are "exclude wins over include" with no rule
///   ordering, so a re-include cannot override an exclude.
List<String> parseOmnyIgnore(String content) {
  final patterns = <String>[];
  for (final raw in const LineSplitter().convert(content)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) continue;
    patterns.add(line);
  }
  return patterns;
}

/// Reads the ignore file named [fileName] (default [omnyIgnoreFileName]) under
/// [directoryPath] and returns its parsed exclude patterns, or an empty list
/// when the file is absent or has no usable patterns.
///
/// Best-effort: an unreadable file yields an empty list rather than throwing.
Future<List<String>> loadOmnyIgnore(
  String directoryPath, {
  String fileName = omnyIgnoreFileName,
}) async {
  final file = File(p.join(directoryPath, fileName));
  if (!await file.exists()) return const [];
  try {
    return parseOmnyIgnore(await file.readAsString());
  } on IOException {
    return const [];
  }
}
