import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/i18n/translate.dart';
import 'package:toden_flutter/src/liveness/face_detection.dart';
import 'package:toden_flutter/src/liveness/selfie_candidates.dart';
import 'package:toden_flutter/src/liveness/selfie_pick.dart';
import 'package:toden_flutter/src/liveness/selfie_shutter.dart';

// Choosing the selfie from the live run. Mirrors the web SDK's
// lib/selfie-pick.test.ts; the pose here is the native detector's Euler
// angles in degrees rather than a landmark estimate.

LivenessFaceData face({
  double yaw = 0,
  double pitch = 0,
  double roll = 0,
  double eyes = 0.9,
  double width = 0.4,
  double cx = 0.5,
  double cy = 0.5,
}) =>
    LivenessFaceData(
      headEulerAngleX: pitch,
      headEulerAngleY: yaw,
      headEulerAngleZ: roll,
      smilingProbability: 0,
      leftEyeOpenProbability: eyes,
      rightEyeOpenProbability: eyes,
      faceSizeRatio: width,
      faceCenterX: cx,
      faceCenterY: cy,
    );

/// A box (x, y, width, height, normalised) as its centre and width.
SelfieFace box(double x, double y, double w, double h) =>
    SelfieFace(centreX: x + w / 2, centreY: y + h / 2, width: w);

