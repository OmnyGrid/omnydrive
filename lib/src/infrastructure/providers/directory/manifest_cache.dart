import 'package:path/path.dart' as p;

import '../../../domain/value_objects/content_hash.dart';
import '../../../shared/utils/atomic_file.dart';

/// One file's stat fingerprint plus its previously computed content hash.
///
/// The fingerprint ([size] + [mtime]) lets [ManifestBuilder] decide — with a
/// cheap `stat()` and no file read — whether a file is unchanged and its
/// [hash] can be reused.
class CachedEntry {
  /// File size in bytes at the time the hash was computed.
  final int size;

  /// Last-modified time (UTC) at the time the hash was computed.
  final DateTime mtime;

  /// The content hash recorded for this fingerprint.
  final ContentHash hash;

  const CachedEntry({
    required this.size,
    required this.mtime,
    required this.hash,
  });

  Map<String, dynamic> toJson() => {
    'size': size,
    'mtime': mtime.toIso8601String(),
    'hash': hash.value,
  };

  static CachedEntry? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      final size = raw['size'];
      final mtime = raw['mtime'];
      final hash = raw['hash'];
      if (size is! num || mtime is! String || hash is! String) return null;
      return CachedEntry(
        size: size.toInt(),
        mtime: DateTime.parse(mtime).toUtc(),
        hash: ContentHash.parse(hash),
      );
    } catch (_) {
      return null;
    }
  }
}

/// A persisted stat-cache mapping posix relative path → [CachedEntry].
///
/// The cache is a pure accelerator for [ManifestBuilder]: a missing, stale, or
/// corrupt cache only costs extra file reads, never a wrong manifest, because
/// every reused hash is gated on the file's current stat fingerprint. All load
/// and save errors are therefore swallowed.
class ManifestCache {
  /// Bumped whenever the cache schema (or the manifest line format it feeds)
  /// changes, so an old cache is discarded instead of misread.
  static const int currentVersion = 1;

  /// File name stored under the drive's ignored `.omnydrive` directory.
  static const String fileName = 'manifest-cache.json';

  /// When this cache snapshot was built (UTC), captured before its walk began.
  ///
  /// Files whose mtime is not strictly older than [builtAt] are re-hashed
  /// rather than trusted (git's "racy clean" rule): such a file may have been
  /// modified within the filesystem's mtime resolution of the build, so its
  /// fingerprint cannot be trusted to have moved.
  final DateTime builtAt;

  /// Cached entries keyed by posix relative path.
  final Map<String, CachedEntry> entries;

  const ManifestCache({required this.builtAt, required this.entries});

  /// An empty cache (epoch [builtAt] so nothing is ever trusted from it).
  static final empty = ManifestCache(
    builtAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    entries: const {},
  );

  /// The cache file path for a directory [rootPath].
  static String pathFor(String rootPath) =>
      p.join(rootPath, '.omnydrive', fileName);

  CachedEntry? lookup(String posixPath) => entries[posixPath];

  /// Loads the cache for [rootPath]. Returns [empty] on any
  /// missing/empty/malformed/version-mismatched file — never throws.
  static Future<ManifestCache> load(String rootPath) async {
    try {
      final json = await AtomicFile.readJson(pathFor(rootPath));
      if (json == null) return empty;
      if (json['version'] != currentVersion) return empty;
      final builtAtRaw = json['builtAt'];
      final builtAt = builtAtRaw is String
          ? DateTime.parse(builtAtRaw).toUtc()
          : empty.builtAt;
      final rawEntries = json['entries'];
      final entries = <String, CachedEntry>{};
      if (rawEntries is Map) {
        rawEntries.forEach((key, value) {
          if (key is String) {
            final entry = CachedEntry.tryFromJson(value);
            if (entry != null) entries[key] = entry;
          }
        });
      }
      return ManifestCache(builtAt: builtAt, entries: entries);
    } catch (_) {
      return empty;
    }
  }

  /// Persists this cache for [rootPath]. Best-effort: any error (e.g. a
  /// read-only filesystem) is swallowed so a build never fails on a cache
  /// write.
  Future<void> save(String rootPath) async {
    try {
      await AtomicFile.writeJson(pathFor(rootPath), {
        'version': currentVersion,
        'builtAt': builtAt.toIso8601String(),
        'entries': {for (final e in entries.entries) e.key: e.value.toJson()},
      });
    } catch (_) {
      // Cache is advisory; ignore write failures.
    }
  }
}
