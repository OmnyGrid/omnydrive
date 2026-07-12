import 'dart:convert';

import 'package:omnydrive/src/infrastructure/http/drive_http.dart';
import 'package:omnydrive/src/shared/errors/domain_exception.dart';
import 'package:omnyhub/omnyhub.dart'
    show HubRequest, HubResponse, TransportProtocol;
import 'package:test/test.dart';

HubRequest get req => HubRequest(
  method: 'GET',
  uri: Uri.parse('http://h/'),
  protocol: TransportProtocol.http,
);

void main() {
  group('driveErrorMapper', () {
    test(
      'renders a DomainException as its status + {success,error} envelope',
      () async {
        final handler = driveErrorMapper()(
          (_) async => throw const ValidationException('bad input'),
        );
        final res = await handler(req);
        expect(res.statusCode, 400);
        expect(jsonDecode(await res.readAsString()), {
          'success': false,
          'error': {'code': 'validation_error', 'message': 'bad input'},
        });
      },
    );

    test('maps a NotFoundException with a custom code', () async {
      final handler = driveErrorMapper()(
        (_) async => throw const NotFoundException(
          code: 'drive_not_found',
          message: 'gone',
        ),
      );
      final res = await handler(req);
      expect(res.statusCode, 404);
      expect(
        (jsonDecode(await res.readAsString())['error'] as Map)['code'],
        'drive_not_found',
      );
    });

    test('maps an unexpected error to a 500 envelope', () async {
      final handler = driveErrorMapper()((_) async => throw StateError('boom'));
      final res = await handler(req);
      expect(res.statusCode, 500);
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(body['success'], false);
      expect((body['error'] as Map)['code'], 'internal_error');
    });

    test('passes a successful response through unchanged', () async {
      final handler = driveErrorMapper()((_) async => HubResponse.text('ok'));
      expect((await handler(req)).statusCode, 200);
    });
  });
}
