/// Stable, machine-readable error codes returned to API consumers and used by
/// the CLI to choose exit codes. Always snake_case.
class ErrorCodes {
  // Generic.
  static const String validationError = 'validation_error';
  static const String invalidJson = 'invalid_json';
  static const String notFound = 'not_found';
  static const String internalError = 'internal_error';

  // Drives.
  static const String driveNotFound = 'drive_not_found';
  static const String driveAlreadyExists = 'drive_already_exists';

  // Endpoints.
  static const String endpointNotFound = 'endpoint_not_found';
  static const String endpointAlreadyExists = 'endpoint_already_exists';

  // Mounts.
  static const String mountNotFound = 'mount_not_found';
  static const String mountAlreadyExists = 'mount_already_exists';

  // Auth & access control.
  static const String unauthorized = 'unauthorized';
  static const String accessDenied = 'access_denied';
  static const String readOnlyViolation = 'read_only_violation';
  static const String capabilityUnsupported = 'capability_unsupported';

  // Synchronization & conflicts.
  static const String conflictDetected = 'conflict_detected';
  static const String refMoved = 'ref_moved';
  static const String syncFailed = 'sync_failed';
  static const String lockHeld = 'lock_held';

  // Providers.
  static const String providerError = 'provider_error';
  static const String unsupportedProvider = 'unsupported_provider';

  const ErrorCodes._();
}
