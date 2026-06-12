import 'dart:async';
import 'dart:math' as math;

/// Runs [action] over every entry of [items] with at most [concurrency]
/// invocations in flight at once.
///
/// A fixed pool of workers drains a shared cursor, so slow items never block
/// faster ones and the in-flight count never exceeds [concurrency]. This is the
/// single-threaded equivalent of a bounded worker pool: the cursor is read and
/// advanced synchronously before any `await`, so no locking is required.
///
/// Fail-fast: the first error stops workers from picking up new items and is
/// rethrown to the caller (items already in flight are awaited first).
Future<void> forEachConcurrent<T>(
  List<T> items,
  Future<void> Function(T item) action, {
  int concurrency = 8,
}) async {
  if (items.isEmpty) return;

  final limit = math.max(1, concurrency);
  final workers = math.min(limit, items.length);
  var next = 0;
  var failed = false;

  Future<void> worker() async {
    while (!failed && next < items.length) {
      final item = items[next++];
      await action(item);
    }
  }

  try {
    await Future.wait(List.generate(workers, (_) => worker()));
  } catch (_) {
    failed = true;
    rethrow;
  }
}
