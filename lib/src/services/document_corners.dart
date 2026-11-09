import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

// ─── Document corners ─────────────────────────────────────────────────────────
//
// A document may only be photographed when all four of its corners are in the
// part of the camera frame the user can SEE, with a little space (the bleed)
// past each one. People capture a passport with its bottom edge cut, which is
// where the machine-readable zone is, and an MRZ missing a line cannot be read.
//
// One rule on all three SDKs, as data in test/document_corners_vectors.json:
// change it there and in the web and React Native mirrors together.
// Coordinates are normalised (0..1) in the UPRIGHT frame, x right and y down.

/// Space kept past each corner, as a share of the frame width on x and of the
/// frame height on y.
const double kCornerBleed = 0.04;

/// A corner this close to the visible edge counts as cut off (detectors clamp
/// a document running out of shot onto the edge).
const double kCornerEdgeEpsilon = 0.005;

/// Below this share of the frame the shape is not a document held to read.
const double kCornerMinAreaFraction = 0.05;

/// Why the corners do not allow a capture.
enum DocumentCornersProblem {
  /// Nothing usable: none, not a convex four-sided shape, or too small.
  noDocument,

  /// A corner is outside the visible frame, or on its edge.
  cornerCutOff,

  /// Every corner is visible, but one sits inside the bleed.
  tooClose,
}

/// The four corners of a detected document.
class DocumentQuad {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  const DocumentQuad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// In order: top-left, top-right, bottom-right, bottom-left.
  List<Offset> get corners => [topLeft, topRight, bottomRight, bottomLeft];

  /// From eight numbers (x, y per corner, [corners] order), else null.
  static DocumentQuad? fromList(Object? raw) {
    if (raw is! List || raw.length != 8) return null;
    final v = <double>[];
    for (final e in raw) {
      if (e is! num || !e.isFinite) return null;
      v.add(e.toDouble());
    }
    return DocumentQuad(
      topLeft: Offset(v[0], v[1]),
      topRight: Offset(v[2], v[3]),
      bottomRight: Offset(v[4], v[5]),
      bottomLeft: Offset(v[6], v[7]),
    );
  }

  /// Maps into a frame in which this quad's frame occupies [region].
  DocumentQuad within(Rect region) {
    Offset map(Offset p) => Offset(
          region.left + p.dx * region.width,
          region.top + p.dy * region.height,
        );
    return DocumentQuad(
      topLeft: map(topLeft),
      topRight: map(topRight),
      bottomRight: map(bottomRight),
      bottomLeft: map(bottomLeft),
    );
  }
}

/// How much larger than the drawn guide the found document may be before it
/// counts as held too close. A document much bigger than the guide is running
/// off the picture, and what the detector found is a box printed inside it (a
/// NIN slip's bordered table), whose four corners are all in view while the
/// slip's own are cut. Mirrors GUIDE_OVERSIZE in the React Native SDK.
const double kGuideOversize = 1.15;

/// True when [quad] is more than [factor] times the [guide]'s width or
/// height. [guide] is in the quad's normalised frame space.
bool exceedsGuide(DocumentQuad quad, Rect guide, {double factor = kGuideOversize}) {
  final xs = quad.corners.map((c) => c.dx);
  final ys = quad.corners.map((c) => c.dy);
  final w = xs.reduce(math.max) - xs.reduce(math.min);
  final h = ys.reduce(math.max) - ys.reduce(math.min);
  return w > guide.width * factor || h > guide.height * factor;
}

/// [guide], drawn in a preview of [view], in the normalised frame space of
/// [visible] (see [visibleFrameRegion]). Null when the view is empty.
Rect? guideInFrame(Rect guide, Size view, Rect visible) {
  if (view.isEmpty) return null;
  return Rect.fromLTRB(
    visible.left + guide.left / view.width * visible.width,
    visible.top + guide.top / view.height * visible.height,
    visible.left + guide.right / view.width * visible.width,
    visible.top + guide.bottom / view.height * visible.height,
  );
}

/// A crop in whole pixels.
class CropRect {
  final int x;
  final int y;
  final int width;
  final int height;

