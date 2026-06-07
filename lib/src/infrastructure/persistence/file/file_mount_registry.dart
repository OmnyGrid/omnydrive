import '../../../domain/entities/mount_info.dart';
import '../../../domain/repositories/mount_registry.dart';
import '../../../domain/value_objects/drive_id.dart';
import '../../../domain/value_objects/local_path.dart';
import '../../../domain/value_objects/mount_id.dart';
import '../../../shared/utils/atomic_file.dart';

/// A [MountRegistry] persisted as a single JSON document, so mounts created by
/// one CLI invocation are visible to later `sync`/`mounts` commands.
class FileMountRegistry implements MountRegistry {
  final String path;

  FileMountRegistry(this.path);

  Future<List<MountInfo>> _load() async {
    final json = await AtomicFile.readJson(path);
    if (json == null) return [];
    final list = (json['mounts'] as List?) ?? const [];
    return list.cast<Map<String, dynamic>>().map(MountInfo.fromJson).toList();
  }

  Future<void> _store(List<MountInfo> mounts) => AtomicFile.writeJson(path, {
    'mounts': [for (final m in mounts) m.toJson()],
  });

  @override
  Future<void> save(MountInfo mount) async {
    final mounts = await _load()
      ..removeWhere((m) => m.id == mount.id)
      ..add(mount);
    await _store(mounts);
  }

  @override
  Future<MountInfo?> findById(MountId id) async {
    for (final m in await _load()) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  Future<MountInfo?> findByPath(LocalPath path) async {
    for (final m in await _load()) {
      if (m.localPath == path) return m;
    }
    return null;
  }

  @override
  Future<List<MountInfo>> findAll() async {
    final mounts = await _load()
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    return List.unmodifiable(mounts);
  }

  @override
  Future<List<MountInfo>> findByDrive(DriveId driveId) async =>
      List.unmodifiable((await _load()).where((m) => m.driveId == driveId));

  @override
  Future<void> delete(MountId id) async {
    final mounts = await _load()
      ..removeWhere((m) => m.id == id);
    await _store(mounts);
  }
}
