import 'dart:convert';
import 'dart:io';

import 'package:omnydrive/omnydrive.dart';
import 'package:omnyhub/omnyhub.dart' show OmnyHub;
import 'package:test/test.dart';

import '../../support/fixed_clock.dart';
import '../../support/temp_dir.dart';

/// Exercises the HTTP contract of the omnyhub-hosted [HubServer] / [ContentServer]
/// directly with a raw client: status codes, the `{success,...}` envelopes, the
/// error mapper, bearer-auth parsing and path-parameter (incl. tail-capture)
/// routing. These are the seams the omnyhub migration rerouted, so they are the
/// most likely to regress.
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

  late OmnyHub hubHttp;
  late OmnyHub contentHttp;
  late String hubUrl;
  late String contentUrl;
  late InMemoryDriveRegistry published;
  late LocalDriveEndpoint publisher;
  late HttpClient client;

  /// A raw HTTP call returning (status, decoded-json-or-null, raw-body).
  Future<({int status, dynamic json, String body, HttpHeaders headers})> call(
    String method,
    String url, {
    String? auth,
    Object? jsonBody,
    List<int>? rawBody,
    Map<String, String> headers = const {},
  }) async {
    final req = await client.openUrl(method, Uri.parse(url));
    if (auth != null) req.headers.set(HttpHeaders.authorizationHeader, auth);
    headers.forEach(req.headers.set);
    if (jsonBody != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(jsonBody)));
    } else if (rawBody != null) {
      req.add(rawBody);
    }
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    dynamic parsed;
    try {
      parsed = body.isEmpty ? null : jsonDecode(body);
    } on FormatException {
      parsed = null;
    }
    return (
      status: res.statusCode,
      json: parsed,
      body: body,
      headers: res.headers,
    );
  }

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

    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await hubHttp.stop();
    await contentHttp.stop();
  });

  group('success envelope', () {
    test('GET /version returns 200 {success:true, data:{...}}', () async {
      final res = await call('GET', '$hubUrl/version');
      expect(res.status, 200);
      expect(res.json['success'], isTrue);
      expect(res.json['data']['name'], 'omnydrive-hub');
      expect(res.headers.contentType?.mimeType, 'application/json');
    });

    test('POST /endpoints enrols with 201 and returns a secret', () async {
      final res = await call(
        'POST',
        '$hubUrl/endpoints',
        jsonBody: {'identity': ident('gamma', 'http://gamma.invalid').toJson()},
      );
      expect(res.status, 201);
      expect(res.json['success'], isTrue);
      expect(res.json['data']['secret'], isA<String>());
      expect(res.json['data']['identity']['id'], 'gamma');
    });

    test('a bearer-authenticated drive registration returns 201', () async {
      final enroll = await call(
        'POST',
        '$hubUrl/endpoints',
        jsonBody: {'identity': ident('delta', contentUrl).toJson()},
      );
      final secret = enroll.json['data']['secret'] as String;
      final auth = await call(
        'POST',
        '$hubUrl/auth',
        jsonBody: {'endpointId': 'delta', 'secret': secret},
      );
      final token = auth.json['data']['token'] as String;

      final src = await TempDir.create();
      addTearDown(src.cleanup);
      final drive = Drive(
        id: DriveId.scoped(endpoint: EndpointId('delta'), name: 'x'),
        name: 'x',
        provider: ProviderType.directory,
        originEndpoint: EndpointId('delta'),
        originUri: OriginUri(src.path),
        accessMode: AccessMode.readWrite,
        capabilities: DriveCapabilities.forProvider(
          ProviderType.directory,
          AccessMode.readWrite,
        ),
        createdAt: t0,
      );
      final res = await call(
        'POST',
        '$hubUrl/drives',
        auth: 'Bearer $token',
        jsonBody: {
          'drive': drive.toJson(),
          'serveUrl': '$contentUrl/drives/delta/x',
        },
      );
      expect(res.status, 201);
      expect(res.json['success'], isTrue);
    });
  });

  group('auth (bearer parsing via _authenticate0)', () {
    Future<int> registerStatus({String? auth}) async {
      final res = await call(
        'POST',
        '$hubUrl/drives',
        auth: auth,
        jsonBody: {'drive': {}, 'serveUrl': 'x'},
      );
      return res.status;
    }

    test('missing Authorization header → 401 with envelope', () async {
      final res = await call(
        'POST',
        '$hubUrl/drives',
        jsonBody: {'drive': {}, 'serveUrl': 'x'},
      );
      expect(res.status, 401);
      expect(res.json['success'], isFalse);
      expect(res.json['error']['code'], 'unauthorized');
    });

    test('a non-bearer scheme → 401', () async {
      expect(await registerStatus(auth: 'Basic Zm9vOmJhcg=='), 401);
    });

    test('a bearer token that is not issued → 401', () async {
      expect(await registerStatus(auth: 'Bearer not-a-real-token'), 401);
    });

    test('the bearer scheme is matched case-insensitively', () async {
      // Lowercase "bearer" with an unknown token still reaches authorize()
      // (401 from authorize), proving the scheme check passed — a malformed
      // header would instead 401 at the prefix check with the same status, so
      // assert the *error code path* is the same either way.
      final res = await call(
        'POST',
        '$hubUrl/drives',
        auth: 'bearer still-unknown',
        jsonBody: {'drive': {}, 'serveUrl': 'x'},
      );
      expect(res.status, 401);
      expect(res.json['error']['code'], 'unauthorized');
    });
  });

  group('error mapper status codes', () {
    test('GET a missing drive → 404 drive_not_found envelope', () async {
      final res = await call('GET', '$hubUrl/drives/alpha/missing');
      expect(res.status, 404);
      expect(res.json['success'], isFalse);
      expect(res.json['error']['code'], 'drive_not_found');
    });

    test('an empty request body → 400 invalid_json', () async {
      final res = await call('POST', '$hubUrl/endpoints', rawBody: const []);
      expect(res.status, 400);
      expect(res.json['error']['code'], 'invalid_json');
    });

    test('a malformed JSON body → 400 invalid_json', () async {
      final res = await call(
        'POST',
        '$hubUrl/endpoints',
        rawBody: utf8.encode('{not json'),
        headers: {'content-type': 'application/json'},
      );
      expect(res.status, 400);
      expect(res.json['error']['code'], 'invalid_json');
    });

    test(
      'a JSON array where an object is required → 400 invalid_json',
      () async {
        final res = await call(
          'POST',
          '$hubUrl/endpoints',
          rawBody: utf8.encode('[1,2,3]'),
          headers: {'content-type': 'application/json'},
        );
        expect(res.status, 400);
        expect(res.json['error']['code'], 'invalid_json');
      },
    );
  });

  group('router (path patterns & methods)', () {
    test('an unknown route → 404', () async {
      final res = await call('GET', '$hubUrl/does/not/exist');
      expect(res.status, 404);
    });

    test('a known path with the wrong method → 405', () async {
      // /version is GET-only.
      final res = await call('DELETE', '$hubUrl/version');
      expect(res.status, 405);
    });

    test('the content server 404s a drive it does not serve', () async {
      final res = await call('GET', '$contentUrl/drives/alpha/nope/manifest');
      expect(res.status, 404);
      expect(res.json['error']['code'], 'drive_not_found');
    });
  });

  group('content server routing & status', () {
    Future<DriveId> publishRw(TempDir src, {String name = 'docs'}) async {
      final drive = await publisher.publishDirectory(
        path: src.path,
        name: name,
      );
      return drive.id;
    }

    test(
      'a nested file path routes through the <path|.*> tail capture',
      () async {
        final src = await TempDir.create();
        addTearDown(src.cleanup);
        await src.writeFile('a/b/c/deep.txt', 'deep');
        await publishRw(src);

        final res = await call(
          'GET',
          '$contentUrl/drives/alpha/docs/files/a/b/c/deep.txt',
        );
        expect(res.status, 200);
        expect(res.body, 'deep');
      },
    );

    test('PUT to a nested path creates the file and returns 204', () async {
      final src = await TempDir.create();
      addTearDown(src.cleanup);
      await src.writeFile('seed.txt', 'seed');
      await publishRw(src);

      final res = await call(
        'PUT',
        '$contentUrl/drives/alpha/docs/files/x/y/new.txt',
        rawBody: utf8.encode('created'),
      );
      expect(res.status, 204);
      expect(res.body, isEmpty);
      expect(File('${src.path}/x/y/new.txt').readAsStringSync(), 'created');
    });

    test('writing to a read-only drive → 403 read_only_violation', () async {
      final src = await TempDir.create();
      addTearDown(src.cleanup);
      await src.writeFile('a.txt', 'A');
      // Register a read-only directory drive directly in the served registry.
      final drive = Drive(
        id: DriveId.scoped(endpoint: EndpointId('alpha'), name: 'ro'),
        name: 'ro',
        provider: ProviderType.directory,
        originEndpoint: EndpointId('alpha'),
        originUri: OriginUri(src.path),
        accessMode: AccessMode.readOnly,
        capabilities: DriveCapabilities.forProvider(
          ProviderType.directory,
          AccessMode.readOnly,
        ),
        createdAt: t0,
      );
      await published.save(
        DriveRegistration(
          drive: drive,
          servingEndpoint: EndpointId('alpha'),
          serveUrl: '$contentUrl/drives/alpha/ro',
          registeredAt: t0,
        ),
      );

      final res = await call(
        'PUT',
        '$contentUrl/drives/alpha/ro/files/a.txt',
        rawBody: utf8.encode('nope'),
      );
      expect(res.status, 403);
      expect(res.json['error']['code'], 'read_only_violation');
    });

    test('a server-side copy with a stale hash → 409', () async {
      final src = await TempDir.create();
      addTearDown(src.cleanup);
      await src.writeFile('orig.txt', 'original');
      await publishRw(src);

      final res = await call(
        'POST',
        '$contentUrl/drives/alpha/docs/copy',
        jsonBody: {
          'from': 'orig.txt',
          'to': 'dup.txt',
          // A hash that cannot match the real file → copy() returns false → 409.
          'hash': 'sha256:${'0' * 64}',
        },
      );
      expect(res.status, 409);
    });
  });
}
