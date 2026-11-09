import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/providers/verification_provider.dart';
import 'package:toden_flutter/src/services/api_service.dart';
import 'package:toden_flutter/src/providers/verification_state.dart'
    show ServerConfigStatus, ServerSdkConfig;
import 'package:toden_flutter/src/screens/applicant_role_screen.dart';
import 'package:toden_flutter/src/screens/business_details_screen.dart';
import 'package:toden_flutter/src/screens/business_documents_screen.dart';
import 'package:toden_flutter/src/screens/business_key_people_screen.dart';

// ─── KYB screens ──────────────────────────────────────────────────────────────
//
// The gating logic has its own unit tests; this pins the part those can't reach
// — that each screen actually BUILDS, and that the Continue button's enabled
// state tracks the workflow's requirements. A disabled-forever Continue (or a
// screen that throws in build) is the failure mode that only shows up on a
// device, which is exactly what these are here to catch.

/// A network that never happens: the notifier now also mints an attempt
/// session at launch, and a live dio request in a widget test is a pending
/// timer at teardown. The stub answers instantly, from the same seam a real
/// mount builds its client behind.
class _StubApi extends VerificationApiService {
  _StubApi({this.searchError})
      : super(baseUrl: 'http://stub', apiKey: 'pk_test_stub');

  /// What a search throws, when a test wants the server to refuse it.
  final Object? searchError;

  /// The session the last search carried, and how many searches ran.
  String? lastSearchSessionId;
  int searches = 0;

  @override
  Future<SessionStartResponse> startSession({
    String? externalUserId,
    String? workflowId,
    String? deviceRef,
    Map<String, dynamic>? device,
  }) async =>
      const SessionStartResponse(sessionId: 'hs_test', resumed: false);

  @override
  Future<void> saveProgress(
      String sessionId, Map<String, dynamic> progress) async {}

  @override
  Future<BusinessSelectResponse> businessSelect({
    required String sessionId,
    required String country,
    required String registrationNumber,
    String? subdivisionCode,
    String? registrationName,
    String? product,
  }) async =>
      const BusinessSelectResponse(checked: false, found: false);

  @override
  Future<BusinessSearchResponse> businessSearch({
    required String country,
    required String query,
    String? subdivisionCode,
    int? limit,
    String? sessionId,
  }) async {
    searches++;
    lastSearchSessionId = sessionId;
    final error = searchError;
    if (error != null) throw error;
    return const BusinessSearchResponse(results: []);
  }

  @override
  Future<BusinessRegionsResponse> businessRegions(String country) async =>
      const BusinessRegionsResponse();
}

Widget host(VerificationConfig config, Widget child,
        {VerificationApiService? api}) =>
    ProviderScope(
      overrides: [
        verificationConfigProvider.overrideWithValue(config),
        verificationApiServiceProvider.overrideWithValue(api ?? _StubApi()),
        // Preloading the server config is what a real workflow mount does, and
        // it skips the /api/v1/config fetch — without it the notifier fires a
        // live dio request and the test ends with a pending timer.
        preloadedServerConfigProvider.overrideWithValue(
          const ServerSdkConfig(status: ServerConfigStatus.ready),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [UiColorScheme.light]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 390, child: child),
          ),
        ),
      ),
    );

VerificationConfig config(Map<String, dynamic> businessJson) =>
    VerificationConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      workflowId: 'wf_test',
      subjectType: 'business',
      business:
          WorkflowBusinessConfig.fromJson({'country': 'NG', ...businessJson}),
    );

/// The screen's primary action (always the last UiButton on these screens).
bool continueEnabled(WidgetTester tester) => buttonEnabled(tester, 'Continue');

/// The details phase's primary action — the button renames once the register
/// has been asked, so "continue" means confirming what it said.
bool continueEnabled2(WidgetTester tester) =>
    buttonEnabled(tester, 'Confirm details & continue');

/// Whether the last UiButton with [label] currently has an onPressed.
bool buttonEnabled(WidgetTester tester, String label) {
  final buttons = tester
      .widgetList<UiButton>(find.byType(UiButton))
      .where((b) => b.label == label);
  return buttons.last.onPressed != null;
}

