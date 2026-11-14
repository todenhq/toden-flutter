import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/session_declined.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/providers/verification_provider.dart';
import 'package:toden_flutter/src/providers/verification_state.dart';
import 'package:toden_flutter/src/screens/contact_verification_screen.dart';
import 'package:toden_flutter/src/services/api_service.dart';
import 'package:toden_flutter/src/services/contact_errors.dart';

// ─── A used-up code ──────────────────────────────────────────────────────────
//
// A wrong code answers 400 { error: 'invalid_code', attemptsRemaining }. At 0
// that code is used up, and a further check answers 429 too_many_attempts.
// Either way the field goes read-only and the primary action sends a new code;
// a code sent successfully clears it and opens the field again. A workflow
// with declineOnLastAttempt has the server decline the session instead.

const _usedUp = 'Too many incorrect attempts. Request a new code.';

VerificationApiException _wrong(int left) => VerificationApiException(
      statusCode: 400,
      error: 'invalid_code',
      details: errorDetailsFrom(400, {'error': 'invalid_code', 'attemptsRemaining': left}),
    );

const _tooMany = VerificationApiException(statusCode: 429, error: 'too_many_attempts');

class _Api extends VerificationApiService {
  _Api() : super(baseUrl: 'http://stub', apiKey: 'pk_test_stub');

  final sends = <String>[];
  final checks = <String>[];
  /// The session each check named (the server declines and charges by it).
  final checkSessions = <String?>[];
  final failures = <Object>[];

  @override
  Future<ContactSendResponse> contactSend({
    required String channel,
    required String destination,
    String? country,
    String? via,
    int? codeLength,
    int? maxAttempts,
    String? sessionId,
  }) async {
    sends.add(destination);
    return ContactSendResponse(challengeId: 'chal_${sends.length}');
  }

  @override
  Future<ContactCheckResponse> contactCheck({
    required String challengeId,
    required String code,
    String? sessionId,
    String? country,
  }) async {
    checks.add(code);
    checkSessions.add(sessionId);
    if (failures.isNotEmpty) throw failures.removeAt(0);
    return const ContactCheckResponse(verified: true, token: 'tok_1');
  }

  @override
  Future<SessionStartResponse> startSession({
    String? externalUserId,
    String? workflowId,
    String? deviceRef,
    Map<String, dynamic>? device,
  }) async =>
      const SessionStartResponse(sessionId: 'hs_test', resumed: false);

  @override
  Future<void> saveProgress(String sessionId, Map<String, dynamic> progress) async {}
}

Future<ProviderContainer> _pump(WidgetTester tester, _Api api) async {
  final container = ProviderContainer(overrides: [
    verificationConfigProvider.overrideWithValue(const VerificationConfig(
      apiKey: 'pk_test_stub',
      country: 'NG',
      consentStep: false,
      emailVerification: EmailVerificationConfig(enabled: true),
    )),
    verificationApiServiceProvider.overrideWithValue(api),
    preloadedServerConfigProvider.overrideWithValue(
      const ServerSdkConfig(status: ServerConfigStatus.ready),
    ),
    kYCNotifierProvider.overrideWith(VerificationNotifier.new),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData(extensions: const [UiColorScheme.light]),
      home: const Scaffold(
        body: SingleChildScrollView(child: ContactVerificationScreen(channel: 'email')),
      ),
    ),
  ));
  await tester.pump();
  // Enter the address and send the first code.
  await tester.enterText(find.byType(TextField), 'ada@example.com');
  await tester.pump();
  await tester.tap(find.text('Send code'));
  await tester.pump();
  await tester.pump();
  return container;
}

/// The code field (the only text field once a code is out).
TextField _codeField(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField));

Future<void> _type(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField), code);
  await tester.pump();
  await tester.pump();
}

