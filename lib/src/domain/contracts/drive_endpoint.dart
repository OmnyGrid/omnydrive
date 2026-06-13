import '../entities/drive.dart';
import '../entities/endpoint_identity.dart';
import '../entities/mount_info.dart';
import '../entities/sync_result.dart';
import '../value_objects/path_filter.dart';
import '../../shared/observability/progress.dart';

/// A device that participates in the network: it can publish, mount, clone and
/// synchronize drives, coordinated through a hub.
abstract interface class DriveEndpoint {
  /// This endpoint's public identity.
  EndpointIdentity get identity;

  /// Publishes a local directory as a drive.
  ///
  /// [filter] optionally limits which sub-paths of [path] are exposed.
  Future<Drive> publishDirectory({
    required String path,
    String? name,
    bool readOnly = false,
    PathFilter? filter,
  });

  /// Publishes a git repository as a drive.
  Future<Drive> publishGit({
    required String url,
    String? name,
    bool bare = false,
    bool readOnly = false,
  });

  /// Clones a drive from the network into [dest].
  Future<MountInfo> cloneDrive({
    required String driveId,
    required String dest,
    bool readOnly = false,
  });

  /// Synchronizes a mount; may throw `ConflictDetectedException`.
  ///
  /// When [progress] is supplied, transfer progress is reported to it as the
  /// sync runs (per-file upload progress plus a final summary in the result).
  Future<SyncResult> syncMount(String mountId, {ProgressReporter? progress});
}
