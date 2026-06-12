import 'package:http/http.dart' as http;

import '../../application/provider_registry.dart';
import '../../domain/contracts/content_source.dart';
import '../../domain/value_objects/endpoint_id.dart';
import '../../domain/value_objects/origin_uri.dart';
import '../../domain/value_objects/path_filter.dart';
import '../../shared/utils/clock.dart';
import '../providers/directory/directory_provider.dart';
import '../providers/git/git_cli.dart';
import '../providers/git/git_provider.dart';
import 'http_content_source.dart';

/// Builds a [ProviderRegistry] whose directory provider resolves remote
/// `http(s)` origins through an [HttpContentSource] (and still handles local
/// `dir`/`file` origins). This is what a networked endpoint uses so it can
/// clone and sync directory drives served by other endpoints.
ProviderRegistry networkedProviderRegistry({
  required EndpointId endpoint,
  http.Client? client,
  GitCli git = const GitCli(),
  Clock? clock,
}) {
  final httpClient = client ?? http.Client();

  // The filter only bites on local directories; a remote `http(s)` origin is
  // already filtered server-side, so the parameter is ignored there.
  ContentSource resolve(
    OriginUri origin, {
    required bool writable,
    PathFilter? filter,
  }) {
    switch (origin.scheme) {
      case OriginUriScheme.http:
      case OriginUriScheme.https:
        return HttpContentSource(
          origin.value,
          client: httpClient,
          isWritable: writable,
        );
      default:
        return DirectoryProvider.localDirectoryResolver(
          origin,
          writable: writable,
          filter: filter,
        );
    }
  }

  return ProviderRegistry([
    DirectoryProvider(endpoint: endpoint, resolveSource: resolve),
    GitProvider(endpoint: endpoint, git: git, clock: clock),
  ]);
}
