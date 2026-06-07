import '../../shared/errors/domain_exception.dart';

/// The synchronization state of a mount relative to its origin.
enum SyncStatus {
  /// Local and origin are at the same reference; nothing to do.
  clean,

  /// Local has changes the origin does not yet have.
  ahead,

  /// Origin has changes the local copy does not yet have.
  behind,

  /// Both sides have diverged from the common baseline.
  diverged,

  /// A conflict was detected and must be resolved explicitly.
  conflicted,

  /// A synchronization is currently in progress.
  syncing,

  /// The last synchronization failed.
  error;

  String get wireValue => name;

  static SyncStatus fromWire(String value) => values.firstWhere(
    (e) => e.wireValue == value,
    orElse: () => throw ValidationException('Unknown sync status: $value'),
  );
}
