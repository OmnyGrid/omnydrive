import '../../shared/errors/domain_exception.dart';

/// Identifies a hub (the central coordinator).
class HubId {
  final String value;

  HubId(String input) : value = input.trim() {
    if (value.isEmpty) {
      throw const ValidationException('Hub id is required');
    }
  }

  @override
  bool operator ==(Object other) => other is HubId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
