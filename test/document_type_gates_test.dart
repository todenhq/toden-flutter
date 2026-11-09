import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/capture_hints.dart';
import 'package:toden_flutter/src/config/document_guide.dart';
import 'package:toden_flutter/src/config/document_turn.dart';
import 'package:toden_flutter/src/services/document_corner_gate.dart';
import 'package:toden_flutter/src/services/document_corners.dart';
import 'package:toden_flutter/src/services/document_detection.dart';
import 'package:toden_flutter/src/services/document_framing_gate.dart';
import 'package:toden_flutter/src/services/document_identity.dart';
import 'package:toden_flutter/src/services/document_open_passport.dart';
import 'package:toden_flutter/src/services/document_text_gate.dart';
import 'package:toden_flutter/src/services/mrz_extract.dart';

// ─── Every document type through every capture gate ───────────────────────────
//
// A correctly held document, filling its guide with all four corners in view,
// must clear each gate the iPhone camera applies, in order: the framing gate
// (shape, size, centring), the corner gate (in view, space past each corner,
// no bigger than the guide), the text check (keywords on THAT side of THAT
// document), and the dwell. Run on an iPhone 16 Pro Max's full-screen camera:
// a 440 x 956 view over a 1080 x 1920 upright frame.
//
// The texts are what each document actually prints, accents included: a
// keyword list that a real front does not satisfy holds the camera at "move
// closer" for good, which is how a Ghana Card and a Côte d'Ivoire CNI never
// captured.

const _view = Size(440, 956);
const _frame = Size(1080, 1920);
final _band = documentGuideBand(topInset: 62, bottomInset: 34);
final _visible = visibleFrameRegion(_frame, _view);
final _t0 = DateTime(2026, 11, 9, 12);

/// ICAO 9303 check digit.
int _check(String s) {
  const weights = [7, 3, 1];
  var sum = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final v = c == 60
        ? 0
        : c >= 48 && c <= 57
            ? c - 48
            : c - 55;
    sum += v * weights[i % 3];
  }
  return sum % 10;
}

/// A check-digit-valid TD3 (passport) MRZ for [country].
List<String> _passportMrz(String country) {
  final line1 = 'P<${country}OKAFOR<<CHIDI<EMEKA'.padRight(44, '<');
  const number = 'A12345678';
  const birth = '900115';
  const expiry = '310101';
  final optional = '<' * 14;
  final body = '$number${_check(number)}$country'
      '$birth${_check(birth)}M$expiry${_check(expiry)}'
      '$optional${_check(optional)}';
  final composite = '$number${_check(number)}$birth${_check(birth)}'
      '$expiry${_check(expiry)}$optional${_check(optional)}';
  return [line1, '$body${_check(composite)}'];
}

class _Doc {
  final String name;
  final String country;
  final String idType;
  final double aspect;
  final List<String> front;
  final List<String>? back;

  const _Doc(this.name, this.country, this.idType, this.aspect, this.front,
      [this.back]);
}

