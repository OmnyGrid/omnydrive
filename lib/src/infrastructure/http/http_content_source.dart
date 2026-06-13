import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../domain/contracts/content_source.dart';
import '../../domain/entities/file_manifest.dart';
import '../../domain/value_objects/content_hash.dart';
import '../../shared/errors/domain_exception.dart';
import '../../shared/utils/content_compression.dart';
import '../../shared/version.dart';
import 'api_errors.dart';

/// A [ContentSource] backed by a remote endpoint's HTTP content server.
///
/// It mirrors [LocalContentSource] over the wire, talking to the routes exposed
/// by [ContentServer]:
///
/// ```
/// GET    {base}/manifest      -> FileManifest JSON
/// GET    {base}/files/{path}  -> raw bytes
/// PUT    {base}/files/{path}  -> write bytes
/// DELETE {base}/files/{path}  -> delete
/// ```
///
/// where `{base}` is the drive's `serveUrl` (e.g.
/// `http://host/drives/{endpoint}/{name}`).
class HttpContentSource implements ContentSource {
  /// Base URL of the drive on its serving endpoint, without a trailing slash.
  final String base;

  final http.Client _client;

  /// The compression policy applied to writes and advertised on reads.
  final ContentCompression _compression;

  /// Caches the one-time server capability probe for [supportsCopy], so a
  /// transfer pays at most one `/version` round trip.
  Future<bool>? _copySupport;

  @override
  final bool isWritable;

  HttpContentSource(
    String base, {
    http.Client? client,
    this.isWritable = false,
    ContentCompression? compression,
  }) : base = base.endsWith('/') ? base.substring(0, base.length - 1) : base,
       _client = client ?? defaultClient(),
       _compression = compression ?? ContentCompression.standard;

  /// The client used when none is injected.
  ///
  /// Auto-uncompress is disabled so gzip handling stays fully explicit: the
  /// body arrives exactly as the server sent it, so a `content-encoding: gzip`
  /// header reliably means the bytes are still compressed. (The default
  /// `IOClient` decompresses transparently yet *keeps* the header, which makes
  /// the body's state ambiguous.)
  static http.Client defaultClient() =>
      IOClient(HttpClient()..autoUncompress = false);

  @override
  Future<FileManifest> manifest() async {
    final response = await _client.get(
      Uri.parse('$base/manifest'),
      headers: _accept,
    );
    if (response.statusCode != 200) {
      throwApiError(response.statusCode, response.body);
    }
    final json = utf8.decode(_decoded(response));
    return FileManifest.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  @override
  Future<List<int>> readBytes(String relativePath) async {
    final response = await _client.get(
      _fileUri(relativePath),
      headers: _accept,
    );
    if (response.statusCode != 200) {
      throwApiError(response.statusCode, response.body);
    }
    return _decoded(response);
  }

  @override
  Future<void> writeBytes(
    String relativePath,
    List<int> bytes, {
    void Function(int sent, int total)? onProgress,
  }) async {
    _ensureWritable();
    final compress = _compression.shouldCompress(relativePath, bytes.length);
    final payload = compress ? _compression.encode(bytes) : bytes;

    if (onProgress == null) {
      final response = await _client.put(
        _fileUri(relativePath),
        headers: compress ? const {'content-encoding': 'gzip'} : null,
        body: payload,
      );
      if (response.statusCode != 200 && response.statusCode != 204) {
        throwApiError(response.statusCode, response.body);
      }
      return;
    }

    // Stream the (already-encoded) payload so progress reflects the wire size.
    // The request yields chunks on demand, so [onProgress] tracks the socket's
    // own pace rather than how fast we can buffer.
    final request = _ProgressUpload(
      'PUT',
      _fileUri(relativePath),
      payload,
      onProgress,
    );
    if (compress) request.headers['content-encoding'] = 'gzip';
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throwApiError(response.statusCode, response.body);
    }
  }

