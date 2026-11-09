import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/poa_subtypes.dart';
import 'package:toden_flutter/src/config/proof_of_address.dart';
import 'package:toden_flutter/src/i18n/translate.dart';

// The documents inside each proof-of-address kind, how they read, and how
// recent each kind must be. Mirrors the web SDK's lib/poa-subtypes.ts.
void main() {
  test("a voter's ID card is a government document", () {
    expect(kPoaSubtypesByKind[PoaDocumentType.governmentDocument], contains('voter_id'));
  });

  test('every subtype has a name and a short name', () {
    for (final list in kPoaSubtypesByKind.values) {
      for (final s in list) {
        expect(defaultTextFn(poaSubtypeKey(s)), isNot(poaSubtypeKey(s)), reason: s);
        expect(defaultTextFn(poaSubtypeShortKey(s)), isNot(poaSubtypeShortKey(s)), reason: s);
      }
    }
    expect(poaSubtypeKey('electricity_bill'), 'proofOfAddress.subtype.electricityBill');
  });

  test('the workflow narrows a kind only where it names that kind\'s subtypes', () {
    const picked = ['water_bill', 'lease_agreement', 'not_a_thing'];
    expect(acceptedPoaSubtypes(PoaDocumentType.utilityBill, picked), ['water_bill']);
    expect(acceptedPoaSubtypes(PoaDocumentType.tenancyAgreement, picked), ['lease_agreement']);
    expect(acceptedPoaSubtypes(PoaDocumentType.bankStatement, picked),
        kPoaSubtypesByKind[PoaDocumentType.bankStatement]);
  });

  test('a kind reads as one phrase, joined with "or"', () {
    expect(
      poaKindSummary(PoaDocumentType.tenancyAgreement, const [], defaultTextFn),
      'Tenancy, lease, or title deed',
    );
    expect(
      poaKindSummary(PoaDocumentType.utilityBill, const ['water_bill', 'gas_bill'], defaultTextFn),
      'Water or gas',
    );
    expect(
      poaKindSummary(PoaDocumentType.tenancyAgreement, const [], defaultTextFn, language: 'en-GB'),
      'Tenancy, lease or title deed',
    );
  });

  test('the window is the kind\'s own, else maxAgeDays, else 90', () {
    const poa = ProofOfAddressConfig(maxAgeDays: 60, documentValidity: {'bank_statement': 30});
    expect(poaKindDays(poa, PoaDocumentType.bankStatement), 30);
    expect(poaKindDays(poa, PoaDocumentType.utilityBill), 60);
    expect(poaKindDays(null, PoaDocumentType.utilityBill), 90);
  });

  test('a window reads in months or years, or any date', () {
    expect(poaPeriodLabel(90, defaultTextFn), '3 months');
    expect(poaPeriodLabel(30, defaultTextFn), '1 month');
    expect(poaPeriodLabel(365, defaultTextFn), '1 year');
    expect(poaPeriodLabel(730, defaultTextFn), '2 years');
    expect(poaPeriodLabel(0, defaultTextFn), 'Any date');
  });

  test('the new fields parse off a resolved workflow', () {
    final cfg = ProofOfAddressConfig.fromJson({
      'enabled': true,
      'capture': 'camera',
      'documentSubtypes': ['water_bill'],
      'documentValidity': {'utility_bill': 180},
      'documentSubtypeValidity': {'water_bill': 60},
    });
    expect(cfg.capture, PoaCapture.camera);
    expect(cfg.documentSubtypes, ['water_bill']);
    expect(cfg.documentValidity, {'utility_bill': 180});
    expect(cfg.documentSubtypeValidity, {'water_bill': 60});
    expect(ProofOfAddressConfig.fromJson({}).capture, PoaCapture.both);
    expect(ProofOfAddressConfig.fromJson({'capture': 'scanner'}).capture, PoaCapture.both);
  });
}
