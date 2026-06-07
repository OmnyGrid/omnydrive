import 'dart:async';
import 'dart:math';

/// Decides whether a failed operation should be retried and how long to wait
/// between attempts. Used by the client transport and remote sync steps to
/// recover from transient connection failures.
class RetryPolicy {
  /// Maximum number of attempts (including the first). `1` disables retries.
  final int maxAttempts;

  /// Delay before the first retry; doubled each subsequent attempt.
  final Duration initialDelay;

  /// Upper bound on the backoff delay.
  final Duration maxDelay;

  /// Fraction of jitter applied to each delay (0.0 = none, 1.0 = up to +100%).
  final double jitter;

  const RetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 200),
    this.maxDelay = const Duration(seconds: 10),
    this.jitter = 0.2,
  });

  /// A policy that never retries.
  static const none = RetryPolicy(maxAttempts: 1);

  /// Computes the backoff delay before the given retry [attempt] (1-based:
  /// `attempt == 1` is the delay before the second overall try).
  Duration delayFor(int attempt, {Random? random}) {
    final exp = initialDelay.inMilliseconds * pow(2, attempt - 1);
    final capped = min(exp.toDouble(), maxDelay.inMilliseconds.toDouble());
    final r = random ?? Random();
    final jittered = capped * (1 + jitter * r.nextDouble());
    return Duration(milliseconds: jittered.round());
  }
}

/// Runs [action], retrying according to [policy] while [retryable] returns true
/// for the thrown error. Re-throws the last error once attempts are exhausted.
Future<T> runWithRetry<T>(
  Future<T> Function() action, {
  RetryPolicy policy = const RetryPolicy(),
  bool Function(Object error)? retryable,
  Random? random,
}) async {
  var attempt = 0;
  while (true) {
    attempt++;
    try {
      return await action();
    } catch (error) {
      final canRetry = retryable == null || retryable(error);
      if (!canRetry || attempt >= policy.maxAttempts) rethrow;
      await Future<void>.delayed(policy.delayFor(attempt, random: random));
    }
  }
}
