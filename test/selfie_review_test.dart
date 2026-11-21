import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:toden_flutter/src/liveness/selfie_review.dart';
import 'package:toden_flutter/src/screens/liveness_cutout.dart';
import 'package:toden_flutter/src/screens/liveness_review_scene.dart';

// ─── The camera frame on the selfie review ───────────────────────────────────
//
// The web SDK's lib/selfie-review.test.ts, on this SDK's phone windows: the
// face always inside the window and at most 0.8 of it, the picture exactly as
// the camera drew it when the face was placed, smaller (never larger) for a
// face held too close, and central where the picture allows.

const _phoneCamera = Size(480, 640);
const _screens = {
  'phone': Size(393, 852),
  'small phone': Size(360, 640),
};
const _faces = {'placed': 0.6, 'close': 0.95, 'very close': 1.3};

double _top(Size frame, Size window) =>
    (frame.height - window.height) / 2 + livenessWindowDrop(frame, window);

ShareBox _faceBox(Size frame, Size scene, double fill,
    {double x = 0.5, double y = 0.5}) {
  final cover = math.max(frame.width / scene.width, frame.height / scene.height);
  final width = fill * livenessCutout(frame).width / (scene.width * cover);
  final height = width * scene.width * 1.3 / scene.height;
  return ShareBox(x: x - width / 2, y: y - height / 2, width: width, height: height);
}

void main() {
  _screens.forEach((name, frame) {
    final window = livenessCutout(frame);
    final top = _top(frame, window);
    final windowLeft = (frame.width - window.width) / 2;
    _faces.forEach((held, share) {
      for (final centre in const [(0.5, 0.5), (0.42, 0.56)]) {
        test('keeps the face inside the window on a $name, face $held, at $centre', () {
          final face = _faceBox(frame, _phoneCamera, share, x: centre.$1, y: centre.$2);
          if (face.x < 0 || face.y < 0 || face.x + face.width > 1 || face.y + face.height > 1) {
            return; // not a frame the camera could give
          }
          final at = sceneOnReview(_phoneCamera, face, frame, window, top);
          final left = at.left + face.x * at.width;
          final up = at.top + face.y * at.height;
          final wide = face.width * at.width;
          final tall = face.height * at.height;
          expect(wide, lessThanOrEqualTo(window.width * kReviewFaceMaxFill + 0.01));
          expect(tall, lessThanOrEqualTo(window.height * kReviewFaceMaxFill + 0.01));
          expect(left, greaterThanOrEqualTo(windowLeft - 0.01));
          expect(left + wide, lessThanOrEqualTo(windowLeft + window.width + 0.01));
          expect(up, greaterThanOrEqualTo(top - 0.01));
          expect(up + tall, lessThanOrEqualTo(top + window.height + 0.01));
        });
      }
    });

    test('shows a $name as the camera did when the face was placed in the window', () {
      final at = sceneOnReview(
          _phoneCamera, _faceBox(frame, _phoneCamera, _faces['placed']!), frame, window, top);
      final cover = math.max(frame.width / _phoneCamera.width, frame.height / _phoneCamera.height);
      expect(at.width, closeTo(_phoneCamera.width * cover, 1e-6));
      expect(uncovered(at, frame), (left: false, right: false, top: false, bottom: false));
    });
  });

  test('makes the picture smaller, never larger, for a face held too close', () {
    const frame = Size(393, 852);
    final window = livenessCutout(frame);
    final face = _faceBox(frame, _phoneCamera, 1.3);
    final at = sceneOnReview(_phoneCamera, face, frame, window, _top(frame, window));
    final cover = math.max(frame.width / _phoneCamera.width, frame.height / _phoneCamera.height);
    expect(at.width, lessThan(_phoneCamera.width * cover));
    // The picture no longer reaches every edge, and the view is told which.
    final gaps = uncovered(at, frame);
    expect(gaps.top && gaps.bottom, isTrue);
  });

  test('moves a face that had drifted back to the centre where the picture allows', () {
    // A frame wider than the screen's shape: there is room to move it across.
    const frame = Size(393, 852);
    const wide = Size(720, 1280);
    final window = livenessCutout(frame);
    final face = _faceBox(frame, wide, 0.6, x: 0.47);
    final at = sceneOnReview(wide, face, frame, window, _top(frame, window));
    expect(at.left + (face.x + face.width / 2) * at.width, closeTo(frame.width / 2, 1e-6));
    final gaps = uncovered(at, frame);
    expect(gaps.left || gaps.right, isFalse);
  });

  test("the detectors' face box is about square in pixels", () {
    final box = faceShareBox(
        centreX: 0.5, centreY: 0.4, width: 0.3, frameWidth: 480, frameHeight: 640);
    expect(box.width * 480, closeTo(box.height * 640, 1e-9));
    expect(box.x + box.width / 2, closeTo(0.5, 1e-9));
    expect(box.y + box.height / 2, closeTo(0.4, 1e-9));
  });

  testWidgets('draws the frame where the placement says, faded where it falls short',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final jpeg = img.encodeJpg(img.Image(width: 48, height: 64));
    final scene = SelfieScene(
      jpeg: jpeg,
      width: 480,
      height: 640,
      face: _faceBox(const Size(393, 852), _phoneCamera, 1.3),
    );
    await tester.pumpWidget(MaterialApp(home: ReviewScene(scene: scene)));
    const frame = Size(393, 852);
    final window = livenessCutout(frame);
    final at = sceneOnReview(_phoneCamera, scene.face, frame, window, _top(frame, window));
    expect(tester.getRect(find.byType(Image)), at);
    expect(find.byType(ShaderMask), findsWidgets);
  });
}
