import 'dart:io';

import '../domain/contracts/git_credential_resolver.dart';
import '../domain/value_objects/git_credential.dart';
import '../domain/value_objects/origin_uri.dart';
import '../shared/utils/atomic_file.dart';
import 'endpoint_config.dart';

/// A host-scoped store of Git credentials, persisted at
/// `<stateDir>/credentials.json`.
///
/// Credentials are kept only in this local endpoint state — never on the
/// [Drive] entity — so they are never transmitted to the hub or peers. Each
/// entry is keyed by the git host (e.g. `github.com`); [resolve] looks a
/// credential up by the host of an [OriginUri].
///
/// The file is best-effort restricted to owner-only permissions (`0600`) on
/// POSIX platforms after each write.
class GitCredentialStore implements GitCredentialResolver {
  final Map<String, GitCredential> _byHost;

  GitCredentialStore([Map<String, GitCredential>? byHost])
    : _byHost = {...?byHost};

  /// The hosts that currently have a stored credential.
  List<String> get hosts => _byHost.keys.toList(growable: false);

  GitCredential? get(String host) => _byHost[host];

  void put(String host, GitCredential credential) => _byHost[host] = credential;

  /// Removes the credential for [host]. Returns true if one was present.
  bool remove(String host) => _byHost.remove(host) != null;

  @override
  GitCredential? resolve(OriginUri origin) {
    final host = origin.host;
    return host == null ? null : _byHost[host];
  }

  Map<String, dynamic> toJson() => {
    'credentials': {
      for (final entry in _byHost.entries) entry.key: entry.value.toJson(),
    },
  };

  factory GitCredentialStore.fromJson(Map<String, dynamic> json) {
    final raw = (json['credentials'] as Map<String, dynamic>?) ?? const {};
    return GitCredentialStore({
      for (final entry in raw.entries)
        entry.key: GitCredential.fromJson(entry.value as Map<String, dynamic>),
    });
  }

  /// Loads the store from [stateDir], returning an empty store if the file does
  /// not exist yet.
  static Future<GitCredentialStore> load(String stateDir) async {
    final json = await AtomicFile.readJson(
      EndpointConfig.credentialsPath(stateDir),
    );
    return json == null
        ? GitCredentialStore()
        : GitCredentialStore.fromJson(json);
  }

  /// Persists this store to [stateDir], then tightens file permissions to owner
  /// read/write only where the platform supports it.
  Future<void> save(String stateDir) async {
    final path = EndpointConfig.credentialsPath(stateDir);
    await AtomicFile.writeJson(path, toJson());
    if (!Platform.isWindows) {
      // Best-effort: don't fail the operation if chmod is unavailable.
      try {
        await Process.run('chmod', ['600', path]);
      } catch (_) {}
    }
  }
}
