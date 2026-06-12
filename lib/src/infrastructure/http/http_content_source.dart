import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../domain/contracts/content_source.dart';
import '../../domain/entities/file_manifest.dart';
import '../../shared/errors/domain_exception.dart';
import '../../shared/utils/content_compression.dart';
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

  @override
  final bool isWritable;

  HttpContentSource(String base, {http.Client? client, this.isWritable = false})
    : base = base.endsWith('/') ? base.substring(0, base.length - 1) : base,
      _client = client ?? defaultClient();

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
      headers: _acceptGzip,
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
      headers: _acceptGzip,
    );
    if (response.statusCode != 200) {
      throwApiError(response.statusCode, response.body);
    }
    return _decoded(response);
  }

  @override
  Future<void> writeBytes(String relativePath, List<int> bytes) async {
    _ensureWritable();
    final headers =
        ContentCompression.shouldCompress(relativePath, bytes.length)
        ? const {'content-encoding': 'gzip'}
        : null;
    final body = headers != null ? ContentCompression.encode(bytes) : bytes;
    final response = await _client.put(
      _fileUri(relativePath),
      headers: headers,
      body: body,
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throwApiError(response.statusCode, response.body);
    }
  }

  static const Map<String, String> _acceptGzip = {'accept-encoding': 'gzip'};

  /// Returns the response body bytes, gunzipping when the server still marks
  /// them gzip-encoded. A client that transparently uncompresses (Dart's
  /// default `IOClient`) strips the `content-encoding` header, so this no-ops.
  List<int> _decoded(http.Response response) =>
      ContentCompression.isGzip(response.headers['content-encoding'])
      ? ContentCompression.decode(response.bodyBytes)
      : response.bodyBytes;

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
