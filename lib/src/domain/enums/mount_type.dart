import '../../shared/errors/domain_exception.dart';

/// Relationship between a mount and its source drive.
enum MountType {
  /// A direct representation of the source (the original local directory or
  /// git repository). Operations act on the source in place.
  origin,

  /// A local synchronized copy (a directory mirror or a git clone) that retains
  /// metadata linking it back to the origin.
  mirror;

  String get wireValue => name;

  static MountType fromWire(String value) => values.firstWhere(
    (e) => e.wireValue == value,
    orElse: () => throw ValidationException('Unknown mount type: $value'),
  );
}
