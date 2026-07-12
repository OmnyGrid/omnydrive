import 'package:omnyhub/omnyhub.dart' show Middleware, errorEnvelope, mapErrors;

import '../../shared/errors/domain_exception.dart';
import '../../shared/errors/error_codes.dart';

/// Middleware that renders any thrown [DomainException] as the
/// `{success:false, error:{code, message}}` envelope at its status code, and any
/// other error as a `500`.
///
/// This is the shared replacement for the per-server `_guard` helper the two
/// HTTP servers previously duplicated — the hub now maps domain failures to
/// responses centrally, before the framework's own error mapper.
Middleware driveErrorMapper() => mapErrors((error, _) {
  if (error is DomainException) {
    return errorEnvelope(
      error.code,
      error.message,
      statusCode: error.statusCode,
    );
  }
  return errorEnvelope(
    ErrorCodes.internalError,
    'Internal server error',
    statusCode: 500,
  );
});
