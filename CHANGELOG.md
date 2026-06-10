## 1.1.0

- Added: per-file progress events during directory sync. `DirectorySynchronizer.apply`
  now emits a `transferring` `ProgressEvent` after each file is written or deleted (in
  both push and pull directions), carrying the path (`message`), cumulative `bytes`, and
  `completed`/`total` counts — enabling consumers to render live progress. Backward
  compatible: the start and `done` events are unchanged and `progress` stays optional.

## 1.0.0

First stable release. Promotes the complete vertical slice — directory and git
providers, the hub + content HTTP servers, the `OmnyClient` SDK and the
`omnydrive` CLI — to a stable API, with content-addressed conflict detection
throughout.

- Domain model: drives, mounts, endpoints, sync refs, conflicts, capabilities.
- Providers: directory (HTTP-mirrored) and git (via the `git` CLI).
- Application layer: `LocalDriveHub` and `LocalDriveEndpoint` (publish, clone,
  sync) with content-addressed conflict detection.
- HTTP transport: hub server, endpoint content server, and matching clients
  (`HttpDriveHub`, `HttpContentSource`).
- Client SDK: `OmnyClient` and the `package:omnydrive/omnydrive_client.dart`
  surface.
- `omnydrive` CLI: `serve`, `serve-content`, `login`, `publish`, `clone`,
  `sync`, `mounts`, `drives`, with file-backed per-endpoint state.
- In-memory and file-backed persistence implementations.
- Runnable examples: core round-trip, conflict detection & resolution,
  read-only mirror, client SDK, and a git drive walkthrough.

## 0.1.0

Initial release.

- Domain model: drives, mounts, endpoints, sync refs, conflicts, capabilities.
- Providers: directory (HTTP-mirrored) and git (via the `git` CLI).
- Application layer: `LocalDriveHub` and `LocalDriveEndpoint` (publish, clone,
  sync) with content-addressed conflict detection.
- HTTP transport: hub server, endpoint content server, and matching clients
  (`HttpDriveHub`, `HttpContentSource`).
- Client SDK: `OmnyClient` and the `package:omnydrive/omnydrive_client.dart`
  surface.
- `omnydrive` CLI: `serve`, `serve-content`, `login`, `publish`, `clone`,
  `sync`, `mounts`, `drives`, with file-backed per-endpoint state.
- In-memory and file-backed persistence implementations.
- Runnable examples: core round-trip, conflict detection & resolution,
  read-only mirror, client SDK, and a git drive walkthrough.
