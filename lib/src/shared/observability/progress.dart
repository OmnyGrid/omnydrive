/// Phases a long-running synchronization transfer moves through.
enum ProgressPhase { counting, transferring, finalizing, done }

/// How a single file reached the destination during a transfer.
///
/// [transferred] files had their bytes sent over the wire; [copied] files were
/// deduplicated via a server-side copy (no bytes sent); [removed] files were
/// deleted from the destination.
enum ProgressItemKind { transferred, copied, removed }

/// The lifecycle stage of a per-file [ProgressEvent].
///
/// [started] fires once before work on the item begins, [progress] fires
/// repeatedly while bytes stream, and [completed] fires once when it settles.
enum ProgressItemState { started, progress, completed }

/// A single progress update emitted during a transfer.
///
/// Carries two layers of information: an *aggregate* view of the whole transfer
/// ([completed]/[total]/[bytes]) and an optional *per-item* view of the file the
/// event concerns ([path]/[itemKind]/[itemState]/[itemBytes]/[itemTotalBytes]),
/// which lets a UI draw a live progress bar for each concurrent upload.
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

  /// Relative path of the file this event concerns, if any.
  final String? path;

  /// How [path] is being applied to the destination, if known.
  final ProgressItemKind? itemKind;

  /// Lifecycle stage of [path] within this transfer, if known.
  final ProgressItemState? itemState;

  /// Bytes of [path] sent so far, if streamed.
  final int? itemBytes;

  /// Total bytes to send for [path], if known. For a compressed transfer this
  /// is the compressed (wire) size, so [itemBytes]/[itemTotalBytes] share a basis.
  final int? itemTotalBytes;

  /// Original, uncompressed size of [path] in bytes, if known. Unlike
  /// [itemTotalBytes] this is never the compressed figure, so a UI can show the
  /// real file size alongside the wire progress.
  final int? itemSize;

  const ProgressEvent({
    required this.phase,
    this.message = '',
    this.completed,
    this.total,
    this.bytes,
    this.path,
    this.itemKind,
    this.itemState,
    this.itemBytes,
    this.itemTotalBytes,
    this.itemSize,
  });

  /// Fraction complete in `[0, 1]`, or null when totals are unknown.
  double? get fraction {
    final t = total;
    final c = completed;
    if (t == null || c == null || t == 0) return null;
    return (c / t).clamp(0.0, 1.0);
  }

  /// Fraction of [path] sent in `[0, 1]`, or null when its size is unknown.
  double? get itemFraction {
    final t = itemTotalBytes;
    final b = itemBytes;
    if (t == null || b == null || t == 0) return null;
    return (b / t).clamp(0.0, 1.0);
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