  /// Only advertise gzip when this policy is enabled; a disabled policy asks the
  /// server for plain bytes (and the magic-byte check below still decodes
  /// anything that arrives gzipped anyway).
  Map<String, String>? get _accept =>
      _compression.enabled ? const {'accept-encoding': 'gzip'} : null;

  /// Returns the response body bytes, gunzipping only when the server marked
  /// them gzip-encoded **and** they still look like a gzip stream. This stays
  /// correct regardless of the injected client: Dart's default `IOClient`
  /// transparently uncompresses the body yet keeps the `content-encoding`
  /// header, so keying on the header alone would double-decode — the magic-byte
  /// check ([ContentCompression.looksGzipped]) guards against that.
  List<int> _decoded(http.Response response) {
    final bytes = response.bodyBytes;
    return ContentCompression.isGzip(response.headers['content-encoding']) &&
            ContentCompression.looksGzipped(bytes)
        ? ContentCompression.decode(bytes)
        : bytes;
  }

  @override
  Future<void> delete(String relativePath) async {
    _ensureWritable();
    final response = await _client.delete(_fileUri(relativePath));
    if (response.statusCode != 200 &&
        response.statusCode != 204 &&
        response.statusCode != 404) {
      throwApiError(response.statusCode, response.body);
    }
  }

  @override
  Future<bool> supportsCopy() {
    if (!isWritable) return Future.value(false);
    return _copySupport ??= _probeCopySupport();
  }

  /// Probes the server-root `/version` endpoint for the
  /// [serverSideCopyCapability]. The `/version` route lives at the host root,
  /// not under `/drives/...`, so derive it from [base]. Any failure or a server
  /// that doesn't advertise the capability resolves to `false` (older servers
  /// then transparently fall back to full byte transfers).
  Future<bool> _probeCopySupport() async {
    try {
      final root = Uri.parse(base).replace(path: '/version', query: null);
      final response = await _client.get(root, headers: _accept);
      if (response.statusCode != 200) return false;
      // The endpoint wraps payloads in a {success, data} envelope.
      final body = jsonDecode(utf8.decode(_decoded(response)));
      final data = body is Map<String, dynamic> ? body['data'] : null;
      final caps = data is Map<String, dynamic> ? data['capabilities'] : null;
      return caps is List && caps.contains(serverSideCopyCapability);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> copy(
    String fromPath,
    String toPath,
    ContentHash expectedHash,
  ) async {
    _ensureWritable();
    final response = await _client.post(
      Uri.parse('$base/copy'),
      headers: const {'content-type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'from': fromPath,
        'to': toPath,
        'hash': expectedHash.value,
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 204) return true;
    // 409 means the source drifted or vanished; the caller transfers bytes.
    if (response.statusCode == 409) return false;
    throwApiError(response.statusCode, response.body);
  }

  void _ensureWritable() {
    if (!isWritable) {
      throw const AccessDeniedException(
        message: 'Remote content source is read-only',
      );
    }
  }

  /// Builds the file URL, percent-encoding each path segment so names with
  /// reserved characters survive the round trip.
  Uri _fileUri(String relativePath) {
    final segments = relativePath
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    return Uri.parse('$base/files/$segments');
  }
}

/// A PUT request whose body is fed from an in-memory buffer in chunks, invoking
/// a callback as each chunk is pulled by the HTTP client. Because the chunks are
/// yielded on demand, the reported byte count follows the socket's actual drain
/// rate rather than how fast the buffer can be enqueued.
class _ProgressUpload extends http.BaseRequest {
  static const _chunkSize = 64 * 1024;

  final List<int> _payload;
  final void Function(int sent, int total) _onProgress;

  _ProgressUpload(super.method, super.url, this._payload, this._onProgress) {
    contentLength = _payload.length;
  }

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_chunks());
  }

  Stream<List<int>> _chunks() async* {
    final total = _payload.length;
    var sent = 0;
    _onProgress(0, total);
    while (sent < total) {
      final end = sent + _chunkSize < total ? sent + _chunkSize : total;
      yield _payload.sublist(sent, end);
      sent = end;
      _onProgress(sent, total);
    }
  }
}
