# OmnyDrive examples

Each program is self-contained: it starts an in-process hub and content server
over loopback, runs the scenario, and tears everything down. Run any of them with
`dart run example/<file>`.

| Example | Shows |
|---------|-------|
| [`omnydrive_example.dart`](omnydrive_example.dart) | The core round-trip: publish a directory, clone it, edit the mirror, push back to the origin. |
| [`conflict_detection.dart`](conflict_detection.dart) | A push refused because the origin moved off the baseline (`ConflictDetectedException`), then resolved by re-cloning and re-applying. |
| [`readonly_mirror.dart`](readonly_mirror.dart) | A read-only clone that pulls origin updates on sync. |
| [`client_sdk.dart`](client_sdk.dart) | Discovering drives and reading content with `OmnyClient` (the `omnydrive_client` SDK). |
| [`git_drive.dart`](git_drive.dart) | Publishing a git repo, cloning it, committing locally, and publishing the commit as a feature branch. Requires `git`. |

[`scenario.dart`](scenario.dart) is a shared test harness used by the examples —
not part of the public API.
