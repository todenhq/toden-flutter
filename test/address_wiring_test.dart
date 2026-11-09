import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/address_flow.dart';
import 'package:toden_flutter/src/providers/address_step_order.dart';
import 'package:toden_flutter/src/providers/verification_state.dart';
import 'package:toden_flutter/src/providers/step_order.dart';
import 'package:toden_flutter/src/utils/step_log.dart';

// ─── The address flow, wired into the step machine ───────────────────────────
//
// The four screens are REAL steps, so entering, leaving and going back are
// ordinary step navigation. These tests pin the seams that carry that: what
// the order contains, what the progress bar counts, and where a resumed
// session is allowed to land.

VerificationConfig _individual({
  String? photo,
  bool proofOfAddress = false,
  bool questionnaire = false,
}) =>
    VerificationConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      addressCollection:
          AddressCollectionConfig(enabled: true, photo: photo),
      proofOfAddress:
          proofOfAddress ? const ProofOfAddressConfig(enabled: true) : null,
      questionnaire: questionnaire
          ? QuestionnaireConfig.fromJson(const {
              'fields': [
                {'key': 'source_of_funds', 'label': 'Source', 'type': 'text'},
              ],
            })
          : null,
    );

VerificationConfig _business() => VerificationConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      subjectType: 'business',
      business: WorkflowBusinessConfig.fromJson(const {'country': 'NG'}),
      addressCollection: const AddressCollectionConfig(enabled: true),
    );

VerificationState _withSearch() => const VerificationState(
      serverConfig: ServerSdkConfig(
        status: ServerConfigStatus.ready,
        addressSearch: true,
        addressSearchMode: 'basic',
      ),
    );

void main() {
  group('wire names', () {
    test('are the canonical four, in flow order', () {
      // The server's timeline titles and every session snapshot key off these,
      // so Flutter must never leak its camelCase enum names. A CROSS-SDK
      // MIRROR: the same four strings appear in the web and RN SDKs.
      expect(
        [for (final step in kAddressFlowOrder) kStepWireNames[step]],
        ['address-search', 'address-collection', 'address-entrance',
         'address-review'],
      );
    });

    test('the pin step keeps the ORIGINAL name though it moved second', () {
      // Session progress saved by a build that had one address screen restores
      // onto this one. Renaming it would strand every one of those snapshots.
      expect(kStepWireNames[VerificationStep.addressCollection], 'address-collection');
    });
  });

  group('entering and leaving', () {
    test('the flow is entered at its FIRST step, not at the pin', () {
      // Routing straight to the pin skips the search entirely. `nextStep`
      // indexes into this order, so what follows Proof of Address IS where the
      // applicant lands.
      final order = buildStepOrder(
        _individual(proofOfAddress: true),
        _withSearch(),
      );
      final poa = order.indexOf(VerificationStep.proofOfAddress);
      expect(order[poa + 1], VerificationStep.addressSearch);
    });

    test('backing in from the questionnaire lands on the review', () {
      // `previousStep` indexes into the same order, so the step before the
      // questionnaire is where a back press from it arrives.
      final order = buildStepOrder(
        _individual(questionnaire: true),
        _withSearch(),
      );
      final questionnaire = order.indexOf(VerificationStep.questionnaire);
      expect(order[questionnaire - 1], VerificationStep.addressReview);
    });

    test('the whole flow sits contiguously in the order', () {
      final order = buildStepOrder(
        _individual(proofOfAddress: true, questionnaire: true),
        _withSearch(),
      );
      final poa = order.indexOf(VerificationStep.proofOfAddress);
      final questionnaire = order.indexOf(VerificationStep.questionnaire);
      expect(order.sublist(poa + 1, questionnaire), kAddressFlowOrder);
    });
  });

  group('the progress indicator', () {
    test('counts every address step', () {
      // The bar reads the same `buildStepOrder` navigation does, minus the
      // terminal step. Four screens the applicant walks are four it must count.
      int countable(VerificationConfig config, VerificationState state) =>
          buildStepOrder(config, state)
              .where((s) => s != VerificationStep.submitted)
              .length;

      final withFlow = countable(_individual(), _withSearch());
      final withoutFlow = countable(
        const VerificationConfig(
          apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          country: 'NG',
        ),
        _withSearch(),
      );
      expect(withFlow - withoutFlow, 4);
    });

    test('every step it counts can be placed in the order', () {
      // A step absent from the order has no index, so the bar cannot place it
      // and both next and back become no-ops. That is the dead end the resume
      // clamp below exists to prevent.
      final order = buildStepOrder(_individual(), _withSearch());
      for (final step in kAddressFlowOrder) {
        expect(order.indexOf(step), greaterThan(-1), reason: '$step');
      }
    });
  });

  group('KYB runs the same address steps as a person', () {
    test('offers the pin, the entrance and the review', () {
      expect(addressStepsFor(_business(), const VerificationState()), [
        VerificationStep.addressCollection,
        VerificationStep.addressEntrance,
        VerificationStep.addressReview,
      ]);
    });

    test('adds search when a backend is on, and keeps the photo slot', () {
      final config = VerificationConfig(
        apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        subjectType: 'business',
        business: WorkflowBusinessConfig.fromJson(const {'country': 'NG'}),
        addressCollection:
            const AddressCollectionConfig(enabled: true, photo: 'required'),
      );
      expect(buildStepOrder(config, _withSearch())
          .where(kAddressFlowOrder.contains)
          .toList(),
          kAddressFlowOrder);
    });

    test('the review is therefore the step that COMMITS', () {
      // The screen asks the flow, not the subject type: the pin now advances,
      // and the review takes the attest fix and stores the presence pin.
      final offered = addressStepsFor(_business(), const VerificationState());
      expect(nextAddressStep(offered, VerificationStep.addressCollection), isNotNull);
      expect(nextAddressStep(offered, VerificationStep.addressReview), isNull);
    });

    test('on an individual flow the review commits instead', () {
      final offered = addressStepsFor(_individual(), _withSearch());
      expect(nextAddressStep(offered, VerificationStep.addressCollection), isNotNull);
      expect(nextAddressStep(offered, VerificationStep.addressReview), isNull);
    });
  });

}
