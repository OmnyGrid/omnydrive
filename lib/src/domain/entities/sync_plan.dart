import '../value_objects/sync_ref.dart';

/// The direction of a synchronization operation.
enum SyncDirection {
  /// Bring local up to date with the origin.
  pull,

  /// Publish local changes to the origin.
  push;

  String get wireValue => name;
}

/// A computed description of the work a synchronization will perform.
class SyncPlan {
  final SyncDirection direction;

  /// The baseline both sides share.
  final SyncRef baselineRef;

  /// The reference the operation will move toward.
  final SyncRef targetRef;

  /// Relative paths that differ between baseline and target.
  final List<String> changedPaths;

  /// Whether applying this plan requires explicit conflict resolution first.
  final bool requiresConflictResolution;

  const SyncPlan({
    required this.direction,
    required this.baselineRef,
    required this.targetRef,
    this.changedPaths = const [],
    this.requiresConflictResolution = false,
  });

  bool get isEmpty => changedPaths.isEmpty && baselineRef == targetRef;

  Map<String, dynamic> toJson() => {
    'direction': direction.wireValue,
    'baselineRef': baselineRef.toJson(),
    'targetRef': targetRef.toJson(),
    'changedPaths': changedPaths,
    'requiresConflictResolution': requiresConflictResolution,
  };
}
