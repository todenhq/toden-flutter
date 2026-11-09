import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/address_book.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/providers/address_book_provider.dart';
import 'package:toden_flutter/src/providers/verification_provider.dart';
import 'package:toden_flutter/src/providers/verification_state.dart';
import 'package:toden_flutter/src/screens/address/address_pin_step.dart';
import 'package:toden_flutter/src/screens/address/address_search_step.dart';
import 'package:toden_flutter/src/screens/address/save_address_sheet.dart';
import 'package:toden_flutter/src/screens/address/saved_address_sheet.dart';
import 'package:toden_flutter/src/services/api_service.dart';

// ─── The address book in a running flow ──────────────────────────────────────
//
// The offer asks about the flow's email and shows only when it is recognised,
// walks offer → code → pick against a stub server in one sheet, a pick replaces
// the address on the submission, and a refused pick brings the offer back saying
// why.

class _Api extends VerificationApiService {
  _Api() : super(baseUrl: 'http://stub', apiKey: 'pk_test_stub');

  final codes = <String>[];
  final lookups = <String>[];
  final presences = <bool>[];
  bool recognised = true;
  VerifyRequest? submitted;

  @override
  Future<bool> addressBookLookup(String email, {required bool presence}) async {
    lookups.add(email);
    presences.add(presence);
    return recognised;
  }

  @override
  Future<String> addressBookCode(String email) async {
    codes.add(email);
    return 'chal_1';
  }

  @override
  Future<AddressBookListing> addressBookAddresses(String challengeId, String code) async =>
      const AddressBookListing(grant: 'abr_1', addresses: [
        SavedAddress(entryId: 'adb_1', label: 'Bassey Street', area: 'Calabar', presenceStatus: 'verified'),
      ]);

  @override
  Future<VerifyResponse> verify(VerifyRequest request) async {
    submitted = request;
    return const VerifyResponse(verificationId: 'ver_1', status: 'pending');
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

List<Override> _overrides(_Api api, {String? email = 'ada@example.com'}) => [
      verificationConfigProvider.overrideWithValue(VerificationConfig(
        apiKey: 'pk_test_stub',
        country: 'NG',
        scope: 'address',
        consentStep: false,
        userData: UserData(email: email),
        addressCollection: const AddressCollectionConfig(enabled: true),
      )),
      verificationApiServiceProvider.overrideWithValue(api),
      preloadedServerConfigProvider.overrideWithValue(const ServerSdkConfig(
        status: ServerConfigStatus.ready,
        addressBook: AddressBookSwitches(save: true, reuse: true),
      )),
      kYCNotifierProvider.overrideWith(VerificationNotifier.new),
      addressBookProvider.overrideWith(AddressBookNotifier.new),
    ];

const _reuse = AddressBookReuse(grant: 'abr_1', entryId: 'adb_1', label: 'Bassey Street', area: 'Calabar');

Widget _themed(ProviderContainer container, Widget home) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: const [UiColorScheme.light]),
        home: Scaffold(body: home),
      ),
    );

