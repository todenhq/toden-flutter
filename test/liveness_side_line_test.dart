import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/liveness/liveness_types.dart';
import 'package:toden_flutter/src/providers/liveness_provider.dart';
import 'package:toden_flutter/src/screens/liveness_instruction_pill.dart';
import 'package:toden_flutter/src/screens/liveness_screen.dart';
import 'package:toden_flutter/src/screens/liveness_window_line.dart';

// ─── The line round the window ───────────────────────────────────────────────
//
// The web SDK's SideRing.test.tsx and window-segments: with head directions
// the line is four sides; the asked side is amber and thicker, a done side
// green, the rest a quiet white; the line closes into one green ring, with one
// pulse, when the run's directions are done. Left and right are the person's
// own, which on the mirrored picture are the screen's. On the full-screen
// camera every line runs 7 outside the window, 6 wide.

const _window = Size(240, 317);

void main() {
  group('where the line runs', () {
    test('outside the window: a 7 gap, then a 6 stroke', () {
      expect(kRingGap, 7);
      expect(kRingStroke, 6);
      final rect = lineRect(_window, kRingOutset);
      // The inside edge of the stroke is the gap away from the window.
      expect(rect.left + kRingStroke / 2, -kRingGap);
      expect(rect.right - kRingStroke / 2, _window.width + kRingGap);
    });

    test('four sides, each centred on its side of the window', () {
      final rect = lineRect(_window, kRingOutset);
      final sides = sideSegments(rect);
      final top = sides[WindowSide.top]!.getBounds();
      final bottom = sides[WindowSide.bottom]!.getBounds();
      final left = sides[WindowSide.left]!.getBounds();
      final right = sides[WindowSide.right]!.getBounds();
      expect(top.center.dx, closeTo(rect.center.dx, 0.5));
      expect(bottom.center.dx, closeTo(rect.center.dx, 0.5));
      expect(left.center.dy, closeTo(rect.center.dy, 0.5));
      expect(right.center.dy, closeTo(rect.center.dy, 0.5));
      expect(top.top, closeTo(rect.top, 0.5));
      expect(left.left, closeTo(rect.left, 0.5));
      // The gaps are at the shoulders: no side runs into the next.
      expect(top.bottom, lessThan(right.top + 1));
      expect(left.right, lessThan(bottom.left + 1));
    });
  });

  group('what each side shows', () {
    test('the asked side lights; a done side stays green', () {
      final states = sideStates(WindowSide.left, const [WindowSide.top]);
      expect(states[WindowSide.left], SideState.asked);
      expect(states[WindowSide.top], SideState.done);
      expect(states[WindowSide.right], SideState.idle);
      expect(sideStates(WindowSide.top, const [WindowSide.top])[WindowSide.top],
          SideState.done);
    });

    test("each direction lights the person's own side, which is the screen's",
        () {
      expect(kSideOf[LivenessChallenge.turnLeft], WindowSide.left);
      expect(kSideOf[LivenessChallenge.turnRight], WindowSide.right);
      expect(kSideOf[LivenessChallenge.lookUp], WindowSide.top);
      expect(kSideOf[LivenessChallenge.lookDown], WindowSide.bottom);
    });

    test('from the state: asked while a direction is asked, done in order', () {
      const state = LivenessState(
        phase: LivenessPhase.challenge,
        faceDetected: true,
        activeChallenge: LivenessChallenge.turnRight,
        completedCount: 1,
        directions: [
          LivenessChallenge.lookUp,
          LivenessChallenge.turnRight,
          LivenessChallenge.lookDown,
        ],
      );
      final sides = sidesFor(state)!;
      expect(sides.asked, WindowSide.right);
      expect(sides.done, [WindowSide.top]);
      expect(sides.run, [WindowSide.top, WindowSide.right, WindowSide.bottom]);
      // Not lit while the person is asked to move back into place.
      expect(sidesFor(LivenessState(
        phase: LivenessPhase.challenge,
        activeChallenge: LivenessChallenge.turnRight,
        positionGuidance: 'too_far',
        directions: state.directions,
      ))!.asked, isNull);
      // Classic gestures keep the line in parts.
      expect(sidesFor(const LivenessState(phase: LivenessPhase.challenge)), isNull);
    });

    test('the colours: white at 70% waiting, amber 10 against 6 asked', () {
      expect(kSideWaiting, const Color(0xB3FFFFFF));
      expect(kSideAttention, const Color(0xFFFFB020));
      expect(kSideLitStroke, 10);
    });
  });

  group('closing', () {
    Widget host(List<WindowSide> done, {bool still = false}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: still),
            child: Center(
              child: SizedBox.fromSize(
                size: _window,
                child: LivenessSideLine(
                  asked: null,
                  done: done,
                  run: const [WindowSide.left, WindowSide.top, WindowSide.bottom],
                ),
              ),
            ),
          ),
        );

    testWidgets("closes when the run's directions are done, not all four",
        (tester) async {
      await tester.pumpWidget(host(const [WindowSide.left, WindowSide.top]));
      expect(tester.widget<LivenessSideLine>(find.byType(LivenessSideLine)).closed,
          isFalse);
      await tester.pumpWidget(
          host(const [WindowSide.left, WindowSide.top, WindowSide.bottom]));
      expect(tester.widget<LivenessSideLine>(find.byType(LivenessSideLine)).closed,
          isTrue);
      // One pulse, then still.
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(kSidePulse + const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('no pulse with less motion', (tester) async {
      await tester.pumpWidget(host(const [WindowSide.left, WindowSide.top], still: true));
      await tester.pump(kSideEase);
      await tester.pumpWidget(host(
          const [WindowSide.left, WindowSide.top, WindowSide.bottom],
          still: true));
      await tester.pump();
      await tester.pump(kSideEase + const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      // The sides' own ease is over and no pulse was started (it would run
      // for kSidePulse, longer than this).
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('is a picture only, hidden from screen readers', (tester) async {
      await tester.pumpWidget(host(const []));
      expect(
        find.descendant(
            of: find.byType(LivenessSideLine),
            matching: find.byType(ExcludeSemantics)),
        findsOneWidget,
      );
    });
  });

  group('the step count with head directions', () {
    testWidgets('is for screen readers only', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: LivenessStepCount(step: 2, total: 3, screenReaderOnly: true),
        ),
      ));
      expect(find.text('Step 2 of 3'), findsNothing);
      expect(find.bySemanticsLabel('Step 2 of 3'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('classic gestures keep the pill on screen', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LivenessStepCount(step: 1, total: 2)),
      ));
      expect(find.text('Step 1 of 2'), findsOneWidget);
    });
  });
}
