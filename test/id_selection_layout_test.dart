import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/id_selection_layout.dart';
import 'package:toden_flutter/src/config/workflow_merge.dart';
import 'package:toden_flutter/src/providers/step_order.dart';
import 'package:toden_flutter/src/providers/verification_provider.dart';
import 'package:toden_flutter/src/providers/verification_state.dart'
    show ServerConfigStatus, ServerSdkConfig, VerificationState;
import 'package:toden_flutter/src/screens/id_country_field.dart';
import 'package:toden_flutter/src/screens/id_type_screen.dart' show kIdTypeIconSize;
import 'package:toden_flutter/src/services/api_service.dart';

// Where a multi-country flow picks the ID's country. Mirrors the web SDK's
// lib/id-selection-layout.test.ts, plus the step order and the combined step
// itself, mounted in the real flow.

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

SdkConfigIdType _row(String country, String idType, String label) => SdkConfigIdType(
      country: country,
      idType: idType,
      label: label,
      requiresDocumentCapture: false,
      features: const SdkIdTypeFeatures(
        documentVerification: true,
        livenessCheck: true,
        govDbCheck: true,
      ),
    );

VerificationConfig _config([IdSelectionLayout? layout]) => VerificationConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      consentStep: false,
      countries: const [
        WorkflowCountryOption(country: 'NG'),
        WorkflowCountryOption(country: 'GH'),
      ],
      idSelectionLayout: layout,
    );

final _server = ServerSdkConfig(
  status: ServerConfigStatus.ready,
  idTypes: [
    _row('NG', 'bvn', 'Bank Verification Number'),
    _row('GH', 'ghana-card', 'Ghana Card'),
  ],
);

void main() {
  test('the country is on the ID-type step unless the workflow keeps a step of its own', () {
    expect(countryOnIdStep(null), isTrue);
    expect(countryOnIdStep(IdSelectionLayout.combined), isTrue);
    expect(countryOnIdStep(IdSelectionLayout.separate), isFalse);
  });

  test('the step order has a country step only on the separate layout', () {
    final state = VerificationState(serverConfig: _server);
    expect(buildStepOrder(_config(), state), isNot(contains(VerificationStep.countrySelect)));
    expect(buildStepOrder(_config(IdSelectionLayout.combined), state),
        isNot(contains(VerificationStep.countrySelect)));
    expect(buildStepOrder(_config(IdSelectionLayout.separate), state).first,
        VerificationStep.countrySelect);
    expect(countryOnIdTypeStep(_config(), state), isTrue);
    expect(countryOnIdTypeStep(_config(IdSelectionLayout.separate), state), isFalse);
  });

  test('a workflow sets it, and a workflow that says nothing keeps the prop', () {
    final base = _config(IdSelectionLayout.separate);
    final set = mergeWorkflowIntoConfig(
        base, WorkflowFlowConfig.fromJson({'idSelectionLayout': 'combined'}));
    expect(set.idSelectionLayout, IdSelectionLayout.combined);
    final silent = mergeWorkflowIntoConfig(base, WorkflowFlowConfig.fromJson({}));
    expect(silent.idSelectionLayout, IdSelectionLayout.separate);
    expect(IdSelectionLayout.tryParse('sideways'), isNull);
  });

  test('the field opens on the workflow country, else the visitor, else the first', () {
    expect(initialIdCountry(['NG', 'GH'], configured: 'gh', geo: 'NG'), 'GH');
    expect(initialIdCountry(['NG', 'GH'], configured: 'KE', geo: 'gh'), 'GH');
    expect(initialIdCountry(['NG', 'GH'], configured: null, geo: null), 'NG');
  });

  testWidgets('the combined step carries the country above the IDs', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        verificationApiServiceProvider.overrideWithValue(_StubApi()),
        preloadedServerConfigProvider.overrideWithValue(_server),
      ],
      child: MaterialApp(home: Scaffold(body: VerificationWidget(config: _config()))),
    ));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Choose your ID'), findsOneWidget);
    expect(find.text('Your ID was issued in'), findsOneWidget);
    expect(find.text('Nigeria'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('BVN'), findsOneWidget);
    // The ID glyph is bare and larger (no tile behind it).
    expect(kIdTypeIconSize, 40);
    expect(
      find.byWidgetPredicate((w) => w is HugeIcon && w.size == kIdTypeIconSize),
      findsWidgets,
    );

    // The sheet pins the current answer, then lists the rest.
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('SELECTED'), findsOneWidget);
    expect(find.text('Search countries…'), findsOneWidget);
    await tester.tap(find.text('Ghana'));
    await tester.pumpAndSettle();

    // The list beneath follows the country.
    expect(find.text('Ghana Card'), findsOneWidget);
    expect(find.text('BVN'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
