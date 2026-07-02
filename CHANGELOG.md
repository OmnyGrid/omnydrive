## 1.10.0

- `GitCredentialStore` is now a **public, exported** class (moved out of the
  private `src/cli` tree into `src/infrastructure/persistence`), so embedding apps
  can reuse the same host-scoped git-credential store — either via `load`/`save`,
  or by composing its in-memory API (`fromJson`/`toJson`/`resolve`/`get`/`put`/
  `remove`/`hosts`) into their own persistence. `load`/`save` take an optional
  `fileName` (defaulting to `defaultFileName`) to host the store elsewhere.
- **The credential file is now `git-credentials.json`** (was `credentials.json`),
  a `git-` prefix that keeps git credentials distinct from any other
  `credentials.json` in the state directory. The name is exposed as
  `GitCredentialStore.defaultFileName`. The `omnydrive credential` CLI reads/writes the
  new file; an existing `credentials.json` is not migrated automatically —
  re-add credentials or rename the file.

## 1.9.0

- Git drives can now authenticate to private remotes with explicit credentials.
  A new `GitCredential` value object models three variants — an HTTPS personal
  access token (`GitPat`), an HTTPS username+password (`GitUserPass`), and an
  SSH private key (`GitSshKey`) — each injecting itself at the single `GitCli`
  process chokepoint (HTTPS via `-c http.extraHeader` basic auth, SSH via
  `GIT_SSH_COMMAND`). `GIT_TERMINAL_PROMPT=0` is always set so a missing or
  wrong credential fails fast instead of hanging.
- Credentials are stored **host-scoped** in a local `credentials.json` (keyed by
  git host, tightened to `0600`) and resolved by the origin's host at
  invocation time via `GitCredentialResolver`. They are never placed on the
  `Drive` entity, so they are never serialized to `drives.json`, registered with
  the hub, or transmitted to peers. Manage them with a new CLI command:
  `omnydrive credential add <host> (--pat | --username/--password | --ssh-key)`,
  `omnydrive credential list`, and `omnydrive credential remove <host>`.
  `publish`/`clone`/`sync` pick up the matching credential automatically by
  host, so no per-command flags are needed. Passphrase-protected SSH keys still
  require an ssh-agent.

## 1.8.0

- Directory sync now preserves the executable (`+x`) bit. `FileManifestEntry`
  records whether a file carries a POSIX execute bit (serialized as
  `executable`, kept out of the content-addressed manifest hash), and the
  destination applies `chmod +x` on write/copy. The manifest differ compares the
  bit explicitly, so a chmod-only change (identical content) still syncs. No-op
  on platforms without execute bits; existing directory references are
  unaffected.

## 1.7.0

- `PathFilter` now matches slash-less patterns at **any depth**, matching
  gitignore semantics. Previously `*.dill` (or any wildcard pattern without a
  `/`) only matched files at the drive root, so nested files like
  `bin/server.dill` slipped past `.omnyignore`/`--exclude`. Patterns with a
  leading or internal `/` (e.g. `/build`, `a/b`) remain anchored to the root.
- Added `PathFilter.scope(prefix, patterns)`, which rewrites raw patterns (e.g.
  from a nested `.omnyignore`) so they apply within a subtree — anchored
  patterns bind to `<prefix>/…`, slash-less patterns to `<prefix>/**/…`,
  mirroring how git applies a nested `.gitignore`.

## 1.6.0

- Default ignore file: a directory can carry a gitignore-style `.omnyignore`
  file at its root listing glob patterns to exclude from the published drive.
  - `omnydrive publish <dir>` consults it **only when neither `--include` nor
    `--exclude` is given**, turning its patterns into the drive's default
    `exclude` set. Explicit filter flags override the file entirely.
  - The patterns are baked into `Drive.filter` at publish time, so every cloner
    and subsequent `sync` automatically skips the ignored sub-paths — no
    client-side configuration.
  - The file name is customizable with `--ignore-file <name>` (defaults to
    `.omnyignore`).
  - New `parseOmnyIgnore` / `loadOmnyIgnore` utilities and the
    `omnyIgnoreFileName` constant are exported from `omnydrive.dart`.
  - Lines are trimmed; blank lines and `#` comments are skipped. Negation
    (`!pattern`) is not supported (PathFilter has no rule ordering to re-include
    an excluded path) and such lines are ignored.

## 1.5.0

