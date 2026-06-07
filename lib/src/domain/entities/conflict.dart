import '../enums/conflict_kind.dart';
import '../value_objects/drive_id.dart';
import '../value_objects/sync_ref.dart';

/// A structured description of why a synchronization could not proceed, carried
/// by [ConflictDetectedException] and surfaced through the conflicts API.
class Conflict {
  final ConflictKind kind;
  final DriveId driveId;

  /// The baseline the caller synchronized against.
  final SyncRef expectedRef;

  /// The reference the origin actually points at now.
  final SyncRef? actualRef;

  /// Paths involved in the conflict, when known (content divergence).
  final List<String> paths;

  /// Human-readable explanation.
  final String message;

  Conflict({
    required this.kind,
    required this.driveId,
    required this.expectedRef,
    this.actualRef,
    this.paths = const [],
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    'kind': kind.wireValue,
    'driveId': driveId.value,
    'expectedRef': expectedRef.toJson(),
    if (actualRef != null) 'actualRef': actualRef!.toJson(),
    'paths': paths,
    'message': message,
  };

  factory Conflict.fromJson(Map<String, dynamic> json) => Conflict(
    kind: ConflictKind.fromWire(json['kind'] as String),
    driveId: DriveId(json['driveId'] as String),
    expectedRef: SyncRef.fromJson(json['expectedRef'] as Map<String, dynamic>),
    actualRef: json['actualRef'] == null
        ? null
        : SyncRef.fromJson(json['actualRef'] as Map<String, dynamic>),
    paths: (json['paths'] as List?)?.cast<String>() ?? const [],
    message: json['message'] as String,
  );
}
