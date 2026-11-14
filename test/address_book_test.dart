import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/address_book.dart';
import 'package:toden_flutter/src/config/address_flow.dart';
import 'package:toden_flutter/src/config/address_state_json.dart';
import 'package:toden_flutter/src/config/submit_recovery.dart';
import 'package:toden_flutter/src/i18n/translate.dart';
import 'package:toden_flutter/src/providers/address_step_order.dart';
import 'package:toden_flutter/src/providers/step_order.dart';
import 'package:toden_flutter/src/providers/verification_state.dart';
import 'package:toden_flutter/src/services/api_service.dart';
import 'package:toden_flutter/src/utils/step_log.dart';

// ─── The Toden address book ──────────────────────────────────────────────────
//
// A port of the web SDK's lib/address-book.test.ts (the same pure rules and
// vectors), plus this SDK's own seams: the wire, the parsers, the step order
// and where a refused pick goes.

const _on = AddressBookSwitches(save: true, reuse: true);

VerificationConfig _addressScope({bool presence = false}) => VerificationConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      scope: 'address',
      addressCollection: AddressCollectionConfig(enabled: true, presenceEnabled: presence),
    );

VerificationState _ready({AddressBookSwitches? book = _on, AddressBookReuse? reuse}) =>
    VerificationState(
      serverConfig: ServerSdkConfig(
        status: ServerConfigStatus.ready,
        addressSearch: true,
        addressSearchMode: 'basic',
        addressBook: book,
      ),
      addressBookReuse: reuse,
    );

const _reuse = AddressBookReuse(grant: 'abr_1', entryId: 'adb_1', label: 'Adebayo Street', area: 'Calabar');

