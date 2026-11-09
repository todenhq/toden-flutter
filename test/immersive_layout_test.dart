import 'dart:ui' show Color, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/document_guide.dart';
import 'package:toden_flutter/src/config/document_turn.dart';
import 'package:toden_flutter/src/config/immersive_layout.dart';
import 'package:toden_flutter/src/services/document_framing_gate.dart';
import 'package:toden_flutter/src/widgets/immersive_glass.dart';

// The full-screen document camera: top bar, instruction, guide, bottom row.
// The guide must keep clear of both, with the stated gaps, on every phone.
// Mirrors the React Native SDK's __tests__/immersiveLayout.test.ts.

class _Phone {
  final String name;
  final double width, height, top, bottom;
  const _Phone(this.name, this.width, this.height, this.top, this.bottom);
  Size get size => Size(width, height);
}

const _phones = [
  _Phone('iPhone 15', 393, 852, 56, 34),
  _Phone('iPhone 16 Pro Max', 440, 956, 56, 34),
  _Phone('iPhone SE', 375, 667, 56, 0),
  _Phone('small Android', 360, 740, 32, 16),
];

/// The room left of a turned guide, where its hint is drawn turned
/// (document_viewfinder kTurnedHintQuarterTurns): before the turn, as deep as
/// the space beside the guide.
double _turnedHintDepth(Rect guide) => guide.left < 0 ? 0 : guide.left;

void main() {
  group('the layout rhythm', () {
    test(
        'puts the top bar 8 under the safe inset and the instruction 12 '
        'under the bar', () {
      expect(immersiveTopBarTop(56), 64);
      expect(immersiveHintTop(56), 64 + kImmersiveTopBarHeight + 12);
      expect(kImmersiveHintMaxHeight,
          2 * kImmersiveHintLineHeight + 2 * kImmersiveHintPaddingV);
    });

    test('sits the bottom row 16 above the safe inset, captions included', () {
      // Shutter 80; the 52 side buttons centred on it with a 6 gap and a 16
      // caption below.
      expect(kImmersiveBottomRowHeight, 88);
      expect(immersiveBottomRowReserve(34), 34 + 16 + 88);
    });
  });

  for (final phone in _phones) {
    group('the guide on ${phone.name}', () {
      final band =
          documentGuideBand(topInset: phone.top, bottomInset: phone.bottom);
      final upright = screenGuideAspect(kNinSlipGuideAspect, true);

      test(
          'stands a turned NIN slip 16 below the top bar and 24 above the '
          'bottom row, centred between', () {
        final g = documentGuideRect(phone.size, upright, band: band);
        final above =
            g.top - (immersiveTopBarTop(phone.top) + kImmersiveTopBarHeight);
        final below =
            phone.height - immersiveBottomRowReserve(phone.bottom) - g.bottom;
        expect(
            above, greaterThanOrEqualTo(kImmersiveGuideGapBelowTopBar - 0.001));
        expect(below,
            greaterThanOrEqualTo(kImmersiveGuideGapAboveControls - 0.001));
        expect(above - kImmersiveGuideGapBelowTopBar,
            closeTo(below - kImmersiveGuideGapAboveControls, 1e-5));
        expect(g.height / g.width, closeTo(kNinSlipGuideAspect, 1e-5));
      });

      test('leaves room beside a turned slip for its one-line hint', () {
        final g = documentGuideRect(phone.size, upright, band: band);
        expect(
            _turnedHintDepth(g),
            greaterThanOrEqualTo(
                kImmersiveHintLineHeight + 2 * kImmersiveHintPaddingV));
      });

      for (final (name, aspect) in [
        ('card', kCardGuideAspect),
        ('passport', kPassportGuideAspect),
      ]) {
        test(
            'keeps a $name guide 16 below a two-line instruction and 24 above '
            'the bottom row', () {
          final g = documentGuideRect(phone.size, aspect);
          expect(g.top - immersiveHintBottom(phone.top),
              greaterThanOrEqualTo(kImmersiveGuideGapBelowHint));
          expect(
              phone.height - immersiveBottomRowReserve(phone.bottom) - g.bottom,
              greaterThanOrEqualTo(kImmersiveGuideGapAboveControls));
        });
      }
    });
  }

  group('a landscape guide on a 393 x 852 phone', () {
    // React Native's guideRect: a card or passport guide is centred in the
    // viewfinder with no upward nudge and no height cap, and sits inside the
    // free band between the top bar and the bottom row.
    const phone = Size(393, 852);
    final band = documentGuideBand(topInset: 59, bottomInset: 34);
    for (final (name, aspect) in [
      ('card', kCardGuideAspect),
      ('passport', kPassportGuideAspect),
    ]) {
      test('centres a $name guide exactly, inside the band', () {
        final g = documentGuideRect(phone, aspect, band: band);
        expect(g.center.dy, closeTo(phone.height / 2, 1e-9));
        expect(g.center.dx, closeTo(phone.width / 2, 1e-9));
        expect(
            g.width, closeTo(phone.width * kDocumentGuideWidthFraction, 1e-9));
        expect(g.top, greaterThanOrEqualTo(band.topReserve));
        expect(g.bottom, lessThanOrEqualTo(phone.height - band.bottomReserve));
        // The band is passed everywhere; for a landscape guide it changes
        // nothing, so the gate and the crop read what the overlay draws.
        expect(g, documentGuideRect(phone, aspect));
      });
    }
  });

  group('immersiveHintTone', () {
    ImmersiveHintTone tone({
      DocumentHint hint = DocumentHint.searching,
      DocumentFraming framing = DocumentFraming.none,
      bool? hintIsAction = false,
      bool blocked = false,
    }) =>
        immersiveHintTone(
          hint: hint,
          framing: framing,
          hintIsAction: hintIsAction,
          blocked: blocked,
        );

    test('is neutral while searching', () {
      expect(tone(), ImmersiveHintTone.neutral);
    });

    test('is an action when the gate asks for one or holds the shutter', () {
      expect(
          tone(
              hint: DocumentHint.moveCloser,
              framing: DocumentFraming.adjust,
              hintIsAction: true),
          ImmersiveHintTone.action);
      expect(tone(blocked: true, framing: DocumentFraming.ready),
          ImmersiveHintTone.action);
    });

    test('warns for too dark and the wrong document', () {
      expect(tone(hint: DocumentHint.moreLight, hintIsAction: true),
          ImmersiveHintTone.warning);
      expect(tone(hint: DocumentHint.wrongDocument, hintIsAction: true),
          ImmersiveHintTone.warning);
      expect(
          tone(framing: DocumentFraming.wrongShape), ImmersiveHintTone.warning);
    });

    test('is ready while holding', () {
      expect(
          tone(hint: DocumentHint.holdStill, framing: DocumentFraming.holding),
          ImmersiveHintTone.ready);
      expect(tone(hint: DocumentHint.captured, framing: DocumentFraming.ready),
          ImmersiveHintTone.ready);
    });

    test('reads the gate\'s own action flag when none is given', () {
      expect(tone(hint: DocumentHint.moveBack, hintIsAction: null),
          ImmersiveHintTone.action);
    });
  });

  group('primaryOnDark', () {
    test('lifts the brand colour towards white', () {
      expect(primaryOnDark(const Color(0xFF5645F5)),
          isNot(const Color(0xFF5645F5)));
      expect(primaryOnDark(const Color(0xFF000000)).toARGB32(), 0xFF595959);
    });
  });
}
