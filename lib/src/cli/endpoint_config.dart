import 'package:path/path.dart' as p;

import '../domain/entities/endpoint_identity.dart';
import '../shared/utils/atomic_file.dart';

/// The persisted local state of a CLI endpoint: which hub it talks to, its
/// public identity, the shared secret it authenticates with, and the most
/// recent bearer token.
///
/// Stored at `<stateDir>/config.json`. The drive/mount/sync stores live beside
/// it as separate JSON files.
class EndpointConfig {
  final String hubUrl;
  final EndpointIdentity identity;
  final String secret;
  final String? token;

  const EndpointConfig({
    required this.hubUrl,
    required this.identity,
    required this.secret,
    this.token,
  });

  EndpointConfig withToken(String token) => EndpointConfig(
    hubUrl: hubUrl,
    identity: identity,
    secret: secret,
    token: token,
  );

  Map<String, dynamic> toJson() => {
    'hubUrl': hubUrl,
    'identity': identity.toJson(),
    'secret': secret,
    'token': ?token,
  };

  factory EndpointConfig.fromJson(Map<String, dynamic> json) => EndpointConfig(
    hubUrl: json['hubUrl'] as String,
    identity: EndpointIdentity.fromJson(
      json['identity'] as Map<String, dynamic>,
    ),
    secret: json['secret'] as String,
    token: json['token'] as String?,
  );

  // --- Paths within a state directory ---------------------------------------

  static String configPath(String stateDir) => p.join(stateDir, 'config.json');
  static String drivesPath(String stateDir) => p.join(stateDir, 'drives.json');
  static String mountsPath(String stateDir) => p.join(stateDir, 'mounts.json');
  static String syncPath(String stateDir) => p.join(stateDir, 'sync.json');

  /// Loads the config from [stateDir], or null if the endpoint is not set up.
  static Future<EndpointConfig?> load(String stateDir) async {
    final json = await AtomicFile.readJson(configPath(stateDir));
    return json == null ? null : EndpointConfig.fromJson(json);
  }

  /// Persists this config to [stateDir].
  Future<void> save(String stateDir) =>
      AtomicFile.writeJson(configPath(stateDir), toJson());
}