/// The first screen when there is no search: type the number, Continue checks
/// the register (the stub answers "not checked", which continues), and the
/// details screen opens.
Future<void> enterNumberAndContinue(WidgetTester tester) async {
  await tester.enterText(
      find.widgetWithText(TextField, 'e.g. RC0000000'), 'RC0000001');
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

void main() {
  group('BusinessDetailsScreen', () {
    testWidgets('renders and gates Continue on the registration number',
        (tester) async {
      await tester.pumpWidget(host(config({}), const BusinessDetailsScreen()));
      await tester.pump();

      // The pick phase opens on the search; nothing is chosen yet.
      expect(find.widgetWithText(TextField, 'Search by company name'),
          findsOneWidget);
      expect(continueEnabled(tester), isFalse);

      // Manual entry swaps the search for the number box on the SAME first
      // screen; Continue then checks the register and opens the details.
      await tester.tap(find.text('Enter the details myself'));
      await tester.pumpAndSettle();
      expect(continueEnabled(tester), isFalse);
      // The details form is not on this screen: the register fills it next.
      expect(find.textContaining('Registered address'), findsNothing);

      await tester.enterText(
          find.widgetWithText(TextField, 'e.g. RC0000000'), 'RC0000001');
      await tester.pump();
      expect(continueEnabled(tester), isTrue);
    });

    testWidgets('the country of registration is the shared summary row',
        (tester) async {
      await tester.pumpWidget(host(
          config({'countries': ['NG', 'GH']}), const BusinessDetailsScreen()));
      await tester.pump();

      expect(find.text('Registered in'), findsOneWidget);
      expect(find.text('Nigeria'), findsOneWidget);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(find.text('SELECTED'), findsOneWidget);
      await tester.tap(find.text('Ghana'));
      await tester.pumpAndSettle();
      expect(find.text('Ghana'), findsOneWidget);
    });

    testWidgets('a required company field blocks Continue until filled',
        (tester) async {
      await tester.pumpWidget(host(
        config({
          'companyInfo': {'address': 'required'},
        }),
        const BusinessDetailsScreen(),
      ));
      await tester.pump();

      // Company fields live on the DETAILS phase: the number, then Continue.
      await tester.tap(find.text('Enter the details myself'));
      await tester.pumpAndSettle();
      await enterNumberAndContinue(tester);

      // Labels are Text.rich (name + a " *" / " (optional)" suffix span), so
      // match on the substring rather than the exact node text.
      expect(find.textContaining('Registered address'), findsOneWidget);
      // The number alone isn't enough — the required address still blocks.
      expect(continueEnabled2(tester), isFalse);

      await tester.enterText(
          find.widgetWithText(TextField, 'e.g. 12 Marina Road, Lagos'),
          '12 Marina Road, Lagos');
      await tester.pump();
      expect(continueEnabled2(tester), isTrue);
    });

    testWidgets('collectCompanyInfo: false hides the whole section',
        (tester) async {
      await tester.pumpWidget(host(
        config({'collectCompanyInfo': false}),
        const BusinessDetailsScreen(),
      ));
      await tester.pump();
      // Even on the details phase, where the section would live.
      await tester.tap(find.text('Enter the details myself'));
      await tester.pumpAndSettle();
      await enterNumberAndContinue(tester);
      expect(continueEnabled2(tester), isTrue);
      expect(find.text('Company information'), findsNothing);
      expect(find.textContaining('Registered address'), findsNothing);
    });

    testWidgets('a malformed company email blocks Continue', (tester) async {
      await tester.pumpWidget(host(config({}), const BusinessDetailsScreen()));
      await tester.pump();

      await tester.tap(find.text('Enter the details myself'));
      await tester.pumpAndSettle();
      await enterNumberAndContinue(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'hello@company.com'), 'not-an-email');
      await tester.pump();
      expect(continueEnabled2(tester), isFalse);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });
  });

  group('BusinessDetailsScreen search by name', () {
    testWidgets('the search carries the attempt session', (tester) async {
      final api = _StubApi();
      await tester.pumpWidget(
          host(config({}), const BusinessDetailsScreen(), api: api));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Search by company name'), 'Acme');
      await tester.pump();
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(api.searches, 1);
      // Whatever attempt session the notifier holds is what the search sends.
      // (Under widget tests the launch mint stalls on device metadata, so it
      // may be null here; config/business_search.dart's params are unit
      // tested with a real id in business_search_test.dart.)
      final container = ProviderScope.containerOf(
          tester.element(find.byType(BusinessDetailsScreen)));
      expect(api.lastSearchSessionId,
          container.read(kYCNotifierProvider).sessionId);
    });

    testWidgets('a refusal moves to number entry with the server message',
        (tester) async {
      final api = _StubApi(
        searchError: const VerificationApiException(
          statusCode: 400,
          error: 'session_required',
          message: 'Searching this register needs the verification session.',
        ),
      );
      await tester.pumpWidget(
          host(config({}), const BusinessDetailsScreen(), api: api));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Search by company name'), 'Acme');
      await tester.pump();
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      // Never "no matches": the search is gone and the number field is up.
      expect(find.textContaining('Nothing found'), findsNothing);
      expect(find.widgetWithText(TextField, 'Search by company name'),
          findsNothing);
      expect(
          find.text('Searching this register needs the verification session.'),
          findsOneWidget);
      expect(find.widgetWithText(TextField, 'e.g. RC0000000'), findsOneWidget);
    });

    testWidgets('an outage keeps the search to retry', (tester) async {
      final api = _StubApi(
        searchError: const VerificationApiException(
          statusCode: 503,
          error: 'search_unavailable',
        ),
      );
      await tester.pumpWidget(
          host(config({}), const BusinessDetailsScreen(), api: api));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Search by company name'), 'Acme');
      await tester.pump();
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.text('Search is unavailable'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Search by company name'),
          findsOneWidget);
    });

    testWidgets('nameSearch false opens on number entry with no search',
        (tester) async {
      final api = _StubApi();
      await tester.pumpWidget(host(
          config({'nameSearch': false}), const BusinessDetailsScreen(),
          api: api));
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Search by company name'),
          findsNothing);
      expect(find.text('Enter the details myself'), findsNothing);
      // Just the number: the details form is not on this screen.
      expect(find.textContaining('Registered address'), findsNothing);
      await tester.enterText(
          find.widgetWithText(TextField, 'e.g. RC0000000'), 'RC0000001');
      await tester.pump();
      expect(continueEnabled(tester), isTrue);

      // Continue checks the register and opens the details screen.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Registered address'), findsOneWidget);
      expect(continueEnabled2(tester), isTrue);
      expect(api.searches, 0);
    });
  });

  group('BusinessKeyPeopleScreen', () {
    final collect = {
      'keyPeople': {'enabled': true, 'collect': true, 'minEntries': 1},
    };

    testWidgets('minEntries blocks Continue until a valid person is added',
        (tester) async {
      await tester
          .pumpWidget(host(config(collect), const BusinessKeyPeopleScreen()));
      await tester.pump();

      expect(find.text('List at least 1 person to continue.'), findsOneWidget);
      expect(continueEnabled(tester), isFalse);

      // The step is SECTIONED now, so the add tile belongs to a section
      // rather than the list as a whole. A person added here starts wearing
      // that section's hat. The FIRST section on purpose: their card then
      // renders above the quick-add chips the later sections offer for them,
      // so `.first` is unambiguously the card.
      await tester.ensureVisible(find.text('Add a beneficial owner'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a beneficial owner'));
      await tester.pumpAndSettle();
      expect(buttonEnabled(tester, 'Add person'), isFalse);

      await tester.enterText(
          find.widgetWithText(TextField, 'e.g. Bola Owner'), 'Bola Owner');
      await tester.pump();
      expect(buttonEnabled(tester, 'Add person'), isTrue);
      // A beneficial owner must give a stake (keyPeople.requireOwnership).
      await tester.enterText(find.widgetWithText(TextField, 'e.g. 60'), '60');
      await tester.pump();

      await tester.tap(find.text('Add person'));
      await tester.pumpAndSettle();

      // The saved person renders as a summary card in the section they were
      // added to, and is offered as a quick-add chip in the others: sections
      // are VIEWS over one list, so a named person appears wherever they could
      // also belong. Hence findsWidgets, not findsOneWidget.
      expect(find.text('Bola Owner'), findsWidgets);
      expect(continueEnabled(tester), isTrue);
    });

    testWidgets('a beneficial owner with no stake holds Continue, and says why',
        (tester) async {
      await tester
          .pumpWidget(host(config(collect), const BusinessKeyPeopleScreen()));
      await tester.pump();
      await tester.ensureVisible(find.text('Add a beneficial owner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a beneficial owner'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'e.g. Bola Owner'), 'Bola Owner');
      await tester.pump();
      await tester.tap(find.text('Add person'));
      await tester.pumpAndSettle();
      expect(find.text('Ownership % required, tap to add'), findsOneWidget);
      expect(continueEnabled(tester), isFalse);
    });

    testWidgets('with no minimum the step is skippable', (tester) async {
      await tester.pumpWidget(host(
        config({
          'keyPeople': {'enabled': true, 'collect': true},
        }),
        const BusinessKeyPeopleScreen(),
      ));
      await tester.pump();
      expect(continueEnabled(tester), isTrue);
    });

    testWidgets('removing a person from the edit sheet drops their card',
        (tester) async {
      await tester
          .pumpWidget(host(config(collect), const BusinessKeyPeopleScreen()));
      await tester.pump();

      await tester.ensureVisible(find.text('Add a beneficial owner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a beneficial owner'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'e.g. Bola Owner'), 'Bola Owner');
      await tester.enterText(find.widgetWithText(TextField, 'e.g. 60'), '60');
      await tester.pump();
      await tester.tap(find.text('Add person'));
      await tester.pumpAndSettle();
      // Their card, plus quick-add chips in the sections they could also join.
      expect(find.text('Bola Owner'), findsWidgets);
      expect(continueEnabled(tester), isTrue);

      // Tapping the card opens the edit sheet; removal lives INSIDE it —
      // never a one-tap delete on the list. `.first` is the card because they
      // were added to the first section; a chip would have granted them a role
      // instead of opening anything.
      await tester.ensureVisible(find.text('Bola Owner').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bola Owner').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove this person'));
      await tester.pumpAndSettle();

      expect(find.text('Bola Owner'), findsNothing);
      expect(continueEnabled(tester), isFalse);
    });
  });

  group('BusinessDocumentsScreen', () {
    testWidgets('walks the groups one at a time, a required one blocking Continue',
        (tester) async {
      await tester.pumpWidget(host(
        config({
          'documents': {
            'enabled': true,
            'types': [
              {'key': 'incorporation_certificate', 'required': true},
              {'key': 'registry_extract'},
              {'key': 'memart', 'required': true},
              {'key': 'proof_of_address', 'required': true},
            ],
          },
        }),
        const BusinessDocumentsScreen(),
      ));
      await tester.pump();

      // The open card: the first group, its position, what it accepts.
      expect(find.text('Legal presence'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
      expect(find.text('Any one of these'), findsOneWidget);
      expect(find.text('Certificate of incorporation'), findsOneWidget);
      expect(find.text('Official company extract or profile from the registrar'),
          findsOneWidget);
      // Nothing asks which document it is: the server recognises it.
      expect(find.textContaining('Which document'), findsNothing);
      expect(find.textContaining('You do not need to say'), findsNothing);
      // The whole upload area is the control; no separate buttons.
      expect(find.text('Tap to choose a file'), findsOneWidget);
      expect(find.text('Choose a file'), findsNothing);
      expect(find.text('Take a photo'), findsNothing);
      // The next group is tucked behind at the top as one note listing what it
      // will ask for; later ones are unseen, and nothing is tucked below.
      expect(
        find.bySemanticsLabel(RegExp(r'^Next: Company details\. Memorandum')),
        findsOneWidget,
      );
      expect(find.text('Business address'), findsNothing);
      expect(find.text('Change'), findsNothing);
      // Nothing uploaded yet, so the required group blocks the button, which
      // reads Next while groups are still to come.
      expect(buttonEnabled(tester, 'Next'), isFalse);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('Skip opens the next group and tucks the skipped one below',
        (tester) async {
      await tester.pumpWidget(host(
        config({
          'documents': {
            'enabled': true,
            'types': [
              {'key': 'tax_document'},
              {'key': 'regulatory_license', 'required': true},
            ],
          },
        }),
        const BusinessDocumentsScreen(),
      ));
      await tester.pump();
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Next: Licences and permits')),
          findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      // The next group is open (and read out); the skipped one is tucked
      // behind it at the bottom.
      expect(find.text('2 of 2'), findsOneWidget);
      expect(find.bySemanticsLabel('2 of 2: Licences and permits'),
          findsOneWidget);
      expect(find.text('Licences and permits'), findsOneWidget);
      expect(find.text('Skipped'), findsOneWidget);
      expect(find.bySemanticsLabel('Tax registration. Skipped. Change'),
          findsOneWidget);
      // The last group has nothing tucked above it.
      expect(find.bySemanticsLabel(RegExp('^Next:')), findsNothing);
      expect(continueEnabled(tester), isFalse);

      // Change reopens the skipped group.
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.text('Skipped'), findsNothing);
      expect(buttonEnabled(tester, 'Skip'), isTrue);
    });

    testWidgets('the button reads Skip, Next, then Continue on the last group',
        (tester) async {
      await tester.pumpWidget(host(
        config({
          'documents': {
            'enabled': true,
            'types': [
              {'key': 'proof_of_address'},
              {'key': 'regulatory_license', 'required': true},
            ],
          },
        }),
        const BusinessDocumentsScreen(),
      ));
      await tester.pump();
      // An optional group with nothing uploaded.
      expect(buttonEnabled(tester, 'Skip'), isTrue);

      // A document lands for it (the upload itself is the picker's business).
      ProviderScope.containerOf(
              tester.element(find.byType(BusinessDocumentsScreen)))
          .read(kYCNotifierProvider.notifier)
          .setBusinessDocuments(const [
        BusinessDocumentUpload(
          type: 'proof_of_address',
          group: 'address',
          mediaId: 'med_1',
          // A camera's random id: shown as the group title, never as itself.
          fileName: '940f84e9-18c6-4894-accc-3621f5b1a2c3.jpg',
        ),
      ]);
      await tester.pump();
      expect(find.textContaining('940f84e9'), findsNothing);
      expect(find.text('Business address'), findsNWidgets(2));
      expect(find.text('Skip'), findsNothing);
      expect(buttonEnabled(tester, 'Next'), isTrue);

      // ("Next" is also the pill on the tucked card above.)
      await tester.tap(find.widgetWithText(UiButton, 'Next'));
      await tester.pumpAndSettle();
      // The last group: Continue, and the filled group tucked below, keeping
      // its number and reading Uploaded.
      expect(find.text('2 of 2'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(continueEnabled(tester), isFalse);
      expect(find.bySemanticsLabel('Business address. Uploaded. Change'),
          findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('shows how recent each accepted document must be', (tester) async {
      await tester.pumpWidget(host(
        config({
          'documents': {
            'enabled': true,
            'types': [
              {'key': 'proof_of_address', 'required': true, 'maxAgeMonths': 3},
            ],
          },
        }),
        const BusinessDocumentsScreen(),
      ));
      await tester.pump();
      expect(find.textContaining('From the last 3 months'), findsOneWidget);
      expect(find.text('Upload this document'), findsOneWidget);
      // One group: no position, nothing tucked behind it.
      expect(find.text('1 of 1'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('^Next:')), findsNothing);
    });

    testWidgets('an optional group can be skipped', (tester) async {
      await tester.pumpWidget(host(
        config({
          'documents': {
            'enabled': true,
            'types': [
              {'key': 'tax_document'},
            ],
          },
        }),
        const BusinessDocumentsScreen(),
      ));
      await tester.pump();
      // One group: the card names it and the document it accepts.
      expect(find.text('Tax registration'), findsOneWidget);
      expect(find.text('Tax registration or clearance certificate'),
          findsOneWidget);
      expect(buttonEnabled(tester, 'Skip'), isTrue);
    });
  });

  group('ApplicantRoleScreen', () {
    testWidgets('Continue needs a declared role', (tester) async {
      await tester.pumpWidget(host(
        config({
          'applicant': {'verification': true}
        }),
        const ApplicantRoleScreen(),
      ));
      await tester.pump();

      expect(continueEnabled(tester), isFalse);
      expect(find.text('Your role at the business'), findsOneWidget);
    });
  });
}
