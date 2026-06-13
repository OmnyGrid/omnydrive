import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../domain/entities/file_manifest.dart';
import '../../../domain/entities/file_manifest_entry.dart';
import '../../../domain/value_objects/content_hash.dart';
import '../../../domain/value_objects/path_filter.dart';
import 'manifest_cache.dart';

/// Walks a directory tree and produces a content-addressed [FileManifest].
///
/// Internal directories (`.omnydrive`, `.git`, `.dart_tool`) are skipped by
/// default so the drive's own metadata and any embedded git repository don't
/// pollute the manifest.
///
/// To avoid re-reading and re-hashing every file on each build, a stat-cache is
/// kept under `<root>/.omnydrive/[ManifestCache.fileName]`. A file is hashed
/// from disk only when its `(size, mtime)` differ from the cached fingerprint
/// (or the racy-clean guard fires); otherwise the cached hash is reused. The
/// resulting manifest — and therefore its [FileManifest.hash] — is identical to
/// a full rebuild, so the directory reference stays reproducible.
class ManifestBuilder {
  /// Directory names skipped during the walk.
  final Set<String> ignoredDirs;

  /// Optional sub-path filter. When set, files whose relative path does not
  /// survive the filter are excluded from the manifest (and never hashed).
  final PathFilter? filter;

  /// When false, every file is read and hashed and no cache is consulted or
  /// written. Used by tests to compare cached vs. non-cached builds.
  final bool useCache;

  const ManifestBuilder({
    this.ignoredDirs = const {'.omnydrive', '.git', '.dart_tool'},
    this.filter,
    this.useCache = true,
  });

  /// Builds the manifest for the tree rooted at [rootPath]. Returns an empty
  /// manifest when the directory does not exist.
  Future<FileManifest> build(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return FileManifest.empty;

    final oldCache = useCache
        ? await ManifestCache.load(rootPath)
        : ManifestCache.empty;
    // Captured before the walk: any file modified during or after this instant
    // is treated as untrustworthy next time (racy-clean guard).
    final builtAt = DateTime.now().toUtc();

    final entries = <String, FileManifestEntry>{};
    final newCacheEntries = <String, CachedEntry>{};

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: rootPath);
      if (_isIgnored(relative)) continue;
      final posixPath = p.split(relative).join('/');
      if (filter != null && !filter!.matches(posixPath)) continue;

      final stat = await entity.stat();
      final mtime = stat.modified.toUtc();
      // Any POSIX execute bit (user/group/other, 0o111). Zero on platforms
      // without execute bits, so non-POSIX builds simply record `false`.
      final executable = (stat.mode & 0x49) != 0;

      final cached = oldCache.lookup(posixPath);
      final ContentHash hash;
      final int size;
      if (cached != null &&
          cached.size == stat.size &&
          cached.mtime == mtime &&
          mtime.isBefore(oldCache.builtAt)) {
        // Fast path: fingerprint unchanged and safely older than the cache —
        // reuse the recorded hash without reading the file. `stat.size` equals
        // the byte length for a regular file, so the manifest line is identical
        // to a full read.
        hash = cached.hash;
        size = stat.size;
      } else {
        final bytes = await entity.readAsBytes();
        hash = ContentHash(hex: sha256.convert(bytes).toString());
        size = bytes.length;
      }

      entries[posixPath] = FileManifestEntry(
        path: posixPath,
        size: size,
        hash: hash,
        mtime: mtime,
        executable: executable,
      );
      newCacheEntries[posixPath] = CachedEntry(
        size: size,
        mtime: mtime,
        hash: hash,
      );
    }

    if (useCache) {
      // Rebuilt from the live walk, so additions appear and deletions drop out
      // automatically. Best-effort write.
      await ManifestCache(
        builtAt: builtAt,
        entries: newCacheEntries,
      ).save(rootPath);
    }

    return FileManifest(entries);
  }

  bool _isIgnored(String relative) {
    final segments = p.split(relative);
    return segments.any(ignoredDirs.contains);
  }
}
