import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/presence/presence_device_registration.dart';
import 'package:toden_flutter/src/presence/presence_watch_status.dart';
import 'package:toden_flutter/src/presence/user_token.dart';

// Dart's side of the presence device: ask native first with no token, fetch a
// presence user token only when one is needed, one fresh token on
// user_token_invalid, and nothing at all without a provider. Plus the held
// deadline the native flush keeps later days back for.

final a = 'ut_test_${'A' * 43}';
final b = 'ut_test_${'B' * 43}';

Map<String, dynamic> mint(String token) => {
      'token': token,
      'externalUserId': 'cus_123',
      'purpose': 'presence',
      'expiresAt': DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
    };

class Native {
  Native(this.answers);
  final List<String> answers;
  final calls = <Map<String, Object?>>[];
  Future<Object?> call(String method, Map<String, Object?> args) async {
    calls.add({'method': method, ...args});
    return answers[calls.length - 1];
  }
}

void main() {
  setUp(TodenUserTokens.reset);

  Future<String> register(Native native, {TodenUserTokenProvider? provider, List<Map<String, dynamic>>? mints}) {
    var i = 0;
    return registerPresenceDevice(
      apiKey: 'pk_test_abc',
      externalUserId: 'cus_123',
      presenceToken: 'hmac',
      getUserToken: provider ?? (mints == null ? null : (_) async => mints[i++]),
      invoke: native.call,
    );
  }

  test('no provider: no channel call and no mint', () async {
    final native = Native([]);
    expect(await register(native), 'no_provider');
    expect(native.calls, isEmpty);
  });

  test('a registered phone answers at once, and the host mints nothing', () async {
    var minted = 0;
    final native = Native(['registered']);
    expect(
        await register(native, provider: (_) async {
          minted++;
          return mint(a);
        }),
        'registered');
    expect(minted, 0);
    expect(native.calls.single.containsKey('userToken'), isFalse);
    expect(native.calls.single['presenceToken'], 'hmac');
  });

  test('needs_token: one presence token, then the registration', () async {
    final native = Native(['needs_token', 'registered']);
    expect(await register(native, mints: [mint(a)]), 'registered');
    expect(native.calls[1]['userToken'], a);
    expect(native.calls[1]['baseUrl'], isA<String>());
  });

  test('user_token_invalid: one fresh token and one more try, never a third', () async {
    final native = Native(['needs_token', 'user_token_invalid', 'user_token_invalid']);
    expect(await register(native, mints: [mint(a), mint(b)]), 'user_token_invalid');
    expect(native.calls.map((c) => c['userToken']), [null, a, b]);
  });

  test('a provider that answers null sends nothing', () async {
    final native = Native(['needs_token']);
    expect(await register(native, provider: (_) async => null), 'no_token');
    expect(native.calls.length, 1);
  });

  test('two callers at once share one registration and one mint', () async {
    final native = Native(['needs_token', 'registered']);
    var minted = 0;
    Future<Map<String, dynamic>?> provider(UserTokenPurpose _) async {
      minted++;
      return mint(a);
    }

    final both = await Future.wait([register(native, provider: provider), register(native, provider: provider)]);
    expect(both, ['registered', 'registered']);
    expect(minted, 1);
    expect(native.calls.length, 2);
  });

  test('refused for this verification: no mint until a new 202', () async {
    final native = Native(['refused']);
    expect(await register(native, mints: [mint(a)]), 'refused');
    expect(native.calls.length, 1);
  });

  group('held deadline', () {
    final deadline = DateTime.utc(2026, 11, 20, 18);
    PresenceWatchStatus status(PresenceWatchState state) =>
        PresenceWatchStatus(state: state, rawStatus: state.name, deadlineAt: deadline);

    test('in progress past its deadline: the deadline day', () {
      expect(heldDeadlineDay(status(PresenceWatchState.inProgress), DateTime.utc(2026, 11, 21)), '2026-11-20');
    });

    test('before the deadline, or decided: none', () {
      expect(heldDeadlineDay(status(PresenceWatchState.inProgress), DateTime.utc(2026, 11, 19)), isNull);
      expect(heldDeadlineDay(status(PresenceWatchState.inconclusive), DateTime.utc(2026, 11, 21)), isNull);
    });

    test('is handed to native, null included', () async {
      final native = Native(['', '']);
      await syncHeldDeadline(status(PresenceWatchState.inProgress), now: DateTime.utc(2026, 11, 22), invoke: native.call);
      await syncHeldDeadline(status(PresenceWatchState.verified), now: DateTime.utc(2026, 11, 22), invoke: native.call);
      expect(native.calls.map((c) => c['day']), ['2026-11-20', null]);
      expect(native.calls.first['method'], 'setPresenceHeldDeadline');
    });
  });

  test('logout forgets the device for that user', () async {
    final native = Native(['']);
    await forgetPresenceDevice('cus_123', invoke: native.call);
    expect(native.calls.single, {'method': 'forgetPresenceDevice', 'externalUserId': 'cus_123'});
  });
}
