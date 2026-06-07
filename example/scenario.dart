// Shared harness for the OmnyDrive examples: it starts an in-process hub and a
// content server over loopback and hands out ready-to-use endpoints, so each
// example file can focus on the scenario it demonstrates rather than on setup.
//
// This is not part of the public API — it just removes boilerplate from the
// example programs next to it.

import 'dart:io';

import 'package:omnydrive/omnydrive.dart';

class Scenario {
  final HttpServer _hubHttp;
  final HttpServer _contentHttp;
  final InMemoryDriveRegistry _published;

  /// Base URL of the running hub.
  final String hubUrl;

  /// Base URL of the publisher's content server.
  final String contentUrl;

  /// Temporary root that all working directories are created under.
  final Directory root;

  Scenario._(
    this._hubHttp,
    this._contentHttp,
    this._published,
    this.hubUrl,
    this.contentUrl,
    this.root,
  );

  static Future<Scenario> start() async {
    final root = await Directory.systemTemp.createTemp('omnydrive_scenario_');
    final hubHttp = await HubServer(
      LocalDriveHub(),
    ).serve(address: '127.0.0.1', port: 0);
    final published = InMemoryDriveRegistry();
    final contentHttp = await ContentServer(
      published,
    ).serve(address: '127.0.0.1', port: 0);
    return Scenario._(
      hubHttp,
      contentHttp,
      published,
      'http://127.0.0.1:${hubHttp.port}',
      'http://127.0.0.1:${contentHttp.port}',
      root,
    );
  }

  /// A publishing endpoint, reachable at [contentUrl], sharing the content
  /// server's drive registry.
  Future<LocalDriveEndpoint> publisher(String id) async {
    final hub = HttpDriveHub(hubUrl);
    final identity = _identity(id, contentUrl);
    final creds = await hub.enroll(identity: identity);
    await hub.login(endpointId: identity.id, secret: creds.secret);
    return LocalDriveEndpoint(
      identity: identity,
      hub: hub,
      published: _published,
      providers: ProviderRegistry.local(endpoint: identity.id),
    );
  }

  /// A consuming endpoint that resolves remote directory drives over HTTP.
  Future<LocalDriveEndpoint> cloner(String id) async {
    final hub = HttpDriveHub(hubUrl);
    final identity = _identity(id, 'http://$id.invalid');
    final creds = await hub.enroll(identity: identity);
    await hub.login(endpointId: identity.id, secret: creds.secret);
    return LocalDriveEndpoint(
      identity: identity,
      hub: hub,
      providers: networkedProviderRegistry(endpoint: identity.id),
    );
  }

  /// Creates (and returns the path of) a fresh working directory under [root].
  String dir(String name) {
    final d = Directory('${root.path}/$name')..createSync(recursive: true);
    return d.path;
  }

  EndpointIdentity _identity(String id, String baseUrl) => EndpointIdentity(
    id: EndpointId(id),
    displayName: id,
    baseUrl: baseUrl,
    capabilities: CapabilitySet(Capability.values),
    registeredAt: DateTime.now().toUtc(),
  );

  Future<void> stop() async {
    await _hubHttp.close(force: true);
    await _contentHttp.close(force: true);
    await root.delete(recursive: true);
  }
}
