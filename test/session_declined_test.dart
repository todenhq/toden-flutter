import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/session_cancelled.dart';
import 'package:toden_flutter/src/config/session_declined.dart';
import 'package:toden_flutter/src/config/submit_recovery.dart';
import 'package:toden_flutter/src/providers/verification_provider.dart';
import 'package:toden_flutter/src/providers/verification_state.dart';
import 'package:toden_flutter/src/services/api_service.dart';
import 'package:toden_flutter/src/services/verification_error_mapper.dart';

// A workflow step with declineOnLastAttempt has the server decline the session
// when the applicant uses up a code: 409 { error: 'session_declined',
// reasonCode: 'contact_attempts_exceeded', message }, and the same from every
// later request on the session. Exactly parallel to a cancelled session: one
// terminal screen, Close only, onError hears 'session_declined' once.

const _emailTitle = "We couldn't verify your email address";
const _phoneTitle = "We couldn't verify your phone number";
const _endedTitle = 'This verification has ended';
const _contactBody =
    'The code was entered incorrectly too many times, so this verification has ended. Contact the organisation that sent it if you need help.';
const _genericBody = 'This verification has ended. Contact the organisation that sent it if you need help.';
const _serverMessage = 'Your organisation ended this verification.';

VerificationApiException _declined({String? reason = kContactAttemptsExceeded, String? message}) =>
    VerificationApiException(
      statusCode: 409,
      error: kSessionDeclinedCode,
      message: message,
      details: reason == null ? null : errorDetailsFrom(409, {'error': kSessionDeclinedCode, 'reasonCode': reason}),
    );

class _Api extends VerificationApiService {
  _Api(this.start) : super(baseUrl: 'http://stub', apiKey: 'pk_test_stub');

  final Object? start;

  @override
  Future<SessionStartResponse> startSession({
    String? externalUserId,
    String? workflowId,
    String? deviceRef,
    Map<String, dynamic>? device,
  }) async {
    if (start != null) throw start!;
    return const SessionStartResponse(sessionId: 'hs_test', resumed: false);
  }

  @override
  Future<void> saveProgress(String sessionId, Map<String, dynamic> progress) async {}
}

const _config = VerificationConfig(
  apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  country: 'NG',
  consentStep: false,
  emailVerification: EmailVerificationConfig(enabled: true),
);

const _server = ServerSdkConfig(status: ServerConfigStatus.ready);

