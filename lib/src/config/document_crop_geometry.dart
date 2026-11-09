import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

// ─── The photo cropper's geometry ─────────────────────────────────────────────
//
// The photo cropper's maths (widgets/document_cropper.dart), kept pure so the
// box's shape, its first placement, the Rotate refit and Rotate's on-screen
// turn are unit-tested.
//
// Mirrors the React Native SDK's lib/documentCropGeometry.ts: change both
// together.

/// Clear space between the photo and the edge of its stage, so a crop handle at
/// the photo's edge never touches the screen's (the scan screen's side margin).
const double kCropStageInset = 16;

/// The photo's rect inside a [stage], shown "contain".
Rect containRect(Size natural, Size stage) {
  final natAR = natural.width / natural.height;
  final conAR = stage.width / stage.height;
  final double rw, rh;
  if (natAR > conAR) {
    rw = stage.width;
    rh = stage.width / natAR;
  } else {
    rh = stage.height;
    rw = stage.height * natAR;
  }
  return Rect.fromLTWH(
      (stage.width - rw) / 2, (stage.height - rh) / 2, rw, rh);
}

/// The photo's rect inside a [stage], shown "contain" within [inset] on every
/// side.
Rect insetContainRect(Size natural, Size stage,
    {double inset = kCropStageInset}) {
  final r = containRect(
    natural,
    Size(math.max(1, stage.width - 2 * inset),
        math.max(1, stage.height - 2 * inset)),
  );
  return r.shift(Offset(inset, inset));
}

/// The first box: 85% of the photo's width, centred, at [ar]; capped at 90% of
/// its height.
Rect initialCropRect(Rect img, double ar) {
  var w = img.width * 0.85;
  var h = w / ar;
  if (h > img.height * 0.9) {
    h = img.height * 0.9;
    w = h * ar;
  }
  return Rect.fromLTWH(
      img.left + (img.width - w) / 2, img.top + (img.height - h) / 2, w, h);
}

/// Keeps the box inside the photo [b], at [ar], no narrower than 60.
Rect clampCropRect(Rect crop, Rect b, double ar) {
  var w = math.min(math.max(crop.width, 60.0), b.width);
  var h = w / ar;
  if (h > b.height) {
    h = b.height;
    w = h * ar;
    if (w > b.width) {
      w = b.width;
      h = w / ar;
    }
  }
  final maxLeft = math.max(b.left, b.left + b.width - w);
  final maxTop = math.max(b.top, b.top + b.height - h);
  return Rect.fromLTWH(
    math.min(math.max(crop.left, b.left), maxLeft),
    math.min(math.max(crop.top, b.top), maxTop),
    w,
    h,
  );
}

/// A photo's size after [turns] clockwise quarter turns (Rotate).
Size turnedSize(Size size, int turns) =>
    turns.isEven ? size : Size(size.height, size.width);

/// Rotate's animation: the scale that takes the photo as shown ([from]), turned
/// a quarter about its centre, onto the rect the turned photo will be shown at
/// ([to]). Both are centred on the same stage, so a scale is all it needs: a
/// portrait photo turning landscape shrinks into the stage as it turns, rather
/// than overflowing and snapping back.
double quarterTurnScale(Rect from, Rect to) =>
    // Turned, the photo's width on screen is its height as shown.
    from.height > 0 ? to.width / from.height : 1;
