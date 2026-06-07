import '../value_objects/capability.dart';
import '../value_objects/endpoint_id.dart';

/// The public identity of an endpoint as advertised to the hub and peers.
///
/// [publicKey] is reserved for a future asymmetric-auth upgrade; v1 uses
/// shared-secret/token auth and leaves it null.
class EndpointIdentity {
  final EndpointId id;
  final String displayName;

  /// Base URL of the endpoint's content server (where peers fetch content).
  final String baseUrl;

  /// Capabilities the endpoint supports network-wide.
  final CapabilitySet capabilities;

  /// Reserved for future public-key authentication.
  final String? publicKey;

  final DateTime registeredAt;

  const EndpointIdentity({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    required this.capabilities,
    this.publicKey,
    required this.registeredAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id.value,
    'displayName': displayName,
    'baseUrl': baseUrl,
    'capabilities': capabilities.toJson(),
    if (publicKey != null) 'publicKey': publicKey,
    'registeredAt': registeredAt.toIso8601String(),
  };

  factory EndpointIdentity.fromJson(Map<String, dynamic> json) =>
      EndpointIdentity(
        id: EndpointId(json['id'] as String),
        displayName: json['displayName'] as String,
        baseUrl: json['baseUrl'] as String,
        capabilities: CapabilitySet.fromJson(
          json['capabilities'] as List<dynamic>,
        ),
        publicKey: json['publicKey'] as String?,
        registeredAt: DateTime.parse(json['registeredAt'] as String),
      );
}