- Live sync progress: directory-drive sync now reports per-file upload progress
  as bytes stream, so a TUI/CLI can draw a live progress bar for each of the
  concurrent uploads instead of only learning a file is done after it settles.
  - `ProgressEvent` gains per-item fields: `path`, `itemKind`
    (`transferred`/`copied`/`removed`), `itemState`
    (`started`/`progress`/`completed`), `itemBytes` and `itemTotalBytes` (the
    wire/compressed size), plus `itemSize` (the original uncompressed file size,
    so the real size can be shown alongside compressed progress).
  - `ContentSource.writeBytes` gains an optional `onProgress(sent, total)`
    callback. `HttpContentSource` uploads through a streamed request that reports
    bytes at the socket's own pace; `LocalContentSource` streams via `openWrite`.
  - Each completed path is tagged transferred vs copied (deduplicated), so the
    distinction is visible during and after the sync.
- Final sync report: `SyncMetrics` now carries `transferredPaths`, `copiedPaths`
  and `removedPaths`, plus `bytesOnWire` (bytes after transport compression)
  alongside the existing raw `bytesTransferred`.
- `DriveEndpoint.syncMount` accepts an optional `progress` reporter.
- CLI: `omnydrive sync` renders a live multi-bar transfer view and prints a final
  report (file counts and raw vs on-wire bytes). Pass `-v`/`--verbose` to list
  every transferred/copied/removed path.
- The `omnyDriveVersion` constant (surfaced by `GET /version`) is realigned with
  `pubspec.yaml` after drifting in prior releases.

## 1.4.0

- Performance: directory-drive sync now deduplicates identical content instead
  of transferring it repeatedly. When a write's content hash is already present
  at the destination — either in an existing file or in another file sent the
  same run — the bytes cross the wire once and the destination copies them into
  place. Duplicate build artifacts, vendored files and the like sync for the
  cost of a single payload.
  - New `POST /drives/<endpoint>/<name>/copy` content-server route performs a
    verified in-place copy: it re-hashes the source and returns `409` if it
    drifted or vanished, so the client transparently falls back to a full byte
    transfer (guarding the time-of-check/time-of-use gap).
  - The content server advertises a `server-side-copy` capability in its
    `GET /version` response. Clients probe for it once per transfer; servers
    that don't advertise it (older versions) fall back to full byte transfers,
    so peers interoperate transparently.
  - API: `ContentSource` gains `supportsCopy()` and
    `copy(from, to, expectedHash)`; implemented by `LocalContentSource` and
    `HttpContentSource`.

## 1.3.0

- Performance: directory-drive content now transfers gzip-compressed over HTTP
  by default. File pulls, file pushes and the JSON manifest are gzipped at level
  4 (near-identical ratio to the default level 6, markedly faster) using
  `dart:io`'s `GZipCodec` — no new dependency. Negotiation rides the standard
  `Accept-Encoding` / `Content-Encoding` headers, so peers interoperate
  transparently.
  - Already-compressed file types (jpeg, png, mp4, zip, pdf, …) and payloads
    below the threshold (1 KiB by default) are sent verbatim, since re-gzipping
    them costs CPU for no real gain.
  - The content-source HTTP client disables transparent auto-uncompress so gzip
    handling stays explicit and deterministic; `HttpContentSource` and
    `networkedProviderRegistry` share a single client factory.
- API: compression is now configurable and integration-friendly.
  - `ContentCompression` is an injectable policy (`enabled`, `level`, `minBytes`,
    `skipExtensions`) with `ContentCompression.standard` / `.disabled` presets,
    accepted by `ContentServer`, `HttpContentSource`, `networkedProviderRegistry`
    and `OmnyClient`. Defaults are unchanged.
  - Fix: reading a compressed file (> 1 KiB) through `OmnyClient` — or any
    integrator-supplied `http.Client` with transparent gzip — no longer throws
    `FormatException: Filter error, bad data`. Decoding now also checks the gzip
    magic bytes (`ContentCompression.looksGzipped`), so it never double-decodes a
    body an auto-uncompress client already inflated. `OmnyClient` defaults to the
    non-auto-uncompress content client.
  - `ContentCompression` is transport-agnostic (no HTTP dependency) and exported
    from `omnydrive_client.dart`, so custom `ContentSource` transports can reuse
    `encode` / `decode` / `shouldCompress` / `looksGzipped` directly.

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