void main() {
  group('reading the refusal', () {
    test('attemptsRemaining rides the details of a wrong code', () {
      expect(errorDetailsFrom(400, {'error': 'invalid_code', 'attemptsRemaining': 2}), {'attemptsRemaining': 2});
      expect(attemptsRemainingOf(_wrong(2)), 2);
      expect(attemptsRemainingOf(const VerificationApiException(statusCode: 400, error: 'invalid_code')), isNull);
    });

    test('a wrong code with tries left is not used up', () {
      expect(isCodeUsedUp(_wrong(2)), isFalse);
      expect(describeCheckError(_wrong(2)), 'That code is not correct. Please try again.');
      // An older server that sends no count behaves as before.
      expect(isCodeUsedUp(const VerificationApiException(statusCode: 400, error: 'invalid_code')), isFalse);
    });

    test('the last try used up, or a refused further check, is used up', () {
      expect(isCodeUsedUp(_wrong(0)), isTrue);
      expect(isCodeUsedUp(_tooMany), isTrue);
      expect(describeCheckError(_wrong(0)), _usedUp);
      expect(describeCheckError(_tooMany), _usedUp);
      expect(isCodeUsedUp(Exception('offline')), isFalse);
    });
  });

  group('declineOnLastAttempt', () {
    test('defaults to false on both channels', () {
      expect(const EmailVerificationConfig().declineOnLastAttempt, isFalse);
      expect(const PhoneVerificationConfig().declineOnLastAttempt, isFalse);
      expect(EmailVerificationConfig.fromJson({'enabled': true}).declineOnLastAttempt, isFalse);
      expect(PhoneVerificationConfig.fromJson({'enabled': true}).declineOnLastAttempt, isFalse);
    });

    test('is read from its JSON key, true only when true', () {
      expect(EmailVerificationConfig.fromJson({'declineOnLastAttempt': true}).declineOnLastAttempt, isTrue);
      expect(PhoneVerificationConfig.fromJson({'declineOnLastAttempt': true}).declineOnLastAttempt, isTrue);
      expect(EmailVerificationConfig.fromJson({'declineOnLastAttempt': 'yes'}).declineOnLastAttempt, isFalse);
      expect(PhoneVerificationConfig.fromJson({'declineOnLastAttempt': false}).declineOnLastAttempt, isFalse);
    });
  });

  group('the code step', () {
    testWidgets('a check names the attempt session, as the web SDK does', (tester) async {
      final api = _Api()..failures.add(_wrong(2));
      final container = await _pump(tester, api);
      final notifier = container.read(kYCNotifierProvider.notifier);
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      notifier.state = notifier.state.copyWith(sessionId: 'hs_test');
      await _type(tester, '111111');
      expect(api.checkSessions, ['hs_test']);
      // Let the session's own timers (progress saves) finish.
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('a wrong code with tries left keeps the field open', (tester) async {
      final api = _Api()..failures.add(_wrong(2));
      await _pump(tester, api);
      await _type(tester, '111111');
      expect(api.checks, ['111111']);
      expect(find.text('That code is not correct. Please try again.'), findsOneWidget);
      expect(_codeField(tester).enabled, isTrue);
      expect(find.text('Verify code'), findsOneWidget);
    });

    for (final (label, failure) in [
      ('the last try', _wrong(0)),
      ('a refused further check', _tooMany),
    ]) {
      testWidgets('$label disables the field until a new code is sent', (tester) async {
        final api = _Api()..failures.add(failure);
        await _pump(tester, api);
        await _type(tester, '111111');

        expect(find.text(_usedUp), findsOneWidget);
        expect(_codeField(tester).enabled, isFalse);
        expect(find.text('Send a new code'), findsOneWidget);
        expect(find.text('Verify code'), findsNothing);

        // The field takes nothing more and submits nothing.
        await _type(tester, '222222');
        expect(api.checks, ['111111']);

        // The primary action sends a new code, which opens the field again empty.
        await tester.tap(find.text('Send a new code'));
        await tester.pump();
        await tester.pump();
        expect(api.sends, ['ada@example.com', 'ada@example.com']);
        expect(find.text(_usedUp), findsNothing);
        expect(_codeField(tester).enabled, isTrue);
        expect(_codeField(tester).controller!.text, isEmpty);
        expect(find.text('Verify code'), findsOneWidget);

        // And the new code is checked.
        await _type(tester, '333333');
        expect(api.checks, ['111111', '333333']);
      });
    }

    testWidgets('a declined session ends the flow, naming the email step', (tester) async {
      final api = _Api()
        ..failures.add(const VerificationApiException(
          statusCode: 409,
          error: kSessionDeclinedCode,
          details: {'reasonCode': kContactAttemptsExceeded},
        ));
      final container = await _pump(tester, api);
      await _type(tester, '111111');
      final declined = container.read(kYCNotifierProvider).sessionDeclined;
      expect(declined?.title, "We couldn't verify your email address");
      expect(declined?.message,
          'The code was entered incorrectly too many times, so this verification has ended. Contact the organisation that sent it if you need help.');
      // No generic error on the step under it.
      expect(find.text('Something went wrong. Please try again.'), findsNothing);
    });
  });
}
