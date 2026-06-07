import 'endpoint_identity.dart';

/// The hub-side record for a registered endpoint: its public [identity] plus
/// the hashed shared secret used to authenticate it.
///
/// The raw secret is returned to the endpoint exactly once at registration and
/// never stored; only [secretHash] is persisted.
class EndpointRegistration {
  final EndpointIdentity identity;

  /// SHA-256 hash of the endpoint's shared secret.
  final String secretHash;

  const EndpointRegistration({
    required this.identity,
    required this.secretHash,
  });

  Map<String, dynamic> toJson() => {
    'identity': identity.toJson(),
    'secretHash': secretHash,
  };

  factory EndpointRegistration.fromJson(Map<String, dynamic> json) =>
      EndpointRegistration(
        identity: EndpointIdentity.fromJson(
          json['identity'] as Map<String, dynamic>,
        ),
        secretHash: json['secretHash'] as String,
      );
}
