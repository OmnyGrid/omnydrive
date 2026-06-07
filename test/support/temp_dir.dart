import 'dart:io';

import 'package:path/path.dart' as p;

/// Creates a unique temporary directory for a test and registers no automatic
/// cleanup; callers should `addTearDown(dir.cleanup)`.
class TempDir {
  final Directory dir;

  TempDir._(this.dir);

  static Future<TempDir> create([String prefix = 'omnydrive_test_']) async {
    final d = await Directory.systemTemp.createTemp(prefix);
    return TempDir._(d);
  }

  String get path => dir.path;

  /// Absolute path to [relative] inside this temp dir.
  String resolve(String relative) => p.join(dir.path, relative);

  /// Writes [contents] to [relative], creating parent directories.
  Future<File> writeFile(String relative, String contents) async {
    final file = File(resolve(relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
    return file;
  }

  Future<void> cleanup() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