void main() {
  group('reading the refusal', () {
    test('a session_declined refusal is one, with its reason', () {
      expect(isSessionDeclinedError(_declined()), isTrue);
      expect(errorDetailsFrom(409, {'reasonCode': kContactAttemptsExceeded}), {'reasonCode': kContactAttemptsExceeded});
    });

    test('ignores every other failure, including a cancellation', () {
      expect(sessionDeclinedFor(const VerificationApiException(statusCode: 409, error: 'session_cancelled')), isNull);
      expect(sessionDeclinedFor(const VerificationApiException(statusCode: 429, error: 'too_many_attempts')), isNull);
      expect(sessionDeclinedFor(Exception('offline')), isNull);
      expect(sessionDeclinedFor(null), isNull);
    });
  });

  group('the words', () {
    test('a used-up code names the channel it was on', () {
      expect(sessionDeclinedFor(_declined(), channel: 'email')!.title, _emailTitle);
      expect(sessionDeclinedFor(_declined(), channel: 'phone')!.title, _phoneTitle);
      expect(sessionDeclinedFor(_declined())!.title, _endedTitle);
    });

    test('the body is the server message when it sent one, else the default', () {
      expect(sessionDeclinedFor(_declined(message: _serverMessage), channel: 'email')!.message, _serverMessage);
      expect(sessionDeclinedFor(_declined(), channel: 'email')!.message, _contactBody);
      expect(sessionDeclinedFor(_declined(message: '  '), channel: 'phone')!.message, _contactBody);
    });

    test('another reason, or none, reads as an ended verification', () {
      final other = sessionDeclinedFor(_declined(reason: 'something_else'), channel: 'email')!;
      expect(other.title, _endedTitle);
      expect(other.message, _genericBody);
      final bare = sessionDeclinedFor(_declined(reason: null), channel: 'phone')!;
      expect(bare.title, _endedTitle);
      expect(bare.message, _genericBody);
    });

    test('the step names the channel when the refusal came from elsewhere', () {
      expect(contactChannelOf(VerificationStep.contactEmail), 'email');
      expect(contactChannelOf(VerificationStep.contactPhone), 'phone');
      expect(contactChannelOf(VerificationStep.submitted), isNull);
    });

    test('no default carries an em dash', () {
      for (final copy in [_emailTitle, _phoneTitle, _endedTitle, _contactBody, _genericBody]) {
        expect(copy.contains('—'), isFalse);
      }
    });
  });

  group('every path', () {
    test('a session start refusal stops the flow', () {
      expect(sessionStartStopsFlow(_declined()), isTrue);
    });

    test('the submission maps to its own code, never a retry, with no Go back', () {
      for (final context in ErrorContext.values) {
        final e = mapToVerificationError(_declined(message: _serverMessage), context: context);
        expect(e.code, kSessionDeclinedCode);
        expect(e.message, _serverMessage);
      }
      expect(mapToVerificationError(_declined(), context: ErrorContext.verify).message, _contactBody);
      expect(mapToVerificationError(_declined(reason: null), context: ErrorContext.verify).message, _genericBody);
      const order = [VerificationStep.consent, VerificationStep.liveness, VerificationStep.submitted];
      expect(recoveryStepFor(kSessionDeclinedCode, order), isNull);
    });

    test('the flow ends once, on the first words, and a reset clears it for a fresh start', () {
      final c = ProviderContainer(overrides: [
        verificationConfigProvider.overrideWithValue(_config),
        verificationApiServiceProvider.overrideWithValue(_Api(null)),
        preloadedServerConfigProvider.overrideWithValue(_server),
        kYCNotifierProvider.overrideWith(VerificationNotifier.new),
      ]);
      addTearDown(c.dispose);
      final notifier = c.read(kYCNotifierProvider.notifier);
      expect(c.read(kYCNotifierProvider).currentStep, VerificationStep.contactEmail);

      expect(notifier.endOnSessionRefusal(Exception('offline')), isFalse);
      expect(c.read(kYCNotifierProvider).sessionDeclined, isNull);

      // Off the contact step's own catch, the step the applicant is on names it.
      expect(notifier.endOnSessionRefusal(_declined()), isTrue);
      expect(c.read(kYCNotifierProvider).sessionDeclined!.title, _emailTitle);

      notifier.endOnSessionRefusal(_declined(message: _serverMessage), channel: 'phone');
      expect(c.read(kYCNotifierProvider).sessionDeclined!.message, _contactBody);

      // A decline ends that session only: a reset (a new start) clears it.
      notifier.reset();
      expect(c.read(kYCNotifierProvider).sessionDeclined, isNull);
    });
  });

  testWidgets('a declined session start shows the declined screen and reports once', (tester) async {
    final errors = <VerificationError>[];
    var closed = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        verificationApiServiceProvider.overrideWithValue(_Api(_declined())),
        preloadedServerConfigProvider.overrideWithValue(_server),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: VerificationWidget(
            config: _config,
            onError: errors.add,
            onClose: () => closed++,
          ),
        ),
      ),
    ));
    // The session start reads the device id and metadata first: real async.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(find.text(_emailTitle), findsOneWidget);
    expect(find.text(_contactBody), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.textContaining('try again'), findsNothing);
    expect(errors.map((e) => e.code), [kSessionDeclinedCode]);

    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(closed, 1);
    expect(errors, hasLength(1));
    // Let the screen's entrance timers run out before the tree is torn down.
    await tester.pump(const Duration(seconds: 2));
  });
}
