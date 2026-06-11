import 'dart:io';

import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

import '../../support/fixed_clock.dart';
import '../../support/temp_dir.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1);

  EndpointIdentity ident(String id) => EndpointIdentity(
    id: EndpointId(id),
    displayName: id,
    baseUrl: 'http://$id.local',
    capabilities: CapabilitySet([
      Capability.read,
      Capability.write,
      Capability.clone,
      Capability.mirror,
    ]),
    registeredAt: t0,
  );

  // Point peers straight at the publisher's local origin path, so the
  // application orchestration can be exercised without an HTTP content server.
  String localServe(EndpointIdentity self, Drive drive) =>
      drive.originUri.value;

  late LocalDriveHub hub;
  late LocalDriveEndpoint publisher;
  late LocalDriveEndpoint cloner;
  var driveSeq = 0;

  setUp(() async {
    hub = LocalDriveHub(
      idGenerator: SequentialIdGenerator(),
      clock: FixedClock(t0),
    );
    await hub.enroll(identity: ident('alpha'));
    await hub.enroll(identity: ident('beta'));
    publisher = LocalDriveEndpoint(
      identity: ident('alpha'),
      hub: hub,
      idGenerator: SequentialIdGenerator(),
      clock: FixedClock(t0),
      serveUrl: localServe,
    );
    cloner = LocalDriveEndpoint(
      identity: ident('beta'),
      hub: hub,
      idGenerator: SequentialIdGenerator(),
      clock: FixedClock(t0),
      serveUrl: localServe,
    );
  });

  // Publishes a seeded origin and clones it, returning the origin dir, the
  // mirror path, and the mount — the pieces every sync case needs.
  Future<({TempDir src, String dest, MountInfo mount})> mirror(
    Map<String, String> seed, {
    bool readOnly = false,
  }) async {
    final src = await TempDir.create();
    addTearDown(src.cleanup);
    for (final entry in seed.entries) {
      await src.writeFile(entry.key, entry.value);
    }
    final drive = await publisher.publishDirectory(
      path: src.path,
      name: 'd${driveSeq++}',
    );
    final dst = await TempDir.create();
    addTearDown(dst.cleanup);
    final dest = dst.resolve('mirror');
    final mount = await cloner.cloneDrive(
      driveId: drive.id.value,
      dest: dest,
      readOnly: readOnly,
    );
    return (src: src, dest: dest, mount: mount);
  }

  test('publish makes a drive discoverable on the hub', () async {
    final src = await TempDir.create();
    addTearDown(src.cleanup);
    await src.writeFile('readme.md', 'hello');

    final drive = await publisher.publishDirectory(
      path: src.path,
      name: 'docs',
    );
    expect(drive.id.value, 'alpha/docs');

    final listed = await hub.listDrives();
    expect(listed, hasLength(1));
    expect(listed.single.servingEndpoint, EndpointId('alpha'));
  });

  test('clone mirrors origin content to the destination', () async {
    final src = await TempDir.create();
    addTearDown(src.cleanup);
    await src.writeFile('readme.md', 'hello');
    await src.writeFile('docs/a.txt', 'A');
    final drive = await publisher.publishDirectory(
      path: src.path,
      name: 'docs',
    );

    final dst = await TempDir.create();
    addTearDown(dst.cleanup);
    final dest = dst.resolve('mirror');
    final mount = await cloner.cloneDrive(driveId: drive.id.value, dest: dest);

    expect(mount.driveId, drive.id);
    expect(mount.mountType, MountType.mirror);
    expect(File('$dest/readme.md').readAsStringSync(), 'hello');
    expect(File('$dest/docs/a.txt').readAsStringSync(), 'A');
  });

  test(
    'editing a read-write mirror pushes changes back to the origin',
    () async {
      final src = await TempDir.create();
      addTearDown(src.cleanup);
      await src.writeFile('readme.md', 'hello');
      final drive = await publisher.publishDirectory(
        path: src.path,
        name: 'docs',
      );

      final dst = await TempDir.create();
      addTearDown(dst.cleanup);
      final dest = dst.resolve('mirror');
      final mount = await cloner.cloneDrive(
        driveId: drive.id.value,
        dest: dest,
      );

      await File('$dest/readme.md').writeAsString('hello world');
      await File('$dest/extra.txt').writeAsString('B');

      final result = await cloner.syncMount(mount.id.value);
      expect(result.status, SyncStatus.clean);
      expect(File('${src.path}/readme.md').readAsStringSync(), 'hello world');
      expect(File('${src.path}/extra.txt').readAsStringSync(), 'B');
    },
  );

  test('syncing an unchanged mirror is a clean no-op', () async {
    final src = await TempDir.create();
    addTearDown(src.cleanup);
    await src.writeFile('x.txt', '1');
    final drive = await publisher.publishDirectory(
      path: src.path,
      name: 'docs',
    );

    final dst = await TempDir.create();
    addTearDown(dst.cleanup);
    final dest = dst.resolve('mirror');
    final mount = await cloner.cloneDrive(driveId: drive.id.value, dest: dest);

    final result = await cloner.syncMount(mount.id.value);
    expect(result.status, SyncStatus.clean);
    expect(result.appliedChanges, 0);
  });

  test('a read-only clone pulls origin updates', () async {
    final src = await TempDir.create();
    addTearDown(src.cleanup);
    await src.writeFile('x.txt', '1');
    final drive = await publisher.publishDirectory(path: src.path, name: 'ro');

    final dst = await TempDir.create();
    addTearDown(dst.cleanup);
    final dest = dst.resolve('mirror');
    final mount = await cloner.cloneDrive(
      driveId: drive.id.value,
      dest: dest,
      readOnly: true,
    );
    expect(mount.accessMode, AccessMode.readOnly);

    await src.writeFile('x.txt', '2');
    await src.writeFile('y.txt', 'new');

    final result = await cloner.syncMount(mount.id.value);
    expect(result.status, SyncStatus.clean);
    expect(File('$dest/x.txt').readAsStringSync(), '2');
    expect(File('$dest/y.txt').readAsStringSync(), 'new');
  });

  test('a divergent push raises ConflictDetectedException', () async {
    final src = await TempDir.create();
    addTearDown(src.cleanup);
    await src.writeFile('f.txt', 'base');
    final drive = await publisher.publishDirectory(path: src.path, name: 'c');

    final dst = await TempDir.create();
    addTearDown(dst.cleanup);
    final dest = dst.resolve('mirror');
    final mount = await cloner.cloneDrive(driveId: drive.id.value, dest: dest);

    // Origin moves away from the baseline while the mirror also changes.
    await src.writeFile('f.txt', 'origin-change');
    await File('$dest/f.txt').writeAsString('local-change');

    expect(
      () => cloner.syncMount(mount.id.value),
      throwsA(isA<ConflictDetectedException>()),
    );
  });

  test(
    'creating a new file in a read-write mirror pushes it to the origin',
    () async {
      final src = await TempDir.create();
      addTearDown(src.cleanup);
      await src.writeFile('a.txt', 'A');
      final drive = await publisher.publishDirectory(path: src.path, name: 'd');

      final dst = await TempDir.create();
      addTearDown(dst.cleanup);
      final dest = dst.resolve('mirror');
      final mount = await cloner.cloneDrive(
        driveId: drive.id.value,
        dest: dest,
      );

      // A brand-new file appears only on the mirror side.
      await File('$dest/f1.txt').writeAsString('fresh');

      final result = await cloner.syncMount(mount.id.value);
      expect(result.status, SyncStatus.clean);
      // The new file is uploaded, not discarded, and survives on both sides.
      expect(File('${src.path}/f1.txt').readAsStringSync(), 'fresh');
      expect(File('$dest/f1.txt').readAsStringSync(), 'fresh');
    },
  );

  test(
    'a read-only mirror with local edits conflicts instead of deleting them',
    () async {
      final src = await TempDir.create();
      addTearDown(src.cleanup);
      await src.writeFile('a.txt', 'A');
      final drive = await publisher.publishDirectory(
        path: src.path,
        name: 'ro',
      );

      final dst = await TempDir.create();
      addTearDown(dst.cleanup);
      final dest = dst.resolve('mirror');
      final mount = await cloner.cloneDrive(
        driveId: drive.id.value,
        dest: dest,
        readOnly: true,
      );
      expect(mount.accessMode, AccessMode.readOnly);

      // A new file is created on the (read-only) mirror side.
      await File('$dest/f1.txt').writeAsString('fresh');

      // Syncing must refuse rather than silently delete the local-only file.
      await expectLater(
        () => cloner.syncMount(mount.id.value),
        throwsA(isA<ConflictDetectedException>()),
      );
      expect(File('$dest/f1.txt').existsSync(), isTrue);
      expect(File('$dest/f1.txt').readAsStringSync(), 'fresh');
    },
  );

  test(
    'deleting a file in a read-write mirror removes it from the origin',
    () async {
      final m = await mirror({'a.txt': 'A', 'b.txt': 'B'});
      await File('${m.dest}/a.txt').delete();

      final result = await cloner.syncMount(m.mount.id.value);
      expect(result.status, SyncStatus.clean);
      expect(File('${m.src.path}/a.txt').existsSync(), isFalse);
      expect(File('${m.src.path}/b.txt').readAsStringSync(), 'B');
    },
  );

  test('a read-write mirror pulls an origin edit when it is clean', () async {
    final m = await mirror({'a.txt': 'A'});
    await m.src.writeFile('a.txt', 'A2');

    final result = await cloner.syncMount(m.mount.id.value);
    expect(result.status, SyncStatus.clean);
    expect(File('${m.dest}/a.txt').readAsStringSync(), 'A2');
  });

  test(
    'a read-write mirror pulls an origin deletion when it is clean',
    () async {
      final m = await mirror({'a.txt': 'A', 'b.txt': 'B'});
      await File('${m.src.path}/a.txt').delete();

      final result = await cloner.syncMount(m.mount.id.value);
      expect(result.status, SyncStatus.clean);
      expect(File('${m.dest}/a.txt').existsSync(), isFalse);
      expect(File('${m.dest}/b.txt').readAsStringSync(), 'B');
    },
  );

  test('a read-only mirror pulls an origin deletion', () async {
    final m = await mirror({'a.txt': 'A', 'b.txt': 'B'}, readOnly: true);
    await File('${m.src.path}/a.txt').delete();

    final result = await cloner.syncMount(m.mount.id.value);
    expect(result.status, SyncStatus.clean);
    expect(File('${m.dest}/a.txt').existsSync(), isFalse);
    expect(File('${m.dest}/b.txt').readAsStringSync(), 'B');
  });

  test(
    'a read-only mirror with a local edit conflicts and keeps the edit',
    () async {
      final m = await mirror({'a.txt': 'A'}, readOnly: true);
      await File('${m.dest}/a.txt').writeAsString('local-edit');

      await expectLater(
        () => cloner.syncMount(m.mount.id.value),
        throwsA(isA<ConflictDetectedException>()),
      );
      // The local edit is preserved, not reverted to the origin.
      expect(File('${m.dest}/a.txt').readAsStringSync(), 'local-edit');
    },
  );

  test('a read-only mirror with a local deletion conflicts and preserves both '
      'sides', () async {
    final m = await mirror({'a.txt': 'A', 'b.txt': 'B'}, readOnly: true);
    await File('${m.dest}/a.txt').delete();

    await expectLater(
      () => cloner.syncMount(m.mount.id.value),
      throwsA(isA<ConflictDetectedException>()),
    );
    // The origin keeps the file; the mount is not silently re-synced.
    expect(File('${m.src.path}/a.txt').readAsStringSync(), 'A');
    expect(File('${m.dest}/a.txt').existsSync(), isFalse);
  });

  test('changes on both sides conflict without losing either side', () async {
    final m = await mirror({'base.txt': 'base'});
    await File('${m.dest}/local.txt').writeAsString('L'); // local add
    await m.src.writeFile('origin.txt', 'O'); // origin add

    await expectLater(
      () => cloner.syncMount(m.mount.id.value),
      throwsA(isA<ConflictDetectedException>()),
    );
    expect(File('${m.dest}/local.txt').readAsStringSync(), 'L');
    expect(File('${m.src.path}/origin.txt').readAsStringSync(), 'O');
  });

  test('syncing an unchanged read-only mirror is a clean no-op', () async {
    final m = await mirror({'a.txt': 'A'}, readOnly: true);

    final result = await cloner.syncMount(m.mount.id.value);
    expect(result.status, SyncStatus.clean);
    expect(result.appliedChanges, 0);
  });

  test('cloning an unknown drive throws NotFoundException', () async {
    final dst = await TempDir.create();
    addTearDown(dst.cleanup);
    expect(
      () => cloner.cloneDrive(driveId: 'alpha/ghost', dest: dst.resolve('m')),
      throwsA(isA<NotFoundException>()),
    );
  });

  test('syncing an unknown mount throws NotFoundException', () async {
    expect(
      () => cloner.syncMount('mount_999'),
      throwsA(isA<NotFoundException>()),
    );
  });
}
