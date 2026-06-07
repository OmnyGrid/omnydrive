import '../value_objects/content_hash.dart';

/// A single file recorded in a [FileManifest].
///
/// [mtime] is captured for diagnostics but deliberately excluded from the
/// manifest hash so the directory reference stays content-addressed and
/// reproducible across machines.
class FileManifestEntry {
  /// Forward-slash relative path from the drive root.
  final String path;

  /// File size in bytes.
  final int size;

  /// Content hash of the file bytes.
  final ContentHash hash;

  /// Last modified time, if known. Not part of the manifest hash.
  final DateTime? mtime;

  const FileManifestEntry({
    required this.path,
    required this.size,
    required this.hash,
    this.mtime,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'size': size,
    'hash': hash.value,
    if (mtime != null) 'mtime': mtime!.toIso8601String(),
  };

  factory FileManifestEntry.fromJson(Map<String, dynamic> json) =>
      FileManifestEntry(
        path: json['path'] as String,
        size: (json['size'] as num).toInt(),
        hash: ContentHash.parse(json['hash'] as String),
        mtime: json['mtime'] == null
            ? null
            : DateTime.parse(json['mtime'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is FileManifestEntry &&
      other.path == path &&
      other.size == size &&
      other.hash == hash;

  @override
  int get hashCode => Object.hash(path, size, hash);
}
