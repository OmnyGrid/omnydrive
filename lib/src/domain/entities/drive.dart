import '../enums/access_mode.dart';
import '../enums/provider_type.dart';
import '../value_objects/drive_id.dart';
import '../value_objects/endpoint_id.dart';
import '../value_objects/origin_uri.dart';
import 'drive_capabilities.dart';

/// A published source of files.
///
/// A drive describes *where* content lives and *how* it may be accessed. The
/// per-mount synchronization state lives separately on [MountInfo] because one
/// drive can be mounted in many places.
class Drive {
  final DriveId id;
  final String name;
  final ProviderType provider;

  /// The endpoint that owns and serves this drive.
  final EndpointId originEndpoint;

  /// Where the content actually lives on the origin endpoint.
  final OriginUri originUri;

  final AccessMode accessMode;
  final DriveCapabilities capabilities;
  final DateTime createdAt;

  const Drive({
    required this.id,
    required this.name,
    required this.provider,
    required this.originEndpoint,
    required this.originUri,
    required this.accessMode,
    required this.capabilities,
    required this.createdAt,
  });

  Drive copyWith({
    String? name,
    AccessMode? accessMode,
    DriveCapabilities? capabilities,
  }) => Drive(
    id: id,
    name: name ?? this.name,
    provider: provider,
    originEndpoint: originEndpoint,
    originUri: originUri,
    accessMode: accessMode ?? this.accessMode,
    capabilities: capabilities ?? this.capabilities,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id.value,
    'name': name,
    'provider': provider.wireValue,
    'originEndpoint': originEndpoint.value,
    'originUri': originUri.value,
    'accessMode': accessMode.wireValue,
    'capabilities': capabilities.toJson(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory Drive.fromJson(Map<String, dynamic> json) => Drive(
    id: DriveId(json['id'] as String),
    name: json['name'] as String,
    provider: ProviderType.fromWire(json['provider'] as String),
    originEndpoint: EndpointId(json['originEndpoint'] as String),
    originUri: OriginUri(json['originUri'] as String),
    accessMode: AccessMode.fromWire(json['accessMode'] as String),
    capabilities: DriveCapabilities.fromJson(
      json['capabilities'] as Map<String, dynamic>,
    ),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
