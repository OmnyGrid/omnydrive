import 'package:omnydrive/omnydrive.dart'
    show
        ContentServer,
        HubServer,
        InMemoryDriveRegistry,
        LocalDriveEndpoint,
        LocalDriveHub,
        ProviderRegistry,
        SequentialIdGenerator;
import 'package:omnydrive/omnydrive_client.dart';
import 'package:omnyhub/omnyhub.dart' show OmnyHub;
import 'package:test/test.dart';

import '../../support/fixed_clock.dart';
import '../../support/temp_dir.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1);

  late OmnyHub hubHttp;
  late OmnyHub contentHttp;
  late String hubUrl;
  late String contentUrl;
  late InMemoryDriveRegistry published;
  late LocalDriveEndpoint publisher;

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

    final publisherHub = OmnyClient(hubUrl);
    final identity = EndpointIdentity(
      id: EndpointId('alpha'),
      displayName: 'alpha',
      baseUrl: contentUrl,
      capabilities: CapabilitySet([Capability.read, Capability.write]),
      registeredAt: t0,
    );
    final creds = await publisherHub.enroll(identity: identity);
    await publisherHub.login(endpointId: identity.id, secret: creds.secret);
    publisher = LocalDriveEndpoint(
      identity: identity,
      hub: publisherHub.hub,
      published: published,
      providers: ProviderRegistry.local(endpoint: EndpointId('alpha')),
      idGenerator: SequentialIdGenerator(),
      clock: FixedClock(t0),
    );

    final src = await TempDir.create();
    addTearDown(src.cleanup);
    await src.writeFile('readme.md', 'hello');
    await publisher.publishDirectory(path: src.path, name: 'docs');
  });

  tearDown(() async {
    await hubHttp.stop();
    await contentHttp.stop();
  });

  test('lists drives and reads content through OmnyClient', () async {
    final client = OmnyClient(hubUrl);
    addTearDown(client.close);

    final drives = await client.drives();
    expect(drives, hasLength(1));
    expect(drives.single.id, DriveId('alpha/docs'));

    final reg = await client.drive(DriveId('alpha/docs'));
    final source = client.content(reg);
    final manifest = await source.manifest();
    expect(manifest.sortedPaths, ['readme.md']);

    final bytes = await source.readBytes('readme.md');
    expect(String.fromCharCodes(bytes), 'hello');
  });

  test('reading a missing drive surfaces NotFoundException', () async {
    final client = OmnyClient(hubUrl);
    addTearDown(client.close);
    expect(
      () => client.drive(DriveId('alpha/missing')),
      throwsA(isA<NotFoundException>()),
    );
  });

  test('writing through a read-only content source is denied', () async {
    final client = OmnyClient(hubUrl);
    addTearDown(client.close);
    final reg = await client.drive(DriveId('alpha/docs'));
    final source = client.content(reg); // writable: false
    expect(
      () => source.writeBytes('x.txt', [1, 2, 3]),
      throwsA(isA<AccessDeniedException>()),
    );
  });
}
