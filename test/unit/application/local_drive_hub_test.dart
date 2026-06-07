import 'package:omnydrive/omnydrive.dart';
import 'package:test/test.dart';

import '../../support/fixed_clock.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1);

  EndpointIdentity ident(String id) => EndpointIdentity(
    id: EndpointId(id),
    displayName: id,
    baseUrl: 'http://$id.local:8080',
    capabilities: CapabilitySet([Capability.read, Capability.write]),
    registeredAt: t0,
  );

  late FixedClock clock;
  late LocalDriveHub hub;

  setUp(() {
    clock = FixedClock(t0);
    hub = LocalDriveHub(idGenerator: SequentialIdGenerator(), clock: clock);
  });

  group('enrollment & authentication', () {
    test('enroll returns a one-time secret and stamps registeredAt', () async {
      clock.advance(const Duration(days: 1));
      final result = await hub.enroll(identity: ident('nas'));
      expect(result.secret, isNotEmpty);
      expect(result.identity.registeredAt, clock.now());
    });

    test('enroll rejects a duplicate endpoint', () async {
      await hub.enroll(identity: ident('nas'));
      expect(
        () => hub.enroll(identity: ident('nas')),
        throwsA(isA<ConflictException>()),
      );
    });

    test(
      'authenticate succeeds with the enrolled secret and issues a token',
      () async {
        final e = await hub.enroll(identity: ident('nas'));
        final token = await hub.authenticate(
          endpointId: EndpointId('nas'),
          secret: e.secret,
        );
        expect(hub.authorize(token), EndpointId('nas'));
      },
    );

    test('authenticate rejects a wrong secret', () async {
      await hub.enroll(identity: ident('nas'));
      expect(
        () => hub.authenticate(endpointId: EndpointId('nas'), secret: 'nope'),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('authenticate rejects an unknown endpoint', () async {
      expect(
        () => hub.authenticate(endpointId: EndpointId('ghost'), secret: 'x'),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('authorize rejects an unknown token', () {
      expect(
        () => hub.authorize(AuthToken('bogus')),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('registerEndpoint is an idempotent upsert', () async {
      await hub.registerEndpoint(ident('nas'));
      final again = await hub.registerEndpoint(ident('nas'));
      expect(again.id, EndpointId('nas'));
    });
  });

  group('drive registry & routing', () {
    DriveRegistration reg(String name, {EndpointId? serving}) {
      final endpoint = EndpointId('nas');
      final drive = Drive(
        id: DriveId.scoped(endpoint: endpoint, name: name),
        name: name,
        provider: ProviderType.directory,
        originEndpoint: endpoint,
        originUri: OriginUri('/srv/$name'),
        accessMode: AccessMode.readWrite,
        capabilities: DriveCapabilities.forProvider(
          ProviderType.directory,
          AccessMode.readWrite,
        ),
        createdAt: t0,
      );
      return DriveRegistration(
        drive: drive,
        servingEndpoint: serving ?? endpoint,
        serveUrl: 'http://nas.local/drives/${drive.id.value}',
        registeredAt: t0,
      );
    }

    setUp(() async => hub.enroll(identity: ident('nas')));

    test('registerDrive requires a known serving endpoint', () async {
      expect(
        () => hub.registerDrive(reg('docs', serving: EndpointId('ghost'))),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('registerDrive then getDrive / listDrives / routeSync', () async {
      final r = await hub.registerDrive(reg('docs'));
      expect((await hub.getDrive(r.id)).drive.name, 'docs');
      expect(await hub.listDrives(), hasLength(1));

      final route = await hub.routeSync(r.id, requester: EndpointId('nas'));
      expect(route.servingEndpoint, EndpointId('nas'));
      expect(route.serveUrl, r.serveUrl);
    });

    test('getDrive throws for an unknown drive', () async {
      expect(
        () => hub.getDrive(DriveId('nas/missing')),
        throwsA(isA<NotFoundException>()),
      );
    });
  });
}
