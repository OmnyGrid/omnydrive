import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/contracts/content_source.dart';
import '../../domain/entities/file_manifest.dart';
import '../../shared/errors/domain_exception.dart';
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
      _client = client ?? http.Client();

  @override
  Future<FileManifest> manifest() async {
    final response = await _client.get(Uri.parse('$base/manifest'));
    if (response.statusCode != 200) {
      throwApiError(response.statusCode, response.body);
    }
    return FileManifest.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<List<int>> readBytes(String relativePath) async {
    final response = await _client.get(_fileUri(relativePath));
    if (response.statusCode != 200) {
      throwApiError(response.statusCode, response.body);
    }
    return response.bodyBytes;
  }

  @override
  Future<void> writeBytes(String relativePath, List<int> bytes) async {
    _ensureWritable();
    final response = await _client.put(_fileUri(relativePath), body: bytes);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throwApiError(response.statusCode, response.body);
    }
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
