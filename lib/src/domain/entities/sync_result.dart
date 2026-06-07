import '../../shared/observability/metrics.dart';
import '../enums/sync_status.dart';
import '../value_objects/sync_ref.dart';

/// The outcome of a completed synchronization.
class SyncResult {
  /// The new baseline reference after the sync.
  final SyncRef newRef;

  /// Number of changes applied (files or commits).
  final int appliedChanges;

  final SyncStatus status;
  final SyncMetrics metrics;

  /// For git pushes: the branch the changes were published to, if any.
  final String? publishedBranch;

  const SyncResult({
    required this.newRef,
    required this.appliedChanges,
    required this.status,
    this.metrics = const SyncMetrics(),
    this.publishedBranch,
  });

  Map<String, dynamic> toJson() => {
    'newRef': newRef.toJson(),
    'appliedChanges': appliedChanges,
    'status': status.wireValue,
    'metrics': metrics.toJson(),
    if (publishedBranch != null) 'publishedBranch': publishedBranch,
  };

  factory SyncResult.fromJson(Map<String, dynamic> json) => SyncResult(
    newRef: SyncRef.fromJson(json['newRef'] as Map<String, dynamic>),
    appliedChanges: (json['appliedChanges'] as num).toInt(),
    status: SyncStatus.fromWire(json['status'] as String),
    metrics: json['metrics'] == null
        ? const SyncMetrics()
        : SyncMetrics.fromJson(json['metrics'] as Map<String, dynamic>),
    publishedBranch: json['publishedBranch'] as String?,
  );
}
