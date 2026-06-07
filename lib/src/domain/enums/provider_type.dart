import '../../shared/errors/domain_exception.dart';

/// The kind of backing store a drive is published from.
enum ProviderType {
  /// A filesystem directory (local or served over HTTP by an endpoint).
  directory,

  /// A Git repository (regular or bare, local path or remote URL).
  git;

  /// Stable wire representation used in JSON payloads.
  String get wireValue => name;

  /// Parses a wire value, throwing [ValidationException] on an unknown string.
  static ProviderType fromWire(String value) => values.firstWhere(
    (e) => e.wireValue == value,
    orElse: () => throw ValidationException('Unknown provider type: $value'),
  );
}
