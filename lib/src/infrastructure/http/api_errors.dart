import 'dart:convert';

import '../../shared/errors/domain_exception.dart';
import '../../shared/errors/error_codes.dart';

/// Translates a non-2xx HTTP response from a hub or content server back into the
/// matching [DomainException], so callers of the HTTP clients see the same typed
/// failures they would from an in-process implementation.
///
/// The body is expected to be the standard error envelope
/// `{"success": false, "error": {"code": ..., "message": ...}}`, but a bare or
/// empty body degrades gracefully.
Never throwApiError(int statusCode, String body) {
  String code;
  String message;
  try {
    final decoded = jsonDecode(body);
    final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
    if (error is Map<String, dynamic>) {
      code = (error['code'] as String?) ?? ErrorCodes.internalError;
      message = (error['message'] as String?) ?? 'Request failed';
    } else {
      code = ErrorCodes.internalError;
      message = body.isEmpty ? 'Request failed ($statusCode)' : body;
    }
  } catch (_) {
    code = ErrorCodes.internalError;
    message = body.isEmpty ? 'Request failed ($statusCode)' : body;
  }

  switch (statusCode) {
    case 400:
      throw ValidationException(message);
    case 401:
      throw UnauthorizedException(message);
    case 403:
      throw AccessDeniedException(code: code, message: message);
    case 404:
      throw NotFoundException(code: code, message: message);
    case 409:
      throw ConflictException(code: code, message: message);
    case 423:
      throw LockHeldException(message);
    default:
      throw ProviderException(message);
  }
}
