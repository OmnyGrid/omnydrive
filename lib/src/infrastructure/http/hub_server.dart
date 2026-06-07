import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../application/local_drive_hub.dart';
import '../../domain/entities/drive.dart';
import '../../domain/entities/drive_registration.dart';
import '../../domain/entities/endpoint_identity.dart';
import '../../domain/value_objects/auth_token.dart';
import '../../domain/value_objects/drive_id.dart';
import '../../domain/value_objects/endpoint_id.dart';
import '../../shared/errors/domain_exception.dart';
import '../../shared/json/json_response.dart';
import '../../shared/utils/clock.dart';
import '../../shared/version.dart';

/// HTTP adapter exposing a [LocalDriveHub] as a REST API. The server holds no
/// state of its own — it parses requests, delegates to the hub, and renders the
/// result (or any [DomainException]) through [JsonResponse].
class HubServer {
  final LocalDriveHub hub;
  final Clock _clock;

  HubServer(this.hub, {Clock? clock}) : _clock = clock ?? SystemClock();

  /// The composed request handler (router + error translation).
  Handler get handler {
    final router = Router()
      ..get('/version', _version)
      ..post('/endpoints', _enroll)
      ..post('/auth', _authenticate)
      ..post('/drives', _registerDrive)
      ..get('/drives', _listDrives)
      ..get('/drives/<endpoint>/<name>', _getDrive)
      ..get('/drives/<endpoint>/<name>/route', _routeSync);
    return const Pipeline().addHandler(router.call);
  }

  /// Binds the server to [address]:[port]. Pass port 0 for an ephemeral port.
  Future<HttpServer> serve({Object address = 'localhost', int port = 0}) =>
      shelf_io.serve(handler, address, port);

  // --- Handlers -------------------------------------------------------------

  Response _version(Request request) =>
      JsonResponse.ok({'name': 'omnydrive-hub', 'version': omnyDriveVersion});

  Future<Response> _enroll(Request request) => _guard(() async {
    final body = await _readJson(request);
    final identity = EndpointIdentity.fromJson(
      body['identity'] as Map<String, dynamic>,
    );
    final result = await hub.enroll(
      identity: identity,
      secret: body['secret'] as String?,
    );
    return JsonResponse.created({
      'identity': result.identity.toJson(),
      'secret': result.secret,
    });
  });

  Future<Response> _authenticate(Request request) => _guard(() async {
    final body = await _readJson(request);
    final token = await hub.authenticate(
      endpointId: EndpointId(body['endpointId'] as String),
      secret: body['secret'] as String,
    );
    return JsonResponse.ok({'token': token.value});
  });

  Future<Response> _registerDrive(Request request) => _guard(() async {
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
    return JsonResponse.created(saved.toJson());
  });

  Future<Response> _listDrives(Request request) => _guard(() async {
    final drives = await hub.listDrives();
    return JsonResponse.ok({
      'drives': [for (final d in drives) d.toJson()],
    });
  });

  Future<Response> _getDrive(Request request) => _guard(() async {
    final reg = await hub.getDrive(_driveId(request));
    return JsonResponse.ok(reg.toJson());
  });

  Future<Response> _routeSync(Request request) => _guard(() async {
    final requester = _authenticate0(request);
    final route = await hub.routeSync(_driveId(request), requester: requester);
    return JsonResponse.ok(route.toJson());
  });

  // --- Helpers --------------------------------------------------------------

  DriveId _driveId(Request request) {
    final endpoint = request.params['endpoint']!;
    final name = request.params['name']!;
    return DriveId('$endpoint/$name');
  }

  /// Extracts and verifies the bearer token, returning the authenticated
  /// endpoint or throwing [UnauthorizedException].
  EndpointId _authenticate0(Request request) {
    final header = request.headers['authorization'];
    if (header == null || !header.toLowerCase().startsWith('bearer ')) {
      throw const UnauthorizedException();
    }
    return hub.authorize(AuthToken(header.substring(7).trim()));
  }

  Future<Map<String, dynamic>> _readJson(Request request) async {
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

  Future<Response> _guard(FutureOr<Response> Function() body) async {
    try {
      return await body();
    } on DomainException catch (e) {
      return JsonResponse.fromException(e);
    } catch (_) {
      return JsonResponse.internalError();
    }
  }
}
