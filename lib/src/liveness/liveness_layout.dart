import 'dart:math' as math;
import 'dart:ui' show Size;

import '../config/theme.dart';

// ─── How big the selfie circle may be ────────────────────────────────────────
//
// The circle was a fixed [UiSizing.cameraCircleSize], which is right on a
// tall phone. On a Samsung S24 (360×780 dp, 176 dp shorter than an iPhone 16
// Pro Max) it owned most of the sheet. So the HEIGHT bounds it too: whatever
// the chrome, the instruction, the step dots and the footer leave over is what
// the circle may take. (A gesture avatar used to stand under the circle and
// shrink with it; it is gone, and the budget is kept so the circle keeps its
// size.)
//
// Mirrored in the React Native SDK's lib/livenessLayout.ts; the real phones in
// liveness_layout_test.dart are the shared vectors. Change a number in one and
// change both.

/// The cap is the size this SDK has always drawn; the tall phones keep it.
const double kLivenessCircleMax = UiSizing.cameraCircleSize;

/// A face is still usable at 200; below that the ring and the oval guide start
/// to crowd it, so a very short screen scrolls a little instead.
const double kLivenessCircleMin = 200;

/// Everything on the sheet that is NOT the circle: banner + brand row + title
/// + step bar (~250), the instruction line, the dots, the room the gesture
/// avatar had, the gaps, the step padding and the footer. The same budget as React Native —
/// the two sheets carry the same chrome.
const double kLivenessCircleHeightBudget = 540;

/// The circle keeps the step's own side padding on both sides.
const double kLivenessCircleSideGutter = UiSpacing.md * 4;

class LivenessLayout {
  /// Diameter of the camera circle, dp.
  final double circle;

  const LivenessLayout({required this.circle});
}

LivenessLayout livenessLayout(Size window) {
  final byWidth = window.width - kLivenessCircleSideGutter;
  final byHeight = window.height - kLivenessCircleHeightBudget;
  final circle = math.min(math.min(byWidth, byHeight), kLivenessCircleMax)
      .clamp(kLivenessCircleMin, kLivenessCircleMax)
      .toDouble();
  return LivenessLayout(circle: circle);
}
