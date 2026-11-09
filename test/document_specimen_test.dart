import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/document_specimen.dart';
import 'package:toden_flutter/src/widgets/document_ghost.dart';
import 'package:toden_flutter/src/widgets/turn_over_prompt.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' as vg;

const _base = SpecimenInput(
  kind: SpecimenKind.nationalId,
  title: 'National ID',
  country: 'Ghana',
  side: SpecimenSide.front,
  aspect: 1.586,
  accent: '#5645F5',
  sans: 'sans-serif',
  mono: 'monospace',
);

SpecimenInput _with({
  SpecimenKind? kind,
  String? title,
  String? country,
  SpecimenSide? side,
  double? aspect,
}) =>
    SpecimenInput(
      kind: kind ?? _base.kind,
      title: title ?? _base.title,
      country: country ?? _base.country,
      side: side ?? _base.side,
      aspect: aspect ?? _base.aspect,
      accent: _base.accent,
      sans: _base.sans,
      mono: _base.mono,
    );

/// Every piece of text the phone will print, read by the parser that draws it.
List<String> printedText(String xml) => vg
    .parse(
      xml,
      enableClippingOptimizer: false,
      enableMaskingOptimizer: false,
      enableOverdrawOptimizer: false,
    )
    .text
    .map((config) => config.text)
    .toList();

