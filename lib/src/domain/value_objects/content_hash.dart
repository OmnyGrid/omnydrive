import '../../shared/errors/domain_exception.dart';

/// A content-addressed hash of a file or blob.
///
/// Defaults to SHA-256, stored lowercase hex. Used as the key for
/// content-addressed blob transfer so already-present blobs can be skipped.
class ContentHash {
  static final RegExp _hex = RegExp(r'^[0-9a-f]+$');

  /// Hash algorithm name (e.g. `sha256`).
  final String algorithm;

  /// Lowercase hex digest.
  final String hex;

  ContentHash({this.algorithm = 'sha256', required String hex})
    : hex = hex.toLowerCase() {
    if (this.hex.isEmpty || !_hex.hasMatch(this.hex)) {
      throw ValidationException('Invalid content hash: "$hex"');
    }
  }

  /// Wire form `<algorithm>:<hex>`.
  String get value => '$algorithm:$hex';

  factory ContentHash.parse(String input) {
    final idx = input.indexOf(':');
    if (idx <= 0) {
      throw ValidationException('Invalid content hash format: "$input"');
    }
    return ContentHash(
      algorithm: input.substring(0, idx),
      hex: input.substring(idx + 1),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ContentHash && other.algorithm == algorithm && other.hex == hex;

  @override
  int get hashCode => Object.hash(algorithm, hex);

  @override
  String toString() => value;
}
