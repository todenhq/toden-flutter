import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/presence/user_token.dart';
import 'package:toden_flutter/src/services/api_service.dart';
import 'package:toden_flutter/src/services/mount_user_token.dart';

// The embedded face mount with a scoped key (design rev 4, section 14): a
// fresh biometric token before /session/start, one retry on
// user_token_required, and nothing at all without a provider. Mirrors the RN
// SDK's mountUserToken.test.ts.

final a = 'ut_test_${'A' * 43}';
final b = 'ut_test_${'B' * 43}';
Map<String, dynamic> mint(String token, {String user = 'cus_123'}) => {
      'token': token,
      'externalUserId': user,
      'purpose': 'biometric',
      'expiresAt': DateTime.now().toUtc().add(const Duration(minutes: 10)).toIso8601String(),
    };

class Calls {
  final purposes = <UserTokenPurpose>[];
  final List<Map<String, dynamic>?> answers;
  Calls(this.answers);
  TodenUserTokenProvider get provider => (purpose) async {
        purposes.add(purpose);
        return answers[purposes.length - 1];
      };
}

VerificationApiException refusal(int status, String code) =>
    VerificationApiException(statusCode: status, error: code);

Future<Map<String, String>> headersFor(String? scope, {TodenUserTokenProvider? provider, String? user = 'cus_123'}) =>
    mountTokenHeaders(apiKey: 'pk_test_abc', externalUserId: user, scope: scope, getUserToken: provider);

void main() {
  setUp(TodenUserTokens.reset);

  group('mountTokenHeaders', () {
    test('no provider: no header and no fetch, as 4.4.0', () async {
      expect(await headersFor('biometric-authentication'), isEmpty);
    });

    test('a face scope with a provider fetches a biometric token', () async {
      final calls = Calls([mint(a)]);
      expect(await headersFor('biometric-authentication', provider: calls.provider), {kUserTokenHeader: a});
      expect(calls.purposes, [UserTokenPurpose.biometric]);
    });

    test('enrolment is a face scope too', () async {
      final calls = Calls([mint(a)]);
      expect(await headersFor('biometric-enrollment', provider: calls.provider), {kUserTokenHeader: a});
    });

    test('a fresh token per mount, never the cached one (each mount spends a use)', () async {
      final calls = Calls([mint(a), mint(b)]);
      await headersFor('biometric-authentication', provider: calls.provider);
      expect(await headersFor('biometric-authentication', provider: calls.provider), {kUserTokenHeader: b});
      expect(calls.purposes.length, 2);
    });

    test('a non-face scope sends nothing', () async {
      final calls = Calls([mint(a)]);
      expect(await headersFor('full-kyc', provider: calls.provider), isEmpty);
      expect(await headersFor(null, provider: calls.provider), isEmpty);
      expect(calls.purposes, isEmpty);
    });

    test('no user: nothing to ask for', () async {
      final calls = Calls([mint(a)]);
      expect(await headersFor('biometric-authentication', provider: calls.provider, user: null), isEmpty);
      expect(calls.purposes, isEmpty);
    });

    test("a token for someone else is never sent", () async {
      final calls = Calls([mint(a, user: 'cus_other')]);
      await expectLater(
        headersFor('biometric-authentication', provider: calls.provider),
        throwsA(isA<UserTokenException>().having((e) => e.code, 'code', UserTokenErrorCode.userTokenMismatch)),
      );
    });
  });

  group('startWithMountToken', () {
    Future<String> start(Calls? calls, String? scope, List<Map<String, String>> sent, {List<Object> fail = const []}) =>
        startWithMountToken(
          apiKey: 'pk_test_abc',
          externalUserId: 'cus_123',
          scope: scope,
          getUserToken: calls?.provider,
          start: (headers) async {
            sent.add(headers);
            if (sent.length <= fail.length) throw fail[sent.length - 1];
            return 'ses_1';
          },
        );

    test('a workflow mount told user_token_required fetches once and retries once', () async {
      final calls = Calls([mint(a)]);
      final sent = <Map<String, String>>[];
      expect(await start(calls, null, sent, fail: [refusal(403, 'user_token_required')]), 'ses_1');
      expect(sent, [<String, String>{}, {kUserTokenHeader: a}]);
    });

    test('no second retry when the retried mount is refused again', () async {
      final calls = Calls([mint(a)]);
      final sent = <Map<String, String>>[];
      final refused = refusal(403, 'user_token_required');
      await expectLater(start(calls, null, sent, fail: [refused, refused]), throwsA(same(refused)));
      expect(sent.length, 2);
    });

    test('a mount that already sent a token is not retried', () async {
      final calls = Calls([mint(a), mint(b)]);
      final sent = <Map<String, String>>[];
      final refused = refusal(403, 'user_token_required');
      await expectLater(start(calls, 'biometric-authentication', sent, fail: [refused]), throwsA(same(refused)));
      expect(sent, [
        {kUserTokenHeader: a}
      ]);
    });

    test('without a provider user_token_required is surfaced, never retried', () async {
      final sent = <Map<String, String>>[];
      final refused = refusal(403, 'user_token_required');
      await expectLater(start(null, null, sent, fail: [refused]), throwsA(same(refused)));
      expect(sent, [<String, String>{}]);
    });

    test('too_many_attempts is surfaced, never retried', () async {
      final calls = Calls([mint(a)]);
      final sent = <Map<String, String>>[];
      final refused = refusal(429, 'too_many_attempts');
      await expectLater(start(calls, null, sent, fail: [refused]), throwsA(same(refused)));
      expect(sent.length, 1);
      expect(calls.purposes, isEmpty);
    });
  });

  group('wire', wireTests);

  group('remountFixes', () {
    Future<Map<String, dynamic>?> provider(UserTokenPurpose _) async => null;

    test('user_token_invalid with a provider and a user', () {
      expect(remountFixes(refusal(403, 'user_token_invalid'), externalUserId: 'cus_123', getUserToken: provider), isTrue);
    });
    test('not without a provider, a user, or for another code', () {
      expect(remountFixes(refusal(403, 'user_token_invalid'), externalUserId: 'cus_123'), isFalse);
      expect(remountFixes(refusal(403, 'user_token_invalid'), externalUserId: null, getUserToken: provider), isFalse);
      expect(remountFixes(refusal(429, 'too_many_attempts'), externalUserId: 'cus_123', getUserToken: provider), isFalse);
      expect(remountFixes(Exception('offline'), externalUserId: 'cus_123', getUserToken: provider), isFalse);
    });
  });
}