final _docs = <_Doc>[
  const _Doc('NG driver\'s licence', 'NG', 'drivers-license', kCardGuideAspect, [
    'FEDERAL REPUBLIC OF NIGERIA',
    "NATIONAL DRIVER'S LICENCE",
    'LIC NO ABC12345AA12',
    'SURNAME OKAFOR',
    'DATE OF BIRTH 15-01-1990',
    'CLASS B',
  ], [
    'ENDORSEMENTS',
    'FEDERAL ROAD SAFETY CORPS',
    'ISSUED 01-01-2024',
  ]),
  const _Doc('NG voter\'s card (PVC)', 'NG', 'pvc', kCardGuideAspect, [
    'INDEPENDENT NATIONAL ELECTORAL COMMISSION',
    "VOTER'S CARD",
    'VIN 90F5B1C2D3E4',
    'DELIM 24-01-02-003',
    'NAME OKAFOR CHIDI',
    'DATE OF BIRTH 15 JAN 1990',
  ], [
    'THIS CARD REMAINS THE PROPERTY OF INEC',
    'IF FOUND RETURN TO THE NEAREST INEC OFFICE',
    '90F5B1C2D3E4',
  ]),
  const _Doc('NG NIN slip (upright)', 'NG', 'nin-slip', kNinSlipGuideAspect, [
    'FEDERAL REPUBLIC OF NIGERIA',
    'NATIONAL IDENTITY MANAGEMENT SYSTEM',
    'NATIONAL IDENTIFICATION NUMBER SLIP (NINS)',
    'TRACKING ID ABC123XYZ',
    'NIN 12345678901',
    'SURNAME OKAFOR',
  ]),
  _Doc('NG passport (data page)', 'NG', 'passport', kPassportGuideAspect, [
    'FEDERAL REPUBLIC OF NIGERIA',
    'PASSPORT PASSEPORT',
    'TYPE P CODE NGA',
    'SURNAME OKAFOR',
    ..._passportMrz('NGA'),
  ]),
  const _Doc('GH Ghana Card', 'GH', 'ghana-card', kCardGuideAspect, [
    'ECOWAS IDENTITY CARD',
    'REPUBLIC OF GHANA',
    'SURNAME MENSAH',
    'NATIONALITY GHANAIAN',
    'PERSONAL ID NUMBER',
    'GHA-123456789-0',
  ], [
    'IDGHA1234567890<<<<<<<<<<<<<<',
    '9001150M3101015GHA<<<<<<<<<<<',
    'MENSAH<<KOFI<<<<<<<<<<<<<<<<<',
  ]),
  const _Doc('GH voter\'s card', 'GH', 'voters', kCardGuideAspect, [
    'ELECTORAL COMMISSION OF GHANA',
    'VOTER ID CARD',
    'SURNAME MENSAH',
    'VOTER ID 1234567890',
    'DATE OF BIRTH 15/01/1990',
  ]),
  const _Doc('GH driver\'s licence', 'GH', 'drivers-license', kCardGuideAspect, [
    'REPUBLIC OF GHANA',
    'DRIVER AND VEHICLE LICENSING AUTHORITY',
    'DRIVING LICENCE',
    'LICENCE NO MEN-12345678-90',
    'SURNAME MENSAH',
  ]),
  const _Doc('GH SSNIT', 'GH', 'ssnit', kCardGuideAspect, [
    'SOCIAL SECURITY AND NATIONAL INSURANCE TRUST',
    'SSNIT BIOMETRIC CARD',
    'SOCIAL SECURITY NUMBER C123456789012',
    'NAME MENSAH KOFI',
    'DATE OF BIRTH 15/01/1990',
  ]),
  const _Doc('KE national ID', 'KE', 'national-id', kCardGuideAspect, [
    'JAMHURI YA KENYA',
    'REPUBLIC OF KENYA',
    'SERIAL NUMBER 123456789',
    'ID NUMBER 12345678',
    'FULL NAMES WANJIRU',
  ], [
    'DISTRICT NAIROBI',
    'PLACE OF ISSUE NAIROBI',
    'DATE OF ISSUE 01.01.2024',
  ]),
  const _Doc('ZA national ID', 'ZA', 'national-id', kCardGuideAspect, [
    'REPUBLIC OF SOUTH AFRICA',
    'NATIONAL IDENTITY CARD',
    'SURNAME DLAMINI',
    'IDENTITY NUMBER 9001155800085',
    'DATE OF BIRTH 15 JAN 1990',
  ], [
    'DATE OF ISSUE 01 JAN 2024',
    'DEPARTMENT OF HOME AFFAIRS',
    'CARD NUMBER 123456789',
  ]),
  const _Doc('CI CNI', 'CI', 'cni', kCardGuideAspect, [
    "RÉPUBLIQUE DE CÔTE D'IVOIRE",
    "CARTE NATIONALE D'IDENTITÉ",
    'NOM KOUASSI',
    'PRÉNOMS AYA',
    'DATE DE NAISSANCE 15/01/1990',
  ], [
    'DATE DE DÉLIVRANCE 01/01/2024',
    "DATE D'EXPIRATION 01/01/2034",
    'ADRESSE ABIDJAN',
  ]),
  const _Doc('CI residence card', 'CI', 'residence-card', kCardGuideAspect, [
    "RÉPUBLIQUE DE CÔTE D'IVOIRE",
    'CARTE DE SÉJOUR',
    'TITRE DE SÉJOUR',
    'NOM DIALLO',
    'PRÉNOMS AMADOU',
  ]),
  const _Doc('Global documents ID (FR)', 'FR', 'national-id', kCardGuideAspect, [
    'RÉPUBLIQUE FRANÇAISE',
    "CARTE NATIONALE D'IDENTITÉ",
    'NOM MARTIN',
    'PRÉNOMS CLAIRE',
    'NÉE LE 15 01 1990',
  ]),
  _Doc('Global documents passport (US)', 'US', 'passport',
      kPassportGuideAspect, [
    'UNITED STATES OF AMERICA',
    'PASSPORT',
    'SURNAME SMITH',
    ..._passportMrz('USA'),
  ]),
];

