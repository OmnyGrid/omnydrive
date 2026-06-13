/// Metrics captured for a completed synchronization run, surfaced through the
/// diagnostics API and returned with a sync result.
///
/// As well as the headline counters this carries a per-path breakdown of the
/// run — which files were uploaded ([transferredPaths]), deduplicated via a
/// server-side copy ([copiedPaths]) or deleted ([removedPaths]) — so callers can
/// print a full report. The path lists are empty for providers that don't expose
/// them (e.g. git).
class SyncMetrics {
  /// Wall-clock duration of the whole sync transaction.
  final Duration duration;

  /// Number of files added, modified or deleted.
  final int filesChanged;

  /// Uncompressed bytes of the files whose content was transferred (uploads +
  /// downloads). Excludes deduplicated copies, which send no content.
  final int bytesTransferred;

  /// Bytes actually pushed over the wire — i.e. [bytesTransferred] after any
  /// transport compression. Equal to [bytesTransferred] when nothing compresses.
  final int bytesOnWire;

  /// How many retry attempts were made due to transient failures.
  final int retries;

  /// Paths whose content was sent over the wire.
  final List<String> transferredPaths;

  /// Paths satisfied by a server-side copy of content already at the destination.
  final List<String> copiedPaths;

  /// Paths deleted from the destination.
  final List<String> removedPaths;

  const SyncMetrics({
    this.duration = Duration.zero,
    this.filesChanged = 0,
    this.bytesTransferred = 0,
    this.bytesOnWire = 0,
    this.retries = 0,
    this.transferredPaths = const [],
    this.copiedPaths = const [],
    this.removedPaths = const [],
  });

  /// Number of files whose content was uploaded/downloaded.
  int get filesTransferred => transferredPaths.length;

  /// Number of files deduplicated via a server-side copy.
  int get filesCopied => copiedPaths.length;

  /// Number of files deleted from the destination.
  int get filesRemoved => removedPaths.length;

  SyncMetrics copyWith({
    Duration? duration,
    int? filesChanged,
    int? bytesTransferred,
    int? bytesOnWire,
    int? retries,
    List<String>? transferredPaths,
    List<String>? copiedPaths,
    List<String>? removedPaths,
  }) => SyncMetrics(
    duration: duration ?? this.duration,
    filesChanged: filesChanged ?? this.filesChanged,
    bytesTransferred: bytesTransferred ?? this.bytesTransferred,
    bytesOnWire: bytesOnWire ?? this.bytesOnWire,
    retries: retries ?? this.retries,
    transferredPaths: transferredPaths ?? this.transferredPaths,
    copiedPaths: copiedPaths ?? this.copiedPaths,
    removedPaths: removedPaths ?? this.removedPaths,
  );

  Map<String, dynamic> toJson() => {
    'durationMs': duration.inMilliseconds,
    'filesChanged': filesChanged,
    'bytesTransferred': bytesTransferred,
    'bytesOnWire': bytesOnWire,
    'retries': retries,
    'transferredPaths': transferredPaths,
    'copiedPaths': copiedPaths,
    'removedPaths': removedPaths,
  };

  factory SyncMetrics.fromJson(Map<String, dynamic> json) => SyncMetrics(
    duration: Duration(
      milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
    ),
    filesChanged: (json['filesChanged'] as num?)?.toInt() ?? 0,
    bytesTransferred: (json['bytesTransferred'] as num?)?.toInt() ?? 0,
    bytesOnWire: (json['bytesOnWire'] as num?)?.toInt() ?? 0,
    retries: (json['retries'] as num?)?.toInt() ?? 0,
    transferredPaths: _stringList(json['transferredPaths']),
    copiedPaths: _stringList(json['copiedPaths']),
    removedPaths: _stringList(json['removedPaths']),
  );

  static List<String> _stringList(Object? value) => value is List
      ? value.map((e) => e.toString()).toList(growable: false)
      : const [];
}
