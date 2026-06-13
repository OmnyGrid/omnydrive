import '../entities/file_manifest.dart';
import '../value_objects/content_hash.dart';

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
  ///
  /// When [executable] is true the destination marks the file as executable
  /// (POSIX execute bit); platforms without execute bits ignore it.
  ///
  /// When [onProgress] is supplied it is invoked as the write streams, with the
  /// number of bytes flushed so far and the total to write. For transports that
  /// compress the payload, both figures are the compressed (wire) size, so a
  /// caller can derive a faithful fraction without knowing the encoding.
  Future<void> writeBytes(
    String relativePath,
    List<int> bytes, {
    bool executable = false,
    void Function(int sent, int total)? onProgress,
  });

  /// Deletes the file at [relativePath] if it exists.
  Future<void> delete(String relativePath);

  /// Whether this source permits writes.
  bool get isWritable;

  /// Whether this source can copy an existing file to another path in place,
  /// without re-sending its bytes. May perform a one-time capability probe, so
  /// callers should await and cache the result for the duration of a transfer.
  Future<bool> supportsCopy();

  /// Copies the file at [fromPath] to [toPath] within this source, reusing the
  /// bytes already present — but only after verifying that [fromPath] still
  /// hashes to [expectedHash].
  ///
  /// Returns `true` when the source was verified and copied. Returns `false`
  /// when [fromPath] is missing or its current hash no longer matches
  /// [expectedHash]; the caller must then fall back to a normal byte transfer.
  /// This guards the time-of-check/time-of-use gap between manifest build and
  /// copy execution. Only meaningful when [supportsCopy] resolves `true`.
  ///
  /// When [executable] is true the copied file is marked executable at the
  /// destination, matching a normal [writeBytes].
  Future<bool> copy(
    String fromPath,
    String toPath,
    ContentHash expectedHash, {
    bool executable = false,
  });
}
