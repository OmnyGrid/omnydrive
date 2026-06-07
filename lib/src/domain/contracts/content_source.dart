import '../entities/file_manifest.dart';

/// Low-level, transport-agnostic read/write access to a directory drive's
/// content. Backed locally by `dart:io` and remotely by an endpoint's HTTP
/// content API, so the directory provider works the same in both cases.
abstract interface class ContentSource {
  /// Builds the current [FileManifest] for the source tree.
  Future<FileManifest> manifest();

  /// Reads the bytes of the file at [relativePath].
  Future<List<int>> readBytes(String relativePath);

  /// Writes [bytes] to [relativePath], creating parents as needed.
  /// Throws if the source is read-only.
  Future<void> writeBytes(String relativePath, List<int> bytes);

  /// Deletes the file at [relativePath] if it exists.
  Future<void> delete(String relativePath);

  /// Whether this source permits writes.
  bool get isWritable;
}
