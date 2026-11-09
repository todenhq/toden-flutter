import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/services/document_framing_gate.dart'
    show DocumentHint;
import 'package:toden_flutter/src/services/document_identity.dart';
import 'package:toden_flutter/src/services/document_type_signals.dart';

// A NIN slip had no word list, so auto-capture could not check what was in the
// frame and shot a voter's card held where the slip should be. The lists mirror
// the server's DOCUMENT_SIGNALS (kyc-core src/lib/ocr-parser.ts) and the React
// Native SDK's ninSlipIdentity.test.ts.

const _paperSlip = [
  'FEDERAL REPUBLIC OF NIGERIA',
  'NATIONAL IDENTITY MANAGEMENT COMMISSION',
  'National Identification Number Slip (NINS)',
  'Tracking ID: ABC123XYZ',
];
const _digitalSlip = [
  'FEDERAL REPUBLIC OF NIGERIA',
  'DIGITAL NIN SLIP',
  'NATIONAL IDENTITY MANAGEMENT SYSTEM',
];
const _voterCard = [
  'FEDERAL REPUBLIC OF NIGERIA',
  'INDEPENDENT NATIONAL ELECTORAL COMMISSION',
  "VOTER'S CARD",
  'VIN 90F5 AEF5 1B41 6491 787',
];

void main() {
  test('has signals to check against', () {
    expect(hasDocumentSignals('NG', 'nin-slip'), isTrue);
  });

  test('identifies a paper slip and a digital slip', () {
    expect(detectDocumentType(_paperSlip, 'NG').type, 'nin-slip');
    expect(
      verifyDocumentIdentity(_paperSlip, country: 'NG', idType: 'nin-slip')
          .identified,
      isTrue,
    );
    expect(
      verifyDocumentIdentity(_digitalSlip, country: 'NG', idType: 'nin-slip')
          .identified,
      isTrue,
    );
  });

  test("refuses a voter's card held in place of the slip", () {
    final r =
        verifyDocumentIdentity(_voterCard, country: 'NG', idType: 'nin-slip');
    expect(r.identified, isFalse);
    expect(r.hint, DocumentHint.wrongDocument);
  });

  test("does not take a driver's licence that prints a NIN field", () {
    const dl = ['FEDERAL ROAD SAFETY CORPS', 'DRIVING LICENCE', 'NIN 12345678901'];
    expect(
      verifyDocumentIdentity(dl, country: 'NG', idType: 'nin-slip').identified,
      isFalse,
    );
  });
}
