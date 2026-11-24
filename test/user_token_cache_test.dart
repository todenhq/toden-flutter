import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/presence/user_token.dart';

// The token cache when the host's provider fails: a still-good token is kept
// rather than sending the request bare (which a scoped key refuses with
// user_token_required, never retried). A provider that answers null is the
// host saying "no token", so nothing cached is sent.

const hour = 3600000;
final t0 = DateTime.utc(2026, 11, 22).millisecondsSinceEpoch;
final a = 'ut_test_${'A' * 43}';
Map<String, dynamic> mint(String token) => {
      'token': token,
      'externalUserId': 'cus_123',
      'purpose': 'presence',
      'expiresAt': DateTime.fromMillisecondsSinceEpoch(t0 + 24 * hour, isUtc: true).toIso8601String(),
    };

TodenUserTokenProvider sequence(List<Object?> answers) {
  var i = 0;
  return (purpose) async {
    final answer = answers[i++];
    if (answer is Exception) throw answer;
    return answer as Map<String, dynamic>?;
  };
}

Future<TokenLookup> lookup(TodenUserTokenProvider provider, int at, {bool force = false}) => TodenUserTokens.tokenFor(
      apiKey: 'pk_test_abc',
      externalUserId: 'cus_123',
      purpose: UserTokenPurpose.presence,
      getUserToken: provider,
      force: force,
      now: () => at,
    );

void main() {
  setUp(() {
    TodenUserTokens.reset();
    TodenUserTokens.onAccepted = null;
  });

  test('past half its life, a provider that throws keeps the cached token', () async {
    final provider = sequence([mint(a), Exception('offline')]);
    expect((await lookup(provider, t0)).token, a);
    final again = await lookup(provider, t0 + 13 * hour);
    expect(again.token, a);
    expect(again.mismatch, isFalse);
  });

  test('an expired cached token is never sent, even when the provider throws', () async {
    final provider = sequence([mint(a), Exception('offline')]);
    await lookup(provider, t0);
    expect((await lookup(provider, t0 + 25 * hour)).token, isNull);
  });

  test('a provider that answers null means no token, cached or not', () async {
    final provider = sequence([mint(a), null]);
    await lookup(provider, t0);
    expect((await lookup(provider, t0 + 13 * hour)).token, isNull);
  });

  test('a forced refetch after a refusal never falls back to the refused token', () async {
    final provider = sequence([mint(a), Exception('offline')]);
    await lookup(provider, t0);
    expect((await lookup(provider, t0 + hour, force: true)).token, isNull);
  });
}
