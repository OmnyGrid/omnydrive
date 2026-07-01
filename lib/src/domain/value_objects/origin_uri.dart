import '../../shared/errors/domain_exception.dart';

/// How an [OriginUri] is addressed.
enum OriginUriScheme { dir, http, https, git, ssh, file }

/// Describes where a drive's content originates: a filesystem directory, an
/// HTTP(S) endpoint URL, or a git URL (https/ssh/file).
///
/// The classification drives which provider and transport are used.
class OriginUri {
  /// The raw URI/path as supplied.
  final String value;

  /// The detected scheme.
  final OriginUriScheme scheme;

  OriginUri._(this.value, this.scheme);

  /// Parses [input], inferring the scheme. A bare path (no `scheme://`) is
  /// treated as a local directory.
  factory OriginUri(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Origin URI is required');
    }
    final scheme = _classify(trimmed);
    return OriginUri._(trimmed, scheme);
  }

  static OriginUriScheme _classify(String value) {
    if (value.startsWith('https://')) return OriginUriScheme.https;
    if (value.startsWith('http://')) return OriginUriScheme.http;
    if (value.startsWith('git://')) return OriginUriScheme.git;
    if (value.startsWith('ssh://') || _looksLikeScpSyntax(value)) {
      return OriginUriScheme.ssh;
    }
    if (value.startsWith('file://')) return OriginUriScheme.file;
    // Anything else is treated as a local directory path.
    return OriginUriScheme.dir;
  }

  // git's scp-like syntax, e.g. `git@github.com:org/repo.git`.
  static bool _looksLikeScpSyntax(String value) {
    final at = value.indexOf('@');
    final colon = value.indexOf(':');
    return at > 0 && colon > at && !value.contains('://');
  }

  /// Whether the content lives on another host (vs the local filesystem).
  bool get isRemote =>
      scheme == OriginUriScheme.http ||
      scheme == OriginUriScheme.https ||
      scheme == OriginUriScheme.git ||
      scheme == OriginUriScheme.ssh;

  /// The remote host this origin addresses, or null for local `dir`/`file`
  /// origins. Used to look up a host-scoped git credential.
  String? get host {
    if (_looksLikeScpSyntax(value)) {
      // git@github.com:org/repo.git -> github.com
      final at = value.indexOf('@');
      final colon = value.indexOf(':');
      return value.substring(at + 1, colon);
    }
    switch (scheme) {
      case OriginUriScheme.http:
      case OriginUriScheme.https:
      case OriginUriScheme.git:
      case OriginUriScheme.ssh:
        final parsed = Uri.parse(value);
        return parsed.host.isEmpty ? null : parsed.host;
      case OriginUriScheme.dir:
      case OriginUriScheme.file:
        return null;
    }
  }

  /// Whether this looks like a git endpoint (URL or scp syntax).
  bool get isGitUrl =>
      scheme == OriginUriScheme.git ||
      scheme == OriginUriScheme.ssh ||
      (scheme == OriginUriScheme.https && value.endsWith('.git')) ||
      (scheme == OriginUriScheme.http && value.endsWith('.git'));

  @override
  bool operator ==(Object other) =>
      other is OriginUri && other.value == value && other.scheme == scheme;

  @override
  int get hashCode => Object.hash(value, scheme);

  @override
  String toString() => value;
}
