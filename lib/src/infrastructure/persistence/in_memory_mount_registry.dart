import '../../domain/entities/mount_info.dart';
import '../../domain/repositories/mount_registry.dart';
import '../../domain/value_objects/drive_id.dart';
import '../../domain/value_objects/local_path.dart';
import '../../domain/value_objects/mount_id.dart';

/// In-memory [MountRegistry]. The default for tests.
class InMemoryMountRegistry implements MountRegistry {
  final Map<String, MountInfo> _mounts = {};

  @override
  Future<void> save(MountInfo mount) async {
    _mounts[mount.id.value] = mount;
  }

  @override
  Future<MountInfo?> findById(MountId id) async => _mounts[id.value];

  @override
  Future<MountInfo?> findByPath(LocalPath path) async {
    for (final mount in _mounts.values) {
      if (mount.localPath == path) return mount;
    }
    return null;
  }

  @override
  Future<List<MountInfo>> findAll() async => List.unmodifiable(
    _mounts.values.toList()..sort((a, b) => a.id.value.compareTo(b.id.value)),
  );

  @override
  Future<List<MountInfo>> findByDrive(DriveId driveId) async =>
      List.unmodifiable(_mounts.values.where((m) => m.driveId == driveId));

  @override
  Future<void> delete(MountId id) async {
    _mounts.remove(id.value);
  }
}
