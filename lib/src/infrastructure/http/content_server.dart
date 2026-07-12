import 'dart:convert';

import 'package:omnyhub/omnyhub.dart'
    show
        HttpTransport,
        HubRequest,
        HubResponse,
        OmnyHub,
        RouterService,
        successEnvelope;

import '../../domain/contracts/content_source.dart';
import '../../domain/entities/drive_registration.dart';
import '../../domain/enums/provider_type.dart';
import '../../domain/repositories/drive_registry.dart';
import '../../domain/value_objects/content_hash.dart';
import '../../domain/value_objects/drive_id.dart';
import '../../domain/value_objects/origin_uri.dart';
import '../../shared/errors/domain_exception.dart';
import '../../shared/errors/error_codes.dart';
import '../../shared/utils/content_compression.dart';
import '../../shared/version.dart';
import '../providers/directory/local_content_source.dart';
import 'drive_http.dart';

/// Resolves a published directory drive to the [ContentSource] that backs it.
typedef DriveContentResolver = ContentSource Function(DriveRegistration drive);

/// HTTP server that streams a publishing endpoint's directory drives to peers,
/// hosted on an [OmnyHub].
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

  /// The omnyhub service exposing the content routes.
  RouterService buildService() => RouterService(name: 'content')
    ..get('/version', (r, p) async => _version())
    ..get('/drives/<endpoint>/<name>/manifest', (r, p) => _manifest(r, p))
    ..get(
      '/drives/<endpoint>/<name>/files/<path|.*>',
      (r, p) => _readFile(r, p),
    )
    ..put(
      '/drives/<endpoint>/<name>/files/<path|.*>',
      (r, p) => _writeFile(r, p),
    )
    ..post('/drives/<endpoint>/<name>/copy', (r, p) => _copyFile(r, p))
    ..delete(
      '/drives/<endpoint>/<name>/files/<path|.*>',
      (r, p) => _deleteFile(r, p),
    );

  /// Builds and starts an [OmnyHub] hosting the content routes on
  /// [address]:[port] (port 0 = ephemeral). Stop it with `hub.stop()`.
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

  HubResponse _version() => successEnvelope({
    'name': 'omnydrive-content',
    'version': omnyDriveVersion,
    'capabilities': [serverSideCopyCapability],
  });

  Future<HubResponse> _manifest(
    HubRequest request,
    Map<String, String> params,
  ) async {
    final source = await _sourceFor(params, writable: false);
    final manifest = await source.manifest();
    final bytes = utf8.encode(jsonEncode(manifest.toJson()));
    const contentType = 'application/json; charset=utf-8';
    if (ContentCompression.acceptsGzip(request.header('accept-encoding')) &&
        _compression.shouldCompressBytes(bytes.length)) {
      return HubResponse.bytes(
        _compression.encode(bytes),
        contentType: contentType,
        headers: {'content-encoding': 'gzip'},
      );
    }
    return HubResponse.bytes(bytes, contentType: contentType);
  }

  Future<HubResponse> _readFile(
    HubRequest request,
    Map<String, String> params,
  ) async {
    final source = await _sourceFor(params, writable: false);
    final path = params['path']!;
    final bytes = await source.readBytes(path);
    const contentType = 'application/octet-stream';
    if (ContentCompression.acceptsGzip(request.header('accept-encoding')) &&
        _compression.shouldCompress(path, bytes.length)) {
      return HubResponse.bytes(
        _compression.encode(bytes),
        contentType: contentType,
        headers: {'content-encoding': 'gzip'},
      );
    }
    return HubResponse.bytes(bytes, contentType: contentType);
  }

  Future<HubResponse> _writeFile(
    HubRequest request,
    Map<String, String> params,
  ) async {
    final source = await _sourceFor(params, writable: true);
    var bytes = await request.readBytes();
    if (ContentCompression.isGzip(request.header('content-encoding'))) {
      bytes = ContentCompression.decode(bytes);
    }
    await source.writeBytes(
      params['path']!,
      bytes,
      executable: request.header(executableHeader) == '1',
    );
    return HubResponse(statusCode: 204);
  }

  /// Reuses content already present on this drive: copies `from` to `to` in
  /// place — but only if `from` still hashes to the supplied value — so peers
  /// can avoid re-uploading bytes the origin already holds. A `409` signals the
  /// source drifted or vanished, telling the client to fall back to a transfer.
  Future<HubResponse> _copyFile(
    HubRequest request,
    Map<String, String> params,
  ) async {
    final source = await _sourceFor(params, writable: true);
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final copied = await source.copy(
      body['from'] as String,
      body['to'] as String,
      ContentHash.parse(body['hash'] as String),
      executable: body['executable'] == true,
    );
    if (!copied) {
      return HubResponse.text(
        'copy source no longer matches expected hash',
        statusCode: 409,
      );
    }
    return HubResponse(statusCode: 204);
  }

  Future<HubResponse> _deleteFile(
    HubRequest request,
    Map<String, String> params,
  ) async {
    final source = await _sourceFor(params, writable: true);
    await source.delete(params['path']!);
    return HubResponse(statusCode: 204);
  }

  // --- Helpers --------------------------------------------------------------

  Future<ContentSource> _sourceFor(
    Map<String, String> params, {
    required bool writable,
  }) async {
    final id = DriveId('${params['endpoint']}/${params['name']}');
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
}
