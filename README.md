# OmnyDrive

Distributed file & git drive synchronization in pure Dart.

OmnyDrive lets you **publish** a local directory or git repository as a *drive*,
**clone** or **mirror** it onto other machines, and **sync** changes back and
forth — coordinated by a lightweight **hub** that only ever brokers metadata.
Synchronization is built around explicit, content-addressed conflict detection:
a push that would silently clobber remote work is refused, not merged blindly.

- **Two providers out of the box** — filesystem directories (mirrored over HTTP)
  and git repositories (cloned/pushed via the `git` CLI). New providers (S3,
  WebDAV, …) plug in behind a single interface.
- **Hub-coordinated, peer-served** — the hub holds the registry, auth and sync
  routing; content streams directly between endpoints, so the hub never touches
  a filesystem.
- **Conflict-first sync** — every drive has a baseline reference (a directory
  manifest hash or a git commit SHA). A push only lands when the origin still
  sits at that baseline.
- **Pure Dart, layered** — domain → infrastructure → application → transport,
  with an in-process core that is fully unit-testable without sockets.

## Concepts

| Term | Meaning |
|------|---------|
| **Hub** | Central coordinator: endpoint enrollment, token auth, the drive registry, sync routing. Holds no content. |
| **Endpoint** | A device that publishes, clones and syncs drives. |
| **Drive** | A published source of files (a directory or a git repo), identified as `<endpoint>/<name>`. |
| **Mount** | A drive materialized at a local path (a directory mirror or a git clone). |
| **SyncRef** | The baseline a sync reconciles against — a directory manifest hash or a git commit SHA. |

## Install

```yaml
dependencies:
  omnydrive: ^0.1.0
```

Activate the CLI globally with `dart pub global activate omnydrive`.

## CLI

```console
# 1. Run a hub (on the coordinating machine)
omnydrive serve --port 7070

# 2. On the publishing machine: enroll, serve content, publish a directory
omnydrive login --hub http://hub.local:7070 \
    --id alpha --serve-url http://alpha.local:8080
omnydrive serve-content --port 8080 &
omnydrive publish ./my-docs --name docs

# 3. On another machine: enroll, then clone and sync
omnydrive login --hub http://hub.local:7070 \
    --id beta --serve-url http://beta.local:8080
omnydrive drives                       # discover: alpha/docs
omnydrive clone alpha/docs ./docs-copy # prints a mount id
omnydrive mounts                       # list local mounts
omnydrive sync <mountId>               # push local edits / pull remote changes
```

Endpoint state (identity, credentials, mounts) is persisted under `--state`
(default `~/.omnydrive`). Exit codes map to error categories (2 = validation,
3 = not found, 4 = unauthorized, 5 = access denied, 6 = conflict, …).

## Library

Embed the engine directly — no servers required:

```dart
import 'package:omnydrive/omnydrive.dart';

final hub = LocalDriveHub();
final endpoint = LocalDriveEndpoint(identity: myIdentity, hub: hub);

final drive = await endpoint.publishDirectory(path: '/data/docs', name: 'docs');
final mount = await endpoint.cloneDrive(driveId: drive.id.value, dest: '/tmp/m');
final result = await endpoint.syncMount(mount.id.value); // throws on conflict
```

Or talk to a running hub with the client SDK:

```dart
import 'package:omnydrive/omnydrive_client.dart';

final client = OmnyClient('http://hub.local:7070');
for (final reg in await client.drives()) {
  final manifest = await client.content(reg).manifest();
  print('${reg.id}: ${manifest.entries.length} file(s)');
}
await client.close();
```

A complete, runnable walkthrough lives in
[`example/omnydrive_example.dart`](example/omnydrive_example.dart):

```console
dart run example/omnydrive_example.dart
```

## Architecture

```
domain/          value objects, entities, enums, contracts, pure services
infrastructure/  providers (directory, git), persistence (in-memory, file), HTTP transport
application/     LocalDriveHub, LocalDriveEndpoint, ProviderRegistry — the orchestration
client/ + cli/   OmnyClient facade and the `omnydrive` command line
```

The domain layer has no I/O; providers and persistence are swapped behind
interfaces, which is why the same orchestration code runs in an in-memory test,
a single-process demo, or across the network.

## Status

v0.1.0 — directory and git providers, hub + content HTTP servers, client SDK and
CLI. Hub-side persistence is in-memory; per-endpoint state is file-backed.

## Additional information

Issues and contributions welcome at the
[repository](https://github.com/OmnyGrid/omnydrive).
