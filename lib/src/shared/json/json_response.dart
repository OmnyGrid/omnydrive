import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../errors/domain_exception.dart';
import '../errors/error_codes.dart';

/// Centralized JSON response factory. Keeps the envelope identical across every
/// endpoint of both the hub and endpoint content servers:
///
///   { "success": true, "data": {...} }
///   { "success": false, "error": { "code": "...", "message": "..." } }
class JsonResponse {
  static const _headers = {'content-type': 'application/json; charset=utf-8'};

  static Response ok(Object? data, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: jsonEncode({'success': true, 'data': data}),
      headers: _headers,
    );
  }

  static Response created(Object? data) => ok(data, statusCode: 201);

  /// Encodes [data] as JSON without the `{success, data}` envelope. Used for
  /// payloads consumed by external tooling that expects a bare document.
  static Response rawJson(Object? data, {int statusCode = 200}) =>
      Response(statusCode, body: jsonEncode(data), headers: _headers);

  static Response noContent() => Response(204, headers: _headers);

  static Response error({
    required int statusCode,
    required String code,
    required String message,
  }) {
    return Response(
      statusCode,
      body: jsonEncode({
        'success': false,
        'error': {'code': code, 'message': message},
      }),
      headers: _headers,
    );
  }

  static Response fromException(DomainException e) =>
      error(statusCode: e.statusCode, code: e.code, message: e.message);

  static Response internalError() => error(
    statusCode: 500,
    code: ErrorCodes.internalError,
    message: 'Internal server error',
  );

  static Response notFound([String message = 'Resource not found']) =>
      error(statusCode: 404, code: ErrorCodes.notFound, message: message);

  const JsonResponse._();
}
