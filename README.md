# OmnyDrive

[![pub package](https://img.shields.io/pub/v/omnydrive.svg?logo=dart&logoColor=00b9fc)](https://pub.dev/packages/omnydrive)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![Dart CI](https://github.com/OmnyGrid/omnydrive/actions/workflows/dart.yml/badge.svg?branch=master)](https://github.com/OmnyGrid/omnydrive/actions/workflows/dart.yml)
[![GitHub Tag](https://img.shields.io/github/v/tag/OmnyGrid/omnydrive?logo=git&logoColor=white)](https://github.com/OmnyGrid/omnydrive/releases)
[![New Commits](https://img.shields.io/github/commits-since/OmnyGrid/omnydrive/latest?logo=git&logoColor=white)](https://github.com/OmnyGrid/omnydrive/network)
[![Last Commits](https://img.shields.io/github/last-commit/OmnyGrid/omnydrive?logo=git&logoColor=white)](https://github.com/OmnyGrid/omnydrive/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/OmnyGrid/omnydrive?logo=github&logoColor=white)](https://github.com/OmnyGrid/omnydrive/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/OmnyGrid/omnydrive?logo=github&logoColor=white)](https://github.com/OmnyGrid/omnydrive)
[![License](https://img.shields.io/github/license/OmnyGrid/omnydrive?logo=open-source-initiative&logoColor=green)](https://github.com/OmnyGrid/omnydrive/blob/master/LICENSE)

**Distributed file & git drive synchronization in pure Dart.**

OmnyDrive lets you **publish** a local directory or git repository as a *drive*,
**clone** or **mirror** it onto other machines, and **sync** changes back and
forth — coordinated by a lightweight **hub** that only ever brokers metadata.
Content streams directly between endpoints; the hub never touches a filesystem.

```text
                publish ──►  ┌─────┐  ◄── discover / route
   Endpoint A ──────────────►│ Hub │◄────────────── Endpoint B
   (serves docs)             └─────┘            (clones docs)
        ▲                                            │
        └──────────── content streamed peer-to-peer ─┘
```

```sh
omnydrive publish ./my-docs --name docs   # on the publisher
omnydrive clone alpha/docs ./docs-copy     # on another machine
omnydrive sync <mountId>                    # push edits / pull updates
```

Synchronization is built around **explicit, content-addressed conflict
detection**: a push that would silently clobber remote work is *refused*, not
merged blindly. The whole engine is available both as **first-class Dart APIs**
and as the **`omnydrive` CLI**.

## API Documentation

See the [API Documentation][api_doc] for the full list of classes and APIs.

[api_doc]: https://pub.dev/documentation/omnydrive/latest/

## Features

- **Hub-coordinated, peer-served.** The hub holds the registry, token auth and
  sync routing; content streams directly between endpoints, so the hub never
  reads or writes a single file.
- **Two providers out of the box.** Filesystem directories (mirrored over HTTP)
  and git repositories (cloned/pushed via the `git` CLI). New providers (S3,
  WebDAV, …) plug in behind a single `DriveProvider` interface.
- **Conflict-first sync.** Every drive carries a baseline reference — a directory
  manifest hash or a git commit SHA. A push only lands when the origin still sits
  at that baseline; a two-sided change surfaces a `ConflictDetectedException`
  instead of clobbering work.
- **Automatic sync direction.** Read-only mounts pull; read-write mounts push,
  pull, or no-op based on which side actually changed, compared against the
  stored baseline.
- **Persisted endpoint state.** `omnydrive login` enrolls an endpoint with a hub
  once and saves identity, credentials and mounts under `--state` (default
  `~/.omnydrive`), so every other command runs without connection flags.
- **Pure Dart, strictly layered.** domain → infrastructure → application →
  transport, with an in-process core that is fully unit-testable without
  sockets — the same orchestration code runs in-memory, in one process, or
  across the network.
- **Three ways in.** Embed the engine (`LocalDriveHub` / `LocalDriveEndpoint`),
  talk to a running hub with the `OmnyClient` SDK, or run the `omnydrive` binary
  — all on the same shared core.
- **Tested.** Unit, integration and end-to-end coverage over real loopback HTTP,
  plus five runnable example scenarios.

## Concepts

| Term | Meaning |
|------|---------|
| **Hub** | Central coordinator: endpoint enrollment, token auth, the drive registry, sync routing. Holds no content. |
| **Endpoint** | A device that publishes, clones and syncs drives. |
| **Drive** | A published source of files (a directory or a git repo), identified as `<endpoint>/<name>`. |
| **Mount** | A drive materialized at a local path (a directory mirror or a git clone). |
| **SyncRef** | The baseline a sync reconciles against — a directory manifest hash or a git commit SHA. |

## Architecture

```text
                 OmnyDrive Core (domain model + contracts)
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
   Providers            Persistence            HTTP Transport
   (directory, git)     (in-memory, file)      (hub + content servers)
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
               Application (LocalDriveHub / LocalDriveEndpoint)
                              │
                    Client SDK  +  `omnydrive` CLI
```

The domain layer has no I/O. Providers and persistence sit behind interfaces,
which is why the same orchestration code runs in an in-memory test, a
single-process demo, or across the network.

```text
lib/
├── omnydrive.dart          # engine-side public API (domain → transport)
├── omnydrive_client.dart   # OmnyClient SDK for talking to a running hub
├── omnydrive_cli.dart      # `omnydrive` CLI entry point as a library
└── src/
    ├── domain/             # value objects, entities, enums, contracts, pure services
    ├── infrastructure/     # providers (directory, git), persistence, HTTP transport
    ├── application/        # LocalDriveHub, LocalDriveEndpoint, ProviderRegistry
    ├── client/             # OmnyClient facade
    ├── cli/                # command-line logic and endpoint config
    └── shared/             # errors, clock, ids, atomic file/lock, observability
```

## Getting started

```yaml
dependencies:
  omnydrive: ^1.0.0
```

Or activate the CLI globally:

```sh
dart pub global activate omnydrive
```

OmnyDrive uses `dart:io` for sockets, the filesystem and process execution, so
it runs on any non-web Dart target. The git provider shells out to the `git`
CLI, which must be on `PATH` for git drives.

## Usage

### CLI

```sh
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

### Library

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

## How it works

1. An **endpoint** enrolls with the hub (`login`), receiving an auth token, and
   advertises a content URL where its drives can be fetched.
2. **Publishing** a directory or git repo registers a **drive** in the hub's
   registry under `<endpoint>/<name>`, along with its current **SyncRef**
   baseline (a manifest hash or a commit SHA). The content stays on the
   publisher.
3. Another endpoint **discovers** drives through the hub and **clones** one,
   creating a local **mount** that records the baseline it was cloned at.
4. **Sync** compares the local mount and the origin against that baseline and
   picks a direction: push local edits, pull remote updates, or — if *both*
   sides moved — refuse with a conflict. Directory content streams over HTTP
   between the two endpoints; git drives are pushed/pulled with the `git` CLI.

## Examples

Five self-contained, runnable scenarios live in [`example/`](example/). Each one
starts an in-process hub and content server over loopback, runs the scenario,
and tears everything down:

| Example | Shows |
|---------|-------|
| [`omnydrive_example.dart`](example/omnydrive_example.dart) | The core round-trip: publish, clone, edit the mirror, push back. |
| [`conflict_detection.dart`](example/conflict_detection.dart) | A push refused because the origin moved off the baseline, then resolved. |
| [`readonly_mirror.dart`](example/readonly_mirror.dart) | A read-only clone that pulls origin updates on sync. |
| [`client_sdk.dart`](example/client_sdk.dart) | Discovering drives and reading content with `OmnyClient`. |
| [`git_drive.dart`](example/git_drive.dart) | Publishing a git repo, cloning, committing, and publishing a feature branch. Requires `git`. |

```sh
dart run example/omnydrive_example.dart
```

## Running the tests

```sh
dart pub get
dart analyze
dart test
```

## Status

`1.0.0` ships the full vertical slice: directory and git providers, the
hub + content HTTP servers, the `OmnyClient` SDK and the `omnydrive` CLI, with
content-addressed conflict detection throughout. Per-endpoint state is
file-backed; hub-side registries are currently in-memory. Planned next:
file/db-backed hub persistence, additional providers (S3, WebDAV), and direct
git-over-hub proxying.

# Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## License

[Apache License - Version 2.0][apache_license]

[apache_license]: https://www.apache.org/licenses/LICENSE-2.0.txt
