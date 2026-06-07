import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../domain/contracts/content_source.dart';
import '../../domain/entities/drive_registration.dart';
import '../../domain/enums/provider_type.dart';
import '../../domain/repositories/drive_registry.dart';
import '../../domain/value_objects/drive_id.dart';
import '../../domain/value_objects/origin_uri.dart';
import '../../shared/errors/domain_exception.dart';
import '../../shared/errors/error_codes.dart';
import '../../shared/json/json_response.dart';
import '../../shared/version.dart';
import '../providers/directory/local_content_source.dart';

/// Resolves a published directory drive to the [ContentSource] that backs it.
typedef DriveContentResolver = ContentSource Function(DriveRegistration drive);

/// HTTP server that streams a publishing endpoint's directory drives to peers.
///
/// It reads from the same `published` [DriveRegistry] the endpoint writes to
/// when [DriveEndpoint.publishDirectory] runs, and exposes the routes
/// [HttpContentSource] consumes. Only directory drives are served; git drives
/// are cloned from their own URL.
class ContentServer {
  final DriveRegistry published;
  final DriveContentResolver _resolve;

  ContentServer(this.published, {DriveContentResolver? resolveContent})
    : _resolve = resolveContent ?? _localResolver;

  Handler get handler {
    final router = Router()
      ..get('/version', _version)
      ..get('/drives/<endpoint>/<name>/manifest', _manifest)
      ..get('/drives/<endpoint>/<name>/files/<path|.*>', _readFile)
      ..put('/drives/<endpoint>/<name>/files/<path|.*>', _writeFile)
      ..delete('/drives/<endpoint>/<name>/files/<path|.*>', _deleteFile);
    return const Pipeline().addHandler(router.call);
  }

  /// Binds the server. Pass port 0 for an ephemeral port.
  Future<HttpServer> serve({Object address = 'localhost', int port = 0}) =>
      shelf_io.serve(handler, address, port);

  // --- Handlers -------------------------------------------------------------

  Response _version(Request request) => JsonResponse.ok({
    'name': 'omnydrive-content',
    'version': omnyDriveVersion,
  });

  Future<Response> _manifest(Request request) => _guard(() async {
    final source = await _sourceFor(request, writable: false);
    final manifest = await source.manifest();
    return JsonResponse.rawJson(manifest.toJson());
  });

  Future<Response> _readFile(Request request) => _guard(() async {
    final source = await _sourceFor(request, writable: false);
    final bytes = await source.readBytes(request.params['path']!);
    return Response.ok(
      bytes,
      headers: {'content-type': 'application/octet-stream'},
    );
  });

  Future<Response> _writeFile(Request request) => _guard(() async {
    final source = await _sourceFor(request, writable: true);
    final bytes = await request.read().expand((c) => c).toList();
    await source.writeBytes(request.params['path']!, bytes);
    return JsonResponse.noContent();
  });

  Future<Response> _deleteFile(Request request) => _guard(() async {
    final source = await _sourceFor(request, writable: true);
    await source.delete(request.params['path']!);
    return JsonResponse.noContent();
  });

  // --- Helpers --------------------------------------------------------------

  Future<ContentSource> _sourceFor(
    Request request, {
    required bool writable,
  }) async {
    final id = DriveId(
      '${request.params['endpoint']}/${request.params['name']}',
    );
    final registration = await published.findById(id);
    if (registration == null) {
      throw NotFoundException(
        code: ErrorCodes.driveNotFound,
        message: 'Drive "$id" is not served here',
      );
    }
    if (registration.drive.provider != ProviderType.directory) {
      throw ValidationException(
        'Drive "$id" is not a directory drive and cannot be served over HTTP',
      );
    }
    if (writable && registration.drive.accessMode.isReadOnly) {
      throw const AccessDeniedException(
        code: ErrorCodes.readOnlyViolation,
        message: 'Drive is read-only',
      );
    }
    return _resolve(registration);
  }

  static ContentSource _localResolver(DriveRegistration registration) {
    final origin = registration.drive.originUri;
    final path = origin.scheme == OriginUriScheme.file
        ? Uri.parse(origin.value).toFilePath()
        : origin.value;
    return LocalContentSource(
      path,
      isWritable: registration.drive.accessMode.isReadWrite,
    );
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
