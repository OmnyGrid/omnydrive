import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
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

  group('transfer compression', () {
    // A raw client that does NOT auto-decompress, so we can inspect what the
    // content server actually puts on the wire.
    Future<HttpClientResponse> rawGet(String url) async {
      final client = HttpClient()..autoUncompress = false;
      addTearDown(() => client.close(force: true));
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
      return req.close();
    }

    test('a large compressible file is gzip-encoded on the wire', () async {
      final src = await TempDir.create();
      addTearDown(src.cleanup);
      final big = 'compress me ' * 2000; // well over minBytes, very repetitive.
      await src.writeFile('notes.txt', big);
      await publisher.publishDirectory(path: src.path, name: 'docs');

      final res = await rawGet('$contentUrl/drives/alpha/docs/files/notes.txt');
      expect(res.statusCode, 200);
      expect(res.headers.value('content-encoding'), 'gzip');

      final wire = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(wire.length, lessThan(big.length)); // actually smaller.
      expect(utf8.decode(gzip.decode(wire)), big); // and decodes back.
    });

    test('an already-compressed file is sent verbatim', () async {
      final src = await TempDir.create();
      addTearDown(src.cleanup);
      // .jpg in the incompressible set; bytes are large but not gzipped.
      await src.writeFile('photo.jpg', 'x' * 5000);
      await publisher.publishDirectory(path: src.path, name: 'docs');

      final res = await rawGet('$contentUrl/drives/alpha/docs/files/photo.jpg');
      expect(res.statusCode, 200);
      expect(res.headers.value('content-encoding'), isNull);
    });

    test(
      'a tiny file stays below the threshold and is not compressed',
      () async {
        final src = await TempDir.create();
        addTearDown(src.cleanup);
        await src.writeFile('small.txt', 'hi');
        await publisher.publishDirectory(path: src.path, name: 'docs');

        final res = await rawGet(
          '$contentUrl/drives/alpha/docs/files/small.txt',
        );
        expect(res.statusCode, 200);
        expect(res.headers.value('content-encoding'), isNull);
      },
    );

    test('a large file round-trips intact through the real client', () async {
      final src = await TempDir.create();
      addTearDown(src.cleanup);
      final big = 'lorem ipsum dolor ' * 3000;
      await src.writeFile('doc.txt', big);
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
      expect(File('$dest/doc.txt').readAsStringSync(), big);

      // Push a large edit back; the PUT body is gzip-encoded and decoded server-side.
      final edited = '$big tail';
      await File('$dest/doc.txt').writeAsString(edited);
      final result = await cloner.syncMount(mount.id.value);
      expect(result.status, SyncStatus.clean);
      expect(File('${src.path}/doc.txt').readAsStringSync(), edited);
    });

    test(
      'OmnyClient reads a large compressible file (regression: no double-decode)',
      () async {
        final src = await TempDir.create();
        addTearDown(src.cleanup);
        final big = 'omnyclient ' * 2000; // > 1 KiB, compressible
        await src.writeFile('big.txt', big);
        await src.writeFile('small.txt', 'hi');
        await publisher.publishDirectory(path: src.path, name: 'docs');

        final client = OmnyClient(hubUrl);
        addTearDown(client.close);
        final reg = (await client.drives()).firstWhere(
          (r) => r.id.value == 'alpha/docs',
        );
        final content = client.content(reg);

        // Manifest and a > 1 KiB file both come back gzip-encoded; before the
        // fix the shared auto-uncompress client double-decoded and threw.
        final manifest = await content.manifest();
        expect(
          manifest.sortedPaths,
          containsAll(<String>['big.txt', 'small.txt']),
        );
        expect(utf8.decode(await content.readBytes('big.txt')), big);
        expect(utf8.decode(await content.readBytes('small.txt')), 'hi');
      },
    );

    test(
      'reads correctly through an injected auto-uncompress http.Client',
      () async {
        final src = await TempDir.create();
        addTearDown(src.cleanup);
        final big = 'inject ' * 2000;
        await src.writeFile('doc.txt', big);
        await publisher.publishDirectory(path: src.path, name: 'docs');

        // A default http.Client() has autoUncompress = true: it decodes the body
        // but keeps the content-encoding header. The magic-byte guard must stop
        // _decoded from gunzipping the already-decoded bytes.
        final plain = http.Client();
        addTearDown(plain.close);
        final source = HttpContentSource(
          '$contentUrl/drives/alpha/docs',
          client: plain,
        );
        expect(utf8.decode(await source.readBytes('doc.txt')), big);
      },
    );

    test(
      'a server with compression disabled never sets content-encoding',
      () async {
        final off = await ContentServer(
          published,
          compression: ContentCompression.disabled,
        ).serve(address: '127.0.0.1', port: 0);
        addTearDown(() => off.close(force: true));
        final offUrl = 'http://127.0.0.1:${off.port}';

        final src = await TempDir.create();
        addTearDown(src.cleanup);
        await src.writeFile('notes.txt', 'compress me ' * 2000);
        await publisher.publishDirectory(path: src.path, name: 'docs');

        final res = await rawGet('$offUrl/drives/alpha/docs/files/notes.txt');
        expect(res.statusCode, 200);
        expect(res.headers.value('content-encoding'), isNull);
      },
    );

    test('a custom policy compresses below the default threshold', () async {
      final custom = await ContentServer(
        published,
        compression: ContentCompression(minBytes: 16),
      ).serve(address: '127.0.0.1', port: 0);
      addTearDown(() => custom.close(force: true));
      final customUrl = 'http://127.0.0.1:${custom.port}';

      final src = await TempDir.create();
      addTearDown(src.cleanup);
      final mid = 'a' * 64; // under the 1 KiB default, over the custom 16 B
      await src.writeFile('mid.txt', mid);
      await publisher.publishDirectory(path: src.path, name: 'docs');

      final res = await rawGet('$customUrl/drives/alpha/docs/files/mid.txt');
      expect(res.headers.value('content-encoding'), 'gzip');
      final wire = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(utf8.decode(gzip.decode(wire)), mid);
    });
  });

  group('compression for custom transports', () {
    test('a non-HTTP transport can use the ContentCompression toolkit', () async {
      // Mirrors what a custom ContentSource (e.g. omnyshell's channel transport)
      // does: compress at the sending edge, decompress at the receiving edge,
      // using only the public, HTTP-free toolkit.
      final wire = <String, List<int>>{};
      final gz = ContentCompression.standard;

      Future<void> send(String path, List<int> bytes) async {
        wire[path] = gz.shouldCompress(path, bytes.length)
            ? gz.encode(bytes)
            : bytes;
      }

      Future<List<int>> receive(String path) async {
        final bytes = wire[path]!;
        return ContentCompression.looksGzipped(bytes)
            ? ContentCompression.decode(bytes)
            : bytes;
      }

      final big = utf8.encode('payload ' * 2000); // > 1 KiB
      await send('doc.txt', big);
      expect(ContentCompression.looksGzipped(wire['doc.txt']!), isTrue);
      expect(wire['doc.txt']!.length, lessThan(big.length));
      expect(await receive('doc.txt'), equals(big));

      final tiny = utf8.encode('hi');
      await send('small.txt', tiny);
      expect(ContentCompression.looksGzipped(wire['small.txt']!), isFalse);
      expect(await receive('small.txt'), equals(tiny));
    });
  });
}
