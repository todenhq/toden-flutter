import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'document_corners.dart';
import 'document_detection.dart';
import 'document_identity.dart' show documentCarriesMrz;

// ─── An open passport ─────────────────────────────────────────────────────────
//
// A passport is photographed open: the data page fills the guide and the
// facing page sits above it. Apple's document finder sees one sheet of paper,
// the whole open booklet, about 0.7 wide to 1 tall. That is not the data
// page's 1.42, so the framing gate called it the wrong document, and it runs
// far past the guide, so the corner gate would have said "move back".
//
// The data page proves itself where the shape cannot: a machine-readable zone
// read this moment, check digits and all, which only a passport's data page
// carries. With that, a found shape that covers the guide and runs past it is
// the booklet around the page in the guide, and the guide stands in for the
// page: its corners are in view by construction, and the photo is cropped to
// it. Anything else is judged as before.

/// Share of the guide the found shape must cover to be the booklet around it.
const double kOpenBookletGuideCover = 0.75;

/// How recently a valid MRZ must have been read to vouch for the page.
const Duration kOpenPassportMrzWindow = Duration(milliseconds: 1500);

/// The guide, when [found] is an open passport booklet around a data page
/// framed in it; else null. [guide] is in the frame's normalised space (see
/// [guideInFrame]); [mrzReadAt] is when a check-digit-valid MRZ was last read
/// on this side, and [identified] whether the text check accepted the frame.
Rect? openPassportPage({
  required String idType,
  required bool isBack,
  required DocumentQuad? found,
  required Rect? guide,
  required DateTime? mrzReadAt,
  required bool identified,
  required DateTime now,
}) {
  if (!documentCarriesMrz(idType) || isBack || !identified) return null;
  if (found == null || guide == null || guide.isEmpty) return null;
  if (mrzReadAt == null || now.difference(mrzReadAt) > kOpenPassportMrzWindow) {
    return null;
  }
  // Bigger than the guide, or it is the page itself and needs no stand-in.
  if (!exceedsGuide(found, guide)) return null;
  final xs = found.corners.map((c) => c.dx);
  final ys = found.corners.map((c) => c.dy);
  final bounds = Rect.fromLTRB(
    xs.reduce(math.min),
    ys.reduce(math.min),
    xs.reduce(math.max),
    ys.reduce(math.max),
  );
  final overlap = bounds.intersect(guide);
  if (overlap.width <= 0 || overlap.height <= 0) return null;
  final cover = overlap.width * overlap.height / (guide.width * guide.height);
  return cover >= kOpenBookletGuideCover ? guide : null;
}

/// [page] as the detector's quad.
DocumentQuad quadOfRect(Rect page) => DocumentQuad(
      topLeft: page.topLeft,
      topRight: page.topRight,
      bottomRight: page.bottomRight,
      bottomLeft: Offset(page.left, page.bottom),
    );

/// [page] as the detector's box, at the [aspect] the gate expects (the guide
/// is drawn at the document's shape) and the found shape's [confidence].
DocumentBox boxOfRect(Rect page,
        {required double aspect, required double confidence}) =>
    DocumentBox(
      x: page.left,
      y: page.top,
      width: page.width,
      height: page.height,
      confidence: confidence,
      aspectRatio: aspect,
    );