void main() {
  test('the flow opens on the capture: the offer is a sheet over it', () {
    final c = ProviderContainer(overrides: _overrides(_Api()));
    addTearDown(c.dispose);
    expect(c.read(kYCNotifierProvider).currentStep, VerificationStep.addressCollection);
  });

  test('a picked address replaces the capture on the wire and skips its steps', () async {
    final api = _Api();
    final c = ProviderContainer(overrides: _overrides(api));
    addTearDown(c.dispose);
    final notifier = c.read(kYCNotifierProvider.notifier);
    notifier.setAddress(const AddressState(lat: 4.95, lng: 8.32));
    notifier.setAddressPhoto('med_photo');
    notifier.setAddressBookReuse(_reuse);

    // Anything that would land on a capture step lands on the pick instead.
    notifier.goToStep(VerificationStep.submitted);
    notifier.goToStep(VerificationStep.addressCollection);
    expect(c.read(kYCNotifierProvider).currentStep, VerificationStep.addressBook);

    await notifier.submitAsync();
    final json = api.submitted!.toJson();
    expect(json['addressBookReuse'], {'grant': 'abr_1', 'entryId': 'adb_1'});
    expect(json.containsKey('address'), isFalse);
    expect((json['mediaIds'] as Map?)?['addressPhoto'], isNull);
  });

  test('a ticked save box rides address.book', () async {
    final api = _Api();
    final c = ProviderContainer(overrides: _overrides(api));
    addTearDown(c.dispose);
    final notifier = c.read(kYCNotifierProvider.notifier);
    notifier.setAddress(const AddressState(lat: 4.95, lng: 8.32, directions: 'Blue gate'));
    notifier.setAddressBookSave(const AddressBookSaveChoice(save: true, photo: true, directions: true));
    await notifier.submitAsync();
    expect((api.submitted!.toJson()['address'] as Map)['book'],
        {'save': true, 'photo': false, 'directions': true});
  });

  test('a refused pick brings the offer back over the address step, saying why', () {
    final c = ProviderContainer(overrides: _overrides(_Api()));
    addTearDown(c.dispose);
    final notifier = c.read(kYCNotifierProvider.notifier);
    notifier.setAddressBookReuse(_reuse);
    notifier.goToStep(VerificationStep.submitted);
    notifier.addressBookReuseRefused();
    final s = c.read(kYCNotifierProvider);
    expect(s.currentStep, VerificationStep.addressCollection);
    expect(s.addressBookReuse, isNull);
    final book = c.read(addressBookProvider);
    expect(book.phase, AddressBookPhase.offer);
    expect(book.errorKey, 'address.book.refused');
  });

  test('an answered lookup leaves a decision already made alone', () {
    final c = ProviderContainer(overrides: _overrides(_Api()));
    addTearDown(c.dispose);
    final book = c.read(addressBookProvider.notifier);
    book.checking();
    book.close();
    book.recognised(true);
    expect(c.read(addressBookProvider).phase, AddressBookPhase.closed);
  });

  test('one saved address starts selected', () {
    final c = ProviderContainer(overrides: _overrides(_Api()));
    addTearDown(c.dispose);
    c.read(addressBookProvider.notifier).listed(
      'abr_1',
      const [SavedAddress(entryId: 'adb_1', label: 'Bassey Street', area: 'Calabar')],
      flowRunsPresence: false,
    );
    expect(c.read(addressBookProvider).picked?.entryId, 'adb_1');
  });

  testWidgets('a recognised email: offer, code, pick, then on past the capture', (tester) async {
    final api = _Api();
    final container = ProviderContainer(overrides: _overrides(api));
    addTearDown(container.dispose);
    var used = 0;
    await tester.pumpWidget(_themed(container, SavedAddressOffer(onUsed: () => used++, child: const SizedBox())));
    await tester.pumpAndSettle();

    expect(api.lookups, ['ada@example.com']);
    expect(find.text('You have a saved address'), findsOneWidget);
    await tester.tap(find.text('Use saved address'));
    await tester.pumpAndSettle();
    expect(api.codes, ['ada@example.com']);
    expect(find.text('We sent a 6-digit code to ada@example.com.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '000000');
    await tester.pumpAndSettle();
    expect(container.read(addressBookProvider).phase, AddressBookPhase.pick);
    expect(find.text('Bassey Street, Calabar'), findsOneWidget);
    expect(find.text('Presence confirmed'), findsOneWidget);

    await tester.tap(find.text('Use this address'));
    await tester.pumpAndSettle();
    expect(container.read(kYCNotifierProvider).addressBookReuse?.entryId, 'adb_1');
    expect(container.read(addressBookProvider).phase, AddressBookPhase.closed);
    expect(used, 1);
    expect(find.text('Choose your address'), findsNothing);
  });

  testWidgets('an email with nothing saved shows nothing', (tester) async {
    final api = _Api()..recognised = false;
    final container = ProviderContainer(overrides: _overrides(api));
    addTearDown(container.dispose);
    await tester.pumpWidget(_themed(container, SavedAddressOffer(onUsed: () {}, child: const SizedBox())));
    await tester.pumpAndSettle();
    expect(api.lookups, hasLength(1));
    expect(container.read(addressBookProvider).phase, AddressBookPhase.closed);
    expect(find.text('You have a saved address'), findsNothing);
  });

  testWidgets('no email means no lookup and no offer', (tester) async {
    final api = _Api();
    final container = ProviderContainer(overrides: _overrides(api, email: null));
    addTearDown(container.dispose);
    await tester.pumpWidget(_themed(container, SavedAddressOffer(onUsed: () {}, child: const SizedBox())));
    await tester.pumpAndSettle();
    expect(api.lookups, isEmpty);
    expect(find.text('You have a saved address'), findsNothing);
  });

  testWidgets('entering a new address closes the offer for the attempt', (tester) async {
    final api = _Api();
    final container = ProviderContainer(overrides: _overrides(api));
    addTearDown(container.dispose);
    Widget host(Key key) => _themed(container, SavedAddressOffer(key: key, onUsed: () {}, child: const SizedBox()));
    await tester.pumpWidget(host(const ValueKey('search')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter a new address'));
    await tester.pumpAndSettle();
    expect(container.read(addressBookProvider).phase, AddressBookPhase.closed);
    expect(find.text('You have a saved address'), findsNothing);

    // The next address step hosts it too, and neither asks nor shows again.
    await tester.pumpWidget(host(const ValueKey('pin')));
    await tester.pumpAndSettle();
    expect(api.lookups, hasLength(1));
    expect(find.text('You have a saved address'), findsNothing);
  });

  Future<bool?> saveSheet(WidgetTester tester, ProviderContainer container) async {
    bool? answer;
    await tester.pumpWidget(_themed(
      container,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => answer = await askToSaveAddress(context),
          child: const Text('Confirm'),
        ),
      ),
    ));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets('saving keeps the photo by default and asks only about directions', (tester) async {
    final container = ProviderContainer(overrides: _overrides(_Api()));
    addTearDown(container.dispose);
    container
        .read(kYCNotifierProvider.notifier)
        .setAddress(const AddressState(lat: 4.95, lng: 8.32, directions: 'Blue gate'));
    await saveSheet(tester, container);
    expect(find.text('Save this address for next time?'), findsOneWidget);
    expect(find.text('Include my entrance photo'), findsNothing);
    await tester.tap(find.text('Include my directions'));
    await tester.pump();
    await tester.tap(find.text('Save address'));
    await tester.pumpAndSettle();
    final book = container.read(kYCNotifierProvider).address?.book;
    expect(book?.save, isTrue);
    expect(book?.photo, isTrue);
    expect(book?.directions, isTrue);
  });

  testWidgets('no directions, no directions check; Not now records the answer', (tester) async {
    final container = ProviderContainer(overrides: _overrides(_Api()));
    addTearDown(container.dispose);
    container.read(kYCNotifierProvider.notifier).setAddress(const AddressState(lat: 4.95, lng: 8.32));
    await saveSheet(tester, container);
    expect(find.text('Include my directions'), findsNothing);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(container.read(kYCNotifierProvider).address?.book?.save, isFalse);
  });

  // The flow as a workflow mount really runs it (user report 2026-11-09): no
  // userData, the email proved by the OTP step, the server facts parsed from
  // the workflow resolution exactly as kyc-core serves them, and the offer
  // hosted by the real first address step rather than a bare SizedBox.
  group('a workflow mount, the email proved in the flow', () {
    ProviderContainer workflowFlow(_Api api, {required bool search, bool presence = false}) {
      final res = WorkflowResolution.fromJson({
        'workflow': {'id': 'wf_1', 'name': 'Demo', 'version': 3},
        'config': {
          'country': 'NG',
          'emailVerification': {'enabled': true},
          'addressCollection': {
            'enabled': true,
            if (presence) 'presence': {'enabled': true},
          },
        },
        'environment': 'DEVELOPMENT',
        'idTypes': <Map<String, dynamic>>[],
        'addressBook': {'save': true, 'reuse': true},
        'addressSearch': search,
      });
      final c = ProviderContainer(overrides: [
        verificationConfigProvider.overrideWithValue(VerificationConfig(
          apiKey: 'pk_test_stub',
          country: 'NG',
          addressCollection: AddressCollectionConfig.fromJson(
              (res.config.raw['addressCollection'] as Map).cast<String, dynamic>()),
        )),
        verificationApiServiceProvider.overrideWithValue(api),
        preloadedServerConfigProvider.overrideWithValue(ServerSdkConfig(
          status: ServerConfigStatus.ready,
          environment: res.environment,
          addressSearch: res.addressSearch,
          addressBook: res.addressBook,
        )),
        kYCNotifierProvider.overrideWith(VerificationNotifier.new),
        addressBookProvider.overrideWith(AddressBookNotifier.new),
      ]);
      c.read(kYCNotifierProvider.notifier).setContactProof('email', 'evt_1', 'ada@example.com');
      return c;
    }

    for (final search in [false, true]) {
      final step = search ? VerificationStep.addressSearch : VerificationStep.addressCollection;
      testWidgets('the ${step.name} step opening the flow offers the saved address', (tester) async {
        final api = _Api();
        final container = workflowFlow(api, search: search);
        addTearDown(container.dispose);
        container.read(kYCNotifierProvider.notifier).goToStep(step);
        expect(container.read(kYCNotifierProvider).currentStep, step);
        await tester.pumpWidget(_themed(
            container, search ? const AddressSearchStep() : const AddressPinStep()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(api.lookups, ['ada@example.com']);
        expect(api.presences, [false]);
        expect(container.read(addressBookProvider).phase, AddressBookPhase.offer);
        expect(find.text('You have a saved address'), findsOneWidget);
      });
    }

    testWidgets('a presence flow asks for a saved address with a recent verdict', (tester) async {
      final api = _Api();
      final container = workflowFlow(api, search: false, presence: true);
      addTearDown(container.dispose);
      container.read(kYCNotifierProvider.notifier).goToStep(VerificationStep.addressCollection);
      await tester.pumpWidget(_themed(container, const AddressPinStep()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.lookups, ['ada@example.com']);
      expect(api.presences, [true]);
      expect(find.text('You have a saved address'), findsOneWidget);
    });

    testWidgets('an email typed but not proved (or no email step at all): no lookup', (tester) async {
      final api = _Api();
      final container = workflowFlow(api, search: false);
      addTearDown(container.dispose);
      container.read(kYCNotifierProvider.notifier).clearContactProofs(const ['email']);
      container.read(kYCNotifierProvider.notifier).goToStep(VerificationStep.addressCollection);
      await tester.pumpWidget(_themed(container, const AddressPinStep()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.lookups, isEmpty);
      expect(find.text('You have a saved address'), findsNothing);
    });
  });
}
