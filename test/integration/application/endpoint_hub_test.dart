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
