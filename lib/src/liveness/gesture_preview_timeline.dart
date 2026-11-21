import 'dart:math' as math;

// ─── The liveness intro's picture, frame by frame ─────────────────────────────
//
// A cartoon person in a small copy of the camera's window (widgets/
// gesture_preview.dart). They come in ONCE, from a little way back, a touch
// too close, and settle, as someone finding their distance does. Then they
// turn, nod, blink and smile in a loop, while the window's line, cut into four
// parts, fills green one part per gesture. Each gesture ends as it does in the
// camera: a light green cover over the window and a tick that pops up at once,
// held a moment, then the next. After the last the line empties and it all
// goes round again. A passive check comes in and holds still while the line
// closes, then the tick.
//
// Pure: everything the picture shows at a moment, from the seconds since it
// started, so the widget only draws it. The numbers are the web SDK's
// GesturePreview's.

enum PreviewGesture {
  turn,
  nod,
  blink,
  smile,
  turnLeft,
  turnRight,
  lookUp,
  lookDown,
}

/// The classic gestures, round and round.
const List<PreviewGesture> kAllPreviewGestures = [
  PreviewGesture.turn,
  PreviewGesture.nod,
  PreviewGesture.blink,
  PreviewGesture.smile,
];

/// The head directions set, in the order the picture runs through them.
const List<PreviewGesture> kDirectionPreviewGestures = [
  PreviewGesture.turnLeft,
  PreviewGesture.turnRight,
  PreviewGesture.lookUp,
  PreviewGesture.lookDown,
];

/// Seconds each gesture takes, rest to rest.
const Map<PreviewGesture, double> kPreviewLength = {
  PreviewGesture.turn: 2.4,
  PreviewGesture.nod: 2,
  PreviewGesture.blink: 1.5,
  PreviewGesture.smile: 1.9,
  PreviewGesture.turnLeft: 1.8,
  PreviewGesture.turnRight: 1.8,
  PreviewGesture.lookUp: 1.8,
  PreviewGesture.lookDown: 1.8,
};

/// Coming in: how long, and how much too close it gets on the way.
const double kPreviewComingIn = 1.1;
const double kPreviewOvershoot = 0.06;

/// The tick after each gesture: on screen this long, then the next one.
const double kPreviewPassHold = 0.8;

/// The tick after the last gesture, before it all goes round again.
const double kPreviewTickHold = 1.1;

/// The line eases after its progress, by about this much: the tick waits for
/// the line to be seen to close, and no longer.
const double kPreviewLineCatchUp = 0.15;

/// How long a passive check's line takes to close.
const double kPreviewHold = 2.4;

/// How far the face slides across the head at the end of a turn or a nod, in
/// the drawing's own units (it is 768 across).
const double kPreviewTurnSlide = 46;
const double kPreviewNodSlide = 30;

double _ease(double t) =>
    t <= 0 ? 0 : (t >= 1 ? 1 : (1 - math.cos(math.pi * t)) / 2);
double _swell(double t) =>
    t <= 0 || t >= 1 ? 0 : (1 - math.cos(2 * math.pi * t)) / 2;

/// One way and back: out, held there for a moment, and home.
double _outAndBack(double t) => _ease(t / 0.3) - _ease((t - 0.68) / 0.26);

class PreviewPose {
  const PreviewPose({
    this.across = 0,
    this.down = 0,
    this.shut = false,
    this.smile = false,
  });

  /// Across, -1 (their right, our left) to 1.
  final double across;

  /// Down, -1 (up) to 1.
  final double down;
  final bool shut;
  final bool smile;
}

const PreviewPose kPreviewRest = PreviewPose();

