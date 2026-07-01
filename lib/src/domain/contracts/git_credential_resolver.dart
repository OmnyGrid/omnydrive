import '../value_objects/git_credential.dart';
import '../value_objects/origin_uri.dart';

/// Resolves the [GitCredential] (if any) to use for a given git [OriginUri].
///
/// Implementations typically key on the origin's host, so a single credential
/// can serve every repository on a given remote. Returning `null` means "no
/// explicit credential" — git falls back to the host's own configuration.
abstract class GitCredentialResolver {
  GitCredential? resolve(OriginUri origin);
}
