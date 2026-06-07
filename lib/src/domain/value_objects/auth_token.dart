import '../../shared/errors/domain_exception.dart';

/// An opaque bearer token issued by a hub and presented by endpoints on
/// authenticated requests.
class AuthToken {
  final String value;

  AuthToken(this.value) {
    if (value.trim().isEmpty) {
      throw const ValidationException('Auth token is required');
    }
  }

  @override
  bool operator ==(Object other) => other is AuthToken && other.value == value;

  @override
  int get hashCode => value.hashCode;

  /// Tokens are secrets; never print the raw value.
  @override
  String toString() => 'AuthToken(***)';
}
