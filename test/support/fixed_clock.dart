import 'package:omnydrive/omnydrive.dart';

/// A [Clock] that always returns a fixed instant, for deterministic tests.
class FixedClock implements Clock {
  DateTime _now;

  FixedClock(this._now);

  /// Advances the clock by [delta] and returns the new time.
  DateTime advance(Duration delta) => _now = _now.add(delta);

  @override
  DateTime now() => _now;
}
