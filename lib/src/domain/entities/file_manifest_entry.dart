import '../value_objects/content_hash.dart';

/// A single file recorded in a [FileManifest].
///
/// [mtime] is captured for diagnostics but deliberately excluded from the
/// manifest hash so the directory reference stays content-addressed and
/// reproducible across machines.
///
/// [executable] records whether the file carries a POSIX execute bit. Like
/// [mtime] it is kept out of [hashCode]/[operator ==] (and the manifest hash) so
/// the directory reference stays purely content-addressed; the synchronizer's
/// differ compares it explicitly so an exec-bit change still syncs.
class FileManifestEntry {
  /// Forward-slash relative path from the drive root.
  final String path;

  /// File size in bytes.
  final int size;

  /// Content hash of the file bytes.
  final ContentHash hash;

  /// Last modified time, if known. Not part of the manifest hash.
  final DateTime? mtime;

  /// Whether the file is executable (any POSIX execute bit set). Always `false`
  /// on platforms without execute bits. Not part of the manifest hash.
  final bool executable;

  const FileManifestEntry({
    required this.path,
    required this.size,
    required this.hash,
    this.mtime,
    this.executable = false,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'size': size,
    'hash': hash.value,
    if (mtime != null) 'mtime': mtime!.toIso8601String(),
    if (executable) 'executable': true,
  };

  factory FileManifestEntry.fromJson(Map<String, dynamic> json) =>
      FileManifestEntry(
        path: json['path'] as String,
        size: (json['size'] as num).toInt(),
        hash: ContentHash.parse(json['hash'] as String),
        mtime: json['mtime'] == null
            ? null
            : DateTime.parse(json['mtime'] as String),
        executable: json['executable'] == true,
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
