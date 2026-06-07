import 'dart:convert';
import 'dart:io';

/// Writes file contents atomically: data is written to a sibling temp file,
/// flushed, then renamed over the destination. A crash mid-write therefore
/// leaves the previous file intact instead of a truncated one.
///
/// `rename` is atomic on POSIX filesystems when source and destination live on
/// the same filesystem, which is guaranteed here since the temp file is created
/// next to the destination.
class AtomicFile {
  const AtomicFile._();

  /// Atomically writes [bytes] to [path], creating parent directories.
  static Future<void> writeBytes(String path, List<int> bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final tmp = File('$path.${_suffix()}.tmp');
    try {
      final sink = tmp.openWrite();
      sink.add(bytes);
      await sink.flush();
      await sink.close();
      await tmp.rename(path);
    } catch (_) {
      if (await tmp.exists()) {
        await tmp.delete().catchError((_) => tmp);
      }
      rethrow;
    }
  }

  /// Atomically writes [contents] as UTF-8 to [path].
  static Future<void> writeString(String path, String contents) =>
      writeBytes(path, utf8.encode(contents));

  /// Atomically writes [value] encoded as pretty-printed JSON to [path].
  static Future<void> writeJson(String path, Object? value) =>
      writeString(path, const JsonEncoder.withIndent('  ').convert(value));

  /// Reads and decodes the JSON object at [path], or returns null if the file
  /// does not exist.
  static Future<Map<String, dynamic>?> readJson(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static String _suffix() => '${DateTime.now().microsecondsSinceEpoch}.$pid';
}
