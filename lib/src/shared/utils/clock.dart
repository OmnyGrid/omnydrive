/// Time source used by services so tests can fix `now`.
abstract class Clock {
  DateTime now();
}

/// Production clock returning the current UTC time.
class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now().toUtc();
}
