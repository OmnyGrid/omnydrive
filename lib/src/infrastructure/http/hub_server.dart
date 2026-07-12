import 'dart:convert';

import 'package:omnyhub/omnyhub.dart'
    show
        HttpTransport,
        HubRequest,
        HubResponse,
        OmnyHub,
        RouterService,
        successEnvelope;

import '../../application/local_drive_hub.dart';
import '../../domain/entities/drive.dart';
import '../../domain/entities/drive_registration.dart';
import '../../domain/entities/endpoint_identity.dart';
import '../../domain/value_objects/auth_token.dart';
import '../../domain/value_objects/drive_id.dart';
import '../../domain/value_objects/endpoint_id.dart';
import '../../shared/errors/domain_exception.dart';
import '../../shared/utils/clock.dart';
import '../../shared/version.dart';
import 'drive_http.dart';

/// HTTP adapter exposing a [LocalDriveHub] as a REST API, hosted on an
/// [OmnyHub]. The server holds no state of its own — it parses requests,
/// delegates to the hub, and renders the result (or any [DomainException],
/// via [driveErrorMapper]) as JSON.
class HubServer {
  final LocalDriveHub hub;
  final Clock _clock;

  HubServer(this.hub, {Clock? clock}) : _clock = clock ?? SystemClock();

  /// The omnyhub service exposing the hub REST routes.
  RouterService buildService() => RouterService(name: 'hub')
    ..get('/version', (r, p) async => _version())
    ..post('/endpoints', (r, p) => _enroll(r))
    ..post('/auth', (r, p) => _authenticate(r))
    ..post('/drives', (r, p) => _registerDrive(r))
    ..get('/drives', (r, p) => _listDrives())
    ..get('/drives/<endpoint>/<name>', (r, p) => _getDrive(p))
    ..get('/drives/<endpoint>/<name>/route', (r, p) => _routeSync(r, p));

  /// Builds and starts an [OmnyHub] hosting the API on [address]:[port]
  /// (port 0 = ephemeral). Returns the running hub; stop it with `hub.stop()`.
  Future<OmnyHub> serve({Object address = 'localhost', int port = 0}) async {
    final server = OmnyHub(
      transports: [HttpTransport.http(address: address, port: port)],
      middleware: [driveErrorMapper()],
    );
    await server.registerService(buildService());
    await server.start();
    return server;
  }

  // --- Handlers -------------------------------------------------------------

  HubResponse _version() =>
      successEnvelope({'name': 'omnydrive-hub', 'version': omnyDriveVersion});

  Future<HubResponse> _enroll(HubRequest request) async {
    final body = await _readJson(request);
    final identity = EndpointIdentity.fromJson(
      body['identity'] as Map<String, dynamic>,
    );
    final result = await hub.enroll(
      identity: identity,
      secret: body['secret'] as String?,
    );
    return successEnvelope({
      'identity': result.identity.toJson(),
      'secret': result.secret,
    }, statusCode: 201);
  }

  Future<HubResponse> _authenticate(HubRequest request) async {
    final body = await _readJson(request);
    final token = await hub.authenticate(
      endpointId: EndpointId(body['endpointId'] as String),
      secret: body['secret'] as String,
    );
    return successEnvelope({'token': token.value});
  }

  Future<HubResponse> _registerDrive(HubRequest request) async {
    final endpoint = _authenticate0(request);
    final body = await _readJson(request);
    final drive = Drive.fromJson(body['drive'] as Map<String, dynamic>);
    final registration = DriveRegistration(
      drive: drive,
      // The serving endpoint is taken from the bearer token, never trusted
      // from the body.
      servingEndpoint: endpoint,
      serveUrl: body['serveUrl'] as String,
      registeredAt: _clock.now(),
    );
    final saved = await hub.registerDrive(registration);
    return successEnvelope(saved.toJson(), statusCode: 201);
  }

  Future<HubResponse> _listDrives() async {
    final drives = await hub.listDrives();
    return successEnvelope({
      'drives': [for (final d in drives) d.toJson()],
    });
  }

  Future<HubResponse> _getDrive(Map<String, String> params) async {
    final reg = await hub.getDrive(_driveId(params));
    return successEnvelope(reg.toJson());
  }

  Future<HubResponse> _routeSync(
    HubRequest request,
    Map<String, String> params,
  ) async {
    final requester = _authenticate0(request);
    final route = await hub.routeSync(_driveId(params), requester: requester);
    return successEnvelope(route.toJson());
  }

  // --- Helpers --------------------------------------------------------------

  DriveId _driveId(Map<String, String> params) =>
      DriveId('${params['endpoint']}/${params['name']}');

  /// Extracts and verifies the bearer token, returning the authenticated
  /// endpoint or throwing [UnauthorizedException].
  EndpointId _authenticate0(HubRequest request) {
    final header = request.header('authorization');
    if (header == null || !header.toLowerCase().startsWith('bearer ')) {
      throw const UnauthorizedException();
    }
    return hub.authorize(AuthToken(header.substring(7).trim()));
  }

  Future<Map<String, dynamic>> _readJson(HubRequest request) async {
    final body = await request.readAsString();
    if (body.trim().isEmpty) {
      throw const InvalidJsonException('Request body is empty');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (e) {
      throw InvalidJsonException('Malformed JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const InvalidJsonException('Expected a JSON object');
    }
    return decoded;
  }
}
