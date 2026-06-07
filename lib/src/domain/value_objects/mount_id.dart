import '../../shared/errors/domain_exception.dart';

/// Identifies a local mount of a drive.
class MountId {
  final String value;

  MountId(String input) : value = input.trim() {
    if (value.isEmpty) {
      throw const ValidationException('Mount id is required');
    }
  }

  @override
  bool operator ==(Object other) => other is MountId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
