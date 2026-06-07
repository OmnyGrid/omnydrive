import '../enums/access_mode.dart';
import '../enums/mount_type.dart';
import '../value_objects/drive_id.dart';
import '../value_objects/local_path.dart';
import '../value_objects/mount_id.dart';
import 'sync_state.dart';

/// Records a drive mounted at a local path.
class MountInfo {
  final MountId id;
  final DriveId driveId;
  final LocalPath localPath;
  final AccessMode accessMode;
  final MountType mountType;
  final DateTime mountedAt;
  final SyncState syncState;

  const MountInfo({
    required this.id,
    required this.driveId,
    required this.localPath,
    required this.accessMode,
    required this.mountType,
    required this.mountedAt,
    required this.syncState,
  });

  MountInfo copyWith({SyncState? syncState}) => MountInfo(
    id: id,
    driveId: driveId,
    localPath: localPath,
    accessMode: accessMode,
    mountType: mountType,
    mountedAt: mountedAt,
    syncState: syncState ?? this.syncState,
  );

  Map<String, dynamic> toJson() => {
    'id': id.value,
    'driveId': driveId.value,
    'localPath': localPath.value,
    'accessMode': accessMode.wireValue,
    'mountType': mountType.wireValue,
    'mountedAt': mountedAt.toIso8601String(),
    'syncState': syncState.toJson(),
  };

  factory MountInfo.fromJson(Map<String, dynamic> json) => MountInfo(
    id: MountId(json['id'] as String),
    driveId: DriveId(json['driveId'] as String),
    localPath: LocalPath(json['localPath'] as String),
    accessMode: AccessMode.fromWire(json['accessMode'] as String),
    mountType: MountType.fromWire(json['mountType'] as String),
    mountedAt: DateTime.parse(json['mountedAt'] as String),
    syncState: SyncState.fromJson(json['syncState'] as Map<String, dynamic>),
  );
}
