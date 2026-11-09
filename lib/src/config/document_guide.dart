import 'dart:math' as math;
import 'dart:ui' show Rect, Offset, Size;

import 'id_types.dart';
import 'immersive_layout.dart';

// ─── Document guide geometry ──────────────────────────────────────────────────
//
// THE single definition of where the capture guide sits. It is consumed by the
// on-screen overlay AND by the crop that runs after the shutter, so if the two
// ever disagree the user frames against one rectangle and receives another —
// which is exactly what happened when the scan overlay computed its own rect.
//
// Any change here moves the guide and the crop together, on purpose.

/// Share of the viewfinder width the guide spans.
const double kDocumentGuideWidthFraction = 0.88;

/// The room the camera's controls take along the viewfinder's top and bottom
/// edges, measured from those edges. Only an UPRIGHT guide (a turned NIN slip,
/// see config/document_turn.dart) uses it: upright, a guide 88% of the width
/// wide runs about 84% of a phone's height, under the top bar and over the
/// bottom row.
class DocumentGuideBand {
  final double topReserve;
  final double bottomReserve;

  const DocumentGuideBand(
      {required this.topReserve, required this.bottomReserve});

  @override
  bool operator ==(Object other) =>
      other is DocumentGuideBand &&
      other.topReserve == topReserve &&
      other.bottomReserve == bottomReserve;

  @override
  int get hashCode => Object.hash(topReserve, bottomReserve);
}

/// The band for a full-screen viewfinder whose system bars intrude by
/// [topInset] and [bottomInset] (the view's padding).
///
/// An upright guide is a turned NIN slip, whose hint is drawn turned beside it,
/// so above it is only the top bar (back, document pill, side badge) and 16 of
/// clear space; below it, 24 of clear space and the bottom row (upload,
/// shutter, torch). The numbers are the overlay's own
/// (config/immersive_layout.dart), so the band always matches what is drawn.
/// The React Native SDK's immersiveBand, value for value.
DocumentGuideBand documentGuideBand({
  required double topInset,
  required double bottomInset,
}) =>
    DocumentGuideBand(
      topReserve: immersiveTopBarTop(topInset) +
          kImmersiveTopBarHeight +
          kImmersiveGuideGapBelowTopBar,
      bottomReserve: immersiveBottomRowReserve(bottomInset) +
          kImmersiveGuideGapAboveControls,
    );

/// The guide rectangle inside a viewfinder of [size] for a document of
/// [aspect] (width / height).
///
/// Landscape (every card and passport): 88% of the width, [aspect] preserved,
/// centred in the viewfinder both ways, with no nudge and no height cap. The
/// React Native SDK's guideRect, value for value. [band] is ignored.
///
/// Upright ([aspect] below 1, a turned NIN slip): fills the free [band] between
/// the top controls and the bottom bar, centred in it, never wider than 88% of
/// the width. Without a band the whole height is the band. The overlay, the
/// sample drawing, the turn-over prompt and the guide crop all call this with
/// the same band, so the crop is exactly what was drawn.
Rect documentGuideRect(Size size, double aspect, {DocumentGuideBand? band}) {
  if (aspect < 1) {
    final top = band?.topReserve ?? 0;
    final bandHeight =
        math.max(0.0, size.height - top - (band?.bottomReserve ?? 0));
    var height = bandHeight;
    var width = height * aspect;
    final maxWidth = size.width * kDocumentGuideWidthFraction;
    if (width > maxWidth) {
      width = maxWidth;
      height = width / aspect;
    }
    return Rect.fromLTWH(
      (size.width - width) / 2,
      top + (bandHeight - height) / 2,
      width,
      height,
    );
  }

  final width = size.width * kDocumentGuideWidthFraction;
  final height = width / aspect;
  return Rect.fromLTWH(
    (size.width - width) / 2,
    (size.height - height) / 2,
    width,
    height,
  );
}

/// Centre of the guide — handy for callers that only need the focus point.
Offset documentGuideCenter(Size size, double aspect,
        {DocumentGuideBand? band}) =>
    documentGuideRect(size, aspect, band: band).center;

// ─── Document aspect ratios ───────────────────────────────────────────────────
//
// Passport pages are squarer than ID cards, and a card-shaped crop clips the
// MRZ band off the bottom of a passport. A NIN slip is longer than a card.

/// ISO/IEC 7810 ID-1 (85.6 mm × 53.98 mm).
const double kCardGuideAspect = 1.586;
const double kPassportGuideAspect = 1.42;

/// Paper NIN slips measured 2.00 to 2.32 (median 2.07).
const double kNinSlipGuideAspect = 2.07;

double documentGuideAspect(IdTypeConfig idType) => switch (idType.key) {
      'passport' => kPassportGuideAspect,
      'nin-slip' => kNinSlipGuideAspect,
      _ => kCardGuideAspect,
    };
