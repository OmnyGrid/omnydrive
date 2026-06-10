import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../domain/entities/file_manifest.dart';
import '../../../domain/entities/file_manifest_entry.dart';
import '../../../domain/value_objects/content_hash.dart';

/// Walks a directory tree and produces a content-addressed [FileManifest].
///
/// Internal directories (`.omnydrive`, `.git`, `.dart_tool`) are skipped by
/// default so the drive's own metadata and any embedded git repository don't
/// pollute the manifest.
class ManifestBuilder {
  /// Directory names skipped during the walk.
  final Set<String> ignoredDirs;

  const ManifestBuilder({
    this.ignoredDirs = const {'.omnydrive', '.git', '.dart_tool'},
  });

  /// Builds the manifest for the tree rooted at [rootPath]. Returns an empty
  /// manifest when the directory does not exist.
  Future<FileManifest> build(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return FileManifest.empty;

    final entries = <String, FileManifestEntry>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: rootPath);
      if (_isIgnored(relative)) continue;

      final bytes = await entity.readAsBytes();
      final digest = sha256.convert(bytes);
      final stat = await entity.stat();
      final posixPath = p.split(relative).join('/');
      entries[posixPath] = FileManifestEntry(
        path: posixPath,
        size: bytes.length,
        hash: ContentHash(hex: digest.toString()),
        mtime: stat.modified.toUtc(),
      );
    }
    return FileManifest(entries);
  }

  bool _isIgnored(String relative) {
    final segments = p.split(relative);
    return segments.any(ignoredDirs.contains);
  }
}
