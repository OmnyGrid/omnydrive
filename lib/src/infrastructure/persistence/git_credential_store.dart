import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/contracts/git_credential_resolver.dart';
import '../../domain/value_objects/git_credential.dart';
import '../../domain/value_objects/origin_uri.dart';
import '../../shared/utils/atomic_file.dart';

/// A host-scoped store of Git credentials, persisted at
/// `<stateDir>/git-credentials.json`.
///
/// Credentials are kept only in this local endpoint state — never on the
/// [Drive] entity — so they are never transmitted to the hub or peers. Each
/// entry is keyed by the git host (e.g. `github.com`); [resolve] looks a
/// credential up by the host of an [OriginUri].
///
/// The class is public so embedding apps can reuse it — either through
/// [load]/[save], or by composing the in-memory API ([fromJson]/[toJson]/
/// [resolve]/[get]/[put]/[remove]/[hosts]) into their own persistence (e.g.
/// omnyshell nests per-principal host maps in a single structured file).
///
/// The file is best-effort restricted to owner-only permissions (`0600`) on
/// POSIX platforms after each write.
class GitCredentialStore implements GitCredentialResolver {
  /// The `git-`-prefixed file name [load]/[save] use within a state directory,
  /// keeping git credentials distinct from any other `credentials.json`.
  static const String defaultFileName = 'git-credentials.json';

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
  /// not exist yet. [fileName] overrides [defaultFileName].
  static Future<GitCredentialStore> load(
    String stateDir, {
    String fileName = defaultFileName,
  }) async {
    final json = await AtomicFile.readJson(p.join(stateDir, fileName));
    return json == null
        ? GitCredentialStore()
        : GitCredentialStore.fromJson(json);
  }

  /// Persists this store to [stateDir], then tightens file permissions to owner
  /// read/write only where the platform supports it. [fileName] overrides
  /// [defaultFileName].
  Future<void> save(
    String stateDir, {
    String fileName = defaultFileName,
  }) async {
    final path = p.join(stateDir, fileName);
    await AtomicFile.writeJson(path, toJson());
    if (!Platform.isWindows) {
      // Best-effort: don't fail the operation if chmod is unavailable.
      try {
        await Process.run('chmod', ['600', path]);
      } catch (_) {}
    }
  }
}
