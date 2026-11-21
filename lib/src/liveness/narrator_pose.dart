import 'dart:math' as math;

import 'liveness_types.dart';

// ─── The gesture narrator's poses ─────────────────────────────────────────────
//
// A face icon in the manner of a phone's face unlock: a round head with two
// eyes, a nose and a mouth, acting out a gesture once.
//
//   turn   the features slide to one side and draw together, as a face does
//          turning away, then to the other side, then back to the middle
//   nod    the features drop, rise past the middle, and settle
//   blink  the eyes close and open, twice
//   smile  the mouth curves up and the eyes narrow, then it relaxes
//
// The head directions set has one pose each: the head goes ONE way, holds
// there long enough to be read, and comes back. Left and right are the
// person's own: on the mirrored camera picture their left is the screen's
// left, so `turnLeft` goes toward the left of the screen.
//
// It is alive while it does so, not a stiff diagram (user, 2026-11-17): the
// eyes look where the head is about to go a moment before it gets there, the
// lids follow the eyes down in a nod, it blinks as it swings through the
// middle of a turn, the chin lifts a little with a smile, and it drifts
// slightly as a real head never holds quite still. All of it settles to rest
// at both ends of the pass.
//
// Pure and on its own clock, so the painter only reads numbers. A port of the
// web SDK's liveness/narrator-pose.ts: the same curves and the same lengths.

enum NarratorGesture {
  turn,
  nod,
  blink,
  smile,
  turnLeft,
  turnRight,
  lookUp,
  lookDown,
}

/// Seconds each gesture takes, rest to rest.
const Map<NarratorGesture, double> kNarratorSeconds = {
  NarratorGesture.turn: 2.4,
  NarratorGesture.nod: 2,
  NarratorGesture.blink: 1.5,
  NarratorGesture.smile: 1.9,
  NarratorGesture.turnLeft: 2,
  NarratorGesture.turnRight: 2,
  NarratorGesture.lookUp: 2,
  NarratorGesture.lookDown: 2,
};

/// The gesture the narrator acts out for a challenge, or null for one it has
/// nothing to show for (the passive hold).
NarratorGesture? narratorGestureFor(LivenessChallenge? challenge) =>
    switch (challenge) {
      LivenessChallenge.turn => NarratorGesture.turn,
      LivenessChallenge.nod => NarratorGesture.nod,
      LivenessChallenge.blink => NarratorGesture.blink,
      LivenessChallenge.smile => NarratorGesture.smile,
      LivenessChallenge.turnLeft => NarratorGesture.turnLeft,
      LivenessChallenge.turnRight => NarratorGesture.turnRight,
      LivenessChallenge.lookUp => NarratorGesture.lookUp,
      LivenessChallenge.lookDown => NarratorGesture.lookDown,
      _ => null,
    };

class NarratorPose {
  const NarratorPose({
    this.across = 0,
    this.down = 0,
    this.eyes = 1,
    this.smile = 0,
    this.lookX = 0,
    this.lookY = 0,
  });

  /// Sideways, -1 (towards the left of the screen) to 1.
  final double across;

  /// Down, -1 (up) to 1.
  final double down;

  /// How open the eyes are, 0 (shut) to 1.
  final double eyes;

  /// How far the mouth curves up, 0 (resting) to 1 (a full smile).
  final double smile;

  /// Where the eyes look within the face, -1 to 1 each way, as [across] and
  /// [down]. They lead the head.
  final double lookX;
  final double lookY;

  @override
  bool operator ==(Object other) =>
      other is NarratorPose &&
      other.across == across &&
      other.down == down &&
      other.eyes == eyes &&
      other.smile == smile &&
      other.lookX == lookX &&
      other.lookY == lookY;

  @override
  int get hashCode => Object.hash(across, down, eyes, smile, lookX, lookY);

  @override
  String toString() => 'NarratorPose(across: $across, down: $down, '
      'eyes: $eyes, smile: $smile, lookX: $lookX, lookY: $lookY)';
}

const NarratorPose kNarratorRest = NarratorPose();

/// How far ahead of the head the eyes are, in seconds.
const double _lookLead = 0.12;

/// How far the eyes look past where the head points, at most.
const double _lookReach = 1.25;

/// Smooth from 0 to 1 over [0, 1].
double _ease(double t) =>
    t <= 0 ? 0 : (t >= 1 ? 1 : (1 - math.cos(math.pi * t)) / 2);

/// Smooth from 0 to 1 and back to 0 over [0, 1].
double _swell(double t) =>
    t <= 0 || t >= 1 ? 0 : (1 - math.cos(2 * math.pi * t)) / 2;

