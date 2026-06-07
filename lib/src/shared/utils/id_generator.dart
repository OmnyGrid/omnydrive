import 'dart:math';

/// Generates logical identifiers like `endpoint_1`, `token_2`, etc.
///
/// Injected into services so production code can swap in a non-deterministic
/// implementation without touching callers. Tests rely on the deterministic
/// sequential behavior.
abstract class IdGenerator {
  String next(String prefix);
}

/// Deterministic, in-memory counter per prefix. Intended for tests and
/// single-process defaults.
class SequentialIdGenerator implements IdGenerator {
  final Map<String, int> _counters = {};

  @override
  String next(String prefix) {
    final current = (_counters[prefix] ?? 0) + 1;
    _counters[prefix] = current;
    return '${prefix}_$current';
  }
}

/// Generates random, collision-resistant identifiers using a cryptographically
/// secure RNG. Used for production endpoint ids, tokens and shared secrets so
/// no extra dependency (`uuid`) is required.
class RandomIdGenerator implements IdGenerator {
  final Random _random;

  /// Number of random bytes encoded into each id (defaults to 16 = 128 bits).
  final int byteLength;

  RandomIdGenerator({Random? random, this.byteLength = 16})
    : _random = random ?? Random.secure();

  /// Returns a bare random hex token without a prefix. Useful for opaque
  /// secrets and bearer tokens.
  String token() {
    final bytes = List<int>.generate(byteLength, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  String next(String prefix) => '${prefix}_${token()}';
}
