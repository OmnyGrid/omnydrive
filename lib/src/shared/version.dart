/// The OmnyDrive package version, surfaced by the `GET /version` endpoint of
/// both the hub and the endpoint content server. Keep in sync with
/// `pubspec.yaml`.
const String omnyDriveVersion = '1.5.0';

/// Capability token advertised in the content server's `GET /version`
/// `capabilities` list when it can perform a verified server-side copy
/// (`POST .../copy`). Clients probe for this before reusing duplicate content
/// instead of re-transferring it, so older servers transparently fall back to
/// full byte transfers.
const String serverSideCopyCapability = 'server-side-copy';
