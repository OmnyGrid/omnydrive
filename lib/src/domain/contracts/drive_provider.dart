import '../../shared/observability/progress.dart';
import '../entities/drive.dart';
import '../enums/access_mode.dart';
import '../enums/mount_type.dart';
import '../enums/provider_type.dart';
import '../value_objects/origin_uri.dart';
import '../value_objects/local_path.dart';
import '../value_objects/sync_ref.dart';
import 'mounted_drive.dart';
import 'synchronizer.dart';

/// A pluggable backend that knows how to describe, reference, materialize and
/// synchronize a particular kind of drive (directory, git, ...).
///
/// New providers (S3, WebDAV, SMB) are added by implementing this interface and
/// registering it in the provider registry — nothing else in the system needs
/// to change.
abstract interface class DriveProvider {
  /// Which provider type this implementation handles.
  ProviderType get type;

  /// Inspects [origin] and produces a [Drive] description under [accessMode].
  Future<Drive> describe(OriginUri origin, {required AccessMode accessMode});

  /// Computes the current reference of [origin] (git: branch/HEAD SHA;
  /// directory: manifest hash).
  Future<SyncRef> currentRef(OriginUri origin);

  /// Materializes [drive] into [dest] as the given [mountType], returning the
  /// resulting [MountedDrive].
  Future<MountedDrive> materialize({
    required Drive drive,
    required LocalPath dest,
    required MountType mountType,
    ProgressReporter? progress,
  });

  /// Returns the synchronizer for [drive].
  Synchronizer synchronizer(Drive drive);
}
