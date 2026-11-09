import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/document_crop_geometry.dart';
import 'package:toden_flutter/src/config/document_guide.dart';
import 'package:toden_flutter/src/config/document_turn.dart';

// ─── The photo cropper's geometry ────────────────────────────────────────────
//
// Mirrors the React Native SDK's __tests__/documentCropGeometry.test.ts.

// The photo cropper on a phone held upright (widgets/document_cropper.dart):
// its stage is the screen less the top bar, the help line and the bottom bar.
const _stage = Size(393, 640);

void main() {
  group('the crop box for a NIN slip on a phone', () {
    final guide = documentCropGuide(
        kNinSlipGuideAspect, _stage.width / _stage.height);

    test('stands upright, at the inverse of the slip', () {
      expect(guide.turned, isTrue);
      expect(guide.aspect, closeTo(1 / kNinSlipGuideAspect, 1e-9));
    });

    test('starts upright on a tall photo: 85% wide, capped at 90% high', () {
      final img = containRect(const Size(3024, 4032), _stage);
      final box = initialCropRect(img, guide.aspect);
      expect(box.height, greaterThan(box.width));
      expect(box.width / box.height, closeTo(1 / kNinSlipGuideAspect, 1e-9));
      expect(box.height, closeTo(img.height * 0.9, 1e-9));
      expect(box.left, greaterThanOrEqualTo(img.left));
      expect(box.right, lessThanOrEqualTo(img.right));
    });

    test('a card keeps a landscape box', () {
      final card =
          documentCropGuide(kCardGuideAspect, _stage.width / _stage.height);
      final box = initialCropRect(
          containRect(const Size(3024, 4032), _stage), card.aspect);
      expect(box.width / box.height, closeTo(kCardGuideAspect, 1e-9));
    });
  });

  group('Rotate', () {
    test("swaps the photo's sides on each odd turn", () {
      const s = Size(4032, 3024);
      expect(turnedSize(s, 0), s);
      expect(turnedSize(s, 1), const Size(3024, 4032));
      expect(turnedSize(s, 2), s);
      expect(turnedSize(s, 3), const Size(3024, 4032));
    });

    test('a sideways scan of a slip, turned once, fills more of the upright box',
        () {
      const aspect = 1 / kNinSlipGuideAspect;
      final sideways =
          initialCropRect(containRect(const Size(2070, 1000), _stage), aspect);
      final t = turnedSize(const Size(2070, 1000), 1);
      final img = containRect(t, _stage);
      final stood = initialCropRect(img, aspect);
      expect(stood.height, greaterThan(sideways.height * 2));
      // Refitted at the same aspect, inside the turned photo.
      expect(stood.width / stood.height, closeTo(aspect, 1e-9));
      final kept = clampCropRect(stood, img, aspect);
      expect(kept.left, closeTo(stood.left, 1e-9));
      expect(kept.top, closeTo(stood.top, 1e-9));
      expect(kept.width, closeTo(stood.width, 1e-9));
      expect(kept.height, closeTo(stood.height, 1e-9));
    });
  });

  group('the photo on the stage', () {
    test('sits at least 16 inside every edge, so a handle never meets the screen edge',
        () {
      for (final s in const [
        Size(3024, 4032),
        Size(4032, 3024),
        Size(2070, 1000),
        Size(1000, 4000),
      ]) {
        final img = insetContainRect(s, _stage);
        expect(img.left, greaterThanOrEqualTo(kCropStageInset - 1e-9));
        expect(img.top, greaterThanOrEqualTo(kCropStageInset - 1e-9));
        expect(_stage.width - img.right,
            greaterThanOrEqualTo(kCropStageInset - 1e-9));
        expect(_stage.height - img.bottom,
            greaterThanOrEqualTo(kCropStageInset - 1e-9));
        expect(img.width / img.height, closeTo(s.width / s.height, 1e-9));
      }
    });

    test('touches the inset on its limiting side, centred on the other', () {
      final img = insetContainRect(const Size(4032, 3024), _stage);
      expect(kCropStageInset, 16);
      expect(img.left, closeTo(kCropStageInset, 1e-9));
      expect(img.width, closeTo(_stage.width - 2 * kCropStageInset, 1e-9));
      expect(img.center.dy, closeTo(_stage.height / 2, 1e-9));
    });
  });

  group('the Rotate animation', () {
    ({Rect from, Rect to, double s, double shownW, double shownH}) fits(
        Size natural) {
      final from = insetContainRect(natural, _stage);
      final to = insetContainRect(turnedSize(natural, 1), _stage);
      final s = quarterTurnScale(from, to);
      // The turned view's on-screen box: its sides swap, then scale.
      return (
        from: from,
        to: to,
        s: s,
        shownW: from.height * s,
        shownH: from.width * s,
      );
    }

    test('shrinks a portrait photo turning landscape to fit the stage, inside the inset',
        () {
      final f = fits(const Size(3024, 4032));
      expect(f.s, lessThan(1));
      expect(f.shownW, closeTo(f.to.width, 1e-9));
      expect(f.shownH, closeTo(f.to.height, 1e-9));
      expect(f.shownW,
          lessThanOrEqualTo(_stage.width - 2 * kCropStageInset + 1e-9));
      expect(f.shownH,
          lessThanOrEqualTo(_stage.height - 2 * kCropStageInset + 1e-9));
      // Turned about its own centre, which is the stage's centre, as is the
      // target's.
      expect(f.from.center.dx, closeTo(f.to.center.dx, 1e-9));
      expect(f.from.center.dy, closeTo(f.to.center.dy, 1e-9));
      expect(f.from.center.dx, closeTo(_stage.width / 2, 1e-9));
      expect(f.from.center.dy, closeTo(_stage.height / 2, 1e-9));
    });

    test('grows a landscape photo turning portrait, and still fits', () {
      final f = fits(const Size(4032, 3024));
      expect(f.s, greaterThan(1));
      expect(f.shownW, closeTo(f.to.width, 1e-9));
      expect(f.shownH, closeTo(f.to.height, 1e-9));
      expect(f.shownH,
          lessThanOrEqualTo(_stage.height - 2 * kCropStageInset + 1e-9));
    });
  });
}
