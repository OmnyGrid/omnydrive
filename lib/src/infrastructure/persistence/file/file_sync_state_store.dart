import '../../../domain/entities/sync_state.dart';
import '../../../domain/repositories/sync_state_store.dart';
import '../../../domain/value_objects/mount_id.dart';
import '../../../shared/utils/atomic_file.dart';

/// A [SyncStateStore] persisted as a single JSON document keyed by mount id.
class FileSyncStateStore implements SyncStateStore {
  final String path;

  FileSyncStateStore(this.path);

  Future<Map<String, dynamic>> _load() async =>
      await AtomicFile.readJson(path) ?? <String, dynamic>{};

  @override
  Future<SyncState?> load(MountId mount) async {
    final all = await _load();
    final raw = all[mount.value];
    return raw == null ? null : SyncState.fromJson(raw as Map<String, dynamic>);
  }

  @override
  Future<void> save(MountId mount, SyncState state) async {
    final all = await _load();
    all[mount.value] = state.toJson();
    await AtomicFile.writeJson(path, all);
  }

  @override
  Future<void> delete(MountId mount) async {
    final all = await _load();
    all.remove(mount.value);
    await AtomicFile.writeJson(path, all);
  }
}