/// The guide for a document of [aspect] as the screen draws it, and whether
/// it is turned.
({Rect screen, Rect frame, double aspect, bool turned}) _guide(double aspect) {
  final turned = turnsDocument(aspect, _view.width / _view.height);
  final shown = screenGuideAspect(aspect, turned);
  final screen = documentGuideRect(_view, shown, band: _band);
  return (
    screen: screen,
    frame: guideInFrame(screen, _view, _visible)!,
    aspect: shown,
    turned: turned,
  );
}

/// [r] scaled about its centre.
Rect _scaled(Rect r, double s) =>
    Rect.fromCenter(center: r.center, width: r.width * s, height: r.height * s);

DocumentQuad _quad(Rect r) => quadOfRect(r);

/// The detector's box for a document found at [r] (normalised frame space).
DocumentBox _box(Rect r) => DocumentBox(
      x: r.left,
      y: r.top,
      width: r.width,
      height: r.height,
      confidence: 0.9,
      aspectRatio: r.width * _frame.width / (r.height * _frame.height),
    );

/// The framing gate run over a second of a still hand: ready by the dwell.
DocumentGuidance _frame1s(DocumentFramingGate gate, DocumentBox box) {
  var out = gate.update(box, at: _t0);
  for (var ms = 250; ms <= 1000; ms += 250) {
    out = gate.update(box, at: _t0.add(Duration(milliseconds: ms)));
  }
  return out;
}

