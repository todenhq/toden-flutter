import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/liveness/gesture_preview_timeline.dart';
import 'package:toden_flutter/src/liveness/toon_face.dart';
import 'package:toden_flutter/src/liveness/toon_shades.dart';
import 'package:toden_flutter/src/screens/liveness_window_line.dart';
import 'package:toden_flutter/src/widgets/gesture_preview.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' as vg;

// ─── The liveness intro's picture ─────────────────────────────────────────────
//
// A cartoon person in a small copy of the camera's window, running through the
// gestures with the line filling one part each and a tick after each. The
// numbers are the web SDK's GesturePreview's.

const _brand = Color(0xFF5645F5);

/// Seconds into the loop, after the coming in.
double _loop(double at) => kPreviewComingIn + at;

void main() {
  group('the timeline', () {
    test(
        'comes in once: faded and back a little, past where it fits, then settles',
        () {
      final start = previewFrameAt(kAllPreviewGestures, 0);
      expect(start.opacity, 0);
      expect(start.scale, closeTo(0.86, 1e-9));
      final scales = [
        for (var t = 0.0; t < kPreviewComingIn; t += 0.02)
          previewFrameAt(kAllPreviewGestures, t).scale,
      ];
      final peak = scales.reduce((a, b) => a > b ? a : b);
      expect(peak, closeTo(1 + kPreviewOvershoot, 0.01));
      final settled = previewFrameAt(kAllPreviewGestures, kPreviewComingIn);
      expect(settled.opacity, 1);
      expect(settled.scale, 1);
    });

    test('runs turn, nod, blink and smile, each filling one part of the line',
        () {
      var at = 0.0;
      for (var i = 0; i < 4; i++) {
        final gesture = kAllPreviewGestures[i];
        final half = previewFrameAt(
            kAllPreviewGestures, _loop(at + kPreviewLength[gesture]! / 2));
        expect(half.progress, closeTo((i + 0.5) / 4, 1e-9),
            reason: gesture.name);
        expect(half.passed, isFalse);
        at += kPreviewLength[gesture]!;
        // The tick waits for the line to be seen to close, then pops up.
        final closing = previewFrameAt(kAllPreviewGestures, _loop(at + 0.05));
        expect(closing.progress, closeTo((i + 1) / 4, 1e-9));
        expect(closing.passed, isFalse);
        final ticked = previewFrameAt(
            kAllPreviewGestures, _loop(at + kPreviewLineCatchUp + 0.05));
        expect(ticked.passed, isTrue, reason: gesture.name);
        at += kPreviewLineCatchUp +
            (i == 3 ? kPreviewTickHold : kPreviewPassHold);
      }
      // After the four, it all goes round again with an empty line.
      final again = previewFrameAt(kAllPreviewGestures, _loop(at + 0.1));
      expect(again.round, 1);
      expect(again.progress, lessThan(0.25));
      expect(again.passed, isFalse);
    });

    test(
        'the turn and the nod move the face; the blink and the smile swap drawings',
        () {
      final turn = [
        for (var t = 0.0; t < 2.4; t += 0.05)
          previewPoseAt(PreviewGesture.turn, t).across,
      ];
      expect(turn.reduce((a, b) => a < b ? a : b), lessThan(-0.95));
      expect(turn.reduce((a, b) => a > b ? a : b), greaterThan(0.95));
      final nod = [
        for (var t = 0.0; t < 2; t += 0.05)
          previewPoseAt(PreviewGesture.nod, t).down,
      ];
      expect(nod.reduce((a, b) => a > b ? a : b), greaterThan(0.95));
      var blinks = 0;
      var was = false;
      for (var t = 0.0; t < 1.5; t += 0.01) {
        final shut = previewPoseAt(PreviewGesture.blink, t).shut;
        if (shut && !was) blinks++;
        was = shut;
      }
      expect(blinks, 2);
      expect(previewPoseAt(PreviewGesture.smile, 0.95).smile, isTrue);
      expect(previewPoseAt(PreviewGesture.smile, 0.1).smile, isFalse);
    });

    test('a passive check holds still while the line closes, then the tick',
        () {
      final half = previewFrameAt(const [], _loop(kPreviewHold / 2));
      expect(half.progress, closeTo(0.5, 1e-9));
      expect(half.pose.across, 0);
      expect(half.pose.down, 0);
      expect(half.pose.shut || half.pose.smile, isFalse);
      final ticked = previewFrameAt(
          const [], _loop(kPreviewHold + kPreviewLineCatchUp + 0.1));
      expect(ticked.passed, isTrue);
      final again = previewFrameAt(const [],
          _loop(kPreviewHold + kPreviewLineCatchUp + kPreviewTickHold + 0.1));
      expect(again.round, 1);
    });
  });

  group('the drawing', () {
    final shades = toonShades(_brand);

    test('every colour is a shade of the brand, mixed as the web mixes them',
        () {
      expect(shades['clothes'], _brand);
      // primary 22% over white
      expect(shades['skin'], Color.lerp(Colors.white, _brand, 0.22));
      // primary 40% over black: dark, so the hair reads as hair (2026-11-17)
      expect(shades['hair'], Color.lerp(Colors.black, _brand, 0.40));
      expect(shades['line'], Color.lerp(Colors.black, _brand, 0.30));
    });

    for (final part in kToonParts.keys) {
      test('$part draws in flutter_svg, with no CSS left in it', () {
        final svg = toonPartSvg(part, shades);
        expect(svg, isNot(contains('var(')));
        expect(svg, isNot(contains('style=')));
        expect(svg, isNot(contains('<mask')));
        final drawn = vg.parse(svg,
            enableClippingOptimizer: false,
            enableMaskingOptimizer: false,
            enableOverdrawOptimizer: false);
        expect(drawn.paths, isNotEmpty);
      });
    }

    test("the smiling mouth's mask is the clip it stands for", () {
      expect(toonPartSvg('mouthSmile', shades),
          contains('<clipPath id="toden-mouthLaugh-a">'));
      expect(toonPartSvg('mouthSmile', shades),
          contains('clip-path="url(#toden-mouthLaugh-a)"'));
    });

    test('keeps the credit to its author', () {
      // The file the strings live in carries the CC BY 4.0 credit; the parts
      // are the web SDK's, unchanged.
      expect(kToonViewBox, '0 0 768 768');
      expect(kToonParts.keys, [
        'back',
        'hairBehind',
        'head',
        'brows',
        'eyesOpen',
        'eyesShut',
        'eyesHappy',
        'mouthRest',
        'mouthSmile',
        'hair',
      ]);
    });
  });

  testWidgets('a small copy of the window, hidden from screen readers',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: GesturePreview()),
    ));
    // The window (176 by 232) with room for the line round it: 7 clear of
    // the window and 6 wide, as on the camera, so 13 each side.
    expect(tester.getSize(find.byType(GesturePreview)), const Size(202, 258));
    final painter = tester
        .widgetList<CustomPaint>(find.descendant(
            of: find.byType(GesturePreview), matching: find.byType(CustomPaint)))
        .map((p) => p.painter)
        .whereType<LivenessWindowLinePainter>()
        .single;
    expect(painter.outside, isTrue);
    expect(painter.segments, 4);
    expect(
      find.descendant(
          of: find.byType(GesturePreview),
          matching: find.byType(ExcludeSemantics)),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with less motion it is still, at rest', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Center(child: GesturePreview()),
      ),
    ));
    // It settles: no ticker runs.
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
