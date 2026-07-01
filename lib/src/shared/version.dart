/// The OmnyDrive package version, surfaced by the `GET /version` endpoint of
/// both the hub and the endpoint content server. Keep in sync with
/// `pubspec.yaml`.
const String omnyDriveVersion = '1.9.0';

/// Capability token advertised in the content server's `GET /version`
/// `capabilities` list when it can perform a verified server-side copy
/// (`POST .../copy`). Clients probe for this before reusing duplicate content
/// instead of re-transferring it, so older servers transparently fall back to
/// full byte transfers.
const String serverSideCopyCapability = 'server-side-copy';

/// HTTP header (and copy-request JSON field) signalling that a written file
/// should be marked executable at the destination. Sent as `'1'` on a `PUT`
/// file write and as a boolean `executable` field on a `POST .../copy`; absent
/// or any other value means non-executable, so older servers degrade safely.
const String executableHeader = 'x-omny-executable';
