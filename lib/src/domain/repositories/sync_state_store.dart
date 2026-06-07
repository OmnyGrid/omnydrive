import '../entities/sync_state.dart';
import '../value_objects/mount_id.dart';

/// Persists per-mount synchronization state. The baseline reference stored here
/// is the anchor the conflict check compares against; it is updated atomically
/// only after a successful publish.
abstract interface class SyncStateStore {
  Future<SyncState?> load(MountId mount);
  Future<void> save(MountId mount, SyncState state);
  Future<void> delete(MountId mount);
}