void main() {
  group('choosing the selfie', () {
    test('reads a straight-on face as frontal', () {
      expect(isFrontal(SelfiePose.of(face())), isTrue);
    });

    test('rejects a head still turned after "turn your head"', () {
      expect(isFrontal(SelfiePose.of(face(yaw: 14))), isFalse);
    });

    test('rejects a nod and a tilt', () {
      expect(isFrontal(SelfiePose.of(face(pitch: -13))), isFalse);
      expect(isFrontal(SelfiePose.of(face(roll: 12))), isFalse);
    });

    test('on iPhone, pitch and roll count from the run\'s resting pose', () {
      // Vision's roll carries the camera's orientation: a resting head reads
      // far from zero, and is still frontal against the run's own rest.
      final zero = SelfieAngleZero(fromRun: true);
      for (var i = 0; i < 20; i++) {
        zero.add(face(pitch: 6, roll: 95));
      }
      final pose = SelfiePose.of(face(pitch: 8, roll: 97), pitchZero: zero.pitch, rollZero: zero.roll);
      expect(isFrontal(pose), isTrue);
      expect(isFrontal(SelfiePose.of(face(pitch: 8, roll: 97))), isFalse);
      // Android reports a true zero: nothing is learned.
      final android = SelfieAngleZero(fromRun: false)..add(face(roll: 40));
      expect(android.roll, 0);
    });

    test('wants both eyes open', () {
      expect(eyesOpen(face(eyes: 0.8)), isTrue);
      expect(eyesOpen(face(eyes: 0.3)), isFalse);
    });

    test('scores a squarer, sharper frame higher', () {
      final straight = SelfiePose.of(face());
      final turned = SelfiePose.of(face(yaw: 4));
      expect(selfieScore(straight, 80), greaterThan(selfieScore(turned, 80)));
      expect(selfieScore(straight, 100), greaterThan(selfieScore(straight, 20)));
      // Unmeasured sharpness: the pose alone decides.
      expect(selfieScore(straight, null), greaterThan(selfieScore(turned, null)));
    });

    test('cuts a 3:4 frame with the face at its set share of the width', () {
      // A phone's portrait camera.
      final rect = selfieFrame(box(0.3, 0.3, 0.4, 0.25), 1080, 1920)!;
      expect(rect.width / rect.height, closeTo(0.75, 0.01));
      expect((0.4 * 1080) / rect.width, closeTo(kSelfieFaceShare, 0.01));
      expect(rect.x, greaterThanOrEqualTo(0));
      expect(rect.y + rect.height, lessThanOrEqualTo(1920));
    });

    test('on a short landscape camera, the tallest 3:4 frame that fits', () {
      final rect = selfieFrame(box(0.4, 0.3, 0.2, 0.3), 1920, 1080)!;
      expect(rect.height, 1080);
      expect(rect.width, 810);
    });

    test('keeps the frame inside the camera, moving it rather than squeezing', () {
      final rect = selfieFrame(box(0.02, 0.02, 0.2, 0.3), 1280, 960)!;
      expect(rect.x, 0);
      expect(rect.y, 0);
      expect(rect.width / rect.height, closeTo(0.75, 0.01));
    });

    test('says a face too far away is no selfie, rather than enlarging it', () {
      expect(selfieFrame(box(0.45, 0.4, 0.08, 0.12), 1280, 720), isNull);
      // A still taken without a candidate is still cut, never enlarged.
      final small = selfieFrame(box(0.45, 0.4, 0.08, 0.12), 1280, 720, allowSmall: true)!;
      expect(selfieOutputSize(small).width, small.width);
    });

    test('the output is at most 720 wide and never enlarged', () {
      expect(selfieOutputSize(const PixelRect(0, 0, 1080, 1440)), (width: 720, height: 960));
      expect(selfieOutputSize(const PixelRect(0, 0, 600, 800)), (width: 600, height: 800));
    });

    test('mirrors the frame for the mirrored still', () {
      expect(mirrorRect(const PixelRect(100, 0, 300, 400), 1000).x, 600);
    });

    test('moves the detector\'s face into the still the SDK encodes', () {
      final f = face(cx: 0.3, cy: 0.4);
      // Android: ML Kit's upright frame, the still mirrored.
      final android = SelfieFace.inStill(f, ios: false);
      expect(android.centreX, closeTo(0.7, 1e-9));
      expect(android.centreY, 0.4);
      // iOS: Vision un-mirrors the buffer and counts y from the bottom.
      final ios = SelfieFace.inStill(f, ios: true);
      expect(ios.centreX, closeTo(0.7, 1e-9));
      expect(ios.centreY, closeTo(0.6, 1e-9));
    });

    test('steady only once the face has stayed put for the window', () {
      final s = SelfieSteadiness();
      final t0 = DateTime(2026, 11, 8, 12);
      DateTime at(int ms) => t0.add(Duration(milliseconds: ms));
      s.add(face(), at(0));
      expect(s.steady, isFalse);
      s.add(face(cx: 0.51), at(150));
      expect(s.steady, isFalse);
      s.add(face(cx: 0.49, width: 0.41, yaw: 3), at(300));
      expect(s.steady, isTrue);
      // A tenth of the face's width across, a lunge or a head turn is moving.
      s.add(face(cx: 0.55), at(400));
      expect(s.steady, isFalse);
      s.add(face(cx: 0.55, width: 0.46), at(500));
      expect(s.steady, isFalse);
      s.add(face(cx: 0.55, width: 0.46, yaw: 10), at(600));
      expect(s.steady, isFalse);
      // Held again for the window: steady.
      s.add(face(cx: 0.55, width: 0.46, yaw: 10), at(900));
      expect(s.steady, isTrue);
      s.clear();
      expect(s.steady, isFalse);
    });

    test('a detector without a centre is judged on size and turn', () {
      final s = SelfieSteadiness();
      final t0 = DateTime(2026, 11, 8, 12);
      LivenessFaceData noCentre({double width = 0.4}) => LivenessFaceData(
            headEulerAngleX: 0,
            headEulerAngleY: 0,
            headEulerAngleZ: 0,
            smilingProbability: 0,
            leftEyeOpenProbability: 0.9,
            rightEyeOpenProbability: 0.9,
            faceSizeRatio: width,
          );
      s.add(noCentre(), t0);
      s.add(noCentre(), t0.add(const Duration(milliseconds: 300)));
      expect(s.steady, isTrue);
      s.add(noCentre(width: 0.5), t0.add(const Duration(milliseconds: 400)));
      expect(s.steady, isFalse);
    });

    test('measures sharpness on the frame, flat being zero', () {
      final flat = Uint8List(64 * 64 * 4)..fillRange(0, 64 * 64 * 4, 128);
      expect(bgraSharpness(flat, 64 * 4, const PixelRect(0, 0, 48, 64)), 0);
      final noisy = Uint8List.fromList([for (var i = 0; i < 64 * 64 * 4; i++) (i * 97) % 256]);
      expect(bgraSharpness(noisy, 64 * 4, const PixelRect(0, 0, 48, 64)), greaterThan(0));
    });
  });

  group('the run\'s best frame', () {
    // Each frame is offered after the face has held still in it for longer
    // than the steadiness window, as a steady face's frames are.
    var clock = DateTime(2026, 11, 8, 12);
    void hold(SelfieCandidates<String> c, LivenessFaceData f) {
      for (var i = 0; i < 5; i++) {
        clock = clock.add(const Duration(milliseconds: 100));
        c.observe(f, at: clock);
      }
    }

    SelfieVerdict offer(SelfieCandidates<String> c, LivenessFaceData f, String id) {
      hold(c, f);
      return c.consider(
        f,
        inStill: SelfieFace.inStill(f, ios: false),
        frameWidth: 1080,
        frameHeight: 1920,
        grab: () => id,
      );
    }

    test('keeps the squarest frame and says why others were not kept', () {
      final c = SelfieCandidates<String>(poseZeroFromRun: false);
      expect(offer(c, face(yaw: 5), 'a'), SelfieVerdict.kept);
      expect(offer(c, face(yaw: 1), 'b'), SelfieVerdict.kept);
      expect(offer(c, face(yaw: 6), 'c'), SelfieVerdict.worse);
      expect(offer(c, face(yaw: 20), 'd'), SelfieVerdict.turned);
      expect(offer(c, face(width: 0.1), 'e'), SelfieVerdict.far);
      expect(offer(c, face(eyes: 0.1), 'f'), SelfieVerdict.eyes);
      expect(c.best!.frame, 'b');
    });

    test('a frame from mid-movement is not kept, however straight', () {
      // The user report of 2026-11-08: the phone swung into place, the face
      // passing straight through the frame, and that smeared frame was kept.
      final c = SelfieCandidates<String>(poseZeroFromRun: false);
      var t = DateTime(2026, 11, 8, 12);
      SelfieVerdict at(LivenessFaceData f, int ms) {
        t = t.add(Duration(milliseconds: ms));
        c.observe(f, at: t);
        return c.consider(f,
            inStill: SelfieFace.inStill(f, ios: true),
            frameWidth: 720,
            frameHeight: 1280,
            grab: () => 'swing');
      }

      // The first frame of a run has nothing to be steady against.
      expect(at(face(cx: 0.30), 0), SelfieVerdict.moving);
      expect(at(face(cx: 0.40), 70), SelfieVerdict.moving);
      expect(at(face(cx: 0.50), 70), SelfieVerdict.moving);
      expect(at(face(cx: 0.60), 70), SelfieVerdict.moving);
      expect(c.best, isNull);
      // Settled: once it has held for the window, the frame is a candidate.
      expect(at(face(cx: 0.51), 70), SelfieVerdict.moving);
      expect(at(face(cx: 0.51), 70), SelfieVerdict.moving);
      expect(at(face(cx: 0.51), 70), SelfieVerdict.moving);
      expect(at(face(cx: 0.51), 70), SelfieVerdict.moving);
      expect(at(face(cx: 0.51), 70), SelfieVerdict.moving);
      expect(at(face(cx: 0.51), 70), SelfieVerdict.kept);
      expect(selfieGuidanceFor(SelfieVerdict.moving), SelfieGuidance.holdStill);
    });

    test('a broken run forgets it', () {
      final c = SelfieCandidates<String>(poseZeroFromRun: false);
      offer(c, face(), 'a');
      c.clear();
      expect(c.best, isNull);
    });

    test('a frame it cannot afford to grab is judged, not kept', () {
      final c = SelfieCandidates<String>(poseZeroFromRun: false);
      hold(c, face());
      final v = c.consider(face(),
          inStill: SelfieFace.inStill(face(), ios: false),
          frameWidth: 1080,
          frameHeight: 1920,
          grab: () => 'x',
          admit: false);
      expect(v, SelfieVerdict.worse);
      expect(c.best, isNull);
    });
  });

  group('the final capture', () {
    final t0 = DateTime(2026, 11, 8, 12);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('takes the shot after half a second of usable frames', () {
      final s = SelfieShutter(t0);
      s.feed(SelfieVerdict.kept, at(100));
      expect(s.decide(at(400), hasBest: true), SelfieShutterCall.wait);
      s.feed(SelfieVerdict.worse, at(500));
      expect(s.decide(at(650), hasBest: true), SelfieShutterCall.useBest);
    });

    test('a turned frame restarts the hold', () {
      final s = SelfieShutter(t0);
      s.feed(SelfieVerdict.kept, at(100));
      s.feed(SelfieVerdict.turned, at(500));
      expect(s.decide(at(700), hasBest: true), SelfieShutterCall.wait);
    });

    test('after four seconds the run\'s best frame stands in', () {
      final s = SelfieShutter(t0);
      expect(s.decide(at(3900), hasBest: true), SelfieShutterCall.wait);
      expect(s.decide(at(4000), hasBest: true), SelfieShutterCall.useBest);
      expect(s.decide(at(4000), hasBest: false), SelfieShutterCall.wait);
      expect(s.decide(at(10000), hasBest: false), SelfieShutterCall.fallback);
    });

    test('a face gone for a second breaks the run', () {
      final s = SelfieShutter(t0);
      expect(s.faceLost(at(900), null), isFalse);
      expect(s.faceLost(at(1100), null), isTrue);
      expect(s.faceLost(at(1900), at(1000)), isFalse);
      expect(s.faceLost(at(2100), at(1000)), isTrue);
    });

    test('says what to fix', () {
      expect(selfieGuidanceFor(SelfieVerdict.turned), SelfieGuidance.lookStraight);
      expect(selfieGuidanceFor(SelfieVerdict.far), SelfieGuidance.moveCloser);
      expect(selfieGuidanceFor(SelfieVerdict.kept), isNull);
      expect(defaultTextFn('presence.position.lookStraight'), 'Kindly look straight at the camera');
      expect(defaultTextFn('presence.position.moveCloser'), 'Kindly move closer');
    });
  });
}
