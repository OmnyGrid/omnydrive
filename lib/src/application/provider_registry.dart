import '../domain/contracts/drive_provider.dart';
import '../domain/contracts/git_credential_resolver.dart';
import '../domain/entities/drive.dart';
import '../domain/enums/provider_type.dart';
import '../domain/value_objects/endpoint_id.dart';
import '../infrastructure/providers/directory/directory_provider.dart';
import '../infrastructure/providers/git/git_cli.dart';
import '../infrastructure/providers/git/git_provider.dart';
import '../shared/errors/domain_exception.dart';
import '../shared/utils/clock.dart';

/// Maps a [ProviderType] to the [DriveProvider] that handles it.
///
/// The application layer never instantiates providers directly; it asks the
/// registry. New backends (S3, WebDAV, ...) become available everywhere simply
/// by registering them here.
class ProviderRegistry {
  final Map<ProviderType, DriveProvider> _byType;

  ProviderRegistry(Iterable<DriveProvider> providers)
    : _byType = {for (final p in providers) p.type: p} {
    if (_byType.isEmpty) {
      throw ArgumentError('ProviderRegistry requires at least one provider');
    }
  }

  /// Builds the default registry wired with the local directory and git
  /// providers for [endpoint]. The directory provider resolves local `dir`/
  /// `file` origins; supply a custom registry to add HTTP-backed resolution.
  factory ProviderRegistry.local({
    required EndpointId endpoint,
    GitCli git = const GitCli(),
    GitCredentialResolver? credentials,
    Clock? clock,
  }) => ProviderRegistry([
    DirectoryProvider(endpoint: endpoint),
    GitProvider(
      endpoint: endpoint,
      git: git,
      credentials: credentials,
      clock: clock,
    ),
  ]);

  /// Whether a provider is registered for [type].
  bool supports(ProviderType type) => _byType.containsKey(type);

  /// The provider types this registry can handle.
  List<ProviderType> get types => _byType.keys.toList(growable: false);

  /// Returns the provider for [type], or throws [ProviderException] if none is
  /// registered.
  DriveProvider forType(ProviderType type) {
    final provider = _byType[type];
    if (provider == null) {
      throw ProviderException(
        'No provider registered for "${type.wireValue}"'
        ' (have: ${types.map((t) => t.wireValue).join(', ')})',
      );
    }
    return provider;
  }

  /// Returns the provider that handles [drive].
  DriveProvider forDrive(Drive drive) => forType(drive.provider);
}
