import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:toden_flutter/src/presence/presence_store.dart';

// The HMAC presenceToken in device-only storage (user token design rev 4,
// R65). With the native side present, the 202's token is kept in the Keychain
// (this device only) or noBackupFilesDir, never in myaza-kyc-presence.json
// (the documents directory, which backups copy), and a token an older build
// left in the file is moved once, then deleted from it. A port of the RN SDK's
// presenceTokenSecure.test.ts.

class _TempDocs extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _TempDocs(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kyc_sdk_flutter/presence');
  late Directory dir;
  // The native store: one record, as the Keychain item and the no-backup file hold.
  Map<String, String>? native;
  var nativeRefuses = false;

  File file() => File('${dir.path}/myaza-kyc-presence.json');
  Map<String, dynamic> fileJson() =>
      file().existsSync() ? jsonDecode(file().readAsStringSync()) as Map<String, dynamic> : {};

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('presence_token_device_only');
    PathProviderPlatform.instance = _TempDocs(dir.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map).cast<String, Object?>();
      final user = args['externalUserId'] as String;
      switch (call.method) {
        case 'setPresenceToken':
          if (nativeRefuses) return false;
          native = {'externalUserId': user, 'token': args['presenceToken'] as String};
          return true;
        case 'readPresenceToken':
          return {'token': native?['externalUserId'] == user ? native!['token'] : null, 'held': false};
        case 'forgetPresenceToken':
          if (native?['externalUserId'] == user) native = null;
          return null;
      }
      return null;
    });
  });
  setUp(() {
    native = null;
    nativeRefuses = false;
  });

  test('the token is kept natively and never written to the backed-up file', () async {
    await savePresencePin('u1', 6.4, 3.4);
    await savePresenceToken('u1', 'tok_1');
    expect(native, {'externalUserId': 'u1', 'token': 'tok_1'});
    expect(file().readAsStringSync(), isNot(contains('tok_1')));
    expect((await loadPresencePin('u1'))?.presenceToken, 'tok_1');
  });

  test('a token an older build left in the file is moved once, then deleted from it', () async {
    await savePresencePin('u2', 6.4, 3.4);
    final pins = fileJson();
    (pins['u2'] as Map)['presenceToken'] = 'tok_old';
    file().writeAsStringSync(jsonEncode(pins));
    expect((await loadPresencePin('u2'))?.presenceToken, 'tok_old');
    expect(native, {'externalUserId': 'u2', 'token': 'tok_old'});
    expect((fileJson()['u2'] as Map).containsKey('presenceToken'), isFalse);
    expect((await loadPresencePin('u2'))?.presenceToken, 'tok_old');
  });

  test('when the native side cannot keep it, the file copy stays', () async {
    await savePresencePin('u3', 6.4, 3.4);
    nativeRefuses = true;
    await savePresenceToken('u3', 'tok_3');
    expect((fileJson()['u3'] as Map)['presenceToken'], 'tok_3');
    expect((await loadPresencePin('u3'))?.presenceToken, 'tok_3');
    expect((fileJson()['u3'] as Map)['presenceToken'], 'tok_3');
  });

  test('a new pin and a cleared pin forget the native copy', () async {
    await savePresencePin('u4', 6.4, 3.4);
    await savePresenceToken('u4', 'tok_4');
    await savePresencePin('u4', 6.4, 3.4);
    expect(native, isNull);
    await savePresenceToken('u4', 'tok_5');
    await clearPresencePin('u4');
    expect(native, isNull);
  });
}
