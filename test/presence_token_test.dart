import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/address_collection.dart';
import 'package:toden_flutter/src/config/verification_config.dart';
import 'package:toden_flutter/src/presence/presence_auto_report.dart';
import 'package:toden_flutter/src/presence/presence_store.dart';
import 'package:toden_flutter/src/screens/contact_verification_settings.dart';
import 'package:toden_flutter/src/services/api_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// The presence token proves a report comes from the phone that captured the
// pin. It arrives in the 202, after the pin was saved. A port of the RN SDK's
// presenceToken.test.ts.

class _TempDocs extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _TempDocs(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kyc_sdk_flutter/presence');
  final nativeCalls = <MethodCall>[];

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('presence_token');
    PathProviderPlatform.instance = _TempDocs(dir.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        nativeCalls.add(call);
        return null;
      },
    );
  });
  setUp(nativeCalls.clear);

  group('savePresenceToken', () {
    test('keeps the token beside the pin and hands it to the native tier', () async {
      await savePresencePin('user_keep', 6.4281, 3.4219);
      await savePresenceToken('user_keep', 'tok_1');
      expect((await loadPresencePin('user_keep'))?.presenceToken, 'tok_1');
      expect(nativeCalls.single.method, 'setPresenceToken');
      expect(nativeCalls.single.arguments, {'externalUserId': 'user_keep', 'presenceToken': 'tok_1'});
    });

    test('does nothing without a pin', () async {
      await savePresenceToken('user_none', 'tok_1');
      expect(await loadPresencePin('user_none'), isNull);
      expect(nativeCalls, isEmpty);
    });

    test('a new capture drops the old token', () async {
      await savePresencePin('user_new', 6.4281, 3.4219);
      await savePresenceToken('user_new', 'tok_1');
      await savePresencePin('user_new', 6.4281, 3.4219);
      expect((await loadPresencePin('user_new'))?.presenceToken, isNull);
    });

    test('ignores a value the server would refuse', () async {
      await savePresencePin('user_bad', 6.4281, 3.4219);
      await savePresenceToken('user_bad', null);
      await savePresenceToken('user_bad', '  ');
      await savePresenceToken('user_bad', 'x' * 129);
      expect((await loadPresencePin('user_bad'))?.presenceToken, isNull);
      expect(nativeCalls, isEmpty);
    });
  });

  group('keepPresenceToken', () {
    VerificationConfig config(String userId, {required bool presence}) => VerificationConfig(
          apiKey: 'pk_test_1',
          country: 'NG',
          userId: userId,
          addressCollection: AddressCollectionConfig.fromJson({
            'enabled': true,
            'presence': {'enabled': presence},
          }),
        );

    test('stores it for a presence flow', () async {
      await savePresencePin('user_flow', 6.4281, 3.4219);
      await keepPresenceToken(config('user_flow', presence: true), 'tok_1');
      expect((await loadPresencePin('user_flow'))?.presenceToken, 'tok_1');
    });

    test('a flow with presence off leaves a running check its own token', () async {
      await savePresencePin('user_running', 6.4281, 3.4219);
      await savePresenceToken('user_running', 'tok_1');
      await keepPresenceToken(config('user_running', presence: false), 'tok_2');
      expect((await loadPresencePin('user_running'))?.presenceToken, 'tok_1');
    });
  });

  group('responses', () {
    test('the 202 carries the token', () {
      final res = VerifyResponse.fromJson({
        'verificationId': 'ver_1',
        'status': 'processing',
        'presenceToken': 'tok_1',
      });
      expect(res.presenceToken, 'tok_1');
      expect(VerifyResponse.fromJson({'verificationId': 'ver_1', 'status': 'processing'}).presenceToken, isNull);
    });

    test('the send carries the length', () {
      expect(ContactSendResponse.fromJson({'challengeId': 'c', 'codeLength': 8}).codeLength, 8);
      expect(ContactSendResponse.fromJson({'challengeId': 'c'}).codeLength, isNull);
    });
  });

  group('sentCodeLength', () {
    test('takes the length the server says it sent', () {
      expect(sentCodeLength(8, 6), 8);
      expect(sentCodeLength(4, 6), 4);
    });

    test('keeps the configured length when an older server says nothing', () {
      expect(sentCodeLength(null, 5), 5);
    });

    test('ignores a length no code could have', () {
      expect(sentCodeLength(3, 6), 6);
      expect(sentCodeLength(9, 6), 6);
    });
  });

  group('wiring', () {
    String read(String path) => File(path).readAsStringSync();

    test('every report and every arm carries the token', () {
      expect(read('lib/src/presence/presence_reporter.dart'), contains("'presenceToken': pin.presenceToken"));
      expect(read('lib/src/presence/background_presence.dart'), contains("'presenceToken': pin.presenceToken"));
      expect(read('lib/src/presence/foreground_presence.dart'), contains("'presenceToken': pin.presenceToken"));
    });

    test('both submits store it before the result is published', () {
      final provider = read('lib/src/providers/verification_provider.dart');
      expect('keepPresenceToken(_config, response.presenceToken)'.allMatches(provider).length, 2);
      final kept = provider.indexOf('keepPresenceToken(_config, response.presenceToken)');
      expect(kept, lessThan(provider.indexOf('submissionResult: result', kept)));
    });

    test('the contact step names the session and sizes the field from the response', () {
      final screen = read('lib/src/screens/contact_verification_screen.dart');
      expect(screen, contains('sessionId: ref.read(kYCNotifierProvider).sessionId'));
      expect(screen, contains('sentCodeLength(res.codeLength, settings.codeLength)'));
    });

    test('the native stores persist it', () {
      expect(jsonEncode(read('android/src/main/kotlin/co/toden/flutter/PresenceStore.kt')), contains('presenceToken'));
      expect(
        read('ios/toden_flutter/Sources/toden_flutter/PresenceStore.swift'),
        contains('presenceToken'),
      );
    });
  });
}