// ─── The wire: the header on /session/start only when there is a token, and
// the v1 error envelope read as a code (it used to be cast as a String). ──────

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body, {this.status = 200});
  final Object body;
  final int status;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

VerificationApiService _api(_Adapter adapter) =>
    VerificationApiService(baseUrl: 'https://api.example', apiKey: 'pk_test_x', httpClientAdapter: adapter);

void wireTests() {
  final ok = {'sessionId': 'ses_1', 'url': 'https://example/ses_1'};

  test('startSession sends no user token header, as 4.4.0', () async {
    final adapter = _Adapter(ok);
    await _api(adapter).startSession(externalUserId: 'cus_123');
    expect(adapter.requests.single.headers.keys.map((k) => k.toLowerCase()), isNot(contains('x-toden-user-token')));
  });

  test('startSessionWithUserToken sends the token in X-Toden-User-Token', () async {
    final adapter = _Adapter(ok);
    await _api(adapter).startSessionWithUserToken(externalUserId: 'cus_123', headers: {kUserTokenHeader: a});
    expect(adapter.requests.single.headers[kUserTokenHeader], a);
    expect(adapter.requests.single.path, '/api/v1/session/start');
  });

  test('a v1 error envelope maps to its code', () async {
    final adapter = _Adapter({
      'error': {'code': 'user_token_invalid', 'message': 'The user token is no longer valid.'}
    }, status: 403);
    await expectLater(
      _api(adapter).startSession(externalUserId: 'cus_123'),
      throwsA(isA<VerificationApiException>()
          .having((e) => e.error, 'error', 'user_token_invalid')
          .having((e) => e.statusCode, 'status', 403)
          .having((e) => e.message, 'message', 'The user token is no longer valid.')),
    );
  });

  test('a flat error still maps as before', () async {
    final adapter = _Adapter({'error': 'too_many_attempts', 'message': 'Slow down.'}, status: 429);
    await expectLater(
      _api(adapter).startSession(externalUserId: 'cus_123'),
      throwsA(isA<VerificationApiException>().having((e) => e.error, 'error', 'too_many_attempts')),
    );
  });
}
