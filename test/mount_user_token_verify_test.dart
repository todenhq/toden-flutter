import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/providers/verification_provider.dart';
import 'package:toden_flutter/src/providers/verification_state.dart' show ServerConfigStatus, ServerSdkConfig;
import 'package:toden_flutter/src/services/api_service.dart';

// /verify answering 403 user_token_invalid on a bound face check: a fresh
// biometric token, /session/start again (a resume, which rebinds) and exactly
// one resubmission. Anything else, or a second refusal, goes to the host.

const _invalid = VerificationApiException(statusCode: 403, error: 'user_token_invalid');

class _Api extends VerificationApiService {
  _Api(this.verifyAnswers, {this.resumedId = 'hs_test'}) : super(baseUrl: 'http://stub', apiKey: 'pk_test_stub');

  final List<Object> verifyAnswers;
  final String resumedId;
  final tokenStarts = <Map<String, String>>[];
  var plainStarts = 0;
  var verifies = 0;

  @override
  Future<VerifyResponse> verify(VerifyRequest request) async {
    final answer = verifyAnswers[verifies++];
    if (answer is Exception) throw answer;
    return answer as VerifyResponse;
  }

  @override
  Future<SessionStartResponse> startSession({
    String? externalUserId,
    String? workflowId,
    String? deviceRef,
    Map<String, dynamic>? device,
  }) async {
    plainStarts++;
    return const SessionStartResponse(sessionId: 'hs_test', resumed: false);
  }

  @override
  Future<SessionStartResponse> startSessionWithUserToken({
    String? externalUserId,
    String? workflowId,
    String? deviceRef,
    Map<String, dynamic>? device,
    required Map<String, String> headers,
  }) async {
    tokenStarts.add(headers);
    return SessionStartResponse(sessionId: resumedId, resumed: true);
  }

  @override
  Future<void> saveProgress(String sessionId, Map<String, dynamic> progress) async {}
}

final _token = 'ut_test_${'A' * 43}';

Future<Map<String, dynamic>?> _provider(UserTokenPurpose purpose) async => {
      'token': _token,
      'externalUserId': 'user_1',
      'purpose': purpose == UserTokenPurpose.biometric ? 'biometric' : 'presence',
      'expiresAt': DateTime.now().toUtc().add(const Duration(minutes: 10)).toIso8601String(),
    };

(ProviderContainer, _Api) _container(_Api api, {TodenUserTokenProvider? provider = _provider}) {
  final c = ProviderContainer(overrides: [
    verificationConfigProvider.overrideWithValue(VerificationConfig(
      apiKey: 'pk_test_stub',
      country: 'NG',
      userId: 'user_1',
      getUserToken: provider,
    )),
    verificationApiServiceProvider.overrideWithValue(api),
    preloadedServerConfigProvider.overrideWithValue(const ServerSdkConfig(status: ServerConfigStatus.ready)),
  ]);
  return (c, api);
}

IdTypeConfig get _passport => kCuratedIdTypes['NG']!.firstWhere((t) => t.key == 'passport');

/// What the submission threw, or null; submitAsync rethrows to the host.
Future<Object?> _submit(ProviderContainer c) async {
  final notifier = c.read(kYCNotifierProvider.notifier);
  await Future<void>.delayed(const Duration(milliseconds: 10));
  notifier.setIdType(_passport);
  try {
    await notifier.submitAsync();
    return null;
  } catch (e) {
    return e;
  }
}

const _ok = VerifyResponse(verificationId: 'ver_1', status: 'pending');

void main() {
  setUp(TodenUserTokens.reset);

  test('user_token_invalid re-mounts with a fresh token and resubmits once', () async {
    final (c, api) = _container(_Api([_invalid, _ok]));
    addTearDown(c.dispose);
    expect(await _submit(c), isNull);
    expect(api.tokenStarts, [
      {kUserTokenHeader: _token}
    ]);
    expect(api.verifies, 2);
    expect(c.read(kYCNotifierProvider).submissionResult?.verificationId, 'ver_1');
  });

  test('a second refusal goes to the host, with no third submission', () async {
    final (c, api) = _container(_Api([_invalid, _invalid, _ok]));
    addTearDown(c.dispose);
    expect(await _submit(c), same(_invalid));
    expect(api.tokenStarts.length, 1);
    expect(api.verifies, 2);
    expect(c.read(kYCNotifierProvider).submissionResult, isNull);
  });

  test('a re-mount that answers another session does not resubmit', () async {
    final (c, api) = _container(_Api([_invalid, _ok], resumedId: 'hs_other'));
    addTearDown(c.dispose);
    expect(await _submit(c), same(_invalid));
    expect(api.verifies, 1);
    expect(c.read(kYCNotifierProvider).submissionResult, isNull);
  });

  test('with no provider, nothing is fetched and nothing resubmitted', () async {
    final (c, api) = _container(_Api([_invalid, _ok]), provider: null);
    addTearDown(c.dispose);
    expect(await _submit(c), same(_invalid));
    expect(api.tokenStarts, isEmpty);
    expect(api.verifies, 1);
  });

  test('too_many_attempts is never retried', () async {
    final (c, api) =
        _container(_Api([const VerificationApiException(statusCode: 429, error: 'too_many_attempts'), _ok]));
    addTearDown(c.dispose);
    expect(await _submit(c), isA<VerificationApiException>());
    expect(api.tokenStarts, isEmpty);
    expect(api.verifies, 1);
  });
}