void main() {
  group('addressBookOffer', () {
    test('follows the server', () {
      final on = addressBookOffer(_on);
      expect((on.save, on.reuse), (true, true));
      final saveOff = addressBookOffer(const AddressBookSwitches(save: false, reuse: true));
      expect((saveOff.save, saveOff.reuse), (false, true));
      final none = addressBookOffer(null);
      expect((none.save, none.reuse), (false, false));
    });

    test('is never offered in a preview or for a business', () {
      for (final offer in [
        addressBookOffer(_on, previewMode: true),
        addressBookOffer(_on, subjectType: 'business'),
        addressBookOffer(_on, subjectType: 'business', scope: 'address'),
      ]) {
        expect((offer.save, offer.reuse), (false, false));
      }
    });

    test('reads the server block, and an absent one as nothing', () {
      final parsed = AddressBookSwitches.fromJson({'save': true, 'reuse': false})!;
      expect((parsed.save, parsed.reuse), (true, false));
      expect(AddressBookSwitches.fromJson(null), isNull);
      expect(SdkConfigResponse.fromJson({'addressBook': {'reuse': true}}).addressBook?.reuse, isTrue);
      expect(
        WorkflowResolution.fromJson({'config': <String, dynamic>{}, 'addressBook': {'save': true}})
            .addressBook
            ?.save,
        isTrue,
      );
    });
  });

  group('addressBookEmail', () {
    test('asks about the email passed in, trimmed', () {
      expect(addressBookEmail(' ada@example.com ', null, null), 'ada@example.com');
    });

    test('prefers the passed email over one proved in the flow', () {
      expect(addressBookEmail('ada@example.com', 'bo@example.com', 'proof'), 'ada@example.com');
    });

    test('falls back to an email proved with a code', () {
      expect(addressBookEmail(null, 'bo@example.com', 'proof'), 'bo@example.com');
      expect(addressBookEmail('not an email', 'bo@example.com', 'proof'), 'bo@example.com');
    });

    test('never uses an email nobody proved, and no email means no offer', () {
      expect(addressBookEmail(null, 'bo@example.com', null), isNull);
      expect(addressBookEmail(null, null, null), isNull);
      expect(addressBookEmail('', '', 'proof'), isNull);
    });
  });

  group('the address book step', () {
    test('is never a capture step: the offer is a sheet over them', () {
      final steps = addressStepsFor(_addressScope(), _ready());
      expect(steps, isNot(contains(VerificationStep.addressBook)));
      expect(steps.first, VerificationStep.addressSearch);
    });

    test('sends the capture steps to the address book once a saved address is picked', () {
      for (final step in kAddressFlowOrder) {
        expect(reusedAddressStep(step, true), VerificationStep.addressBook);
        expect(reusedAddressStep(step, false), step);
      }
      expect(reusedAddressStep(VerificationStep.questionnaire, true), VerificationStep.questionnaire);
    });

    test('drops the capture steps from the progress once picked', () {
      final order = buildStepOrder(_addressScope(), _ready());
      expect(order, containsAll([
        VerificationStep.addressSearch,
        VerificationStep.addressCollection,
        VerificationStep.addressReview,
      ]));
      expect(order, isNot(contains(VerificationStep.addressBook)));
      final reused = buildStepOrder(_addressScope(), _ready(reuse: _reuse));
      expect(reused, contains(VerificationStep.addressBook));
      expect(reused, isNot(contains(VerificationStep.addressCollection)));
    });

    test('is not offered on a business premises, and a pick there is ignored', () {
      final business = VerificationConfig(
        apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        subjectType: 'business',
        business: WorkflowBusinessConfig.fromJson(const {'country': 'NG'}),
        addressCollection: const AddressCollectionConfig(enabled: true),
      );
      expect(addressStepsFor(business, _ready(reuse: _reuse)), isNot(contains(VerificationStep.addressBook)));
    });

    test('keeps the presence primer for the first capture step', () {
      final config = _addressScope(presence: true);
      expect(addressIntroGateShowing(config, _ready(reuse: _reuse), VerificationStep.addressBook), isFalse);
      expect(addressIntroGateShowing(config, _ready(), VerificationStep.addressSearch), isTrue);
    });

    test('a saved step with no pick carries on into the capture', () {
      final offered = addressStepsFor(_addressScope(), _ready());
      expect(resumeAddressStep(VerificationStep.addressBook, offered), VerificationStep.addressSearch);
      expect(isAddressFlowStep(VerificationStep.addressBook), isTrue);
    });

    test('has its own wire name', () {
      expect(kStepWireNames[VerificationStep.addressBook], 'address-book');
    });

    test('a refused pick goes back to the address step, where the offer returns', () {
      final order = buildStepOrder(_addressScope(), _ready());
      for (final code in kAddressBookReuseRefusals) {
        expect(recoveryStepFor(code, order), VerificationStep.addressCollection);
      }
    });

    test('words every phase from its own texts', () {
      expect(defaultTextFn('address.book.offer.title'), 'You have a saved address');
      expect(defaultTextFn('address.book.offer.new'), 'Enter a new address');
      expect(defaultTextFn('address.book.offer.email', vars: {'email': 'a@b.co'}),
          "We'll send a code to a@b.co to confirm it's you.");
      expect(defaultTextFn('address.book.code.description', vars: {'email': 'a@b.co'}),
          'We sent a 6-digit code to a@b.co.');
      expect(defaultTextFn('address.book.save.title'), 'Save this address for next time?');
    });
  });

  group('saving', () {
    test('sends nothing unless the box is ticked', () {
      expect(addressBookSaveBlock(null, hasPhoto: true, hasDirections: true), isEmpty);
      expect(
        addressBookSaveBlock(const AddressBookSaveChoice(photo: true, directions: true),
            hasPhoto: true, hasDirections: true),
        isEmpty,
      );
    });

    test('only shares a photo or directions the person gave', () {
      expect(
        addressBookSaveBlock(const AddressBookSaveChoice(save: true, photo: true, directions: true),
            hasPhoto: false, hasDirections: true),
        {
          'book': {'save': true, 'photo': false, 'directions': true},
        },
      );
    });

    test('reads a saved address by street and area', () {
      expect(savedAddressLine(label: 'Adebayo Street', area: 'Calabar South'), 'Adebayo Street, Calabar South');
      expect(savedAddressLine(label: null, area: 'Ikeja'), 'Ikeja');
    });

    test('rides the submission, and session progress keeps the raw choice', () {
      const address = AddressState(
        lat: 4.95,
        lng: 8.32,
        directions: 'Blue gate',
        book: AddressBookSaveChoice(save: true, photo: true, directions: true),
      );
      expect(addressPayload(address, hasPhoto: false)['book'],
          {'save': true, 'photo': false, 'directions': true});
      expect(addressPayload(address).containsKey('book'), isFalse);
      final restored = addressFromProgressJson(addressProgressJson(address))!;
      expect(restored.book?.save, isTrue);
      expect(restored.book?.photo, isTrue);
    });

    test('a picked saved address replaces the address on the wire', () {
      final json = const VerifyRequest(
        country: 'NG',
        idType: 'address',
        addressBookReuse: _reuse,
        metadata: VerifyMetadata(requestId: 'r1'),
      ).toJson();
      expect(json['addressBookReuse'], {'grant': 'abr_1', 'entryId': 'adb_1'});
      expect(json.containsKey('address'), isFalse);
    });
  });

  group('usableSavedAddresses', () {
    final now = DateTime.parse('2026-10-26T12:00:00Z');
    SavedAddress entry(String? status, int? daysAgo) => SavedAddress(
          entryId: 'adb_${status}_$daysAgo',
          label: 'Adebayo Street',
          area: 'Calabar',
          countryCode: 'NG',
          tier: 'attested',
          presenceStatus: status,
          presenceDecidedAt:
              daysAgo == null ? null : now.subtract(Duration(days: daysAgo)).toIso8601String(),
        );

    test('keeps every saved address on a flow without a presence check', () {
      final list = [entry(null, null), entry('verified', 400)];
      final result = usableSavedAddresses(list, false, now: now);
      expect(result.usable, list);
      expect(result.hidden, 0);
    });

    test('keeps only recent confirmed addresses on a presence flow, and counts the rest', () {
      final recent = entry('verified', 30);
      final result = usableSavedAddresses(
          [recent, entry('verified', 200), entry('monitoring', null), entry(null, null)], true,
          now: now);
      expect(result.usable, [recent]);
      expect(result.hidden, 3);
    });

    test('treats the window edge as recent', () {
      expect(
        usableSavedAddresses([entry('verified', kPresenceReuseWindowDays)], true, now: now).usable,
        hasLength(1),
      );
    });

    test('parses a listing, dropping rows nothing could be picked from', () {
      final listing = AddressBookListing.fromJson({
        'grant': 'abr_9',
        'addresses': [
          {'entryId': 'adb_1', 'label': 'Adebayo Street', 'presenceStatus': 'verified'},
          {'label': 'No id'},
        ],
      });
      expect(listing.grant, 'abr_9');
      expect(listing.addresses.map((a) => a.entryId), ['adb_1']);
    });
  });

  group('offerTitleKey', () {
    test('greets the person when the host app named them', () {
      expect(offerTitleKey('Chinedu'), 'address.book.offer.titleNamed');
    });

    test('keeps the plain title without a usable name', () {
      expect(offerTitleKey(null), 'address.book.offer.title');
      expect(offerTitleKey('   '), 'address.book.offer.title');
    });
  });
}