void main() {
  for (final doc in _docs) {
    final sides = <(String, List<String>, bool)>[
      ('front', doc.front, false),
      if (doc.back != null) ('back', doc.back!, true),
    ];
    for (final (side, lines, isBack) in sides) {
      group('${doc.name}, $side, held filling its guide', () {
        final g = _guide(doc.aspect);
        // Held a little inside the guide, as people do.
        final held = _scaled(g.frame, 0.95);

        test('framing: right shape, size and place, then the dwell', () {
          final gate = DocumentFramingGate(expectedAspect: g.aspect);
          final first = gate.update(_box(held), at: _t0);
          expect(first.framing, DocumentFraming.holding,
              reason: 'hint ${first.hint}');
          expect(_frame1s(gate, _box(held)).framing, DocumentFraming.ready);
        });

        test('corners: all four in view, space past each, within the guide',
            () {
          // The screen bounds the size by a turned guide only (_cornerGuide).
          final corners = DocumentCornerGate()
            ..update(_quad(held),
                frame: _frame,
                visible: _visible,
                guide: g.turned ? g.frame : null);
          expect(corners.blocksCapture, isFalse, reason: '${corners.hint}');
        });

        test('Android: the text gate fires on this side', () {
          // The native camera reports where the text sits; on a back it is
          // the small print around a barcode.
          final gate = DocumentTextGate();
          final bounds = isBack ? _scaled(held, 0.6) : _scaled(held, 0.9);
          final mrz = extractMrz(lines);
          DocumentGuidance out = gate.update(lines,
              country: doc.country,
              idType: doc.idType,
              isBack: isBack,
              textBounds: bounds,
              hasValidMrz: mrz != null,
              now: _t0);
          for (var ms = 250;
              ms <= 1000 && out.framing != DocumentFraming.ready;
              ms += 250) {
            out = gate.update(lines,
                country: doc.country,
                idType: doc.idType,
                isBack: isBack,
                textBounds: bounds,
                hasValidMrz: mrz != null,
                now: _t0.add(Duration(milliseconds: ms)));
          }
          expect(out.framing, DocumentFraming.ready, reason: '${out.hint}');
        });

        test('text: the side identifies as this document', () {
          final mrz = extractMrz(lines);
          final identity = verifyDocumentIdentity(
            lines,
            country: doc.country,
            idType: doc.idType,
            isBack: isBack,
            hasValidMrz: mrz != null,
          );
          expect(identity.identified, isTrue, reason: '${identity.hint}');
        });
      });
    }
  }

  group('an open passport booklet, data page filling the guide', () {
    final g = _guide(kPassportGuideAspect);
    // The data page in the guide, the facing page above it: one sheet of
    // paper to the document finder, about 0.71 wide to 1 tall.
    final page = _scaled(g.frame, 0.95);
    final booklet = Rect.fromLTRB(
        page.left, page.top - page.height, page.right, page.bottom);
    final lines = _docs.firstWhere((d) => d.idType == 'passport').front;

    test('found as the booklet alone, its shape is refused', () {
      // Before the stand-in this held at "That doesn't look like your
      // International Passport" for good.
      final gate = DocumentFramingGate(expectedAspect: g.aspect);
      expect(gate.update(_box(booklet), at: _t0).framing,
          DocumentFraming.wrongShape);
      // Its corners are all in view: a landscape guide does not bound the
      // size, as in the React Native SDK.
      final corners = DocumentCornerGate()
        ..update(_quad(booklet), frame: _frame, visible: _visible);
      expect(corners.blocksCapture, isFalse);
    });

    test('a fresh valid MRZ makes the data page in the guide stand in', () {
      expect(extractMrz(lines), isNotNull);
      final standIn = openPassportPage(
        idType: 'passport',
        isBack: false,
        found: _quad(booklet),
        guide: g.frame,
        mrzReadAt: _t0,
        identified: true,
        now: _t0.add(const Duration(milliseconds: 300)),
      );
      expect(standIn, g.frame);
      final gate = DocumentFramingGate(expectedAspect: g.aspect);
      final box = boxOfRect(standIn!, aspect: g.aspect, confidence: 0.9);
      expect(_frame1s(gate, box).framing, DocumentFraming.ready);
      final corners = DocumentCornerGate()
        ..update(quadOfRect(standIn),
            frame: _frame, visible: _visible, guide: g.frame);
      expect(corners.blocksCapture, isFalse);
    });

    test('without a fresh MRZ, or for any other document, nothing stands in',
        () {
      Rect? standIn({
        String idType = 'passport',
        DateTime? readAt,
        bool identified = true,
        bool isBack = false,
      }) =>
          openPassportPage(
            idType: idType,
            isBack: isBack,
            found: _quad(booklet),
            guide: g.frame,
            mrzReadAt: readAt,
            identified: identified,
            now: _t0.add(const Duration(seconds: 1)),
          );
      expect(standIn(readAt: null), isNull);
      expect(standIn(readAt: _t0.subtract(const Duration(seconds: 2))), isNull);
      expect(standIn(readAt: _t0, identified: false), isNull);
      expect(standIn(readAt: _t0, idType: 'drivers-license'), isNull);
      expect(standIn(readAt: _t0, isBack: true), isNull);
    });

    test('a shape beside the guide (the facing page alone) never stands in',
        () {
      final facing = Rect.fromLTRB(
          page.left, page.top - page.height, page.right, page.top);
      expect(
        openPassportPage(
          idType: 'passport',
          isBack: false,
          found: _quad(facing),
          guide: g.frame,
          mrzReadAt: _t0,
          identified: true,
          now: _t0,
        ),
        isNull,
      );
    });
  });

  group('still caught', () {
    final card = _guide(kCardGuideAspect);

    test('a different document is the wrong document', () {
      final pvc = _docs.firstWhere((d) => d.idType == 'pvc').front;
      final identity =
          verifyDocumentIdentity(pvc, country: 'NG', idType: 'drivers-license');
      expect(identity.identified, isFalse);
      expect(identity.hint, DocumentHint.wrongDocument);
    });

    test('a passport page without its MRZ in view is not a passport', () {
      final identity = verifyDocumentIdentity(
        ['FEDERAL REPUBLIC OF NIGERIA', 'PASSPORT PASSEPORT', 'SURNAME OKAFOR'],
        country: 'NG',
        idType: 'passport',
      );
      expect(identity.identified, isFalse);
    });

    test('a NIN slip held where a card is expected is the wrong shape', () {
      final gate = DocumentFramingGate(expectedAspect: kCardGuideAspect);
      final slip = Rect.fromCenter(
          center: card.frame.center,
          width: card.frame.width * 0.95,
          height:
              card.frame.width * 0.95 * _frame.width / _frame.height / 2.07);
      expect(
          gate.update(_box(slip), at: _t0).framing, DocumentFraming.wrongShape);
    });

    test('a corner off the side of the picture is cut off', () {
      final cut = card.frame.shift(Offset(-card.frame.left + 0.02, 0));
      final corners = DocumentCornerGate()
        ..update(_quad(cut),
            frame: _frame, visible: _visible, guide: card.frame);
      expect(corners.blocksCapture, isTrue);
      expect(corners.hint, DocumentHint.fitCorners);
    });

    test('a corner off the bottom of the picture is cut off', () {
      final cut = Rect.fromLTRB(card.frame.left, 0.75, card.frame.right, 1.02);
      final corners = DocumentCornerGate()
        ..update(_quad(cut),
            frame: _frame, visible: _visible, guide: card.frame);
      expect(corners.blocksCapture, isTrue);
      expect(corners.hint, DocumentHint.fitCorners);
    });

    test('a turned slip found far bigger than its guide is held too close', () {
      // The slip runs off the picture and the table printed on it is found.
      final slip = _guide(kNinSlipGuideAspect);
      expect(slip.turned, isTrue);
      final table = Rect.fromCenter(
          center: slip.frame.center,
          width: slip.frame.width * 1.3,
          height: slip.frame.height * 1.3);
      final corners = DocumentCornerGate()
        ..update(_quad(table),
            frame: _frame, visible: _visible, guide: slip.frame);
      expect(corners.blocksCapture, isTrue);
      expect(corners.hint, DocumentHint.spaceAround);
    });

    test('a card held far too close runs past the picture and is caught', () {
      final big = _scaled(card.frame, 1.25);
      final corners = DocumentCornerGate()
        ..update(_quad(big), frame: _frame, visible: _visible);
      expect(corners.blocksCapture, isTrue);
    });
  });

  group('hint copy', () {
    test('the wrong-document hint reads as English for any label', () {
      expect(
        documentHintText(DocumentHint.wrongDocument,
            label: 'International Passport'),
        "That doesn't look like your International Passport",
      );
      expect(documentHintText(DocumentHint.wrongDocument, label: 'NIN (Slip)'),
          "That doesn't look like your NIN (Slip)");
    });

    test('no hint carries an em dash', () {
      for (final hint in DocumentHint.values) {
        expect(documentHintText(hint, label: 'ID card'),
            isNot(contains('\u2014')));
      }
    });
  });
}
