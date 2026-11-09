import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/i18n/translate.dart';
import 'package:toden_flutter/src/providers/verification_provider.dart';
import 'package:toden_flutter/src/providers/verification_state.dart'
    show ServerConfigStatus, ServerSdkConfig, VerificationState;
import 'package:toden_flutter/src/screens/proof_of_address_screen.dart';
import 'package:toden_flutter/src/services/api_service.dart';
import 'package:toden_flutter/src/widgets/flow_step_meta.dart';

// The Proof of Address step, mounted: the country row on every scope, the
// kinds to pick from, the accepted documents sheet and the capture tiles.
// Mirrors the web SDK's ProofOfAddressStep.

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

VerificationConfig _config({String? scope, Map<String, dynamic> poa = const {}}) =>
    VerificationConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      scope: scope,
      proofOfAddress: ProofOfAddressConfig.fromJson({
        'enabled': true,
        'countries': ['NG', 'GB'],
        'documentTypes': ['utility_bill', 'government_document'],
        ...poa,
      }),
    );

Future<ProviderContainer> _pump(WidgetTester tester, VerificationConfig config) async {
  late ProviderContainer container;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      verificationConfigProvider.overrideWithValue(config),
      verificationApiServiceProvider.overrideWithValue(_StubApi()),
      preloadedServerConfigProvider.overrideWithValue(
        const ServerSdkConfig(status: ServerConfigStatus.ready),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: const [UiColorScheme.light]),
      home: Scaffold(
        body: Consumer(builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const SingleChildScrollView(
            child: SizedBox(width: 390, child: ProofOfAddressScreen()),
          );
        }),
      ),
    ),
  ));
  await tester.pump();
  return container;
}

void main() {
  testWidgets('outside the address scope the row starts from the ID country', (tester) async {
    final container = await _pump(tester, _config());

    expect(find.text('Your address is in'), findsOneWidget);
    expect(find.text('Nigeria'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);

    // A pick is the document's own country, not the ID's.
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('United Kingdom'));
    await tester.pumpAndSettle();
    final state = container.read(kYCNotifierProvider);
    expect(state.poaCountry, 'GB');
    expect(state.selectedCountry, isNull);
    expect(find.text('United Kingdom'), findsOneWidget);
  });

  testWidgets('the kinds are radios with their documents and how recent', (tester) async {
    final container = await _pump(tester, _config(poa: {
      'documentSubtypes': ['water_bill', 'gas_bill'],
      'documentValidity': {'government_document': 365},
    }));

    expect(find.text('Utility bill'), findsOneWidget);
    expect(find.text('Water or gas'), findsOneWidget);
    expect(find.text('3 months'), findsOneWidget);
    expect(find.text('1 year'), findsOneWidget);
    // No heading: the kinds say what the choice is.
    expect(find.text('Document type'), findsNothing);

    await tester.tap(find.text('Government-issued document'));
    await tester.pump();
    expect(container.read(kYCNotifierProvider).poaDocumentType, 'government_document');

    // The capture tiles, and no Continue before a document.
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Upload a file'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('See accepted documents lists each kind and marks the picked one', (tester) async {
    await _pump(tester, _config());
    await tester.tap(find.text('See accepted documents'));
    await tester.pumpAndSettle();

    expect(find.text('Accepted documents'), findsOneWidget);
    expect(find.text('Electricity bill'), findsOneWidget);
    expect(find.text("Voter's ID card"), findsOneWidget);
  });

  testWidgets('one kind on offer shows no list', (tester) async {
    await _pump(tester, _config(poa: {'documentTypes': ['bank_statement'], 'capture': 'file'}));
    expect(find.text('Bank statement'), findsNothing);
    expect(find.text('Take a photo'), findsNothing);
    expect(find.text('Upload a file'), findsOneWidget);
  });

  testWidgets('on the address scope the row asks until a country is declared', (tester) async {
    await _pump(tester, _config(scope: 'address'));
    expect(find.text('Select country'), findsOneWidget);
    expect(find.text('Choose'), findsOneWidget);
  });

  test("the header states the picked kind's window", () {
    final config = _config(poa: {'documentValidity': {'government_document': 30}});
    String description(String? kind) => flowStepMeta(
          VerificationStep.proofOfAddress,
          config: config,
          state: VerificationState(poaDocumentType: kind),
          t: defaultTextFn,
          selfieComplete: false,
        ).description!;
    expect(description(null), contains('within the last 90 days'));
    expect(description('government_document'), contains('within the last 30 days'));
  });

  test("the submission names the document's kind and country", () {
    final json = const VerifyRequest(
      country: 'NG',
      idType: 'bvn',
      proofOfAddressType: 'utility_bill',
      proofOfAddressCountry: 'GB',
      metadata: VerifyMetadata(requestId: 'r1'),
    ).toJson();
    expect(json['proofOfAddressType'], 'utility_bill');
    expect(json['proofOfAddressCountry'], 'GB');
  });
}
