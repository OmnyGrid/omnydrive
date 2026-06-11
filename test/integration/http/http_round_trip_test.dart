import 'dart:io';

import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

import '../../support/fixed_clock.dart';
import '../../support/temp_dir.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1);

  EndpointIdentity ident(String id, String baseUrl) => EndpointIdentity(
    id: EndpointId(id),
    displayName: id,
    baseUrl: baseUrl,
    capabilities: CapabilitySet([
      Capability.read,
      Capability.write,
      Capability.clone,
      Capability.mirror,
    ]),
    registeredAt: t0,
  );

  late HttpServer hubHttp;
  late HttpServer contentHttp;
  late String hubUrl;
  late String contentUrl;
  late InMemoryDriveRegistry
  published; // shared: endpoint writes, server reads.
  late LocalDriveEndpoint publisher;
  late LocalDriveEndpoint cloner;

  setUp(() async {
    final hub = LocalDriveHub(
      idGenerator: SequentialIdGenerator(),
      clock: FixedClock(t0),
    );
    hubHttp = await HubServer(hub).serve(address: '127.0.0.1', port: 0);
    hubUrl = 'http://127.0.0.1:${hubHttp.port}';

    published = InMemoryDriveRegistry();
    contentHttp = await ContentServer(
      published,
    ).serve(address: '127.0.0.1', port: 0);
    contentUrl = 'http://127.0.0.1:${contentHttp.port}';

    // Publisher: enrol + log in against the hub over HTTP, serve its own dir.
    final publisherHub = HttpDriveHub(hubUrl);
    final pEnroll = await publisherHub.enroll(
      identity: ident('alpha', contentUrl),
    );
    await publisherHub.login(
      endpointId: EndpointId('alpha'),
      secret: pEnroll.secret,
    );
    publisher = LocalDriveEndpoint(
      identity: pEnroll.identity,
      hub: publisherHub,
      published: published,
      providers: ProviderRegistry.local(endpoint: EndpointId('alpha')),
      idGenerator: SequentialIdGenerator(),
      clock: FixedClock(t0),
    );

    // Cloner: a separate endpoint resolving remote directory drives over HTTP.
    final clonerHub = HttpDriveHub(hubUrl);
    final cEnroll = await clonerHub.enroll(
      identity: ident('beta', 'http://beta.invalid'),
    );
    await clonerHub.login(
      endpointId: EndpointId('beta'),
      secret: cEnroll.secret,
    );
    cloner = LocalDriveEndpoint(
      identity: cEnroll.identity,
      hub: clonerHub,
      providers: networkedProviderRegistry(endpoint: EndpointId('beta')),
      idGenerator: SequentialIdGenerator(),
      clock: FixedClock(t0),
    );
  });

  tearDown(() async {
    await hubHttp.close(force: true);
    await contentHttp.close(force: true);
  });

  test('publish is discoverable through the HTTP hub client', () async {
    final src = await TempDir.create();
    addTearDown(src.cleanup);
    await src.writeFile('a.txt', 'A');

    final drive = await publisher.publishDirectory(
      path: src.path,
      name: 'docs',
    );
    expect(drive.id.value, 'alpha/docs');

    final listed = await cloner.hub.listDrives();
    expect(listed, hasLength(1));
    expect(listed.single.serveUrl, '$contentUrl/drives/alpha/docs');
  });

  test('clone fetches content from the remote content server', () async {
    final src = await TempDir.create();
    addTearDown(src.cleanup);
    await src.writeFile('readme.md', 'hello');
    await src.writeFile('nested/a.txt', 'A');
    final drive = await publisher.publishDirectory(
      path: src.path,
      name: 'docs',
    );

    final dst = await TempDir.create();
    addTearDown(dst.cleanup);
    final dest = dst.resolve('mirror');
    final mount = await cloner.cloneDrive(driveId: drive.id.value, dest: dest);

    expect(mount.driveId, drive.id);
    expect(File('$dest/readme.md').readAsStringSync(), 'hello');
    expect(File('$dest/nested/a.txt').readAsStringSync(), 'A');
  });

  test('editing the mirror pushes changes back over HTTP', () async {
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
    final mount = await cloner.cloneDrive(driveId: drive.id.value, dest: dest);

    await File('$dest/readme.md').writeAsString('hello world');
    await File('$dest/added.txt').writeAsString('new');

    final result = await cloner.syncMount(mount.id.value);
    expect(result.status, SyncStatus.clean);
    expect(File('${src.path}/readme.md').readAsStringSync(), 'hello world');
    expect(File('${src.path}/added.txt').readAsStringSync(), 'new');
  });

  test('a read-only clone pulls remote updates over HTTP', () async {
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
    final mount = await cloner.cloneDrive(
      driveId: drive.id.value,
      dest: dest,
      readOnly: true,
    );

    await src.writeFile('x.txt', '2');
    await src.writeFile('y.txt', 'new');

    final result = await cloner.syncMount(mount.id.value);
    expect(result.status, SyncStatus.clean);
    expect(File('$dest/x.txt').readAsStringSync(), '2');
    expect(File('$dest/y.txt').readAsStringSync(), 'new');
  });

  test('deleting a mirror file pushes the deletion over HTTP', () async {
    final src = await TempDir.create();
    addTearDown(src.cleanup);
    await src.writeFile('a.txt', 'A');
    await src.writeFile('b.txt', 'B');
    final drive = await publisher.publishDirectory(
      path: src.path,
      name: 'docs',
    );

    final dst = await TempDir.create();
    addTearDown(dst.cleanup);
    final dest = dst.resolve('mirror');
    final mount = await cloner.cloneDrive(driveId: drive.id.value, dest: dest);

    await File('$dest/a.txt').delete();

    final result = await cloner.syncMount(mount.id.value);
    expect(result.status, SyncStatus.clean);
    // The content server's DELETE route removed it from the origin.
    expect(File('${src.path}/a.txt').existsSync(), isFalse);
    expect(File('${src.path}/b.txt').readAsStringSync(), 'B');
  });

  test('an origin deletion is pulled into the mirror over HTTP', () async {
    final src = await TempDir.create();
    addTearDown(src.cleanup);
    await src.writeFile('a.txt', 'A');
    await src.writeFile('b.txt', 'B');
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
      readOnly: true,
    );

    await File('${src.path}/a.txt').delete();

    final result = await cloner.syncMount(mount.id.value);
    expect(result.status, SyncStatus.clean);
    expect(File('$dest/a.txt').existsSync(), isFalse);
    expect(File('$dest/b.txt').readAsStringSync(), 'B');
  });

  test('unauthenticated drive registration is rejected', () async {
    final anon = HttpDriveHub(hubUrl);
    final src = await TempDir.create();
    addTearDown(src.cleanup);
    final drive = Drive(
      id: DriveId.scoped(endpoint: EndpointId('alpha'), name: 'x'),
      name: 'x',
      provider: ProviderType.directory,
      originEndpoint: EndpointId('alpha'),
      originUri: OriginUri(src.path),
      accessMode: AccessMode.readWrite,
      capabilities: DriveCapabilities.forProvider(
        ProviderType.directory,
        AccessMode.readWrite,
      ),
      createdAt: t0,
    );
    expect(
      () => anon.registerDrive(
        DriveRegistration(
          drive: drive,
          servingEndpoint: EndpointId('alpha'),
          serveUrl: '$contentUrl/drives/alpha/x',
          registeredAt: t0,
        ),
      ),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('the hub reports its version', () async {
    // /version is not part of the DriveHub contract; hit the route directly.
    final request = await HttpClient().getUrl(Uri.parse('$hubUrl/version'));
    final response = await request.close();
    expect(response.statusCode, 200);
  });
}
