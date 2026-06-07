import 'dart:async';

/// Kinds of events published on the [EventBus].
enum DriveEventKind {
  drivePublished,
  driveUnpublished,
  driveMounted,
  driveUnmounted,
  syncStarted,
  syncCompleted,
  conflictDetected,
  endpointRegistered,
}

/// A structured, observable event emitted by drives, mounts and the sync
/// engine. Consumed by the diagnostics API and the CLI's `--verbose` mode.
class DriveEvent {
  final DriveEventKind kind;
  final DateTime at;

  /// Arbitrary structured payload (drive id, mount id, refs, ...).
  final Map<String, Object?> data;

  DriveEvent(this.kind, {DateTime? at, this.data = const {}})
    : at = at ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'at': at.toIso8601String(),
    'data': data,
  };

  @override
  String toString() => 'DriveEvent(${kind.name}, $data)';
}

/// Broadcast hub for [DriveEvent]s. Multiple listeners may subscribe; a bounded
/// ring buffer of recent events is retained for the diagnostics API.
class EventBus {
  final _controller = StreamController<DriveEvent>.broadcast();
  final List<DriveEvent> _recent = [];
  final int _historyLimit;

  EventBus({int historyLimit = 100}) : _historyLimit = historyLimit;

  /// Stream of events as they are published.
  Stream<DriveEvent> get stream => _controller.stream;

  /// The most recent events, oldest first (up to the history limit).
  List<DriveEvent> get recent => List.unmodifiable(_recent);

  void publish(DriveEvent event) {
    _recent.add(event);
    if (_recent.length > _historyLimit) {
      _recent.removeAt(0);
    }
    if (_controller.hasListener) {
      _controller.add(event);
    }
  }

  Future<void> close() => _controller.close();
}
