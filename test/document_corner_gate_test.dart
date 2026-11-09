import 'dart:io';
import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:toden_flutter/src/config/capture_hints.dart';
import 'package:toden_flutter/src/services/document_corner_gate.dart';
import 'package:toden_flutter/src/services/document_corners.dart';
import 'package:toden_flutter/src/services/document_framing_gate.dart';
import 'package:toden_flutter/src/services/document_quad_crop.dart';
import 'package:toden_flutter/src/services/native_document_camera.dart';

const _all = Rect.fromLTRB(0, 0, 1, 1);
const _frame = Size(720, 1280);

DocumentQuad _q(double l, double t, double r, double b) =>
    DocumentQuad.fromList([l, t, r, t, r, b, l, b])!;

final _centred = _q(0.1, 0.35, 0.9, 0.62);
final _cutOff = _q(0.1, 0.6, 0.9, 1.0);

const _holding =
    DocumentGuidance(DocumentFraming.holding, DocumentHint.holdStill);
const _ready = DocumentGuidance(DocumentFraming.ready, DocumentHint.captured);

void main() {
  group('DocumentCornerGate', () {
    test('never blocks before the detector has reported corners', () {
      final gate = DocumentCornerGate();
      expect(gate.state, CornerDetectorState.unknown);
      expect(gate.blocksCapture, isFalse);
      expect(gate.cropQuad, isNull);
    });

    test('blocks a cut-off document and says why', () {
      final gate = DocumentCornerGate()
        ..update(_cutOff, frame: _frame, visible: _all);
      expect(gate.blocksCapture, isTrue);
      expect(gate.hint, DocumentHint.fitCorners);
      expect(gate.cropQuad, isNull);
    });

    test('a passing frame allows the shot and keeps its quad for the crop', () {
      final gate = DocumentCornerGate()
        ..update(_centred, frame: _frame, visible: _all);
      expect(gate.blocksCapture, isFalse);
      expect(gate.cropQuad, same(_centred));
      expect(gate.cropFrame, _frame);
    });

    test('an unreadable frame before any reading does not block', () {
      final gate = DocumentCornerGate();
      gate.markUnknown();
      expect(gate.state, CornerDetectorState.unknown);
      expect(gate.blocksCapture, isFalse);
    });

    test('an unreadable frame from a working detector keeps the block', () {
      // Dropping the rule for one failed frame let the shutter take a
      // document with its corners cut off.
      final gate = DocumentCornerGate()
        ..update(_cutOff, frame: _frame, visible: _all);
      expect(gate.markUnknown(), isFalse);
      expect(gate.blocksCapture, isTrue);
      expect(gate.hint, DocumentHint.fitCorners);
      expect(gate.cropQuad, isNull);
    });

    test('corners outside the visible part of the frame block capture', () {
      // A cover-fitted portrait preview of a wider frame hides its sides: a
      // corner at x 0.05 is in the frame but not on screen.
      final visible = visibleFrameRegion(
          const Size(1080, 1920), const Size(440, 956));
      final gate = DocumentCornerGate()
        ..update(_q(0.05, 0.2, 0.6, 0.75), frame: _frame, visible: visible);
      expect(gate.blocksCapture, isTrue);
      expect(gate.hint, DocumentHint.fitCorners);
      expect(
        gate.apply(_ready, resetDwell: () {}).framing,
        DocumentFraming.adjust,
      );
    });

    test('a box found far bigger than the guide blocks: the slip runs off', () {
      // The slip is cut off at the frame's edges and Vision finds the bordered
      // table printed on it, whose corners are all in view.
      const guide = Rect.fromLTRB(0.25, 0.18, 0.75, 0.75);
      final table = _q(0.12, 0.1, 0.88, 0.9);
      final gate = DocumentCornerGate()
        ..update(table, frame: _frame, visible: _all, guide: guide);
      expect(gate.blocksCapture, isTrue);
      expect(gate.hint, DocumentHint.spaceAround);
      expect(gate.cropQuad, isNull);
    });

    test('a slip filling its guide passes the guide check', () {
      const guide = Rect.fromLTRB(0.25, 0.18, 0.75, 0.75);
      final slip = _q(0.24, 0.17, 0.76, 0.77);
      final gate = DocumentCornerGate()
        ..update(slip, frame: _frame, visible: _all, guide: guide);
      expect(gate.blocksCapture, isFalse);
      expect(gate.cropQuad, same(slip));
    });

    test('a device without a detector is never blocked', () {
      final gate = DocumentCornerGate()..markUnavailable();
      gate.markUnknown();
      expect(gate.state, CornerDetectorState.unavailable);
      expect(gate.blocksCapture, isFalse);
    });

    test('reset holds the shutter until the next frame passes', () {
      final gate = DocumentCornerGate()
        ..update(_centred, frame: _frame, visible: _all)
        ..reset();
      expect(gate.blocksCapture, isTrue);
      expect(gate.hint, DocumentHint.placeInFrame);
    });

    test('apply holds back a ready gate and restarts its dwell', () {
      final gate = DocumentCornerGate()
        ..update(_q(0.02, 0.3, 0.9, 0.6), frame: _frame, visible: _all);
      var resets = 0;
      final out = gate.apply(_ready, resetDwell: () => resets++);
      expect(out.framing, DocumentFraming.adjust);
      expect(out.hint, DocumentHint.spaceAround);
      expect(resets, 1);
      expect(gate.apply(_holding, resetDwell: () => resets++).framing,
          DocumentFraming.adjust);
    });

    test('apply leaves other verdicts and passing corners alone', () {
      final failing = DocumentCornerGate()
        ..update(null, frame: _frame, visible: _all);
      const wrong =
          DocumentGuidance(DocumentFraming.wrongShape, DocumentHint.wrongDocument);
      expect(failing.apply(wrong, resetDwell: () => fail('no reset')), same(wrong));
      final passing = DocumentCornerGate()
        ..update(_centred, frame: _frame, visible: _all);
      expect(passing.apply(_ready, resetDwell: () => fail('no reset')), same(_ready));
    });
  });

  group('corner hints', () {
    test('say what to do, in plain words', () {
      expect(documentHintText(DocumentHint.placeInFrame, label: 'passport'),
          'Place your ID inside the frame');
      expect(documentHintText(DocumentHint.fitCorners, label: 'passport'),
          'Fit all four corners of your ID inside the frame');
      expect(documentHintText(DocumentHint.spaceAround, label: 'passport'),
          'Move back a little so there is space around your ID');
      for (final h in [
        DocumentHint.placeInFrame,
        DocumentHint.fitCorners,
        DocumentHint.spaceAround,
      ]) {
        expect(documentHintIsAction(h), isTrue);
        expect(documentHintText(h, label: 'ID').contains('—'), isFalse);
      }
    });
  });

  group('cropping the still to the quad', () {
    test('a still the same shape as the stream maps one to one', () {
      final crop = quadCropInStill(_centred, const Size(1080, 1920), 720 / 1280);
      expect(crop, bleedCropRect(_centred, const Size(1080, 1920)));
    });

    test('a 16:9 stream inside a 4:3 still is the still\'s centre band', () {
      // Upright: stream 9:16, still 3:4 of the same width.
      final region = streamRegionInStill(const Size(900, 1200), 9 / 16);
      expect(region.left, closeTo(0.125, 1e-9));
      expect(region.width, closeTo(0.75, 1e-9));
      expect(region.top, 0);
    });

    test('crops a real image with space past every corner', () async {
      final still = img.Image(width: 720, height: 1280);
      final bytes = img.encodeJpg(still);
      final out = await cropToDocumentQuad(bytes, _centred, frameSize: _frame);
      final decoded = img.decodeImage(out!)!;
      final expected = bleedCropRect(_centred, _frame);
      expect(decoded.width, expected.width);
      expect(decoded.height, expected.height);
    });
  });

  group('native frame events', () {
    test('carry the corners and the frame size', () {
      final f = NativeDocumentCamera.parseFrame({
        'lines': ['A'],
        'quadSupported': true,
        'quad': [0.1, 0.35, 0.9, 0.35, 0.9, 0.62, 0.1, 0.62],
        'frameW': 720.0,
        'frameH': 1280.0,
      });
      expect(f.quadSupported, isTrue);
      expect(f.quad!.bottomRight.dy, 0.62);
      expect(f.frameSize, _frame);
    });

    test('without the detector fields mean "cannot tell"', () {
      final f = NativeDocumentCamera.parseFrame({'lines': <String>[]});
      expect(f.quadSupported, isFalse);
      expect(f.quad, isNull);
    });
  });

  group('capture screen wiring', () {
    final src =
        File('lib/src/screens/document_capture_screen.dart').readAsStringSync();

    test('the manual shutter waits for the corners', () {
      expect(src, contains('!_isCapturing && !_corners.blocksCapture'));
      expect(src, contains('shutterDisabledReason:'));
    });

    test('both auto-capture paths go through the corners rule', () {
      expect(src, contains('resetDwell: _gate.reset'));
      expect(src, contains('resetDwell: _textGate.reset'));
    });

    test('the still is cropped to the passing quad when there is one', () {
      expect(src, contains('cropToDocumentQuad(bytes, cropQuad'));
    });
  });
}
