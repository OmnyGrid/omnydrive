import 'dart:convert';

import '../../shared/errors/domain_exception.dart';

/// A credential used to authenticate against a private Git remote.
///
/// Credentials never live on the [Drive] entity (which is serialized to the hub
/// and peers). They are held only in local endpoint state and resolved by host
/// at git-invocation time. Each variant knows how to express itself as
/// additions to a `git` command:
///
/// * [configArgs] — leading `-c key=value` args (used for HTTPS basic auth via
///   `http.extraHeader`), mirroring the `-c user.name=...` pattern `GitCli`
///   already uses for commits.
/// * [envVars] — process environment overrides (used for SSH via
///   `GIT_SSH_COMMAND`).
///
/// Secrets are always masked in [toString].
sealed class GitCredential {
  const GitCredential();

  /// Extra `-c key=value` arguments to prepend to a git invocation.
  List<String> configArgs();

  /// Environment overrides to apply to a git invocation.
  Map<String, String> envVars();

  /// Serializes to JSON for the local, host-keyed credential store. This is the
  /// only place the raw secret is written, and only to local state.
  Map<String, dynamic> toJson();

  /// Reconstructs a credential from its stored JSON form.
  factory GitCredential.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String?;
    switch (kind) {
      case 'pat':
        return GitPat(
          token: json['token'] as String,
          username: (json['username'] as String?) ?? 'x-access-token',
        );
      case 'userpass':
        return GitUserPass(
          username: json['username'] as String,
          password: json['password'] as String,
        );
      case 'ssh':
        return GitSshKey(
          keyPath: json['keyPath'] as String,
          passphrase: json['passphrase'] as String?,
        );
      default:
        throw InvalidJsonException('Unknown git credential kind: $kind');
    }
  }

  /// Builds the `http.extraHeader` config arg carrying HTTP Basic auth for the
  /// given [username]/[secret]. Shared by the two HTTPS variants.
  static List<String> _basicAuthArgs(String username, String secret) {
    final encoded = base64.encode(utf8.encode('$username:$secret'));
    return ['-c', 'http.extraHeader=Authorization: Basic $encoded'];
  }
}

/// A personal access token presented over HTTPS. Most hosts (GitHub, GitLab)
/// accept any non-empty [username] alongside the token; the default works
/// everywhere.
class GitPat extends GitCredential {
  final String token;
  final String username;

  GitPat({required this.token, this.username = 'x-access-token'}) {
    if (token.trim().isEmpty) {
      throw const ValidationException('Git PAT token is required');
    }
  }

  @override
  List<String> configArgs() => GitCredential._basicAuthArgs(username, token);

  @override
  Map<String, String> envVars() => const {};

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'pat',
    'username': username,
    'token': token,
  };

  @override
  String toString() => 'GitPat(username: $username, token: ***)';
}

/// A username and password presented over HTTPS via HTTP Basic auth.
class GitUserPass extends GitCredential {
  final String username;
  final String password;

  GitUserPass({required this.username, required this.password}) {
    if (username.trim().isEmpty) {
      throw const ValidationException('Git username is required');
    }
    if (password.trim().isEmpty) {
      throw const ValidationException('Git password is required');
    }
  }

  @override
  List<String> configArgs() => GitCredential._basicAuthArgs(username, password);

  @override
  Map<String, String> envVars() => const {};

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'userpass',
    'username': username,
    'password': password,
  };

  @override
  String toString() => 'GitUserPass(username: $username, password: ***)';
}

/// An SSH private key used for `ssh://` and scp-syntax remotes.
///
/// Limitation: a passphrase-protected key cannot be used non-interactively
/// without an ssh-agent. [passphrase] is retained for a future `SSH_ASKPASS`
/// upgrade; the v1 `GIT_SSH_COMMAND` below assumes an unencrypted key or a key
/// already loaded into an agent.
class GitSshKey extends GitCredential {
  final String keyPath;
  final String? passphrase;

  GitSshKey({required this.keyPath, this.passphrase}) {
    if (keyPath.trim().isEmpty) {
      throw const ValidationException('SSH key path is required');
    }
  }

  @override
  List<String> configArgs() => const [];

  @override
  Map<String, String> envVars() => {
    'GIT_SSH_COMMAND':
        'ssh -i $keyPath -o IdentitiesOnly=yes '
        '-o StrictHostKeyChecking=accept-new',
  };

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'ssh',
    'keyPath': keyPath,
    if (passphrase != null) 'passphrase': passphrase,
  };

  @override
  String toString() =>
      'GitSshKey(keyPath: $keyPath'
      '${passphrase != null ? ', passphrase: ***' : ''})';
}
