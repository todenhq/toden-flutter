import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/document_guide.dart';
import 'package:toden_flutter/src/config/immersive_layout.dart';

// The guide rect is shared by the on-screen overlay and the post-shutter crop.
// If it ever stops fitting the viewfinder, the user frames against a rectangle
// that runs off the preview — which is exactly the bug these pin.

const _card = 1.586;
const _passport = 1.42;

void main() {
  // The full-screen viewfinder on a 393 x 852 phone.
  const phone = Size(393, 852);

  group('documentGuideRect', () {
    test('is 88% of the width and centred, as React Native draws it', () {
      for (final aspect in [_card, _passport]) {
        final r = documentGuideRect(phone, aspect);
        expect(
            r.width, closeTo(phone.width * kDocumentGuideWidthFraction, 0.01));
        expect(r.height, closeTo(r.width / aspect, 0.01));
        expect(r.center.dx, closeTo(phone.width / 2, 0.01));
        // No upward nudge: React Native's guideRect centres it exactly.
        expect(r.center.dy, closeTo(phone.height / 2, 0.01));
      }
    });

    test('a passport is taller than a card, not narrower (no height cap)', () {
      final card = documentGuideRect(phone, _card);
      final passport = documentGuideRect(phone, _passport);
      expect(passport.width, closeTo(card.width, 0.01));
      expect(passport.height, greaterThan(card.height));
    });

    test('preserves the document aspect at any size', () {
      for (final aspect in [_card, _passport]) {
        for (final size in [
          const Size(320, 568),
          const Size(393, 852),
          const Size(440, 956),
        ]) {
          final r = documentGuideRect(size, aspect);
          expect(r.width / r.height, closeTo(aspect, 0.001),
              reason: 'aspect drifted at $size');
        }
      }
    });

    test('stays inside the viewfinder', () {
      for (final aspect in [_card, _passport]) {
        final r = documentGuideRect(phone, aspect);
        expect(r.top, greaterThan(0));
        expect(r.bottom, lessThan(phone.height));
        expect(r.left, greaterThan(0));
        expect(r.right, lessThan(phone.width));
      }
    });
  });

  group('documentGuideRect upright (a turned NIN slip)', () {
    // The same phone, with a 59pt status bar and a 34pt home indicator.
    final band = documentGuideBand(topInset: 59, bottomInset: 34);
    const upright = 1 / kNinSlipGuideAspect;

    test(
        'reserves what React Native reserves: the top bar + 16 above, the '
        'bottom row + 24 below', () {
      expect(band.topReserve, 59 + 68);
      expect(band.bottomReserve, 34 + 128);
    });

    test('fills the free band between the controls, centred in it', () {
      final r = documentGuideRect(phone, upright, band: band);
      expect(r.top, closeTo(band.topReserve, 0.01));
      expect(r.bottom, closeTo(phone.height - band.bottomReserve, 0.01));
      expect(r.center.dx, closeTo(phone.width / 2, 0.01));
      expect(r.width / r.height, closeTo(upright, 0.001));
    });

    test('is far bigger than the landscape slip it replaces', () {
      final turned = documentGuideRect(phone, upright, band: band);
      final flat = documentGuideRect(phone, kNinSlipGuideAspect);
      // About 272 x 563 against 346 x 167: the slip's long side gets the
      // screen's height.
      expect(turned.height, closeTo(563, 2));
      expect(turned.width, closeTo(272, 2));
      expect(turned.height / flat.width, greaterThan(1.2));
      expect(turned.width / flat.height, greaterThan(1.2));
    });

    test('stays clear of the top controls and the bottom bar', () {
      final r = documentGuideRect(phone, upright, band: band);
      expect(r.top - (immersiveTopBarTop(59) + kImmersiveTopBarHeight),
          greaterThanOrEqualTo(kImmersiveGuideGapBelowTopBar - 0.001));
      expect(phone.height - immersiveBottomRowReserve(34) - r.bottom,
          greaterThanOrEqualTo(kImmersiveGuideGapAboveControls - 0.001));
    });

    test('never wider than 88% of the width', () {
      const short = DocumentGuideBand(topReserve: 0, bottomReserve: 0);
      const view = Size(300, 2000);
      final r = documentGuideRect(view, upright, band: short);
      expect(r.width, closeTo(view.width * kDocumentGuideWidthFraction, 0.01));
      expect(r.width / r.height, closeTo(upright, 0.001));
      expect(r.center.dy, closeTo(view.height / 2, 0.01));
    });

    test('the band does not move a landscape guide', () {
      expect(documentGuideRect(phone, _card, band: band),
          documentGuideRect(phone, _card));
    });
  });
}
