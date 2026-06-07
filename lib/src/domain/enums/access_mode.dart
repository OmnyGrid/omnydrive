import '../../shared/errors/domain_exception.dart';

/// Whether a mounted drive may modify (and synchronize back to) its origin.
enum AccessMode {
  /// Local modifications are never synchronized to the origin; no push/commit.
  readOnly,

  /// Local modifications are tracked and may be synchronized back, subject to
  /// conflict detection.
  readWrite;

  bool get isReadOnly => this == AccessMode.readOnly;
  bool get isReadWrite => this == AccessMode.readWrite;

  String get wireValue => name;

  static AccessMode fromWire(String value) => values.firstWhere(
    (e) => e.wireValue == value,
    orElse: () => throw ValidationException('Unknown access mode: $value'),
  );
}
