import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/presence/presence_watch_status.dart';
import 'package:toden_flutter/src/presence/presence_watch_wait.dart';
import 'package:toden_flutter/src/presence/user_token.dart';

// User tokens on the presence status read, over a real local server: the
// header only with a checked token, 4.4.0's request without one, one new token
// and one retry on a refusal, nothing sent for another user's token, and the
// presence token handed to the native store only after the identity check.
// (No TestWidgetsFlutterBinding: it would answer every HTTP call itself.)

const apiKey = 'pk_dev_abc';
String tokenOf(String c) => 'ut_dev_${c * 43}';
Map<String, dynamic> mint(String c, {String user = 'cus_123'}) => {
      'object': 'user_token',
      'id': 'utk_$c',
      'token': tokenOf(c),
      'purpose': 'presence',
      'externalUserId': user,
      'expiresAt': DateTime.now().add(const Duration(hours: 24)).toUtc().toIso8601String(),
      'maxUses': null,
    };

void main() {
  late HttpServer server;
  late String devUrl;
  final seen = <Map<String, String?>>[];
  final answers = <int>[];
  final handedOver = <CheckedUserToken>[];

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    devUrl = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      seen.add({
        'authorization': req.headers.value('authorization'),
        'token': req.headers.value(kUserTokenHeader),
      });
      final status = answers.isEmpty ? 200 : answers.removeAt(0);
      final body = status == 200
          ? {'status': 'in_progress'}
          : {
              'error': {'type': 'PERMISSION_ERROR', 'code': status == 403 ? 'user_token_invalid' : 'invalid_api_key'}
            };
      req.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await req.response.close();
    });
  });
  tearDownAll(() => server.close(force: true));

  setUp(() {
    seen.clear();
    answers.clear();
    handedOver.clear();
    TodenUserTokens.reset();
    TodenUserTokens.onAccepted = (t) async => handedOver.add(t);
  });

  group('legacy publishable key: the wire is unchanged', () {
    test('no provider: no header', () async {
      final status = await fetchPresenceWatchStatus(apiKey: apiKey, externalUserId: 'cus_123', devUrl: devUrl);
      expect(status?.state, PresenceWatchState.inProgress);
      expect(seen.single, {'authorization': 'Bearer $apiKey', 'token': null});
    });

    test('a provider that answers null, or fails, sends no header', () async {
      await fetchPresenceWatchStatus(
          apiKey: apiKey, externalUserId: 'cus_123', devUrl: devUrl, getUserToken: (_) async => null);
      await fetchPresenceWatchStatus(
          apiKey: apiKey,
          externalUserId: 'cus_123',
          devUrl: devUrl,
          getUserToken: (_) async => throw Exception('422 invalid_publishable_key'));
      expect(seen.map((s) => s['token']), [null, null]);
      expect(handedOver, isEmpty);
    });
  });

  group('scoped publishable key', () {
    test('sends the checked token and hands it to the native store', () async {
      final purposes = <UserTokenPurpose>[];
      await fetchPresenceWatchStatus(
          apiKey: apiKey,
          externalUserId: 'cus_123',
          devUrl: devUrl,
          getUserToken: (p) async {
            purposes.add(p);
            return mint('A');
          });
      expect(purposes, [UserTokenPurpose.presence]);
      expect(seen.single['token'], tokenOf('A'));
      expect(handedOver.single.externalUserId, 'cus_123');
    });

    test('a token for another user sends nothing and says why', () async {
      final read = await readWatch(apiKey, devUrl, 'cus_123', getUserToken: (_) async => mint('A', user: 'cus_999'));
      expect(read.refusal, UserTokenErrorCode.userTokenMismatch);
      expect(seen, isEmpty);
      expect(handedOver, isEmpty);
    });

    test('a refused token: one new token, one retry', () async {
      answers.addAll([403, 200]);
      final tokens = [mint('A'), mint('B')];
      final status = await fetchPresenceWatchStatus(
          apiKey: apiKey, externalUserId: 'cus_123', devUrl: devUrl, getUserToken: (_) async => tokens.removeAt(0));
      expect(status?.state, PresenceWatchState.inProgress);
      expect(seen.map((s) => s['token']), [tokenOf('A'), tokenOf('B')]);
    });

    test('a 401 is an API-key problem: no new token, no retry', () async {
      answers.add(401);
      var calls = 0;
      final read = await readWatch(apiKey, devUrl, 'cus_123', getUserToken: (_) async {
        calls++;
        return mint('A');
      });
      expect(read.state, isNull);
      expect(read.refusal, isNull);
      expect(calls, 1);
      expect(seen, hasLength(1));
    });
  });

  group('setUserToken', () {
    test('refuses a token for another user', () async {
      await expectLater(
        TodenUserTokens.setUserToken(mint('C', user: 'cus_999'), apiKey: apiKey, externalUserId: 'cus_123'),
        throwsA(isA<UserTokenException>().having((e) => e.code, 'code', UserTokenErrorCode.userTokenMismatch)),
      );
      expect(handedOver, isEmpty);
    });

    test('a cold start with nothing armed refuses', () async {
      TodenUserTokens.armedReporter = () async => null;
      await expectLater(TodenUserTokens.setUserToken(mint('C')), throwsA(isA<UserTokenException>()));
      expect(handedOver, isEmpty);
    });

    test('a cold start reads the armed user and key itself, as React Native does', () async {
      TodenUserTokens.armedReporter = () async => (externalUserId: 'cus_123', apiKey: apiKey);
      await TodenUserTokens.setUserToken(mint('C'));
      expect(handedOver.single.externalUserId, 'cus_123');
    });

    test('the armed user never vouches for a token for someone else', () async {
      TodenUserTokens.armedReporter = () async => (externalUserId: 'cus_123', apiKey: apiKey);
      await expectLater(TodenUserTokens.setUserToken(mint('C', user: 'cus_999')), throwsA(isA<UserTokenException>()));
      // Named for another user than the armed one: the armed key is not borrowed.
      await expectLater(
        TodenUserTokens.setUserToken(mint('C', user: 'cus_999'), externalUserId: 'cus_999'),
        throwsA(isA<UserTokenException>()),
      );
      expect(handedOver, isEmpty);
    });

    test('hands a matching token to the native store', () async {
      await TodenUserTokens.setUserToken(mint('C'), apiKey: apiKey, externalUserId: 'cus_123');
      expect(handedOver.single.token, tokenOf('C'));
    });
  });
}
