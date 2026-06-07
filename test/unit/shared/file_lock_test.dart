import 'package:omnydrive/omnydrive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/temp_dir.dart';

void main() {
  late TempDir tmp;

  setUp(() async => tmp = await TempDir.create());
  tearDown(() async => tmp.cleanup());

  test('acquire then release allows re-acquisition', () async {
    final lockPath = p.join(tmp.path, '.omnydrive', 'lock');
    final lock = FileLock(lockPath);
    await lock.acquire();
    expect(lock.isHeld, isTrue);
    await lock.release();
    expect(lock.isHeld, isFalse);

    final again = FileLock(lockPath);
    await again.acquire();
    expect(again.isHeld, isTrue);
    await again.release();
  });

  test('second holder is rejected while the first holds the lock', () async {
    final lockPath = p.join(tmp.path, 'lock');
    final first = FileLock(lockPath);
    await first.acquire();

    final second = FileLock(lockPath);
    await expectLater(second.acquire(), throwsA(isA<LockHeldException>()));

    await first.release();
  });

  test('withLock releases even when the action throws', () async {
    final lockPath = p.join(tmp.path, 'lock');
    final lock = FileLock(lockPath);
    await expectLater(
      lock.withLock(() async => throw StateError('boom')),
      throwsA(isA<StateError>()),
    );
    expect(lock.isHeld, isFalse);
  });

  test('a stale lock is reclaimed', () async {
    final lockPath = p.join(tmp.path, 'lock');
    final first = FileLock(lockPath, staleAfter: Duration.zero);
    await first.acquire();

    // With a zero staleness window, the existing lock is immediately stale.
    final second = FileLock(lockPath, staleAfter: Duration.zero);
    await second.acquire();
    expect(second.isHeld, isTrue);
    await second.release();
  });
}
