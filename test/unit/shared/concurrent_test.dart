import 'dart:async';

import 'package:omnydrive/src/shared/utils/concurrent.dart';
import 'package:test/test.dart';

void main() {
  group('forEachConcurrent', () {
    test('processes every item exactly once', () async {
      final seen = <int>[];
      await forEachConcurrent(List.generate(50, (i) => i), (i) async {
        seen.add(i);
      }, concurrency: 8);
      expect(seen, hasLength(50));
      expect(seen.toSet(), equals({for (var i = 0; i < 50; i++) i}));
    });

    test('never exceeds the concurrency cap', () async {
      var inFlight = 0;
      var peak = 0;
      await forEachConcurrent(List.generate(40, (i) => i), (i) async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        inFlight--;
      }, concurrency: 5);
      expect(peak, lessThanOrEqualTo(5));
      // With 40 items and a real delay the pool should actually fill up.
      expect(peak, equals(5));
    });

    test('runs items concurrently rather than serially', () async {
      final completer = Completer<void>();
      var started = 0;
      final run = forEachConcurrent(List.generate(4, (i) => i), (i) async {
        started++;
        await completer.future; // block until released
      }, concurrency: 4);
      // Let microtasks settle so all four workers reach the await.
      await Future<void>.delayed(Duration.zero);
      expect(
        started,
        equals(4),
        reason: 'all workers should start in parallel',
      );
      completer.complete();
      await run;
    });

    test('caps workers at the item count for tiny inputs', () async {
      var inFlight = 0;
      var peak = 0;
      await forEachConcurrent([1, 2], (i) async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        inFlight--;
      }, concurrency: 16);
      expect(peak, lessThanOrEqualTo(2));
    });

    test('an empty input is a no-op', () async {
      var calls = 0;
      await forEachConcurrent(<int>[], (_) async => calls++);
      expect(calls, isZero);
    });

    test('fail-fast: rethrows and stops scheduling new work', () async {
      final processed = <int>[];
      Future<void> run() =>
          forEachConcurrent(List.generate(20, (i) => i), (i) async {
            if (i == 1) throw StateError('boom on $i');
            await Future<void>.delayed(const Duration(milliseconds: 1));
            processed.add(i);
          }, concurrency: 2);

      await expectLater(run(), throwsA(isA<StateError>()));
      // The failure halts the cursor, so far fewer than all 20 items run.
      expect(processed.length, lessThan(20));
    });
  });
}
