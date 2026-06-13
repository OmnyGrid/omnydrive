import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../domain/contracts/content_source.dart';
import '../../domain/entities/drive_registration.dart';
import '../../domain/enums/provider_type.dart';
import '../../domain/repositories/drive_registry.dart';
import '../../domain/value_objects/content_hash.dart';
import '../../domain/value_objects/drive_id.dart';
import '../../domain/value_objects/origin_uri.dart';
import '../../shared/errors/domain_exception.dart';
import '../../shared/errors/error_codes.dart';
import '../../shared/json/json_response.dart';
import '../../shared/utils/content_compression.dart';
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
  final ContentCompression _compression;

  ContentServer(
    this.published, {
    DriveContentResolver? resolveContent,
    ContentCompression? compression,
  }) : _resolve = resolveContent ?? _localResolver,
       _compression = compression ?? ContentCompression.standard;

  Handler get handler {
    final router = Router()
      ..get('/version', _version)
      ..get('/drives/<endpoint>/<name>/manifest', _manifest)
      ..get('/drives/<endpoint>/<name>/files/<path|.*>', _readFile)
      ..put('/drives/<endpoint>/<name>/files/<path|.*>', _writeFile)
      ..post('/drives/<endpoint>/<name>/copy', _copyFile)
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
    'capabilities': [serverSideCopyCapability],
  });

  Future<Response> _manifest(Request request) => _guard(() async {
    final source = await _sourceFor(request, writable: false);
    final manifest = await source.manifest();
    final bytes = utf8.encode(jsonEncode(manifest.toJson()));
    final headers = {'content-type': 'application/json; charset=utf-8'};
    if (ContentCompression.acceptsGzip(request.headers['accept-encoding']) &&
        _compression.shouldCompressBytes(bytes.length)) {
      return Response.ok(
        _compression.encode(bytes),
        headers: {...headers, 'content-encoding': 'gzip'},
      );
    }
    return Response.ok(bytes, headers: headers);
  });

  Future<Response> _readFile(Request request) => _guard(() async {
    final source = await _sourceFor(request, writable: false);
    final path = request.params['path']!;
    final bytes = await source.readBytes(path);
    final headers = {'content-type': 'application/octet-stream'};
    if (ContentCompression.acceptsGzip(request.headers['accept-encoding']) &&
        _compression.shouldCompress(path, bytes.length)) {
      return Response.ok(
        _compression.encode(bytes),
        headers: {...headers, 'content-encoding': 'gzip'},
      );
    }
    return Response.ok(bytes, headers: headers);
  });

  Future<Response> _writeFile(Request request) => _guard(() async {
    final source = await _sourceFor(request, writable: true);
    var bytes = await request.read().expand((c) => c).toList();
    if (ContentCompression.isGzip(request.headers['content-encoding'])) {
      bytes = ContentCompression.decode(bytes);
    }
    await source.writeBytes(
      request.params['path']!,
      bytes,
      executable: request.headers[executableHeader] == '1',
    );
    return JsonResponse.noContent();
  });

  /// Reuses content already present on this drive: copies [from] to [to] in
  /// place — but only if [from] still hashes to the supplied value — so peers
  /// can avoid re-uploading bytes the origin already holds. A `409` signals the
  /// source drifted or vanished, telling the client to fall back to a transfer.
  Future<Response> _copyFile(Request request) => _guard(() async {
    final source = await _sourceFor(request, writable: true);
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final copied = await source.copy(
      body['from'] as String,
      body['to'] as String,
      ContentHash.parse(body['hash'] as String),
      executable: body['executable'] == true,
    );
    if (!copied) {
      return Response(409, body: 'copy source no longer matches expected hash');
    }
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
    final drive = registration.drive;
    final origin = drive.originUri;
    final path = origin.scheme == OriginUriScheme.file
        ? Uri.parse(origin.value).toFilePath()
        : origin.value;
    return LocalContentSource(
      path,
      isWritable: drive.accessMode.isReadWrite,
      filter: drive.filter,
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
