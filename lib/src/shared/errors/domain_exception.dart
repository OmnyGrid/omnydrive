import '../../domain/entities/conflict.dart';
import 'error_codes.dart';

/// Base type for any expected, user-facing failure raised by the domain or
/// application layers.
///
/// Controllers translate these into JSON error responses via
/// [the JSON response factory], and the CLI maps the [code] to a process exit
/// code. The hierarchy is sealed so callers can pattern-match exhaustively.
sealed class DomainException implements Exception {
  /// Stable, machine-readable error code (see [ErrorCodes]).
  final String code;

  /// Human-readable description of the failure.
  final String message;

  /// HTTP status code controllers should respond with.
  final int statusCode;

  const DomainException({
    required this.code,
    required this.message,
    required this.statusCode,
  });

  @override
  String toString() => '$runtimeType($code): $message';
}

/// Invalid input from a caller (bad value object, malformed DTO, etc.).
class ValidationException extends DomainException {
  const ValidationException(String message)
    : super(
        code: ErrorCodes.validationError,
        message: message,
        statusCode: 400,
      );
}

/// A referenced resource (drive, endpoint, mount, ...) does not exist.
class NotFoundException extends DomainException {
  const NotFoundException({required super.code, required super.message})
    : super(statusCode: 404);
}

/// A resource cannot be created because it already exists, or a generic
/// state conflict prevents the operation.
class ConflictException extends DomainException {
  const ConflictException({required super.code, required super.message})
    : super(statusCode: 409);
}

/// The caller is authenticated but not permitted to perform the operation,
/// or the operation violates the drive's access mode (e.g. writing to a
/// read-only mount).
class AccessDeniedException extends DomainException {
  const AccessDeniedException({
    super.code = ErrorCodes.accessDenied,
    required super.message,
  }) : super(statusCode: 403);
}

/// The caller is not authenticated (missing or invalid bearer token).
class UnauthorizedException extends DomainException {
  const UnauthorizedException([String message = 'Authentication required'])
    : super(code: ErrorCodes.unauthorized, message: message, statusCode: 401);
}

/// Raised by the synchronization engine when the source reference moved away
/// from the baseline the caller synchronized against, so publishing local
/// changes would silently clobber remote work.
///
/// Carries the [conflict] describing what diverged so the caller can resolve
/// it explicitly.
class ConflictDetectedException extends DomainException {
  /// Structured details of the divergence (kind, expected/actual refs, paths).
  final Conflict conflict;

  ConflictDetectedException(this.conflict)
    : super(
        code: ErrorCodes.conflictDetected,
        message: conflict.message,
        statusCode: 409,
      );
}

/// A mount-level lock is currently held by another operation; the caller
/// should retry once the in-flight operation completes.
class LockHeldException extends DomainException {
  const LockHeldException(String message)
    : super(code: ErrorCodes.lockHeld, message: message, statusCode: 423);
}

/// A provider operation failed (a `git` subprocess returned non-zero, a file
/// could not be read, a remote was unreachable, etc.).
class ProviderException extends DomainException {
  const ProviderException(String message)
    : super(code: ErrorCodes.providerError, message: message, statusCode: 500);
}

/// A synchronization operation failed for a reason other than a detected
/// conflict (transfer error, apply failure, ...).
class SyncException extends DomainException {
  const SyncException(String message)
    : super(code: ErrorCodes.syncFailed, message: message, statusCode: 500);
}

/// A request body could not be parsed as a JSON object.
class InvalidJsonException extends DomainException {
  const InvalidJsonException(String message)
    : super(code: ErrorCodes.invalidJson, message: message, statusCode: 400);
}