  const CropRect(this.x, this.y, this.width, this.height);

  @override
  bool operator ==(Object other) => other is CropRect &&
      (other.x, other.y, other.width, other.height) == (x, y, width, height);

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'CropRect($x, $y, ${width}x$height)';
}

/// The part of an upright camera [frame] a cover-fitted preview of [view]
/// shows, normalised to the frame. The whole frame when either size is empty.
Rect visibleFrameRegion(Size frame, Size view) {
  if (frame.isEmpty || view.isEmpty) return const Rect.fromLTRB(0, 0, 1, 1);
  final frameAspect = frame.width / frame.height;
  final viewAspect = view.width / view.height;
  if (frameAspect > viewAspect) {
    final w = viewAspect / frameAspect; // sides are cropped
    return Rect.fromLTWH((1 - w) / 2, 0, w, 1);
  }
  final h = frameAspect / viewAspect; // top and bottom are cropped
  return Rect.fromLTWH(0, (1 - h) / 2, 1, h);
}

/// Null when the corners allow a capture, else why not. [visible]: see
/// [visibleFrameRegion].
DocumentCornersProblem? cornersProblem(
  DocumentQuad? quad,
  Rect visible, {
  double bleed = kCornerBleed,
}) {
  if (quad == null || !_isUsableShape(quad)) {
    return DocumentCornersProblem.noDocument;
  }
  const eps = kCornerEdgeEpsilon;
  for (final c in quad.corners) {
    if (c.dx < visible.left + eps ||
        c.dx > visible.right - eps ||
        c.dy < visible.top + eps ||
        c.dy > visible.bottom - eps) {
      return DocumentCornersProblem.cornerCutOff;
    }
  }
  for (final c in quad.corners) {
    if (c.dx < visible.left + bleed ||
        c.dx > visible.right - bleed ||
        c.dy < visible.top + bleed ||
        c.dy > visible.bottom - bleed) {
      return DocumentCornersProblem.tooClose;
    }
  }
  return null;
}

/// The quad's bounding box plus the bleed, clamped to a [frame] of that pixel
/// size; origin floored, far edge ceiled, so no bleed is lost to rounding.
CropRect bleedCropRect(
  DocumentQuad quad,
  Size frame, {
  double bleed = kCornerBleed,
}) {
  final xs = quad.corners.map((c) => c.dx);
  final ys = quad.corners.map((c) => c.dy);
  final w = frame.width;
  final h = frame.height;
  // Scaled term by term, then snapped: (0.15 - 0.04) * 1000 floors to 109.
  final left = _floor(xs.reduce(math.min) * w - bleed * w);
  final top = _floor(ys.reduce(math.min) * h - bleed * h);
  final right = _ceil(xs.reduce(math.max) * w + bleed * w);
  final bottom = _ceil(ys.reduce(math.max) * h + bleed * h);
  final x = left.clamp(0, w.floor());
  final y = top.clamp(0, h.floor());
  final x2 = right.clamp(x, w.floor());
  final y2 = bottom.clamp(y, h.floor());
  return CropRect(x, y, x2 - x, y2 - y);
}

int _floor(double v) => (v + 1e-6).floor();
int _ceil(double v) => (v - 1e-6).ceil();

/// Convex, not self-intersecting, and big enough to be a document.
bool _isUsableShape(DocumentQuad quad) {
  final c = quad.corners;
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final a = c[i];
    final b = c[(i + 1) % 4];
    final d = c[(i + 2) % 4];
    final cross = (b.dx - a.dx) * (d.dy - b.dy) - (b.dy - a.dy) * (d.dx - b.dx);
    if (!cross.isFinite || cross == 0) return false;
    final s = cross > 0 ? 1 : -1;
    if (sign == 0) {
      sign = s;
    } else if (s != sign) {
      return false;
    }
  }
  var area = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = c[i];
    final b = c[(i + 1) % 4];
    area += a.dx * b.dy - b.dx * a.dy;
  }
  return area.abs() / 2 >= kCornerMinAreaFraction;
}
