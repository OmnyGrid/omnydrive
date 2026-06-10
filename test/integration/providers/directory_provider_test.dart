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
}
