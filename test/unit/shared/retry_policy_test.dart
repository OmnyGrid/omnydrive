import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

void main() {
  group('RetryPolicy', () {
    test('delay grows exponentially and is capped', () {
      const policy = RetryPolicy(
        initialDelay: Duration(milliseconds: 100),
        maxDelay: Duration(milliseconds: 350),
        jitter: 0.0,
      );
      expect(policy.delayFor(1).inMilliseconds, 100);
      expect(policy.delayFor(2).inMilliseconds, 200);
      // 400 would exceed the 350ms cap.
      expect(policy.delayFor(3).inMilliseconds, 350);
    });
  });

  group('runWithRetry', () {
    test('retries until success', () async {
      var attempts = 0;
      final result = await runWithRetry(
        () async {
          attempts++;
          if (attempts < 3) throw StateError('boom');
          return 'ok';
        },
        policy: const RetryPolicy(
          maxAttempts: 5,
          initialDelay: Duration(milliseconds: 1),
          jitter: 0.0,
        ),
      );
      expect(result, 'ok');
      expect(attempts, 3);
    });

    test('rethrows after exhausting attempts', () async {
      var attempts = 0;
      await expectLater(
        runWithRetry(
          () async {
            attempts++;
            throw StateError('always');
          },
          policy: const RetryPolicy(
            maxAttempts: 2,
            initialDelay: Duration(milliseconds: 1),
            jitter: 0.0,
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(attempts, 2);
    });

    test('does not retry when retryable returns false', () async {
      var attempts = 0;
      await expectLater(
        runWithRetry(
          () async {
            attempts++;
            throw StateError('fatal');
          },
          retryable: (_) => false,
          policy: const RetryPolicy(maxAttempts: 5),
        ),
        throwsA(isA<StateError>()),
      );
      expect(attempts, 1);
    });
  });
}
