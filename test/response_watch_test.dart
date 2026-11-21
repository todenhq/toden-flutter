import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/liveness/face_detection.dart';
import 'package:toden_flutter/src/liveness/response_watch.dart';

// ─── Watching whether the person is responding ───────────────────────────────
//
// The web SDK's liveness/response-watch.test.ts, with the face given as the
// native detectors give it: the head's angles in degrees and the smile and
// eye probabilities, rather than face-mesh points.

LivenessFaceData _face({
  double turn = 0,
  double nod = 0,
  double smile = 0.05,
  double eyes = 0.95,
  double size = 0.45,
}) =>
    LivenessFaceData(
      headEulerAngleX: nod,
      headEulerAngleY: turn,
      headEulerAngleZ: 0,
      smilingProbability: smile,
      leftEyeOpenProbability: eyes,
      rightEyeOpenProbability: eyes,
      faceSizeRatio: size,
    );

void main() {
  test('a still face has not responded, however long it is watched', () {
    final watch = ResponseWatch();
    for (var frame = 0; frame < 300; frame++) {
      watch.seen(_face(), frame * 33);
    }
    expect(watch.respondedAt, 0);
  });

  final attempts = <String, LivenessFaceData>{
    'a turn': _face(turn: 20),
    'a nod': _face(nod: -12),
    'a smile': _face(smile: 0.9),
    'a blink': _face(eyes: 0.1),
  };
  attempts.forEach((name, attempt) {
    test('$name is a response, timed when it was seen', () {
      final watch = ResponseWatch();
      watch.seen(_face(), 0);
      watch.seen(_face(), 33);
      watch.seen(attempt, 66);
      expect(watch.respondedAt, 66);
    });
  });

  test("the detector's jitter is not a response", () {
    final watch = ResponseWatch();
    for (var frame = 0; frame < 120; frame++) {
      final wobble = frame.isEven ? 1.0 : -1.0;
      watch.seen(
        _face(
          turn: 1.5 * wobble,
          nod: 1.2 * wobble,
          smile: 0.05 + 0.05 * (wobble + 1),
          eyes: 0.95 - 0.06 * (wobble + 1),
        ),
        frame * 33,
      );
    }
    expect(watch.respondedAt, 0);
  });

  test('a face that drifts slowly is re-learnt, not taken for an attempt', () {
    final watch = ResponseWatch();
    for (var frame = 0; frame < 400; frame++) {
      watch.seen(_face(turn: frame * 0.1), frame * 33);
    }
    expect(watch.respondedAt, 0);
  });

  test('coming back from a gesture is a response too, and holding it is not',
      () {
    final watch = ResponseWatch();
    watch.seen(_face(), 0);
    watch.seen(_face(turn: 25), 100);
    for (var at = 200; at <= 2000; at += 100) {
      watch.seen(_face(turn: 25), at);
    }
    expect(watch.respondedAt, 100);
    watch.seen(_face(), 2100);
    expect(watch.respondedAt, 2100);
  });

  test('the same gesture counts the same near the camera and far from it', () {
    for (final size in [0.3, 0.65]) {
      final watch = ResponseWatch();
      watch.seen(_face(size: size), 0);
      watch.seen(_face(size: size, smile: 0.9), 50);
      expect(watch.respondedAt, 50);
    }
  });

  test('starts again with nothing known', () {
    final watch = ResponseWatch();
    watch.seen(_face(), 0);
    watch.seen(_face(nod: -12), 40);
    watch.reset();
    expect(watch.respondedAt, 0);
    watch.seen(_face(nod: -12), 80);
    expect(watch.respondedAt, 0);
  });
}
