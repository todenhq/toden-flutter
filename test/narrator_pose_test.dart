import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/liveness/liveness_types.dart';
import 'package:toden_flutter/src/liveness/narrator_pose.dart';

// ─── The gesture narrator's poses ─────────────────────────────────────────────
//
// The same cases as the web SDK's liveness/narrator-pose.test.ts.

/// The pose at every 20th of a second through one pass.
List<NarratorPose> _pass(NarratorGesture gesture) {
  final seconds = kNarratorSeconds[gesture]!;
  final steps = (seconds * 20).round();
  return [
    for (var i = 0; i <= steps; i++) narratorPose(gesture, i / steps * seconds),
  ];
}

double _min(Iterable<double> v) => v.reduce((a, b) => a < b ? a : b);
double _max(Iterable<double> v) => v.reduce((a, b) => a > b ? a : b);

void main() {
  for (final gesture in NarratorGesture.values) {
    test(
        '${gesture.name} starts and ends at rest, so it arrives and leaves facing the person',
        () {
      final poses = _pass(gesture);
      for (final pose in [poses.first, poses.last]) {
        expect(pose.across, closeTo(kNarratorRest.across, 1e-3));
        expect(pose.down, closeTo(kNarratorRest.down, 1e-3));
        expect(pose.eyes, closeTo(kNarratorRest.eyes, 1e-3));
        expect(pose.smile, closeTo(kNarratorRest.smile, 1e-3));
        expect(pose.lookX, closeTo(0, 1e-3));
        expect(pose.lookY, closeTo(0, 1e-3));
      }
    });

    test('with less motion, ${gesture.name} holds one pose that says it', () {
      expect(narratorStillPose(gesture), isNot(kNarratorRest));
    });
  }

  test('turns fully to one side and then the other', () {
    final across = _pass(NarratorGesture.turn).map((p) => p.across).toList();
    expect(_min(across), lessThan(-0.95));
    expect(_max(across), greaterThan(0.95));
    expect(across.indexWhere((a) => a < -0.95),
        lessThan(across.indexWhere((a) => a > 0.95)));
  });

  test('nods down, then up past the middle', () {
    final down = _pass(NarratorGesture.nod).map((p) => p.down);
    expect(_max(down), greaterThan(0.95));
    expect(_min(down), lessThan(-0.6));
  });

  test('blinks twice, the eyes fully shut each time', () {
    final eyes = _pass(NarratorGesture.blink).map((p) => p.eyes).toList();
    var blinks = 0;
    for (var i = 1; i < eyes.length; i++) {
      if (eyes[i] < 0.1 && eyes[i - 1] >= 0.1) blinks++;
    }
    expect(blinks, 2);
    expect(_min(eyes), lessThan(0.05));
  });

  test('smiles in full, with the eyes narrowing, and the head only drifting', () {
    final poses = _pass(NarratorGesture.smile);
    expect(_max(poses.map((p) => p.smile)), greaterThan(0.95));
    expect(_min(poses.map((p) => p.eyes)), lessThan(0.75));
    // The chin lifts a little and the head drifts, but it never reads as a
    // turn or a nod.
    expect(poses.every((p) => p.across.abs() < 0.1 && p.down.abs() < 0.2), isTrue);
  });

  test('looks where the head is going, a moment before it gets there', () {
    final turn = _pass(NarratorGesture.turn);
    final firstLook = turn.indexWhere((p) => p.lookX < -0.5);
    final firstTurn = turn.indexWhere((p) => p.across < -0.5);
    expect(firstLook, greaterThan(-1));
    expect(firstLook, lessThan(firstTurn));
    final nod = _pass(NarratorGesture.nod);
    expect(nod.indexWhere((p) => p.lookY > 0.5),
        lessThan(nod.indexWhere((p) => p.down > 0.5)));
  });

  test('blinks as it swings through the middle of a turn, and lowers its lids looking down', () {
    expect(_min(_pass(NarratorGesture.turn).map((p) => p.eyes)), lessThan(0.1));
    final lowest = _pass(NarratorGesture.nod).reduce((a, b) => b.down > a.down ? b : a);
    expect(lowest.eyes, lessThan(0.8));
  });

  test('goes ONE way for a head direction, toward the screen side the person will turn to, and holds there', () {
    final left = _pass(NarratorGesture.turnLeft).map((p) => p.across).toList();
    expect(_min(left), lessThan(-0.95));
    expect(_max(left), lessThan(0.1));
    expect(left.where((a) => a < -0.9).length, greaterThanOrEqualTo(8)); // about 0.4 s
    final right = _pass(NarratorGesture.turnRight).map((p) => p.across);
    expect(_max(right), greaterThan(0.95));
    expect(_min(right), greaterThan(-0.1));
    expect(_min(_pass(NarratorGesture.lookUp).map((p) => p.down)), lessThan(-0.95));
    expect(_max(_pass(NarratorGesture.lookUp).map((p) => p.down)), lessThan(0.1));
    expect(_max(_pass(NarratorGesture.lookDown).map((p) => p.down)), greaterThan(0.95));
  });

  test('acts out the gestures and the head directions, and nothing for the hold', () {
    expect(narratorGestureFor(LivenessChallenge.turnLeft), NarratorGesture.turnLeft);
    expect(narratorGestureFor(LivenessChallenge.turnRight), NarratorGesture.turnRight);
    expect(narratorGestureFor(LivenessChallenge.lookUp), NarratorGesture.lookUp);
    expect(narratorGestureFor(LivenessChallenge.lookDown), NarratorGesture.lookDown);
    expect(narratorGestureFor(LivenessChallenge.turn), NarratorGesture.turn);
    expect(narratorGestureFor(LivenessChallenge.nod), NarratorGesture.nod);
    expect(narratorGestureFor(LivenessChallenge.blink), NarratorGesture.blink);
    expect(narratorGestureFor(LivenessChallenge.smile), NarratorGesture.smile);
    expect(narratorGestureFor(LivenessChallenge.hold), isNull);
    expect(narratorGestureFor(null), isNull);
  });

  test('the lengths are the web SDK\'s', () {
    expect(kNarratorSeconds, {
      NarratorGesture.turn: 2.4,
      NarratorGesture.nod: 2,
      NarratorGesture.blink: 1.5,
      NarratorGesture.smile: 1.9,
      NarratorGesture.turnLeft: 2,
      NarratorGesture.turnRight: 2,
      NarratorGesture.lookUp: 2,
      NarratorGesture.lookDown: 2,
    });
  });
}
