import 'dart:convert';
import 'dart:io';

/// Severity levels, ordered from least to most severe.
enum LogLevel {
  debug,
  info,
  warn,
  error;

  bool operator >=(LogLevel other) => index >= other.index;
}

/// Structured logger. Implementations emit a level, a message and an arbitrary
/// context map. A logger can be scoped with [child] so every record inherits a
/// base context (e.g. the drive or mount id).
abstract class Logger {
  void log(LogLevel level, String message, {Map<String, Object?> context});

  void debug(String message, {Map<String, Object?> context = const {}}) =>
      log(LogLevel.debug, message, context: context);
  void info(String message, {Map<String, Object?> context = const {}}) =>
      log(LogLevel.info, message, context: context);
  void warn(String message, {Map<String, Object?> context = const {}}) =>
      log(LogLevel.warn, message, context: context);
  void error(String message, {Map<String, Object?> context = const {}}) =>
      log(LogLevel.error, message, context: context);

  /// Returns a logger that merges [context] into every record it emits.
  Logger child(Map<String, Object?> context);
}

/// Discards all log records. The default in libraries and tests.
class NoopLogger implements Logger {
  const NoopLogger();

  @override
  void log(
    LogLevel level,
    String message, {
    Map<String, Object?> context = const {},
  }) {}

  @override
  void debug(String message, {Map<String, Object?> context = const {}}) {}
  @override
  void info(String message, {Map<String, Object?> context = const {}}) {}
  @override
  void warn(String message, {Map<String, Object?> context = const {}}) {}
  @override
  void error(String message, {Map<String, Object?> context = const {}}) {}

  @override
  Logger child(Map<String, Object?> context) => this;
}

/// Writes one JSON object per line to an [IOSink] (stderr by default). Records
/// below [minLevel] are dropped.
class StructuredLogger implements Logger {
  final IOSink _sink;
  final LogLevel minLevel;
  final Map<String, Object?> _baseContext;

  StructuredLogger({
    IOSink? sink,
    this.minLevel = LogLevel.info,
    Map<String, Object?> baseContext = const {},
  }) : _sink = sink ?? stderr,
       _baseContext = baseContext;

  @override
  void log(
    LogLevel level,
    String message, {
    Map<String, Object?> context = const {},
  }) {
    if (!(level >= minLevel)) return;
    _sink.writeln(
      jsonEncode({
        'ts': DateTime.now().toUtc().toIso8601String(),
        'level': level.name,
        'msg': message,
        ..._baseContext,
        ...context,
      }),
    );
  }

  @override
  void debug(String message, {Map<String, Object?> context = const {}}) =>
      log(LogLevel.debug, message, context: context);
  @override
  void info(String message, {Map<String, Object?> context = const {}}) =>
      log(LogLevel.info, message, context: context);
  @override
  void warn(String message, {Map<String, Object?> context = const {}}) =>
      log(LogLevel.warn, message, context: context);
  @override
  void error(String message, {Map<String, Object?> context = const {}}) =>
      log(LogLevel.error, message, context: context);

  @override
  Logger child(Map<String, Object?> context) => StructuredLogger(
    sink: _sink,
    minLevel: minLevel,
    baseContext: {..._baseContext, ...context},
  );
}
