import '../../domain/entities/sync_state.dart';
import '../../domain/repositories/sync_state_store.dart';
import '../../domain/value_objects/mount_id.dart';

/// In-memory [SyncStateStore]. The default for tests.
class InMemorySyncStateStore implements SyncStateStore {
  final Map<String, SyncState> _states = {};

  @override
  Future<SyncState?> load(MountId mount) async => _states[mount.value];

  @override
  Future<void> save(MountId mount, SyncState state) async {
    _states[mount.value] = state;
  }

  @override
  Future<void> delete(MountId mount) async {
    _states.remove(mount.value);
  }
}
