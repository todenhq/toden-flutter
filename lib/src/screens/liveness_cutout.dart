import 'dart:math' as math;
import 'dart:ui' show Size;

// The face window of the full-screen liveness camera: its size, from the box
// the camera is drawn in. Pure, so the layout and its tests share one rule.

const double kLivenessCutoutMaxWidth = 280;
const double kLivenessCutoutMinWidth = 200;

/// A face is taller than it is wide.
const double kLivenessCutoutAspect = 1.32;

/// The room above the window at which the long lighting note fits over the
/// instruction: the note and its gap (78) and the instruction's pill (50).
const double kLivenessRoomForLightingNote = 128;

/// What the instruction's pill needs of the room, on two lines.
const double kLivenessInstructionRoom = 66;

/// The height of the block above the window. On a phone too short for the
/// instruction, the block keeps that height and runs over the window's top
/// edge (the hair, not the face) instead of cutting the words off.
///
/// Nothing but the instruction stands here: a gesture is asked for in words,
/// and the face icon that acts it out is drawn inside the window
/// (liveness_gesture_narrator.dart).
double livenessAboveHeight(double room) =>
    math.max(room, kLivenessInstructionRoom);

/// The face cutout: a tall rectangle whose ends are fully round. As wide as
/// the frame allows, and bounded by the height so the instruction above and
/// whatever sits below keep their room.
Size livenessCutout(Size frame) {
  final width = math
      .min(
        math.min(frame.width - 96, frame.height * 0.46 / kLivenessCutoutAspect),
        kLivenessCutoutMaxWidth,
      )
      .clamp(kLivenessCutoutMinWidth, kLivenessCutoutMaxWidth)
      .toDouble();
  return Size(width, width * kLivenessCutoutAspect);
}

// The window sits a little BELOW the centre on a short screen, and only by
// what the block above it is short of. The face is judged against the window
// wherever it sits (faceWindowFor takes the drop). Mirrors windowDrop in the
// web and React Native SDKs.
//
// The room was sized when a gesture picture stood over the instruction: a gap
// (8), the picture on its plate (108), a gap (8), the instruction (46) and the
// gap over the window (20). No SDK has the picture any more; the number is
// kept so the window is in the same place in all three, and it changes in all
// three together.

/// The room wanted above the window, from the top inset down.
const double kLivenessWindowTopRoom = 190;

/// What must stay below the window: the gap under it, the retry panel a failed
/// check shows there (its words and its button), and the gap to the edge. It
/// was sized for the step count alone, and the panel was cut off.
const double kLivenessWindowBelowKeep = 136;

/// The furthest the window drops. More reads as off-centre.
const double kLivenessWindowMaxDrop = 48;

/// How far below the centre the window sits, for a frame and its window.
/// [topInset] is what the frame must keep clear of at its top (the status bar).
double livenessWindowDrop(Size frame, Size window, [double topInset = 0]) {
  final margin = (frame.height - window.height) / 2;
  final wanted = kLivenessWindowTopRoom + topInset - margin;
  final spare = margin - kLivenessWindowBelowKeep;
  final drop = math.min(math.min(wanted, spare), kLivenessWindowMaxDrop);
  return math.max(0.0, drop).roundToDouble();
}
