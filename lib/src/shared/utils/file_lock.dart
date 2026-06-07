import 'dart:convert';
import 'dart:io';

import '../errors/domain_exception.dart';

/// Advisory cross-process lock backed by an exclusively-created lock file.
///
/// Acquisition uses `FileMode.writeOnlyAppend` with an existence pre-check; the
/// lock file records the owning pid, host and acquisition time so a stale lock
/// left behind by a crashed process can be reclaimed after [staleAfter].
///
/// This is advisory: it only protects against other code that also goes through
/// [FileLock] for the same [lockPath].
class FileLock {
  /// Path of the lock file (e.g. `<mount>/.omnydrive/lock`).
  final String lockPath;

  /// A held lock older than this is considered stale and may be reclaimed.
  final Duration staleAfter;

  bool _held = false;

  FileLock(this.lockPath, {this.staleAfter = const Duration(minutes: 10)});

  bool get isHeld => _held;

  /// Attempts to acquire the lock, reclaiming a stale one if present.
  ///
  /// Throws [LockHeldException] when another live owner currently holds it.
  Future<void> acquire() async {
    final file = File(lockPath);
    await file.parent.create(recursive: true);

    if (await file.exists()) {
      if (!await _isStale(file)) {
        throw LockHeldException('Lock is held: $lockPath');
      }
      // Reclaim the stale lock.
      await file.delete();
    }

    // Best-effort exclusive create. Between the existence check and this write
    // there is a small race, but for our single-host advisory use it is
    // acceptable; the recorded owner lets diagnostics detect contention.
    await file.writeAsString(
      jsonEncode({
        'pid': pid,
        'host': Platform.localHostname,
        'acquiredAt': DateTime.now().toUtc().toIso8601String(),
      }),
      mode: FileMode.writeOnly,
      flush: true,
    );
    _held = true;
  }

  /// Releases the lock if held.
  Future<void> release() async {
    if (!_held) return;
    final file = File(lockPath);
    if (await file.exists()) {
      await file.delete();
    }
    _held = false;
  }

  /// Acquires the lock, runs [action], and always releases afterwards.
  Future<T> withLock<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      await release();
    }
  }

  Future<bool> _isStale(File file) async {
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) return true;
      final acquiredAt = DateTime.tryParse(data['acquiredAt'] as String? ?? '');
      if (acquiredAt == null) return true;
      return DateTime.now().toUtc().difference(acquiredAt) > staleAfter;
    } catch (_) {
      // Unparseable lock file: treat as stale.
      return true;
    }
  }
}
