import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/i18n/translate.dart';
import 'package:toden_flutter/src/providers/verification_provider.dart';
import 'package:toden_flutter/src/providers/verification_state.dart'
    show ServerConfigStatus, ServerSdkConfig;
import 'package:toden_flutter/src/screens/consent_copy.dart';
import 'package:toden_flutter/src/screens/consent_emblem.dart';
import 'package:toden_flutter/src/screens/consent_process_steps.dart';
import 'package:toden_flutter/src/screens/consent_screen.dart';
import 'package:toden_flutter/src/services/api_service.dart';
import 'package:toden_flutter/src/widgets/toden_mark.dart';

// The redesigned consent screen. Mirrors the web SDK's
// steps/consent-copy.test.ts: the steps in the order the flow runs them, a
// calm description with a separate time sentence, and the Toden mark.

VerificationConfig _config({
  String? scope,
  bool selfie = true,
  bool scan = true,
  VerificationConsentContent? consent,
}) =>
    VerificationConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      scope: scope,
      enableSelfie: selfie,
      allowDocumentScan: scan,
      consent: consent,
    );

List<String> _labels(VerificationConfig c) => [
      for (final s in consentProcessSteps(c, isBusiness: false, scope: c.scope, t: defaultTextFn))
        s.label,
    ];

class _StubApi extends VerificationApiService {
  _StubApi() : super(baseUrl: 'http://stub', apiKey: 'pk_test_stub');

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

void main() {
  test('scans the ID, then checks it, then the selfie; no personal information step', () {
    expect(_labels(_config()), [
      'Scan your ID document',
      'Check that your ID is genuine',
      'Take a selfie for facial verification',
    ]);
    expect(_labels(_config()).join(' '), isNot(contains('personal information')));
  });

  test('an upload-only flow says upload, not scan', () {
    expect(_labels(_config(scan: false)).first, 'Upload a photo of your ID document');
  });

  test('the time is the steps added up, rounded up to whole minutes', () {
    final steps = consentProcessSteps(_config(), isBusiness: false, scope: null, t: defaultTextFn);
    // 60 + 30 + 45 seconds.
    expect(consentMinutes(steps), 3);
    expect(consentMinutes(const []), 1);
  });

  test('the description, then the time as a sentence of its own', () {
    expect(
      consentDescription(defaultTextFn, isBusiness: false, scope: null, minutes: 3),
      "We're required to confirm who you are, and we'll guide you at every step. "
      'It takes about 3 minutes.',
    );
    expect(
      consentDescription(defaultTextFn, isBusiness: false, scope: null, minutes: 1),
      endsWith('It takes about a minute.'),
    );
    expect(
      consentDescription(defaultTextFn, isBusiness: true, scope: null, minutes: 4),
      startsWith("We're required to confirm your business"),
    );
  });

  test('the face and contact screens already say how long, so no time', () {
    for (final scope in ['biometric-authentication', 'biometric-enrollment', 'contact']) {
      expect(
        consentDescription(defaultTextFn, isBusiness: false, scope: scope, minutes: 2),
        isNot(contains('It takes about')),
        reason: scope,
      );
    }
  });

  test('titles by variant; an older consent.title wins', () {
    expect(consentTitle(defaultTextFn, isBusiness: false, scope: null), 'Identity Verification');
    expect(consentTitle(defaultTextFn, isBusiness: false, scope: 'address'), 'Address Verification');
    expect(consentTitle(defaultTextFn, isBusiness: false, scope: 'address', scopedBusiness: true),
        'Business Address Verification');
    expect(consentTitle(defaultTextFn, isBusiness: true, scope: null), 'Business Verification');
    expect(consentTitle(defaultTextFn, isBusiness: false, scope: null, legacy: 'Hi'), 'Hi');
  });

  testWidgets('the screen: the Toden mark, the grouped steps, Continue', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        verificationConfigProvider.overrideWithValue(_config()),
        verificationApiServiceProvider.overrideWithValue(_StubApi()),
        preloadedServerConfigProvider.overrideWithValue(
          const ServerSdkConfig(status: ServerConfigStatus.ready),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [UiColorScheme.light]),
        home: const Scaffold(body: SingleChildScrollView(child: ConsentScreen())),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ConsentEmblem), findsOneWidget);
    expect(find.byType(TodenMark), findsOneWidget);
    expect(tester.getSize(find.byType(TodenMark)), const Size(36, 36));
    expect(find.textContaining('It takes about 3 minutes.'), findsOneWidget);
    expect(find.text('Scan your ID document'), findsOneWidget);
    // No numbering or counts.
    expect(find.text('1'), findsNothing);
    expect(find.text('Continue'), findsOneWidget);
  });
}
