import 'package:http/http.dart' as http;

import '../application/enrollment.dart';
import '../domain/contracts/content_source.dart';
import '../domain/contracts/drive_hub.dart';
import '../domain/entities/drive_registration.dart';
import '../domain/entities/endpoint_identity.dart';
import '../domain/value_objects/auth_token.dart';
import '../domain/value_objects/drive_id.dart';
import '../domain/value_objects/endpoint_id.dart';
import '../infrastructure/http/http_content_source.dart';
import '../infrastructure/http/http_drive_hub.dart';

/// A thin, high-level client for talking to a running OmnyDrive hub and the
/// endpoint content servers it routes to.
///
/// This is the entry point for consumers who only need to *use* the network
/// (discover drives, read/write content) rather than run an engine. It wraps an
/// [HttpDriveHub] and hands out [ContentSource]s for a drive's `serveUrl`,
/// sharing a single [http.Client] for connection reuse.
///
/// ```dart
/// final client = OmnyClient('http://hub.local:7070');
/// final creds = await client.enroll(identity: myIdentity);
/// await client.login(endpointId: myIdentity.id, secret: creds.secret);
/// for (final reg in await client.drives()) {
///   print('${reg.id} served at ${reg.serveUrl}');
/// }
/// await client.close();
/// ```
class OmnyClient {
  final HttpDriveHub _hub;
  final http.Client _http;
  final bool _ownsClient;

  /// Connects to the hub at [hubUrl]. When no [client] is supplied an
  /// internally-owned [http.Client] is created and closed by [close].
  factory OmnyClient(String hubUrl, {http.Client? client}) {
    final shared = client ?? http.Client();
    return OmnyClient._(
      HttpDriveHub(hubUrl, client: shared),
      shared,
      client == null,
    );
  }

  OmnyClient._(this._hub, this._http, this._ownsClient);

  /// The underlying hub client, for advanced use.
  DriveHub get hub => _hub;

  /// The bearer token currently in use, if authenticated.
  AuthToken? get token => _hub.token;

  /// Enrols a new endpoint, returning its one-time credentials.
  Future<Enrollment> enroll({
    required EndpointIdentity identity,
    String? secret,
  }) => _hub.enroll(identity: identity, secret: secret);

  /// Authenticates and remembers the issued token for later calls.
  Future<AuthToken> login({
    required EndpointId endpointId,
    required String secret,
  }) => _hub.login(endpointId: endpointId, secret: secret);

  /// Lists all drives discoverable on the hub.
  Future<List<DriveRegistration>> drives() => _hub.listDrives();

  /// Looks up a single drive registration by id.
  Future<DriveRegistration> drive(DriveId id) => _hub.getDrive(id);

  /// Opens a [ContentSource] for a directory drive's content, reading (and
  /// optionally writing) bytes directly from its serving endpoint.
  ContentSource content(
    DriveRegistration registration, {
    bool writable = false,
  }) => HttpContentSource(
    registration.serveUrl,
    client: _http,
    isWritable: writable,
  );

  /// Closes the shared HTTP client (only the one this instance created).
  void close() {
    if (_ownsClient) _http.close();
  }
}
