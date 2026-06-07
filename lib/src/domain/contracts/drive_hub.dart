import '../entities/drive_registration.dart';
import '../entities/endpoint_identity.dart';
import '../value_objects/auth_token.dart';
import '../value_objects/drive_id.dart';
import '../value_objects/endpoint_id.dart';

/// Where a drive's content can be fetched from, returned by the hub's sync
/// routing so a peer can talk directly to the serving endpoint.
class DriveRoute {
  final DriveId driveId;
  final EndpointId servingEndpoint;
  final String serveUrl;

  const DriveRoute({
    required this.driveId,
    required this.servingEndpoint,
    required this.serveUrl,
  });

  Map<String, dynamic> toJson() => {
    'driveId': driveId.value,
    'servingEndpoint': servingEndpoint.value,
    'serveUrl': serveUrl,
  };

  factory DriveRoute.fromJson(Map<String, dynamic> json) => DriveRoute(
    driveId: DriveId(json['driveId'] as String),
    servingEndpoint: EndpointId(json['servingEndpoint'] as String),
    serveUrl: json['serveUrl'] as String,
  );
}

/// The central coordinator. Handles endpoint discovery, authentication, the
/// drive registry, capability negotiation and synchronization routing. A hub
/// never needs direct filesystem access — it only brokers metadata.
abstract interface class DriveHub {
  /// Registers an endpoint and returns its established public identity.
  Future<EndpointIdentity> registerEndpoint(EndpointIdentity identity);

  /// Authenticates an endpoint by id + shared secret, returning a bearer token.
  Future<AuthToken> authenticate({
    required EndpointId endpointId,
    required String secret,
  });

  /// Records a published drive in the registry.
  Future<DriveRegistration> registerDrive(DriveRegistration registration);

  /// Lists all discoverable drives.
  Future<List<DriveRegistration>> listDrives();

  /// Looks up a single drive registration.
  Future<DriveRegistration> getDrive(DriveId id);

  /// Resolves which endpoint serves [id]'s content for the [requester].
  Future<DriveRoute> routeSync(DriveId id, {required EndpointId requester});
}