void main() {
  group('specimenKind', () {
    const kinds = {
      'passport': SpecimenKind.passport,
      'drivers-license': SpecimenKind.driversLicense,
      'national-id': SpecimenKind.nationalId,
      'nin': SpecimenKind.nationalId,
      'nin-slip': SpecimenKind.ninSlip,
      'ghana-card': SpecimenKind.nationalId,
      'cni': SpecimenKind.nationalId,
      'pvc': SpecimenKind.voterCard,
      'voters': SpecimenKind.voterCard,
      'residence-card': SpecimenKind.residencePermit,
    };
    kinds.forEach((idType, kind) {
      test('$idType draws as ${kind.name}', () {
        expect(specimenKind(idType), kind);
      });
    });

    test('an ID it does not know is a generic document, never a passport', () {
      expect(specimenKind('ssnit'), SpecimenKind.generic);
      expect(specimenKind(null), SpecimenKind.generic);
    });
  });

  group('documentSpecimen', () {
    test('writes the name of the document and its country on it', () {
      final text = printedText(documentSpecimen(_with(
        kind: SpecimenKind.driversLicense,
        title: "Driver's Licence",
      ))).join(' ');
      expect(text, contains('GHANA'));
      expect(text, contains("DRIVER'S LICENCE"));
    });

    test('draws a NIN slip with the NIN and the same on both sides', () {
      final front = _with(
          kind: SpecimenKind.ninSlip,
          title: 'NIN Slip',
          country: 'Nigeria',
          aspect: 2.07);
      final back = _with(
          kind: SpecimenKind.ninSlip,
          title: 'NIN Slip',
          country: 'Nigeria',
          aspect: 2.07,
          side: SpecimenSide.back);
      final text = printedText(documentSpecimen(front)).join(' ');
      expect(text, contains('NIN SLIP'));
      expect(text, contains('00000000000'));
      expect(documentSpecimen(back), documentSpecimen(front));
    });

    test('draws a slip in an upright guide turned, top facing right', () {
      // On a phone held upright the slip's guide stands upright
      // (config/document_turn.dart); the drawing is the landscape slip turned
      // a quarter clockwise, the direction the text reader tries first.
      final upright = _with(
          kind: SpecimenKind.ninSlip,
          title: 'NIN Slip',
          country: 'Nigeria',
          aspect: 1 / 2.07);
      final xml = documentSpecimen(upright);
      final parsed = vg.parse(xml,
          enableClippingOptimizer: false,
          enableMaskingOptimizer: false,
          enableOverdrawOptimizer: false);
      // Fills the upright guide exactly: 483 wide, 1000 tall.
      expect(parsed.width, specimenHeight(2.07).toDouble());
      expect(parsed.height, 1000);
      // Same printing as the landscape slip.
      expect(printedText(xml).join(' '), contains('00000000000'));
      // The landscape slip's left crest (top-left corner, centre 90, 92, radius
      // 38) lands top-right: turned clockwise, the slip's top faces right.
      final crest = parsed.paths.map((p) => p.bounds()).where((b) =>
          (b.width - 76).abs() < 8 && (b.height - 76).abs() < 8).toList();
      expect(
          crest.any((b) =>
              (b.left + b.width / 2 - (483 - 92)).abs() < 4 &&
              (b.top + b.height / 2 - 90).abs() < 4),
          isTrue);
    });

    test('keeps the same page whichever side a passport is asked for', () {
      final front = _with(kind: SpecimenKind.passport, aspect: 1.42);
      final back = _with(
          kind: SpecimenKind.passport, aspect: 1.42, side: SpecimenSide.back);
      expect(documentSpecimen(back), documentSpecimen(front));
    });

    test('prints a title as written, without letting it break the drawing', () {
      final text = printedText(documentSpecimen(_with(
        title: 'Tax & Levy <ID>',
        country: "Cote d'Ivoire",
      ))).join(' ');
      expect(text, contains('TAX & LEVY <ID>'));
      expect(text, contains("COTE D'IVOIRE"));
    });

    test('drops a bracketed abbreviation rather than shrink a long title', () {
      final text = printedText(documentSpecimen(_with(
        kind: SpecimenKind.voterCard,
        title: "Permanent Voter's Card With A Very Long Official Name (PVC)",
      ))).join(' ');
      expect(text, isNot(contains('(PVC)')));
    });

    for (final kind in SpecimenKind.values) {
      for (final side in SpecimenSide.values) {
        test('${kind.name} ${side.name} parses, with no entity printed', () {
          final text = printedText(documentSpecimen(SpecimenInput(
            kind: kind,
            title: 'Passport',
            country: null,
            side: side,
            aspect: kind == SpecimenKind.passport ? 1.42 : 1.586,
            accent: _base.accent,
            sans: _base.sans,
            mono: _base.mono,
          )));
          expect(text, isNotEmpty);
          for (final piece in text) {
            expect(piece, isNot(matches(RegExp(r'&[a-z#0-9]+;'))));
          }
        });
      }
    }

    test('keeps every machine-readable character inside a passport', () {
      final xml = documentSpecimen(
          _with(kind: SpecimenKind.passport, aspect: 1.42));
      final cells = RegExp(
              r'<text x="([\d.]+)"[^>]*text-anchor="middle"[^>]*>([A-Z0-9])</text>')
          .allMatches(xml)
          .toList();
      expect(cells.length, greaterThan(20));
      for (final cell in cells) {
        expect(double.parse(cell[1]!), inExclusiveRange(44, 956));
      }
    });

    test('marks a passport with the e-passport symbol', () {
      final xml = documentSpecimen(
          _with(kind: SpecimenKind.passport, aspect: 1.42));
      expect(xml, contains('<rect x="468.0" y="46.0" width="84.0" height="56"'));
      expect(xml, contains('<circle cx="510" cy="74" r="14.0"'));
    });
  });

  test('every back differs from its front', () {
    // A passport page and a NIN slip are one-sided: both sides draw the same.
    const oneSided = {SpecimenKind.passport, SpecimenKind.ninSlip};
    for (final kind in SpecimenKind.values.where((k) => !oneSided.contains(k))) {
      expect(documentSpecimen(_with(kind: kind, side: SpecimenSide.back)),
          isNot(documentSpecimen(_with(kind: kind))));
    }
  });

  group('specimenTitle', () {
    test('uses the label the step already has', () {
      expect(specimenTitle('nin', 'National ID Number'), 'National ID Number');
    });

    test('never writes the word Document when the ID has a name', () {
      expect(specimenTitle('drivers-license', 'Document'), 'Drivers License');
    });

    test('calls a passport a passport', () {
      expect(specimenTitle('passport', 'International Passport'), 'Passport');
    });
  });

  testWidgets('the turn-over prompt shows the document and moves on',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TurnOverPrompt(
          aspect: 1.586,
          accent: const Color(0xFF5645F5),
          subject: const DocumentSpecimenSubject(
            idType: 'pvc',
            title: "Voter's Card",
            country: 'Nigeria',
            side: SpecimenSide.back,
          ),
          onDone: () => done = true,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Now turn it over'), findsOneWidget);
    expect(find.text("Hold the back of your Voter's Card inside the frame."),
        findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);

    await tester.tap(find.text("I've turned it over"));
    await tester.pump(const Duration(seconds: 2));
    expect(done, isTrue);
  });
}
