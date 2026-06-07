/// Metrics captured for a completed synchronization run, surfaced through the
/// diagnostics API and returned with a sync result.
class SyncMetrics {
  /// Wall-clock duration of the whole sync transaction.
  final Duration duration;

  /// Number of files added, modified or deleted.
  final int filesChanged;

  /// Bytes transferred over the wire (uploads + downloads).
  final int bytesTransferred;

  /// How many retry attempts were made due to transient failures.
  final int retries;

  const SyncMetrics({
    this.duration = Duration.zero,
    this.filesChanged = 0,
    this.bytesTransferred = 0,
    this.retries = 0,
  });

  SyncMetrics copyWith({
    Duration? duration,
    int? filesChanged,
    int? bytesTransferred,
    int? retries,
  }) => SyncMetrics(
    duration: duration ?? this.duration,
    filesChanged: filesChanged ?? this.filesChanged,
    bytesTransferred: bytesTransferred ?? this.bytesTransferred,
    retries: retries ?? this.retries,
  );

  Map<String, dynamic> toJson() => {
    'durationMs': duration.inMilliseconds,
    'filesChanged': filesChanged,
    'bytesTransferred': bytesTransferred,
    'retries': retries,
  };

  factory SyncMetrics.fromJson(Map<String, dynamic> json) => SyncMetrics(
    duration: Duration(
      milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
    ),
    filesChanged: (json['filesChanged'] as num?)?.toInt() ?? 0,
    bytesTransferred: (json['bytesTransferred'] as num?)?.toInt() ?? 0,
    retries: (json['retries'] as num?)?.toInt() ?? 0,
  );
}
