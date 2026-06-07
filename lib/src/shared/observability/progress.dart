/// Phases a long-running synchronization transfer moves through.
enum ProgressPhase { counting, transferring, finalizing, done }

/// A single progress update emitted during a transfer.
class ProgressEvent {
  final ProgressPhase phase;

  /// Human-readable description of the current step.
  final String message;

  /// Items processed so far (files, objects), if known.
  final int? completed;

  /// Total items to process, if known.
  final int? total;

  /// Bytes transferred so far, if tracked.
  final int? bytes;

  const ProgressEvent({
    required this.phase,
    this.message = '',
    this.completed,
    this.total,
    this.bytes,
  });

  /// Fraction complete in `[0, 1]`, or null when totals are unknown.
  double? get fraction {
    final t = total;
    final c = completed;
    if (t == null || c == null || t == 0) return null;
    return (c / t).clamp(0.0, 1.0);
  }

  @override
  String toString() =>
      'ProgressEvent(${phase.name}, $completed/$total, "$message")';
}

/// Sink for progress updates. Callers that don't care about progress simply
/// pass null where a [ProgressReporter] is accepted.
class ProgressReporter {
  final void Function(ProgressEvent event) _onEvent;

  ProgressReporter(this._onEvent);

  /// Builds a reporter that forwards events to a broadcast stream.
  factory ProgressReporter.toSink(void Function(ProgressEvent) onEvent) =>
      ProgressReporter(onEvent);

  void report(ProgressEvent event) => _onEvent(event);

  void phase(ProgressPhase phase, String message) =>
      report(ProgressEvent(phase: phase, message: message));
}
