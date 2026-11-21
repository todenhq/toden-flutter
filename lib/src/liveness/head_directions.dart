import 'face_detection.dart';
import 'liveness_types.dart';

// ─── Which way the head is facing ─────────────────────────────────────────────
//
// For the head directions gesture set: turned to the person's own left or
// right, looking up or down. A port of the web SDK's
// liveness/gesture-detector/directions.ts.
//
// LEFT AND RIGHT ARE THE PERSON'S OWN. The native detectors report yaw with
// positive meaning the head turned to the person's own left
// (LivenessFaceData.headEulerAngleY, ML Kit's convention, which the iOS plugin
// follows). On screen the preview is mirrored, so their left is the screen's
// left too, and "turn your head to the left" means the same whichever way they
// read it.
//
// The web measures the face mesh's points as shares of the face's size; the
// detectors here report the head's angles directly, so the lines are in
// degrees. Up and down are measured against the person's own resting pitch,
// taken as they hold still before the first gesture: faces differ in where
// they rest, and on iPhone the pitch is a landmark estimate with no
// dependable zero (capture_pose.dart).

/// How far the head must turn, in degrees, to count as a turn: the classic
/// turn's own line (detectTurn), as the web's TURN_OFFSET is its own.
const double kDirectionTurnDegrees = 25;

/// How far the head must tip from its rest, in degrees, to count as looking
/// up or down: the web's LOOK_OFFSET is "about fifteen degrees".
const double kDirectionLookDegrees = 15;

/// A direction must hold for this many frames in a row, so a passing wobble
/// is not taken for the gesture. The web's DIRECTION_HOLD_FRAMES.
const int kDirectionHoldFrames = 4;

/// A head held the wrong way this many frames (about a second) is shown the
/// way again. Never a failure.
const int kWrongWayFrames = 30;

/// The one direction the head is plainly facing, or null when it is facing
/// the camera. [restPitch] is the person's own pitch at rest. The larger of
/// the two movements wins, so a turn with a slight dip is still a turn.
LivenessChallenge? facing(LivenessFaceData face, double restPitch) {
  final turn = face.headEulerAngleY;
  final tilt = face.headEulerAngleX - restPitch;
  final turned = turn.abs() / kDirectionTurnDegrees;
  final tilted = tilt.abs() / kDirectionLookDegrees;
  if (turned < 1 && tilted < 1) return null;
  if (turned >= tilted) {
    return turn > 0 ? LivenessChallenge.turnLeft : LivenessChallenge.turnRight;
  }
  // headEulerAngleX is positive looking up.
  return tilt > 0 ? LivenessChallenge.lookUp : LivenessChallenge.lookDown;
}

/// The direction straight across from one: what "the wrong way" is.
LivenessChallenge oppositeDirection(LivenessChallenge direction) =>
    switch (direction) {
      LivenessChallenge.turnLeft => LivenessChallenge.turnRight,
      LivenessChallenge.turnRight => LivenessChallenge.turnLeft,
      LivenessChallenge.lookUp => LivenessChallenge.lookDown,
      LivenessChallenge.lookDown => LivenessChallenge.lookUp,
      _ => direction,
    };

/// What one frame did to a head direction being asked for.
enum DirectionStep {
  /// Not yet.
  waiting,

  /// Held the asked way long enough: the gesture is done.
  done,

  /// Held the opposite way for [kWrongWayFrames]: show the way again.
  wrongWay,
}

/// Counts the frames of one head direction being asked for. The wrong way is
/// never a failure and never a red warning: it does not count, and after a
/// second of it the narrator shows the way again.
class DirectionWatch {
  int _right = 0;
  int _wrong = 0;

  void reset() {
    _right = 0;
    _wrong = 0;
  }

  DirectionStep update(
    LivenessChallenge expected,
    LivenessFaceData face,
    double restPitch,
  ) {
    final way = facing(face, restPitch);
    if (way == expected) {
      _wrong = 0;
      _right++;
      if (_right >= kDirectionHoldFrames) {
        reset();
        return DirectionStep.done;
      }
      return DirectionStep.waiting;
    }
    _right = 0;
    if (way == oppositeDirection(expected)) {
      _wrong++;
      if (_wrong == kWrongWayFrames) return DirectionStep.wrongWay;
    } else {
      _wrong = 0;
    }
    return DirectionStep.waiting;
  }
}
