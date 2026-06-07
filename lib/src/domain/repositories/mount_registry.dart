import '../entities/mount_info.dart';
import '../value_objects/drive_id.dart';
import '../value_objects/local_path.dart';
import '../value_objects/mount_id.dart';

/// Persists the local endpoint's mounts.
abstract interface class MountRegistry {
  Future<void> save(MountInfo mount);
  Future<MountInfo?> findById(MountId id);
  Future<MountInfo?> findByPath(LocalPath path);
  Future<List<MountInfo>> findAll();
  Future<List<MountInfo>> findByDrive(DriveId driveId);
  Future<void> delete(MountId id);
}
