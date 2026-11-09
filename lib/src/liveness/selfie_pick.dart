import 'dart:math' as math;
import 'dart:typed_data';

import '../utils/selfie_sharpness.dart' show laplacianVariance;
import 'face_detection.dart';

// ─── The selfie, chosen rather than snapped (user decision 2026-11-07) ───────
//
// The still used to be whatever frame first held a straight face after the
// last gesture. A separate "look at the camera" step would be a seam an
// attacker could use (pass the gestures live, then hold up a photo), so there
// is none: frames are scored all through the live check, the best front-on
// one is kept, and the final shot comes from the same unbroken run.
//
// Every selfie is cut to one standard frame: 3:4, head and shoulders, the face
// a set share of the width. Never enlarged: a face too small for the frame is
// a "move closer", not an upscale.
//
// Pure. The Flutter mirror of the web SDK's lib/selfie-pick.ts; the frame cut
// is the same arithmetic. The pose differs by source: the web SDK estimates it
// from mesh landmarks, this SDK reads the native detector's Euler angles in
// degrees (ML Kit on Android, Vision on iOS), so the limits are in degrees.

/// The face's share of the selfie's width.
const double kSelfieFaceShare = 0.42;

/// Width over height of the selfie: 3:4 portrait.
const double kSelfieAspect = 3 / 4;

/// The face's centre sits this far down the frame, leaving room for the head.
const double kSelfieFaceCentreY = 0.46;

/// The selfie's width at most: enough for the face match, small to upload.
const int kSelfieMaxWidth = 720;

/// Narrower than this in camera pixels, the face is too far away to keep.
const int kSelfieMinWidth = 360;

/// Facing the camera: each angle within this many degrees of straight on.
const double kFrontalMaxYaw = 10;
const double kFrontalMaxPitch = 10;
const double kFrontalMaxRoll = 10;

/// Both eyes at least this open (the detectors' 0..1 probability).
const double kSelfieEyesOpen = 0.5;

/// Sharpness (Laplacian variance) counts up to this, so a noisy frame cannot
/// outscore a frontal one. The web SDK's cap, on the same 120px measuring copy.
const double kSelfieSharpnessCap = 120;

/// The measuring copy's width for a candidate's sharpness.
const int kSelfieSharpnessWidth = 120;

/// Head turn, nod and tilt in degrees, each 0 when facing the camera.
class SelfiePose {
  final double yaw;
  final double pitch;
  final double roll;
  const SelfiePose({required this.yaw, required this.pitch, required this.roll});

  /// The detector's angles, each measured from [zero] (see [SelfieAngleZero]).
  factory SelfiePose.of(LivenessFaceData face, {double pitchZero = 0, double rollZero = 0}) =>
      SelfiePose(
        yaw: face.headEulerAngleY,
        pitch: face.headEulerAngleX - pitchZero,
        roll: _angleDelta(face.headEulerAngleZ, rollZero),
      );
}

/// The smallest signed difference between two angles in degrees.
double _angleDelta(double a, double b) {
  var d = (a - b) % 360;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d;
}

/// Facing the camera: no turn, nod or tilt beyond the allowance.
bool isFrontal(SelfiePose? pose) =>
    pose != null &&
    pose.yaw.abs() <= kFrontalMaxYaw &&
    pose.pitch.abs() <= kFrontalMaxPitch &&
    pose.roll.abs() <= kFrontalMaxRoll;

/// Both eyes open.
bool eyesOpen(LivenessFaceData face) =>
    face.leftEyeOpenProbability >= kSelfieEyesOpen &&
    face.rightEyeOpenProbability >= kSelfieEyesOpen;

/// How good a candidate is: more squarely facing the camera and sharper wins.
/// The pose terms are each 0..1 (1 = straight on); an unmeasured sharpness
/// scores nothing, so where no frame reaches Dart (the Android recorder) the
/// pose alone decides.
double selfieScore(SelfiePose pose, double? sharpness) {
  final straight = (1 - math.min(1, pose.yaw.abs() / kFrontalMaxYaw)) +
      (1 - math.min(1, pose.pitch.abs() / kFrontalMaxPitch)) +
      (1 - math.min(1, pose.roll.abs() / kFrontalMaxRoll));
  return straight / 3 + math.min(1, (sharpness ?? 0) / kSelfieSharpnessCap);
}

