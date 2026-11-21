import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

// ─── What the full-screen selfie review shows, and where ─────────────────────
//
// The selfie that is uploaded is a tight 3:4 cut round the face
// (selfie_pick.dart). Spread over the whole screen, that cut was enlarged until
// the face was bigger than the window, which the camera had never shown (user
// report 2026-11-17: "that was not how it looked when it was captured ... it
// must always fit the frame on all devices").
//
// So the review shows the camera FRAME the selfie was cut from, drawn the way
// the camera drew it: filling the screen, under the same light blur round the
// window. Two things are done for the face, in this order:
//
//   it fits         A face held close enough to spill over the window makes
//                   the picture smaller until it fits, and the face is kept
//                   inside the window's edges. This can leave a strip of the
//                   screen without picture, which the view fades out rather
//                   than cutting off.
//   it is central   As far as that goes without uncovering the screen.
//
// Pure. A port of the web SDK's lib/selfie-review.ts.

/// Where the face is in a frame, in shares of it: its top left and size.
class ShareBox {
  const ShareBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}

/// The camera frame a selfie was cut from. Held in memory; never uploaded.
class SelfieScene {
  const SelfieScene({
    required this.jpeg,
    required this.width,
    required this.height,
    required this.face,
  });

  /// The frame, mirrored as the person saw it.
  final Uint8List jpeg;
  final int width;
  final int height;

  /// Where the face is, in shares of the frame.
  final ShareBox face;
}

/// The face is at most this share of the window's width and height.
const double kReviewFaceMaxFill = 0.8;

/// The face box from the detectors' centre and width (shares of the frame's
/// width). The detectors' face boxes are about square, so its height in
/// pixels is taken as its width.
ShareBox faceShareBox({
  required double centreX,
  required double centreY,
  required double width,
  required int frameWidth,
  required int frameHeight,
}) {
  final height = frameHeight <= 0 ? width : width * frameWidth / frameHeight;
  return ShareBox(
    x: centreX - width / 2,
    y: centreY - height / 2,
    width: width,
    height: height,
  );
}

/// One axis: central where the picture covers, and the face inside the window
/// always.
double _along(double screen, double size, double faceStart, double faceSize,
    double windowStart, double windowSize) {
  final central =
      windowStart + windowSize / 2 - (faceStart + faceSize / 2) * size;
  final covering = size >= screen
      ? math.min(0.0, math.max(screen - size, central))
      : (screen - size) / 2;
  // The face's near edge not before the window's, its far edge not past it.
  final least = windowStart - faceStart * size;
  final most = windowStart + windowSize - (faceStart + faceSize) * size;
  return math.min(most, math.max(least, covering));
}

/// Where the camera frame goes on the review, in the camera area's own
/// points. [window] is the face window, its top [windowTop] down the camera
/// area and centred across it.
Rect sceneOnReview(
  Size scene,
  ShareBox face,
  Size frame,
  Size window,
  double windowTop,
) {
  final cover = math.max(frame.width / scene.width, frame.height / scene.height);
  // How much of the window the face takes drawn as the camera drew it.
  final fill = math.max(
    face.width * scene.width * cover / window.width,
    face.height * scene.height * cover / window.height,
  );
  final scale = cover * math.min(1.0, kReviewFaceMaxFill / fill);
  final width = scene.width * scale;
  final height = scene.height * scale;
  return Rect.fromLTWH(
    _along(frame.width, width, face.x, face.width,
        (frame.width - window.width) / 2, window.width),
    _along(frame.height, height, face.y, face.height, windowTop, window.height),
    width,
    height,
  );
}

/// Which edges of the camera area the picture does not reach.
({bool left, bool right, bool top, bool bottom}) uncovered(
        Rect at, Size frame) =>
    (
      left: at.left > 0.5,
      right: at.right < frame.width - 0.5,
      top: at.top > 0.5,
      bottom: at.bottom < frame.height - 0.5,
    );
