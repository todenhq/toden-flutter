import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/presence/user_token.dart';

// The shared user-token cases (test/user_token_vectors.json), replayed here as
// the RN, XCTest and JVM suites replay them. The background cases run in the
// native suites, where the flush lives.

void main() {
  final doc = jsonDecode(File('test/user_token_vectors.json').readAsStringSync()) as Map<String, dynamic>;
  final now = doc['nowMillis'] as int;

  test('names the header the server reads', () {
    expect(kUserTokenHeader, doc['header']);
  });

  group('identity check', () {
    for (final v in (doc['identity'] as List).cast<Map<String, dynamic>>()) {
      test(v['name'], () {
        final checked = checkUserToken(
          v['body'],
          externalUserId: v['actingFor'] as String,
          purpose: UserTokenPurpose.values.byName(v['purpose'] as String),
          apiKey: v['apiKey'] as String,
          nowMillis: now,
        );
        expect(checked == null ? 'user_token_mismatch' : 'ok', v['expected']);
      });
    }
  });

  group('refusal codes', () {
    for (final v in (doc['refusals'] as List).cast<Map<String, dynamic>>()) {
      test(v['name'], () {
        final code = userTokenRefusal(v['body']);
        expect(code == null ? null : userTokenErrorWire(code), v['code']);
      });
    }
  });

  group('foreground: one new token, one retry', () {
    setUp(() {
      TodenUserTokens.reset();
      TodenUserTokens.onAccepted = (_) async {};
    });

    for (final v in (doc['foreground'] as List).cast<Map<String, dynamic>>()) {
      test(v['name'], () async {
        final tokens = ['A', 'B', 'C'].map((c) => 'ut_test_${c * 43}').toList();
        var providerCalls = 0;
        Future<Map<String, dynamic>?> provider(UserTokenPurpose purpose) async => {
              'token': tokens[providerCalls++],
              'externalUserId': 'cus_123',
              'purpose': purpose.name,
              'expiresAt': DateTime.now().add(const Duration(hours: 24)).toUtc().toIso8601String(),
            };
        final responses = (v['responses'] as List).cast<Map<String, dynamic>>();
        final headers = <String?>[];
        var request = 0;
        final sent = await sendWithUserToken<Map<String, dynamic>>(
          apiKey: 'pk_test_abc',
          externalUserId: 'cus_123',
          purpose: UserTokenPurpose.presence,
          getUserToken: v['provider'] == true ? provider : null,
          send: (h) async {
            headers.add(h[kUserTokenHeader]);
            final answer = responses[request++];
            final status = answer['status'] as int;
            final options = RequestOptions(path: '/x');
            final body = answer['code'] == null
                ? <String, dynamic>{}
                : {
                    'error': {'type': 'PERMISSION_ERROR', 'code': answer['code']}
                  };
            final response = Response<Map<String, dynamic>>(requestOptions: options, statusCode: status, data: body);
            if (status >= 400) {
              throw DioException(requestOptions: options, response: response, type: DioExceptionType.badResponse);
            }
            return response;
          },
        );
        expect(headers, v['headers']);
        expect(request, v['requests']);
        expect(providerCalls, v['providerCalls']);
        final outcome = sent.refusal != null ? userTokenErrorWire(sent.refusal!) : (sent.ok ? 'ok' : 'error');
        expect(outcome, v['outcome']);
      });
    }
  });
}
