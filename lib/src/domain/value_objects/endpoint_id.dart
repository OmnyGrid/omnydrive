import '../../shared/errors/domain_exception.dart';

/// Identifies a device (endpoint) participating in the network.
///
/// Endpoint ids are slug-like: lowercase letters, digits, hyphens and
/// underscores. They are stable for the lifetime of the endpoint registration.
class EndpointId {
  static final RegExp _pattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');

  final String value;

  EndpointId(String input) : value = input.trim() {
    if (value.isEmpty) {
      throw const ValidationException('Endpoint id is required');
    }
    if (!_pattern.hasMatch(value)) {
      throw ValidationException(
        'Invalid endpoint id "$value": use 1-64 chars of [a-z0-9_-], '
        'starting with a letter or digit',
      );
    }
  }

  @override
  bool operator ==(Object other) => other is EndpointId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
