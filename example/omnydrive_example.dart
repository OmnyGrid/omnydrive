// A self-contained OmnyDrive demo: it starts a hub and a content server in the
// same process (over loopback), publishes a directory from one endpoint, clones
// it from another, edits the mirror and pushes the change back to the origin —
// the same path a real multi-machine deployment takes.
//
// Run with: dart run example/omnydrive_example.dart

import 'dart:io';

import 'package:omnydrive/omnydrive.dart';

Future<void> main() async {
  // --- Working directories --------------------------------------------------
  final root = await Directory.systemTemp.createTemp('omnydrive_example_');
  final originDir = Directory('${root.path}/origin')..createSync();
  File('${originDir.path}/readme.md').writeAsStringSync('hello from origin\n');
  File('${originDir.path}/notes.txt').writeAsStringSync('first note\n');

  // --- Start the hub --------------------------------------------------------
  final hub = LocalDriveHub();
  final hubHttp = await HubServer(hub).serve(address: '127.0.0.1', port: 0);
  final hubUrl = 'http://127.0.0.1:${hubHttp.port}';
  print('hub listening at $hubUrl');

  // --- Start the publisher's content server ---------------------------------
  // The endpoint and its content server share one `published` registry.
  final published = InMemoryDriveRegistry();
  final contentHttp = await ContentServer(
    published,
  ).serve(address: '127.0.0.1', port: 0);
  final contentUrl = 'http://127.0.0.1:${contentHttp.port}';
  print('content server listening at $contentUrl');

  // --- Publisher: enroll, then publish the origin directory -----------------
  final publisherHub = HttpDriveHub(hubUrl);
  final publisherIdentity = EndpointIdentity(
    id: EndpointId('alpha'),
    displayName: 'Alpha',
    baseUrl: contentUrl,
    capabilities: CapabilitySet(Capability.values),
    registeredAt: DateTime.now().toUtc(),
  );
  final creds = await publisherHub.enroll(identity: publisherIdentity);
  await publisherHub.login(
    endpointId: publisherIdentity.id,
    secret: creds.secret,
  );
  final publisher = LocalDriveEndpoint(
    identity: publisherIdentity,
    hub: publisherHub,
    published: published,
    providers: ProviderRegistry.local(endpoint: publisherIdentity.id),
  );
  final drive = await publisher.publishDirectory(
    path: originDir.path,
    name: 'docs',
  );
  print('\npublished drive: ${drive.id}');

  // --- Cloner: discover and clone the drive over HTTP -----------------------
  final clonerHub = HttpDriveHub(hubUrl);
  final clonerIdentity = EndpointIdentity(
    id: EndpointId('beta'),
    displayName: 'Beta',
    baseUrl: 'http://beta.invalid',
    capabilities: CapabilitySet(Capability.values),
    registeredAt: DateTime.now().toUtc(),
  );
  final clonerCreds = await clonerHub.enroll(identity: clonerIdentity);
  await clonerHub.login(
    endpointId: clonerIdentity.id,
    secret: clonerCreds.secret,
  );
  final cloner = LocalDriveEndpoint(
    identity: clonerIdentity,
    hub: clonerHub,
    providers: networkedProviderRegistry(endpoint: clonerIdentity.id),
  );

  print('drives on hub: ${(await cloner.hub.listDrives()).map((d) => d.id)}');

  final mirrorDir = '${root.path}/mirror';
  final mount = await cloner.cloneDrive(
    driveId: drive.id.value,
    dest: mirrorDir,
  );
  print('\ncloned ${mount.driveId} -> $mirrorDir');
  print(
    '  readme.md: ${File('$mirrorDir/readme.md').readAsStringSync().trim()}',
  );

  // --- Edit the mirror and push back to the origin --------------------------
  File('$mirrorDir/readme.md').writeAsStringSync('edited on the mirror\n');
  File('$mirrorDir/added.txt').writeAsStringSync('brand new file\n');
  final result = await cloner.syncMount(mount.id.value);
  print(
    '\nsynced: ${result.appliedChanges} change(s), now at ${result.newRef}',
  );

  print('\norigin after push:');
  print(
    '  readme.md: '
    '${File('${originDir.path}/readme.md').readAsStringSync().trim()}',
  );
  print(
    '  added.txt: '
    '${File('${originDir.path}/added.txt').readAsStringSync().trim()}',
  );

  // --- Tear down ------------------------------------------------------------
  await hubHttp.stop();
  await contentHttp.stop();
  await root.delete(recursive: true);
  print('\ndone.');
}