/// Where pitch and roll read zero.
///
/// On Android ML Kit reports both against a true zero. On iPhone they have
/// none to rely on (capture_pose.dart): roll carries the camera's orientation
/// and pitch is often a landmark estimate. There the zero is the run's own
/// resting pose: the median of the recent frames, so the gestures (a nod is
/// symmetrical about rest) do not move it.
class SelfieAngleZero {
  /// Frames the median is taken over (about three seconds at 15fps).
  static const int window = 45;

  final bool fromRun;
  final List<double> _pitch = [];
  final List<double> _roll = [];

  SelfieAngleZero({required this.fromRun});

  void clear() {
    _pitch.clear();
    _roll.clear();
  }

  void add(LivenessFaceData face) {
    if (!fromRun) return;
    _pitch.add(face.headEulerAngleX);
    _roll.add(face.headEulerAngleZ);
    if (_pitch.length > window) _pitch.removeAt(0);
    if (_roll.length > window) _roll.removeAt(0);
  }

  double get pitch => fromRun ? _median(_pitch) : 0;
  double get roll => fromRun ? _median(_roll) : 0;

  static double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}

/// The face held this long without moving before its frame may be the selfie.
const Duration kSelfieSteadyFor = Duration(milliseconds: 300);

/// Steady: the face's centre moved at most this share of its own width over
/// [kSelfieSteadyFor]. Measured against the face, not the frame, because the
/// selfie is cut to the face: 0.1 of it is about 3px of smear in the 720px
/// selfie at a dim room's 1/30s exposure.
const double kSelfieSteadyShift = 0.1;

/// Steady: the face's width changed by at most this share (no lunge at the
/// camera) over [kSelfieSteadyFor].
const double kSelfieSteadyScale = 0.1;

/// Steady: the head turned by at most this many degrees over
/// [kSelfieSteadyFor]. Generous, the detectors' yaw is noisy.
const double kSelfieSteadyTurn = 8;

/// Whether the face has held still (user report 2026-11-08: an iPhone kept a
/// frame from the moment the phone swung into place, smeared sideways).
///
/// Pose and the sharpness measure could not see it: the swing passed through
/// a straight face, and the 120px measuring copy of a smeared frame still
/// reached [kSelfieSharpnessCap]. Movement is what smears a frame, so it is
/// asked directly: every analysed face is fed in, and a frame counts as
/// steady only once the face has stayed put for [kSelfieSteadyFor]. The first
/// frames of a run are never steady (there is nothing yet to compare with).
class SelfieSteadiness {
  final List<({DateTime at, LivenessFaceData face})> _seen = [];

  void clear() => _seen.clear();

  void add(LivenessFaceData face, DateTime at) {
    _seen.add((at: at, face: face));
    // Keep the window plus the one face just before it, which proves the
    // window is covered.
    final from = at.subtract(kSelfieSteadyFor);
    while (_seen.length > 1 && !_seen[1].at.isAfter(from)) {
      _seen.removeAt(0);
    }
  }

  /// The latest face has stayed put for [kSelfieSteadyFor].
  bool get steady {
    if (_seen.isEmpty) return false;
    final last = _seen.last;
    final from = last.at.subtract(kSelfieSteadyFor);
    if (_seen.first.at.isAfter(from)) return false;
    return _seen.every((s) => !_moved(s.face, last.face));
  }

  static bool _moved(LivenessFaceData a, LivenessFaceData b) {
    final width = math.max(b.faceSizeRatio, 1e-6);
    if ((a.faceSizeRatio - b.faceSizeRatio).abs() / width > kSelfieSteadyScale) return true;
    if (_angleDelta(a.headEulerAngleY, b.headEulerAngleY).abs() > kSelfieSteadyTurn) return true;
    final ax = a.faceCenterX, ay = a.faceCenterY, bx = b.faceCenterX, by = b.faceCenterY;
    // A detector that reports no centre is judged on size and turn alone.
    if (ax == null || ay == null || bx == null || by == null) return false;
    // Centres are shares of the frame's sides, the width a share of its
    // width; the frame's aspect only stretches y, which errs toward moving.
    final shift = math.sqrt(math.pow(ax - bx, 2) + math.pow(ay - by, 2));
    return shift / width > kSelfieSteadyShift;
  }
}

/// The face in the still's own pixels, normalised 0..1: its centre and width.
class SelfieFace {
  final double centreX;
  final double centreY;
  final double width;
  const SelfieFace({required this.centreX, required this.centreY, required this.width});