PreviewPose previewPoseAt(PreviewGesture gesture, double at) {
  final t = at / kPreviewLength[gesture]!;
  switch (gesture) {
    case PreviewGesture.turn:
      // One way, across to the other, and back to the middle.
      return PreviewPose(
        across: -_ease(t / 0.3) +
            2 * _ease((t - 0.35) / 0.3) -
            _ease((t - 0.72) / 0.22),
      );
    case PreviewGesture.nod:
      return PreviewPose(
          down: _swell(t / 0.45) - 0.7 * _swell((t - 0.45) / 0.45));
    // One way, held for a moment, and back. The picture is the camera's own
    // mirrored view, so the person's left is the left of the screen.
    case PreviewGesture.turnLeft:
      return PreviewPose(across: -_outAndBack(t));
    case PreviewGesture.turnRight:
      return PreviewPose(across: _outAndBack(t));
    case PreviewGesture.lookUp:
      return PreviewPose(down: -_outAndBack(t));
    case PreviewGesture.lookDown:
      return PreviewPose(down: _outAndBack(t));
    case PreviewGesture.blink:
      // Twice, quickly.
      return PreviewPose(
          shut: (t > 0.25 && t < 0.35) || (t > 0.55 && t < 0.65));
    case PreviewGesture.smile:
      return PreviewPose(smile: t > 0.15 && t < 0.85);
  }
}

/// Everything the picture shows at one moment.
class PreviewFrame {
  const PreviewFrame({
    required this.opacity,
    required this.scale,
    required this.pose,
    required this.progress,
    required this.passed,
    required this.round,
  });

  /// The person, coming in.
  final double opacity;
  final double scale;
  final PreviewPose pose;

  /// How much of the line has been earned, 0 to 1.
  final double progress;

  /// The cover and the tick are up.
  final bool passed;

  /// How many times it has gone round: the line starts again on each.
  final int round;
}

/// The picture [seconds] after it started, running through [gestures] (none:
/// a passive check, which holds still while the line closes).
PreviewFrame previewFrameAt(List<PreviewGesture> gestures, double seconds) {
  if (seconds < kPreviewComingIn) {
    final t = seconds / kPreviewComingIn;
    // From a little way back, past where it fits, and back.
    final scale = 0.86 +
        (0.14 + kPreviewOvershoot) * _ease(t / 0.6) -
        kPreviewOvershoot * _ease((t - 0.6) / 0.4);
    return PreviewFrame(
      opacity: math.min(1, t / 0.35),
      scale: scale,
      pose: kPreviewRest,
      progress: 0,
      passed: false,
      round: 0,
    );
  }
  // One time round: each gesture and the tick after it.
  final steps = <(PreviewGesture?, double)>[
    if (gestures.isEmpty) (null, kPreviewHold),
    for (final g in gestures) (g, kPreviewLength[g]!),
  ];
  double holdAfter(int i) =>
      kPreviewLineCatchUp +
      (i == steps.length - 1 ? kPreviewTickHold : kPreviewPassHold);
  var lap = 0.0;
  for (var i = 0; i < steps.length; i++) {
    lap += steps[i].$2 + holdAfter(i);
  }
  final clock = seconds - kPreviewComingIn;
  final round = (clock / lap).floor();
  var at = clock - round * lap;
  for (var i = 0; i < steps.length; i++) {
    final (gesture, length) = steps[i];
    final share = 1 / steps.length;
    if (at < length) {
      return PreviewFrame(
        opacity: 1,
        scale: 1,
        pose: gesture == null ? kPreviewRest : previewPoseAt(gesture, at),
        progress: (i + at / length) * share,
        passed: false,
        round: round,
      );
    }
    at -= length;
    if (at < holdAfter(i)) {
      return PreviewFrame(
        opacity: 1,
        scale: 1,
        pose: kPreviewRest,
        progress: (i + 1) * share,
        // The tick pops up as its part of the line is seen to close.
        passed: at >= kPreviewLineCatchUp,
        round: round,
      );
    }
    at -= holdAfter(i);
  }
  // Floating point at the very end of a lap: the start of the next.
  return PreviewFrame(
    opacity: 1,
    scale: 1,
    pose: kPreviewRest,
    progress: 0,
    passed: false,
    round: round + 1,
  );
}
