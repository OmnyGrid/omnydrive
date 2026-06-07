import '../enums/sync_status.dart';
import '../value_objects/sync_ref.dart';

/// The persisted synchronization state of a single mount.
///
/// [baselineRef] is the reference the local copy was last reconciled with — the
/// anchor the conflict check compares against. It only advances after a
/// successful publish.
class SyncState {
  /// The reference the local copy was materialized from / last synced to.
  final SyncRef baselineRef;

  /// The reference the local working copy currently represents, if computed.
  final SyncRef? currentRef;

  final SyncStatus status;
  final DateTime? lastSyncedAt;

  /// The last error message, when [status] is [SyncStatus.error].
  final String? lastError;

  const SyncState({
    required this.baselineRef,
    this.currentRef,
    this.status = SyncStatus.clean,
    this.lastSyncedAt,
    this.lastError,
  });

  SyncState copyWith({
    SyncRef? baselineRef,
    SyncRef? currentRef,
    SyncStatus? status,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) => SyncState(
    baselineRef: baselineRef ?? this.baselineRef,
    currentRef: currentRef ?? this.currentRef,
    status: status ?? this.status,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );

  Map<String, dynamic> toJson() => {
    'baselineRef': baselineRef.toJson(),
    if (currentRef != null) 'currentRef': currentRef!.toJson(),
    'status': status.wireValue,
    if (lastSyncedAt != null) 'lastSyncedAt': lastSyncedAt!.toIso8601String(),
    if (lastError != null) 'lastError': lastError,
  };

  factory SyncState.fromJson(Map<String, dynamic> json) => SyncState(
    baselineRef: SyncRef.fromJson(json['baselineRef'] as Map<String, dynamic>),
    currentRef: json['currentRef'] == null
        ? null
        : SyncRef.fromJson(json['currentRef'] as Map<String, dynamic>),
    status: SyncStatus.fromWire(json['status'] as String),
    lastSyncedAt: json['lastSyncedAt'] == null
        ? null
        : DateTime.parse(json['lastSyncedAt'] as String),
    lastError: json['lastError'] as String?,
  );
}
