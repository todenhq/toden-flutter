import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/document_guide.dart';
import 'package:toden_flutter/src/services/document_corner_gate.dart';
import 'package:toden_flutter/src/services/document_corners.dart';
import 'package:toden_flutter/src/services/native_document_camera.dart';

// The corners rule on an Android phone, in the phone's own geometry: a Galaxy
// S24 held upright (a 360 x 780 viewfinder), the back sensor mounted landscape
// (CameraX reports 90, or 270 on some phones) and the preview cover-fitted to
// the screen. The native camera turns each analysed frame upright before it
// looks for corners (DocumentBorderDetector.kt) and reports the upright size as
// frameW x frameH; these tests carry sensor points through that same turn and
// judge them in the part of the upright frame the screen shows, as
// document_capture_screen.dart does.

const _view = Size(360, 780);

/// The detector's turn: a sensor pixel to the normalised upright frame.
Offset _sensorToUpright(Offset p, Size sensor, int rotation) => rotation == 90
    ? Offset((sensor.height - p.dy) / sensor.height, p.dx / sensor.width)
    : Offset(p.dy / sensor.height, (sensor.width - p.dx) / sensor.width);

/// Where the sensor sees a point of the upright frame (the inverse turn).
Offset _uprightToSensor(Offset u, Size sensor, int rotation) => rotation == 90
    ? Offset(u.dy * sensor.width, sensor.height - u.dx * sensor.height)
    : Offset(sensor.width - u.dy * sensor.width, u.dx * sensor.height);

/// The native payload for a document at [upright] (frame shares), found in a
/// [sensor] frame turned by [rotation]: as DocumentCamera.kt sends it.
RecognizedFrame _frame(Rect upright, Size sensor, int rotation) {
  final corners = [
    upright.topLeft,
    upright.topRight,
    upright.bottomRight,
    upright.bottomLeft,
  ].map((u) => _sensorToUpright(
      _uprightToSensor(u, sensor, rotation), sensor, rotation));
  final xs = corners.map((c) => c.dx).toList();
  final ys = corners.map((c) => c.dy).toList();
  double lo(List<double> v) => v.reduce((a, b) => a < b ? a : b);
  double hi(List<double> v) => v.reduce((a, b) => a > b ? a : b);
  final l = lo(xs), r = hi(xs), t = lo(ys), b = hi(ys);
  return NativeDocumentCamera.parseFrame({
    'lines': <String>[],
    'quadSupported': true,
    // A quarter turn swaps the sides.
    'frameW': sensor.height,
    'frameH': sensor.width,
    'quad': [l, t, r, t, r, b, l, b],
  });
}

/// The corners rule exactly as the capture screen applies it to a frame.
DocumentCornersProblem? _judge(RecognizedFrame f, {Rect? guide}) {
  final gate = DocumentCornerGate();
  final visible = visibleFrameRegion(f.frameSize, _view);
  gate.update(
    f.quad,
    frame: f.frameSize,
    visible: visible,
    guide: guide == null ? null : guideInFrame(guide, _view, visible),
  );
  return gate.problem;
}

void main() {
  // The upright NIN slip's guide as drawn on the S24, under its status bar and
  // above its gesture bar.
  final slipGuide = documentGuideRect(
    _view,
    1 / 2.07,
    band: documentGuideBand(topInset: 40, bottomInset: 24),
  );

  group('the turn from the sensor frame to the upright frame', () {
    for (final rotation in [90, 270]) {
      test('puts a sensor point where the upright frame shows it ($rotation)',
          () {
        const s = Size(1280, 720);
        expect(
          _sensorToUpright(Offset.zero, s, rotation),
          rotation == 90 ? const Offset(1, 0) : const Offset(0, 1),
        );
        expect(_sensorToUpright(const Offset(640, 360), s, rotation),
            const Offset(0.5, 0.5));
      });
    }

    test(
        'the payload reports the upright size, so the screen judges a portrait frame',
        () {
      final f = _frame(
          const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8), const Size(1280, 720), 90);
      expect(f.frameSize, const Size(720, 1280));
    });
  });

  group('the part of the frame an upright S24 shows', () {
    test('a 16:9 frame: its middle 82% across, all of its height', () {
      final v = visibleFrameRegion(const Size(720, 1280), _view);
      expect(v.left, closeTo(0.0897, 1e-3));
      expect(v.right, closeTo(0.9103, 1e-3));
      expect(v.top, 0);
      expect(v.bottom, 1);
    });

    test('a 4:3 frame: its middle 62% across', () {
      final v = visibleFrameRegion(const Size(960, 1280), _view);
      expect(v.width, closeTo(0.615, 1e-3));
    });
  });

  for (final sensor in const [Size(1280, 720), Size(1280, 960)]) {
    final name = sensor.width / sensor.height > 1.5 ? '16:9' : '4:3';
    group('a $name sensor', () {
      final visible =
          visibleFrameRegion(Size(sensor.height, sensor.width), _view);
      // A slip sitting in the drawn guide, in upright frame shares.
      final inGuide = guideInFrame(slipGuide, _view, visible)!;

      for (final rotation in [90, 270]) {
        test('passes a slip in the guide ($rotation)', () {
          expect(_judge(_frame(inGuide, sensor, rotation), guide: slipGuide),
              isNull);
        });

        test(
            'refuses a slip whose side is off the screen though in the frame ($rotation)',
            () {
          final shift = visible.right + (1 - visible.right) / 2 - inGuide.right;
          final off = inGuide.shift(Offset(shift, 0));
          expect(off.right, lessThan(1));
          expect(_judge(_frame(off, sensor, rotation), guide: slipGuide),
              DocumentCornersProblem.cornerCutOff);
        });

        test(
            'refuses a slip whose bottom runs to the edge of the screen ($rotation)',
            () {
          final low = Rect.fromLTRB(
              inGuide.left, inGuide.top + 0.2, inGuide.right, 0.999);
          expect(_judge(_frame(low, sensor, rotation), guide: slipGuide),
              DocumentCornersProblem.cornerCutOff);
        });

        test('calls a box far taller than the guide too close ($rotation)', () {
          // In view with space round it, but 1.2 times the guide's height: the
          // slip runs off the picture and this is a box printed on it.
          final cy = inGuide.center.dy;
          final hh = inGuide.height / 2 * 1.2;
          final big =
              Rect.fromLTRB(inGuide.left, cy - hh, inGuide.right, cy + hh);
          expect(_judge(_frame(big, sensor, rotation)), isNull);
          expect(_judge(_frame(big, sensor, rotation), guide: slipGuide),
              DocumentCornersProblem.tooClose);
        });
      }
    });
  }

  test('a frame that could not be read keeps the block (and the pass) it had',
      () {
    final gate = DocumentCornerGate();
    final f = _frame(
        const Rect.fromLTRB(0.3, 0.2, 0.95, 0.8), const Size(1280, 720), 90);
    final visible = visibleFrameRegion(f.frameSize, _view);
    gate.update(f.quad, frame: f.frameSize, visible: visible);
    expect(gate.blocksCapture, isTrue);
    gate.markUnknown();
    expect(gate.blocksCapture, isTrue);
  });
}
