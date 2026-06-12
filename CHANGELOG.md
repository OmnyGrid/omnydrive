## 1.2.0

- Feature: publish only part of a local directory with sub-path filters. A new
  `PathFilter` value object (gitignore-style globs: `*`, `**`, `?`, trailing-slash
  / bare-directory subtree matching) carries `include`/`exclude` patterns with
  exclude-wins, include-as-whitelist semantics.
  - CLI: `omnydrive publish` gains repeatable `--include` / `--exclude` options
    (directory drives only; combining them with `--git` is rejected).
  - API: `DriveEndpoint.publishDirectory` accepts an optional `filter:`; the
    filter is stored on `Drive` (serialized, registered with the hub) and applied
    during the manifest walk in `ManifestBuilder`, so excluded files are never
    hashed.
  - The filter is enforced at the serving boundary (`ContentServer`), so every
    cloner automatically receives only the surviving sub-paths with no
    client-side configuration. `currentRef`/`describe` (provider contract) and
    the `ContentSourceResolver` now thread the filter through; `syncMount`
    applies it on both sides so a filtered drive syncs cleanly.

## 1.1.4

- Performance: building a directory manifest (the `currentRef` computed twice on
  every `syncMount`) no longer reads and SHA-256-hashes every file. A persisted
  stat-cache lets `ManifestBuilder` reuse a file's recorded hash when its
  `(size, mtime)` are unchanged, so an unchanged mount with thousands of files
  costs one `stat()` per file instead of a full read + hash. The produced
  `FileManifest` — and therefore the directory's content-addressed `SyncRef` —
  is byte-identical to a full rebuild.
  - The cache lives at `<root>/.omnydrive/manifest-cache.json` (an
    already-ignored directory) and is purely advisory: a missing, malformed, or
    version-mismatched cache, or a write failure on a read-only filesystem,
    falls back to a full rebuild and never errors.
  - Correctness: a file is trusted only when its mtime is strictly older than
    the cache's build timestamp, re-hashing anything modified within the
    filesystem's mtime resolution of the last build (git's "racy clean" rule).
  - Added `ManifestCache`/`CachedEntry`
    (`lib/src/infrastructure/providers/directory/manifest_cache.dart`) and a
    `useCache` flag on `ManifestBuilder` (default on; off disables the cache).

## 1.1.3

- Performance: directory drive sync now transfers changed files concurrently
  instead of one at a time. `DirectorySynchronizer` runs up to
  `transferConcurrency` (default 8) reads/writes in flight over the existing
  per-file content routes, so syncs dominated by per-file HTTP round-trips are
  substantially faster. Conflict detection, baseline checks, and progress
  reporting are unchanged. The limit is configurable via the
  `DirectorySynchronizer` constructor.
  - Added `forEachConcurrent` bounded worker-pool helper
    (`lib/src/shared/utils/concurrent.dart`).

## 1.1.2

- Fixed: syncing a mount could silently delete local-only changes. A pull
  overwrites/deletes local files to match the origin, and `syncMount` previously
  pulled whenever it was not pushing — so a read-only mount (or any mount whose
  local copy had diverged) would discard a newly created or edited file instead
  of preserving it. `syncMount` now only pushes when the mount is read-write and
  only the local side changed; any other divergent case raises
  `ConflictDetectedException` (via the new `ConflictDetector.detectForPull`)
  rather than destroying local work.
  - Added `ConflictKind.localDivergence` for a local copy that diverged from the
    baseline but cannot be published.

## 1.1.1

- `ManifestBuilder`:
  - Updated default `ignoredDirs` to include `.dart_tool` directory.
  - Documentation updated to reflect the addition of `.dart_tool` to ignored directories.

- Dependency updates:
  - `args`: ^2.5.0 → ^2.7.0
  - `crypto`: ^3.0.3 → ^3.0.7
  - `http`: ^1.2.0 → ^1.6.0
  - `path`: ^1.9.0 → ^1.9.1
  - `shelf`: ^1.4.1 → ^1.4.2
  - `lints`: ^6.0.0 → ^6.1.0
  - `test`: ^1.25.6 → ^1.31.1

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
