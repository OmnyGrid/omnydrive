import 'dart:io';

import 'package:omnydrive/omnydrive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/temp_dir.dart';

void main() {
  late TempDir origin;
  late TempDir work;
  late DirectoryProvider provider;

  setUp(() async {
    origin = await TempDir.create('omnydrive_origin_');
    work = await TempDir.create('omnydrive_work_');
    provider = DirectoryProvider(endpoint: EndpointId('nas'));
    await origin.writeFile('readme.md', 'hello');
    await origin.writeFile('src/main.dart', 'void main() {}');
  });

  tearDown(() async {
    await origin.cleanup();
    await work.cleanup();
  });

  OriginUri originUri() => OriginUri(origin.path);

  // --- Helpers to keep the change-type matrix DRY --------------------------

  /// Materializes a read-write mirror of the origin and returns the pieces a
  /// sync needs: the drive, the mirror path, and the baseline ref.
  Future<({Drive drive, LocalPath dest, SyncRef baseline})>
  materializeMirror() async {
    final drive = await provider.describe(
      originUri(),
      accessMode: AccessMode.readWrite,
    );
    final dest = LocalPath(p.join(work.path, 'mirror'));
    await provider.materialize(
      drive: drive,
      dest: dest,
      mountType: MountType.mirror,
    );
    final baseline = await provider.currentRef(originUri());
    return (drive: drive, dest: dest, baseline: baseline);
  }

  MountInfo mountAt(Drive drive, LocalPath dest, SyncRef baseline) => MountInfo(
    id: MountId('m1'),
    driveId: drive.id,
    localPath: dest,
    accessMode: AccessMode.readWrite,
    mountType: MountType.mirror,
    mountedAt: DateTime.utc(2026),
    syncState: SyncState(baselineRef: baseline),
  );

  /// Plans and applies a sync in [direction] for a materialized [mirror].
  Future<SyncResult> runSync(
    ({Drive drive, LocalPath dest, SyncRef baseline}) mirror,
    SyncDirection direction,
  ) async {
    final sync = provider.synchronizer(mirror.drive);
    final mount = mountAt(mirror.drive, mirror.dest, mirror.baseline);
    final plan = await sync.plan(
      mount: mount,
      baseline: mirror.baseline,
      direction: direction,
    );
    return sync.apply(mount: mount, plan: plan, baseline: mirror.baseline);
  }

  String originFile(String rel) => p.join(origin.path, rel);
  String destFile(LocalPath dest, String rel) => p.join(dest.value, rel);

  test('describe derives drive metadata from the directory', () async {
    final drive = await provider.describe(
      originUri(),
      accessMode: AccessMode.readWrite,
    );
    expect(drive.provider, ProviderType.directory);
    expect(drive.capabilities.canWrite, isTrue);
    expect(drive.id.endpoint, EndpointId('nas'));
  });

  test('currentRef is stable and content-addressed', () async {
    final ref1 = await provider.currentRef(originUri());
    final ref2 = await provider.currentRef(originUri());
    expect(ref1, ref2);

    await origin.writeFile('readme.md', 'changed');
    final ref3 = await provider.currentRef(originUri());
    expect(ref3, isNot(ref1));
  });

  test('materialize mirror copies all files locally', () async {
    final drive = await provider.describe(
      originUri(),
      accessMode: AccessMode.readWrite,
    );
    final dest = LocalPath(p.join(work.path, 'mirror'));
    final mounted = await provider.materialize(
      drive: drive,
      dest: dest,
      mountType: MountType.mirror,
    );

    expect(File(p.join(dest.value, 'readme.md')).existsSync(), isTrue);
    expect(File(p.join(dest.value, 'src/main.dart')).existsSync(), isTrue);
    expect(await mounted.localRef(), await provider.currentRef(originUri()));
  });

  test('push uploads local changes when origin is unchanged', () async {
    final drive = await provider.describe(
      originUri(),
      accessMode: AccessMode.readWrite,
    );
    final dest = LocalPath(p.join(work.path, 'mirror'));
    await provider.materialize(
      drive: drive,
      dest: dest,
      mountType: MountType.mirror,
    );
    final baseline = await provider.currentRef(originUri());

    // Modify the local mirror.
    await File(p.join(dest.value, 'readme.md')).writeAsString('edited');

    final sync = provider.synchronizer(drive);
    final mount = MountInfo(
      id: MountId('m1'),
      driveId: drive.id,
      localPath: dest,
      accessMode: AccessMode.readWrite,
      mountType: MountType.mirror,
      mountedAt: DateTime.utc(2026),
      syncState: SyncState(baselineRef: baseline),
    );
    final plan = await sync.plan(
      mount: mount,
      baseline: baseline,
      direction: SyncDirection.push,
    );
    expect(plan.changedPaths, contains('readme.md'));

    final result = await sync.apply(
      mount: mount,
      plan: plan,
      baseline: baseline,
    );
    expect(result.appliedChanges, greaterThan(0));
    expect(File(p.join(origin.path, 'readme.md')).readAsStringSync(), 'edited');
  });

  test('push throws ConflictDetectedException when origin moved', () async {
    final drive = await provider.describe(
      originUri(),
      accessMode: AccessMode.readWrite,
    );
    final dest = LocalPath(p.join(work.path, 'mirror'));
    await provider.materialize(
      drive: drive,
      dest: dest,
      mountType: MountType.mirror,
    );
    final baseline = await provider.currentRef(originUri());

    // Local change.
    await File(p.join(dest.value, 'readme.md')).writeAsString('local-edit');
    // Concurrent origin change — moves the source ref away from baseline.
    await origin.writeFile('other.txt', 'origin-edit');

    final sync = provider.synchronizer(drive);
    final mount = MountInfo(
      id: MountId('m1'),
      driveId: drive.id,
      localPath: dest,
      accessMode: AccessMode.readWrite,
      mountType: MountType.mirror,
      mountedAt: DateTime.utc(2026),
      syncState: SyncState(baselineRef: baseline),
    );
    final plan = await sync.plan(
      mount: mount,
      baseline: baseline,
      direction: SyncDirection.push,
    );
    expect(plan.requiresConflictResolution, isTrue);

    await expectLater(
      sync.apply(mount: mount, plan: plan, baseline: baseline),
      throwsA(isA<ConflictDetectedException>()),
    );
  });

  test('push emits a per-file progress event for every change', () async {
    final drive = await provider.describe(
      originUri(),
      accessMode: AccessMode.readWrite,
    );
    final dest = LocalPath(p.join(work.path, 'mirror'));
    await provider.materialize(
      drive: drive,
      dest: dest,
      mountType: MountType.mirror,
    );
    final baseline = await provider.currentRef(originUri());

    // One added, one modified, one removed → 3 changed paths.
    await File(p.join(dest.value, 'added.txt')).writeAsString('new');
    await File(p.join(dest.value, 'readme.md')).writeAsString('edited');
    await File(p.join(dest.value, 'src/main.dart')).delete();

    final sync = provider.synchronizer(drive);
    final mount = MountInfo(
      id: MountId('m1'),
      driveId: drive.id,
      localPath: dest,
      accessMode: AccessMode.readWrite,
      mountType: MountType.mirror,
      mountedAt: DateTime.utc(2026),
      syncState: SyncState(baselineRef: baseline),
    );
    final plan = await sync.plan(
      mount: mount,
      baseline: baseline,
      direction: SyncDirection.push,
    );

    final events = <ProgressEvent>[];
    await sync.apply(
      mount: mount,
      plan: plan,
      baseline: baseline,
      progress: ProgressReporter((e) => events.add(e)),
    );

    final perFile = events
        .where(
          (e) => e.phase == ProgressPhase.transferring && e.message.isNotEmpty,
        )
        .toList();
    expect(perFile, hasLength(3));
    expect(
      perFile.map((e) => e.completed).toList(),
      [1, 2, 3],
      reason: 'completed should increase by one per file',
    );
    expect(perFile.last.completed, perFile.last.total);
    expect(events.last.phase, ProgressPhase.done);

    // The changes are actually propagated to the origin, not just reported.
    expect(File(p.join(origin.path, 'added.txt')).readAsStringSync(), 'new');
    expect(File(p.join(origin.path, 'readme.md')).readAsStringSync(), 'edited');
    expect(File(p.join(origin.path, 'src/main.dart')).existsSync(), isFalse);
  });

  test('pull emits a per-file progress event for every change', () async {
    final drive = await provider.describe(
      originUri(),
      accessMode: AccessMode.readWrite,
    );
    final dest = LocalPath(p.join(work.path, 'mirror'));
    await provider.materialize(
      drive: drive,
      dest: dest,
      mountType: MountType.mirror,
    );
    final baseline = await provider.currentRef(originUri());

    // One added, one modified, one removed on the origin → 3 changed paths.
    await origin.writeFile('added.txt', 'new');
    await origin.writeFile('readme.md', 'edited');
    await File(p.join(origin.path, 'src/main.dart')).delete();

    final sync = provider.synchronizer(drive);
    final mount = MountInfo(
      id: MountId('m1'),
      driveId: drive.id,
      localPath: dest,
      accessMode: AccessMode.readWrite,
      mountType: MountType.mirror,
      mountedAt: DateTime.utc(2026),
      syncState: SyncState(baselineRef: baseline),
    );
    final plan = await sync.plan(
      mount: mount,
      baseline: baseline,
      direction: SyncDirection.pull,
    );

    final events = <ProgressEvent>[];
    await sync.apply(
      mount: mount,
      plan: plan,
      baseline: baseline,
      progress: ProgressReporter((e) => events.add(e)),
    );

    final perFile = events
        .where(
          (e) => e.phase == ProgressPhase.transferring && e.message.isNotEmpty,
        )
        .toList();
    expect(perFile, hasLength(3));
    expect(
      perFile.map((e) => e.completed).toList(),
      [1, 2, 3],
      reason: 'completed should increase by one per file',
    );
    expect(perFile.last.completed, perFile.last.total);
    expect(events.last.phase, ProgressPhase.done);

    // The changes actually land in the mirror, not just reported.
    expect(File(p.join(dest.value, 'added.txt')).readAsStringSync(), 'new');
    expect(File(p.join(dest.value, 'readme.md')).readAsStringSync(), 'edited');
    expect(File(p.join(dest.value, 'src/main.dart')).existsSync(), isFalse);
  });

  test('pull brings origin changes into the local mirror', () async {
    final drive = await provider.describe(
      originUri(),
      accessMode: AccessMode.readWrite,
    );
    final dest = LocalPath(p.join(work.path, 'mirror'));
    await provider.materialize(
      drive: drive,
      dest: dest,
      mountType: MountType.mirror,
    );
    final baseline = await provider.currentRef(originUri());

    await origin.writeFile('new.txt', 'fresh');

    final sync = provider.synchronizer(drive);
    final mount = MountInfo(
      id: MountId('m1'),
      driveId: drive.id,
      localPath: dest,
      accessMode: AccessMode.readWrite,
      mountType: MountType.mirror,
      mountedAt: DateTime.utc(2026),
      syncState: SyncState(baselineRef: baseline),
    );
    final plan = await sync.plan(
      mount: mount,
      baseline: baseline,
      direction: SyncDirection.pull,
    );
    await sync.apply(mount: mount, plan: plan, baseline: baseline);
    expect(File(p.join(dest.value, 'new.txt')).readAsStringSync(), 'fresh');
  });

  // Change-type matrix: each kind of change (add / modify / delete, top-level
  // and nested) propagated through an explicit push and pull, asserting the
  // actual file state on the target side.
  group('push (local mirror → origin)', () {
    test('adds a new file to the origin', () async {
      final m = await materializeMirror();
      await File(destFile(m.dest, 'added.txt')).writeAsString('new');
      await runSync(m, SyncDirection.push);
      expect(File(originFile('added.txt')).readAsStringSync(), 'new');
    });

    test('modifies an existing file on the origin', () async {
      final m = await materializeMirror();
      await File(destFile(m.dest, 'readme.md')).writeAsString('edited');
      await runSync(m, SyncDirection.push);
      expect(File(originFile('readme.md')).readAsStringSync(), 'edited');
    });

    test('deletes a removed file from the origin', () async {
      final m = await materializeMirror();
      await File(destFile(m.dest, 'readme.md')).delete();
      await runSync(m, SyncDirection.push);
      expect(File(originFile('readme.md')).existsSync(), isFalse);
      // Untouched files are preserved.
      expect(File(originFile('src/main.dart')).existsSync(), isTrue);
    });

    test('modifies a nested file on the origin', () async {
      final m = await materializeMirror();
      await File(
        destFile(m.dest, 'src/main.dart'),
      ).writeAsString('void m() {}');
      await runSync(m, SyncDirection.push);
      expect(
        File(originFile('src/main.dart')).readAsStringSync(),
        'void m() {}',
      );
    });

    test('deletes a nested file from the origin', () async {
      final m = await materializeMirror();
      await File(destFile(m.dest, 'src/main.dart')).delete();
      await runSync(m, SyncDirection.push);
      expect(File(originFile('src/main.dart')).existsSync(), isFalse);
    });
  });

  group('pull (origin → local mirror)', () {
    test('adds a new origin file into the mirror', () async {
      final m = await materializeMirror();
      await origin.writeFile('added.txt', 'new');
      await runSync(m, SyncDirection.pull);
      expect(File(destFile(m.dest, 'added.txt')).readAsStringSync(), 'new');
    });

    test('modifies an existing file in the mirror', () async {
      final m = await materializeMirror();
      await origin.writeFile('readme.md', 'edited');
      await runSync(m, SyncDirection.pull);
      expect(File(destFile(m.dest, 'readme.md')).readAsStringSync(), 'edited');
    });

    test('deletes a removed origin file from the mirror', () async {
      final m = await materializeMirror();
      await File(originFile('readme.md')).delete();
      await runSync(m, SyncDirection.pull);
      expect(File(destFile(m.dest, 'readme.md')).existsSync(), isFalse);
      // Untouched files are preserved.
      expect(File(destFile(m.dest, 'src/main.dart')).existsSync(), isTrue);
    });

    test('modifies a nested file in the mirror', () async {
      final m = await materializeMirror();
      await origin.writeFile('src/main.dart', 'void m() {}');
      await runSync(m, SyncDirection.pull);
      expect(
        File(destFile(m.dest, 'src/main.dart')).readAsStringSync(),
        'void m() {}',
      );
    });

    test('deletes a nested origin file from the mirror', () async {
      final m = await materializeMirror();
      await File(originFile('src/main.dart')).delete();
      await runSync(m, SyncDirection.pull);
      expect(File(destFile(m.dest, 'src/main.dart')).existsSync(), isFalse);
    });
  });
}
