import '../value_objects/drive_id.dart';
import '../value_objects/endpoint_id.dart';
import 'drive.dart';

/// The hub-side registry record for a published drive: the [drive] metadata
/// plus the URL of the endpoint content server that serves its bytes.
class DriveRegistration {
  final Drive drive;

  /// The endpoint currently serving this drive's content.
  final EndpointId servingEndpoint;

  /// Base URL peers should use to fetch this drive's content.
  final String serveUrl;

  final DateTime registeredAt;

  const DriveRegistration({
    required this.drive,
    required this.servingEndpoint,
    required this.serveUrl,
    required this.registeredAt,
  });

  DriveId get id => drive.id;

  Map<String, dynamic> toJson() => {
    'drive': drive.toJson(),
    'servingEndpoint': servingEndpoint.value,
    'serveUrl': serveUrl,
    'registeredAt': registeredAt.toIso8601String(),
  };

  factory DriveRegistration.fromJson(Map<String, dynamic> json) =>
      DriveRegistration(
        drive: Drive.fromJson(json['drive'] as Map<String, dynamic>),
        servingEndpoint: EndpointId(json['servingEndpoint'] as String),
        serveUrl: json['serveUrl'] as String,
        registeredAt: DateTime.parse(json['registeredAt'] as String),
      );
}