  /// The face as the native detector reports it, moved into the still the
  /// SDK encodes.
  ///
  ///  - iOS: the still is the camera's BGRA buffer as delivered (already
  ///    selfie-mirrored). Vision reads it as `.upMirrored`, which un-mirrors
  ///    it, and puts its origin bottom-left, so both axes flip.
  ///  - Android: ML Kit reports the upright, un-mirrored frame; the still is
  ///    the same frame upright and mirrored, so x flips.
  ///
  /// A detector that reports no centre is taken as centred: the capture only
  /// runs once the face sits in the circle.
  factory SelfieFace.inStill(LivenessFaceData face, {required bool ios}) {
    final x = face.faceCenterX ?? 0.5;
    final y = face.faceCenterY ?? 0.5;
    return SelfieFace(
      centreX: face.faceCenterX == null ? 0.5 : 1 - x,
      centreY: ios && face.faceCenterY != null ? 1 - y : y,
      width: face.faceSizeRatio,
    );
  }
}

/// A rectangle in pixels.
class PixelRect {
  final int x;
  final int y;
  final int width;
  final int height;
  const PixelRect(this.x, this.y, this.width, this.height);

  @override
  bool operator ==(Object other) =>
      other is PixelRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'PixelRect($x, $y, $width, $height)';
}

/// The standard selfie frame around [face], in the frame's pixels: 3:4, the
/// face [kSelfieFaceShare] of its width, the face's centre
/// [kSelfieFaceCentreY] down. Moved (never squeezed) to stay inside the frame;
/// when the frame is too small for it, the tallest 3:4 frame that fits,
/// centred on the face. Null when the face is too far away for a selfie worth
/// keeping, unless [allowSmall], which the encoder passes for a still taken
/// without a candidate (it still never enlarges).
PixelRect? selfieFrame(
  SelfieFace face,
  int frameWidth,
  int frameHeight, {
  bool allowSmall = false,
}) {
  final faceWidth = face.width * frameWidth;
  var width = faceWidth / kSelfieFaceShare;
  var height = width / kSelfieAspect;
  if (height > frameHeight) {
    height = frameHeight.toDouble();
    width = height * kSelfieAspect;
  }
  if (width > frameWidth) {
    width = frameWidth.toDouble();
    height = width / kSelfieAspect;
  }
  if (width < kSelfieMinWidth) {
    if (!allowSmall || width <= 0) return null;
  }
  final cx = face.centreX * frameWidth;
  final cy = face.centreY * frameHeight;
  double clamp(double v, double size, int limit) => math.min(math.max(0, v), limit - size);
  return PixelRect(
    clamp(cx - width / 2, width, frameWidth).round(),
    clamp(cy - height * kSelfieFaceCentreY, height, frameHeight).round(),
    width.round(),
    height.round(),
  );
}

/// The rectangle mirrored left to right, for a frame drawn mirrored.
PixelRect mirrorRect(PixelRect rect, int frameWidth) =>
    PixelRect(frameWidth - rect.x - rect.width, rect.y, rect.width, rect.height);

/// The selfie's size once cut: at most [kSelfieMaxWidth] wide, never enlarged.
({int width, int height}) selfieOutputSize(PixelRect rect) {
  final scale = math.min(1.0, kSelfieMaxWidth / rect.width);
  return (width: (rect.width * scale).round(), height: (rect.height * scale).round());
}

/// The Laplacian variance of [rect] in a BGRA (or RGBA) frame, on a grey copy
/// [kSelfieSharpnessWidth] wide (nearest neighbour). Cheap enough for the
/// frame loop, and only run on a frame that already faces the camera.
double bgraSharpness(Uint8List bytes, int bytesPerRow, PixelRect rect) {
  const width = kSelfieSharpnessWidth;
  final height = math.max(3, (rect.height / rect.width * width).round());
  final gray = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    final sy = rect.y + (y * rect.height / height).floor();
    final row = sy * bytesPerRow;
    for (var x = 0; x < width; x++) {
      final sx = rect.x + (x * rect.width / width).floor();
      final i = row + sx * 4;
      if (i + 2 >= bytes.length) continue;
      // Channel order does not matter for luminance weights this coarse: the
      // weights below assume BGRA, and an RGBA frame only swaps the small
      // red/blue terms.
      gray[y * width + x] =
          (0.114 * bytes[i] + 0.587 * bytes[i + 1] + 0.299 * bytes[i + 2]).round();
    }
  }
  return laplacianVariance(gray, width, height);
}
