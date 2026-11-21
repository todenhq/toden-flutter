import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/document_specimen.dart';
import 'package:toden_flutter/src/widgets/document_ghost.dart';
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
      'pvc': SpecimenKind.pvc,
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

  /// Where each barcode bar sits down the card, from the drawing itself.
  List<(double, double)> barcodeBars(String xml) => RegExp(
          r'<rect x="[\d.]+" y="([\d.]+)" width="[\d.]+" height="([\d.]+)" fill="#12141F"/>')
      .allMatches(xml)
      .map((bar) => (
            double.parse(bar[1]!),
            double.parse(bar[1]!) + double.parse(bar[2]!)
          ))
      .toList();

  test(
      "puts a PVC's two barcodes where the card has them: the top half of the back, the linear one first",
      () {
    final bars = barcodeBars(documentSpecimen(
        _with(kind: SpecimenKind.pvc, side: SpecimenSide.back)));
    final linear = bars.where((bar) => bar.$2 - bar.$1 == 84).toList();
    final stacked = bars.where((bar) => bar.$2 - bar.$1 < 84).toList();
    expect(linear.length, greaterThan(20));
    expect(stacked.length, greaterThan(100));
    final height = (1000 / _base.aspect).round();
    for (final bar in bars) {
      expect(bar.$2, lessThan(height * 0.55));
    }
    final linearFoot = linear.map((bar) => bar.$2).reduce((a, b) => a > b ? a : b);
    for (final bar in stacked) {
      expect(bar.$1, greaterThanOrEqualTo(linearFoot));
    }
  });

  test("draws no barcode on a PVC's front: both of the card's barcodes are on its back", () {
    expect(barcodeBars(documentSpecimen(_with(kind: SpecimenKind.pvc))), isEmpty);
  });

  test(
      "puts a Nigerian licence's barcodes in the top half of its back: a short linear one at the right, the block under it",
      () {
    final xml = documentSpecimen(
        _with(kind: SpecimenKind.driversLicenseNg, side: SpecimenSide.back));
    final bars = barcodeBars(xml);
    final linear = bars.where((bar) => bar.$2 - bar.$1 == 44).toList();
    final block = bars.where((bar) => bar.$2 - bar.$1 != 44).toList();
    expect(linear.length, greaterThan(10));
    expect(block.length, greaterThan(100));
    final height = (1000 / _base.aspect).round();
    for (final bar in bars) {
      expect(bar.$2, lessThan(height * 0.56));
    }
    for (final bar in block) {
      expect(bar.$1, greaterThanOrEqualTo(136 + 44));
    }
    // The linear barcode keeps to the right half, as on the card.
    final lefts = RegExp(
            r'<rect x="([\d.]+)" y="136" width="[\d.]+" height="44" fill="#12141F"/>')
        .allMatches(xml)
        .map((bar) => double.parse(bar[1]!));
    expect(lefts.reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(450));
  });

  test("draws a licence as Nigeria's own card only for Nigeria", () {
    expect(specimenKind('drivers-license', 'NG'), SpecimenKind.driversLicenseNg);
    expect(specimenKind('drivers-license', 'ng'), SpecimenKind.driversLicenseNg);
    expect(specimenKind('drivers-license', 'GH'), SpecimenKind.driversLicense);
    expect(specimenKind('drivers-license', null), SpecimenKind.driversLicense);
    expect(specimenKind('drivers-license'), SpecimenKind.driversLicense);
    // The country changes nothing for an ID that has no card of its own drawn.
    expect(specimenKind('passport', 'NG'), SpecimenKind.passport);
  });

  test(
      "keeps any other country's licence barcode as one block in the lower half of its back",
      () {
    final bars = barcodeBars(documentSpecimen(
        _with(kind: SpecimenKind.driversLicense, side: SpecimenSide.back)));
    final height = (1000 / _base.aspect).round();
    expect(bars.length, greaterThan(100));
    for (final bar in bars) {
      expect(bar.$1, greaterThanOrEqualTo(300));
    }
    expect(bars.map((bar) => bar.$2).reduce((a, b) => a > b ? a : b),
        greaterThan(height * 0.8));
  });

  test("leaves any other voter card's barcode along the foot of its back", () {
    final bars = barcodeBars(documentSpecimen(
        _with(kind: SpecimenKind.voterCard, side: SpecimenSide.back)));
    expect(bars.length, greaterThan(20));
    final height = (1000 / _base.aspect).round();
    for (final bar in bars) {
      expect(bar.$1, greaterThan(height / 2));
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

  group('the turn-over, in the frame', () {
    const back = DocumentSpecimenSubject(
      idType: 'pvc',
      title: "Voter's Card",
      country: 'Nigeria',
      side: SpecimenSide.back,
    );

    Future<void> pumpGhost(WidgetTester tester, {required bool holding}) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: DocumentGhost(
              key: const ValueKey(true),
              aspect: 1.586,
              accent: const Color(0xFF5645F5),
              subject: back,
              turnFrom: SpecimenSide.front,
              holding: holding,
            ),
          ),
        ));

    String drawn(WidgetTester tester) {
      final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
      return (picture.bytesLoader as SvgStringLoader).provideSvg(null);
    }

    testWidgets('shows the side just taken, then turns over where it stands',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpGhost(tester, holding: true);
      await tester.pump();
      final front = documentSpecimen(SpecimenInput(
        kind: specimenKind('pvc'),
        title: "Voter's Card",
        country: 'Nigeria',
        side: SpecimenSide.front,
        aspect: 1.586,
        accent: '#5645f5',
        sans: 'sans-serif',
        mono: 'monospace',
      ));
      // One card, the front, at the frame's own place and size.
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(drawn(tester), front);
      final placed = tester.getRect(find.byType(SvgPicture));

      await tester.pump(kGhostTurnDelay);
      await tester.pump(kGhostTurn);
      final state = tester.state<DocumentGhostState>(find.byType(DocumentGhost));
      expect(state.turned, isTrue);
      expect(drawn(tester), isNot(front));
      expect(tester.getRect(find.byType(SvgPicture)), placed);
    });

    testWidgets('stays while the turn-over holds, and its time starts after',
        (tester) async {
      await pumpGhost(tester, holding: true);
      await tester.pump(kDocumentGhostDuration + const Duration(seconds: 1));
      final state = tester.state<DocumentGhostState>(find.byType(DocumentGhost));
      expect(state.leaving, isFalse, reason: 'held through the turn-over');

      // The back's scan starts: it stays for its own time, then fades.
      await pumpGhost(tester, holding: false);
      await tester.pump(kDocumentGhostDuration - const Duration(seconds: 1));
      expect(state.leaving, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(state.leaving, isTrue);
      await tester.pump(kDocumentGhostFade);
    });

    testWidgets('with less motion it is the back at once', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: DocumentGhost(
              aspect: 1.586,
              accent: Color(0xFF5645F5),
              subject: back,
              turnFrom: SpecimenSide.front,
              holding: true,
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(drawn(tester), contains('svg'));
      final front = specimenSvg(back, SpecimenSide.front, 1.586, const Color(0xFF5645F5));
      expect(drawn(tester), isNot(front));
    });
  });
}
