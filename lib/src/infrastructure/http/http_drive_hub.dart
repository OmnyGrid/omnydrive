import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../application/enrollment.dart';
import '../../domain/contracts/drive_hub.dart';
import '../../domain/entities/drive_registration.dart';
import '../../domain/entities/endpoint_identity.dart';
import '../../domain/value_objects/auth_token.dart';
import '../../domain/value_objects/drive_id.dart';
import '../../domain/value_objects/endpoint_id.dart';
import 'api_errors.dart';

/// A [DriveHub] that talks to a remote hub server over HTTP. Endpoints use it in
/// place of an in-process [LocalDriveHub] so the same orchestration code runs
/// against a networked hub.
///
/// After [login] (or [authenticate]) the issued bearer token is attached to all
/// authenticated requests automatically.
class HttpDriveHub implements DriveHub {
  /// Base URL of the hub server, without a trailing slash.
  final String base;

  final http.Client _client;
  AuthToken? _token;

  HttpDriveHub(String base, {http.Client? client, AuthToken? token})
    : base = base.endsWith('/') ? base.substring(0, base.length - 1) : base,
      _client = client ?? http.Client(),
      _token = token;

  /// The bearer token currently in use, if authenticated.
  AuthToken? get token => _token;

  Map<String, String> get _jsonHeaders => {
    'content-type': 'application/json',
    if (_token != null) 'authorization': 'Bearer ${_token!.value}',
  };

  /// Enrolls a new endpoint and returns its one-time credentials.
  Future<Enrollment> enroll({
    required EndpointIdentity identity,
    String? secret,
  }) async {
    final response = await _client.post(
      Uri.parse('$base/endpoints'),
      headers: _jsonHeaders,
      body: jsonEncode({'identity': identity.toJson(), 'secret': ?secret}),
    );
    final data = _data(response, expected: 201);
    return Enrollment(
      identity: EndpointIdentity.fromJson(
        data['identity'] as Map<String, dynamic>,
      ),
      secret: data['secret'] as String,
    );
  }

  /// Authenticates and remembers the issued token for subsequent calls.
  Future<AuthToken> login({
    required EndpointId endpointId,
    required String secret,
  }) => authenticate(endpointId: endpointId, secret: secret);

  @override
  Future<EndpointIdentity> registerEndpoint(EndpointIdentity identity) async {
    final result = await enroll(identity: identity);
    return result.identity;
  }

  @override
  Future<AuthToken> authenticate({
    required EndpointId endpointId,
    required String secret,
  }) async {
    final response = await _client.post(
      Uri.parse('$base/auth'),
      headers: _jsonHeaders,
      body: jsonEncode({'endpointId': endpointId.value, 'secret': secret}),
    );
    final data = _data(response);
    final token = AuthToken(data['token'] as String);
    _token = token;
    return token;
  }

  @override
  Future<DriveRegistration> registerDrive(
    DriveRegistration registration,
  ) async {
    final response = await _client.post(
      Uri.parse('$base/drives'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'drive': registration.drive.toJson(),
        'serveUrl': registration.serveUrl,
      }),
    );
    return DriveRegistration.fromJson(_data(response, expected: 201));
  }

  @override
  Future<List<DriveRegistration>> listDrives() async {
    final response = await _client.get(Uri.parse('$base/drives'));
    final data = _data(response);
    final list = (data['drives'] as List).cast<Map<String, dynamic>>();
    return list.map(DriveRegistration.fromJson).toList();
  }

  @override
  Future<DriveRegistration> getDrive(DriveId id) async {
    final response = await _client.get(Uri.parse('$base/drives/${id.value}'));
    return DriveRegistration.fromJson(_data(response));
  }

  @override
  Future<DriveRoute> routeSync(
    DriveId id, {
    required EndpointId requester,
  }) async {
    final response = await _client.get(
      Uri.parse('$base/drives/${id.value}/route'),
      headers: _jsonHeaders,
    );
    return DriveRoute.fromJson(_data(response));
  }

  /// Validates [response], unwraps the `{success, data}` envelope and returns
  /// the data object, or throws the matching [DomainException].
  Map<String, dynamic> _data(http.Response response, {int expected = 200}) {
    if (response.statusCode != expected) {
      throwApiError(response.statusCode, response.body);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['data'] as Map<String, dynamic>;
  }
}