double _clamp1(double n) => n.clamp(-1.0, 1.0).toDouble();

/// One way and back: out, held there for a moment, and home. 0 at both ends.
double _outAndBack(double t) => _ease(t / 0.3) - _ease((t - 0.68) / 0.26);

/// The turn's sideways path, on the pass's own 0..1 clock.
double _turnAcross(double t) =>
    -_ease(t / 0.3) + 2 * _ease((t - 0.35) / 0.3) - _ease((t - 0.72) / 0.22);

/// The nod's path, on the pass's own 0..1 clock.
double _nodDown(double t) =>
    _swell(t / 0.45) - 0.7 * _swell((t - 0.45) / 0.45);

/// A slight drift, nothing at either end: a real head never holds quite still.
double _drift(double t, double size) =>
    size * math.sin(2 * math.pi * t) * _swell(t);

/// The pose [at] seconds into one pass of [gesture]. At rest at both ends.
NarratorPose narratorPose(NarratorGesture gesture, double at) {
  final seconds = kNarratorSeconds[gesture]!;
  final t = at / seconds;
  // Where the head will be a moment from now, which is where the eyes look.
  final ahead = math.min(1.0, t + _lookLead / seconds);
  // It arrives looking at the person, and the glance comes in from there.
  final arrived = _ease(t / 0.1);
  switch (gesture) {
    case NarratorGesture.turn:
      return NarratorPose(
        across: _turnAcross(t),
        down: _drift(t, 0.06),
        // A quick blink as the head swings through the middle.
        eyes: 1 - _swell((t - 0.44) / 0.1),
        lookX: arrived * _clamp1(_lookReach * _turnAcross(ahead)),
      );
    case NarratorGesture.nod:
      final down = _nodDown(t);
      return NarratorPose(
        down: down,
        across: _drift(t, 0.05),
        // The lids follow the eyes down.
        eyes: 1 - 0.3 * math.max(0, down),
        lookY: arrived * _clamp1(_lookReach * _nodDown(ahead)),
      );
    case NarratorGesture.turnLeft:
    case NarratorGesture.turnRight:
      final side = gesture == NarratorGesture.turnLeft ? -1 : 1;
      return NarratorPose(
        across: side * _outAndBack(t),
        down: _drift(t, 0.05),
        lookX: arrived * _clamp1(_lookReach * side * _outAndBack(ahead)),
      );
    case NarratorGesture.lookUp:
    case NarratorGesture.lookDown:
      final way = gesture == NarratorGesture.lookUp ? -1 : 1;
      final down = way * _outAndBack(t);
      return NarratorPose(
        down: down,
        across: _drift(t, 0.04),
        // The lids follow the eyes down, and open a touch looking up.
        eyes: 1 - 0.3 * math.max(0, down),
        lookY: arrived * _clamp1(_lookReach * way * _outAndBack(ahead)),
      );
    case NarratorGesture.blink:
      // Two quick blinks, each shutting faster than it opens, the head
      // dipping a touch with each.
      final shut = _swell((t - 0.2) / 0.18) + _swell((t - 0.52) / 0.18);
      return NarratorPose(
          eyes: 1 - shut, down: 0.06 * shut, across: _drift(t, 0.05));
    case NarratorGesture.smile:
      final smile = _ease((t - 0.1) / 0.2) - _ease((t - 0.75) / 0.2);
      // The cheeks lift into the eyes, and the chin comes up a little.
      return NarratorPose(
        smile: smile,
        eyes: 1 - 0.3 * smile,
        down: -0.12 * smile,
        across: _drift(t, 0.05),
      );
  }
}

/// The one pose that says the gesture, for a person who asked for less motion.
NarratorPose narratorStillPose(NarratorGesture gesture) => switch (gesture) {
      NarratorGesture.turn => const NarratorPose(across: 1, lookX: 1),
      NarratorGesture.nod => const NarratorPose(down: 1, eyes: 0.7, lookY: 1),
      NarratorGesture.turnLeft => const NarratorPose(across: -1, lookX: -1),
      NarratorGesture.turnRight => const NarratorPose(across: 1, lookX: 1),
      NarratorGesture.lookUp => const NarratorPose(down: -1, lookY: -1),
      NarratorGesture.lookDown =>
        const NarratorPose(down: 1, eyes: 0.7, lookY: 1),
      NarratorGesture.blink => const NarratorPose(eyes: 0),
      NarratorGesture.smile =>
        const NarratorPose(smile: 1, eyes: 0.7, down: -0.12),
    };
