import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/verification_config.dart';
import 'package:toden_flutter/src/config/workflow_merge.dart';
import 'package:toden_flutter/src/liveness/liveness_types.dart';
import 'package:toden_flutter/src/liveness/narrator_pose.dart';
import 'package:toden_flutter/src/providers/liveness_provider.dart';
import 'package:toden_flutter/src/screens/liveness_gesture_narrator.dart';
import 'package:toden_flutter/src/screens/liveness_narrator_painter.dart';
import 'package:toden_flutter/src/services/api_service.dart';

// ─── The gesture narrator ─────────────────────────────────────────────────────
//
// A face icon that pops up in the camera's window, acts out the gesture once
// and goes; it comes back only when the person has stopped responding for
// 5 seconds, never on a plain timer. The web SDK's GestureNarrator.test.tsx.

const _base = VerificationConfig(apiKey: 'pk_test_x', country: 'NG');

WorkflowFlowConfig _flow(Map<String, dynamic> config) =>
    WorkflowResolution.fromJson({
      'flow': {'id': 'wf_x', 'name': 'Face', 'version': 1},
      'config': {'country': 'NG', ...config},
      'environment': 'SANDBOX',
      'idTypes': <dynamic>[],
    }).config;

class _Clock {
  int now = 0;
  int responded = 0;
}

Widget _host(
  NarratorGesture? gesture,
  _Clock clock, {
  bool still = false,
  int showAgain = 0,
}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: Center(
          child: GestureNarrator(
            gesture: gesture,
            respondedAt: () => clock.responded,
            now: () => clock.now,
            windowWidth: 250,
            showAgain: showAgain,
          ),
        ),
      ),
    );

GestureNarratorState _state(WidgetTester tester) =>
    tester.state<GestureNarratorState>(find.byType(GestureNarrator));

/// Moves the fake clock and the test's timers on together.
Future<void> _wait(WidgetTester tester, _Clock clock, Duration by) async {
  const step = Duration(milliseconds: 100);
  var gone = Duration.zero;
  while (gone < by) {
    clock.now += step.inMilliseconds;
    await tester.pump(step);
    gone += step;
  }
}

void main() {
  group('the head directions', () {
    test('are acted out while asked for', () {
      for (final d in kDirectionChallenges) {
        expect(
          narratedGestureFor(
            LivenessState(
              phase: LivenessPhase.challenge,
              faceDetected: true,
              activeChallenge: d,
            ),
            enabled: true,
          ),
          narratorGestureFor(d),
        );
      }
    });
  });

  group('when it shows', () {
    const challenge = LivenessState(
      phase: LivenessPhase.challenge,
      faceDetected: true,
      activeChallenge: LivenessChallenge.nod,
    );

    test('acts out the gesture being asked for', () {
      expect(narratedGestureFor(challenge, enabled: true), NarratorGesture.nod);
    });

    test('not when the workflow switches it off', () {
      expect(narratedGestureFor(challenge, enabled: false), isNull);
    });

    test('not while the person is asked to move into place, or is out of view',
        () {
      expect(
        narratedGestureFor(challenge.copyWith(positionGuidance: 'too_far'),
            enabled: true),
        isNull,
      );
      expect(
        narratedGestureFor(challenge.copyWith(multipleFaces: true),
            enabled: true),
        isNull,
      );
      expect(
        narratedGestureFor(challenge.copyWith(faceDetected: false),
            enabled: true),
        isNull,
      );
    });

    test('a wrong gesture is when it helps, so it stays', () {
      expect(
        narratedGestureFor(challenge.copyWith(wrongGesture: true),
            enabled: true),
        NarratorGesture.nod,
      );
    });

    test('not for the hold, the passed tick, the capture or a failure', () {
      expect(
        narratedGestureFor(
            challenge.copyWith(activeChallenge: LivenessChallenge.hold),
            enabled: true),
        isNull,
      );
      for (final phase in [
        LivenessPhase.positioning,
        LivenessPhase.challengePassed,
        LivenessPhase.capturing,
        LivenessPhase.complete,
        LivenessPhase.failed,
      ]) {
        expect(
            narratedGestureFor(challenge.copyWith(phase: phase), enabled: true),
            isNull,
            reason: phase.name);
      }
    });
  });

  group('livenessGestureSet and livenessDirectionCount', () {
    test('unset is classic, three directions', () {
      expect(_base.livenessGestureSet, isNull);
      expect(_base.livenessDirectionCount, isNull);
    });

    test('ride a workflow, and a prop stands where the workflow is silent', () {
      final merged = mergeWorkflowIntoConfig(_base,
          _flow({'livenessGestureSet': 'directions', 'livenessDirectionCount': 4}));
      expect(merged.livenessGestureSet, 'directions');
      expect(merged.livenessDirectionCount, 4);
      const prop = VerificationConfig(
          apiKey: 'pk_test_x', livenessGestureSet: 'directions', livenessDirectionCount: 2);
      final silent = mergeWorkflowIntoConfig(prop, _flow({}));
      expect(silent.livenessGestureSet, 'directions');
      expect(silent.livenessDirectionCount, 2);
      // A value this SDK does not know is not taken.
      expect(
          mergeWorkflowIntoConfig(_base, _flow({'livenessGestureSet': 'dance'}))
              .livenessGestureSet,
          isNull);
    });

    test("an applicant workflow's own set governs the applicant's selfie", () {
      const app = ApplicantWorkflow(
        id: 'wf_app',
        name: 'Applicant',
        version: 1,
        config: {
          'country': 'NG',
          'livenessGestureSet': 'directions',
          'livenessDirectionCount': 2,
        },
      );
      final overlaid = overlayApplicantWorkflow(_base, app);
      expect(overlaid.livenessGestureSet, 'directions');
      expect(overlaid.livenessDirectionCount, 2);
    });
  });

  group('livenessGestureGuide', () {
    test('is on by default', () {
      expect(_base.livenessGestureGuide, isTrue);
      expect(_base.copyWith().livenessGestureGuide, isTrue);
    });

    test('rides a workflow: absent leaves it on, only false turns it off', () {
      expect(mergeWorkflowIntoConfig(_base, _flow({})).livenessGestureGuide,
          isTrue);
      expect(
        mergeWorkflowIntoConfig(_base, _flow({'livenessGestureGuide': true}))
            .livenessGestureGuide,
        isTrue,
      );
      expect(
        mergeWorkflowIntoConfig(_base, _flow({'livenessGestureGuide': false}))
            .livenessGestureGuide,
        isFalse,
      );
    });

    test("an applicant workflow's own setting governs the applicant's selfie",
        () {
      const off = ApplicantWorkflow(
        id: 'wf_app',
        name: 'Applicant',
        version: 1,
        config: {'country': 'NG', 'livenessGestureGuide': false},
      );
      expect(
          overlayApplicantWorkflow(_base, off).livenessGestureGuide, isFalse);
      const silent = ApplicantWorkflow(
          id: 'wf_s', name: 'S', version: 1, config: {'country': 'NG'});
      expect(
          overlayApplicantWorkflow(_base, silent).livenessGestureGuide, isTrue);
    });
  });

  testWidgets('pops in, acts the gesture out once, and goes', (tester) async {
    final clock = _Clock();
    await tester.pumpWidget(_host(NarratorGesture.turn, clock));
    await tester.pump();
    expect(_state(tester).showing, isTrue);
    // Sized to the window, solid white, flat.
    expect(tester.getSize(find.byKey(const ValueKey('gesture-narrator'))),
        const Size(150, 150));
    expect(
        find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is NarratorPainter),
        findsOneWidget);

    await _wait(tester, clock, const Duration(milliseconds: 2500));
    expect(_state(tester).showing, isFalse);
    await tester.pumpWidget(_host(null, clock));
    await tester.pumpAndSettle();
  });

  testWidgets('is solid white, the colour of the line round the window',
      (tester) async {
    final clock = _Clock();
    await tester.pumpWidget(_host(NarratorGesture.turnLeft, clock));
    await tester.pump();
    final painter = tester
        .widget<CustomPaint>(find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is NarratorPainter))
        .painter! as NarratorPainter;
    expect(painter.color, const Color(0xFFFFFFFF));
    await tester.pumpWidget(_host(null, clock));
    await tester.pumpAndSettle();
  });

  testWidgets('shows the way again at once when the head went the wrong way',
      (tester) async {
    final clock = _Clock();
    await tester.pumpWidget(_host(NarratorGesture.turnLeft, clock));
    await tester.pump();
    await _wait(tester, clock, const Duration(milliseconds: 2200));
    expect(_state(tester).showing, isFalse);
    // The person is moving (the wrong way), so patience alone would wait.
    clock.responded = clock.now;
    await tester.pumpWidget(_host(NarratorGesture.turnLeft, clock, showAgain: 1));
    await tester.pump();
    expect(_state(tester).showing, isTrue);
    await tester.pumpWidget(_host(null, clock, showAgain: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('comes back only after 5 seconds with no response',
      (tester) async {
    final clock = _Clock();
    await tester.pumpWidget(_host(NarratorGesture.blink, clock));
    await tester.pump();
    // The blink takes 1.5 s, then it goes.
    await _wait(tester, clock, const Duration(milliseconds: 1600));
    expect(_state(tester).showing, isFalse);

    // The person keeps trying: it is left to them.
    for (var i = 0; i < 8; i++) {
      clock.responded = clock.now;
      await _wait(tester, clock, const Duration(seconds: 1));
      expect(_state(tester).showing, isFalse, reason: 'responding, ${i + 1} s');
    }

    // They go quiet (their last move was a second ago): 5 seconds after it,
    // it shows them again.
    await _wait(tester, clock, const Duration(milliseconds: 3500));
    expect(_state(tester).showing, isFalse);
    await _wait(tester, clock, const Duration(milliseconds: 1000));
    expect(_state(tester).showing, isTrue);

    await tester.pumpWidget(_host(null, clock));
    await tester.pumpAndSettle();
  });

  testWidgets('goes at once when the gesture lands', (tester) async {
    final clock = _Clock();
    await tester.pumpWidget(_host(NarratorGesture.smile, clock));
    await tester.pump();
    await _wait(tester, clock, const Duration(milliseconds: 500));
    expect(_state(tester).showing, isTrue);
    await tester.pumpWidget(_host(null, clock));
    expect(_state(tester).showing, isFalse);
    // Quicker to go than it came.
    await tester.pump(const Duration(milliseconds: 200));
    final fade = tester.widget<FadeTransition>(find.descendant(
        of: find.byType(GestureNarrator),
        matching: find.byType(FadeTransition)));
    expect(fade.opacity.value, 0);
    // And it does not come back on a timer.
    await _wait(tester, clock, const Duration(seconds: 10));
    expect(_state(tester).showing, isFalse);
  });

  testWidgets('with less motion: the still pose for 2.5 s, then it fades',
      (tester) async {
    final clock = _Clock();
    await tester.pumpWidget(_host(NarratorGesture.nod, clock, still: true));
    await tester.pump();
    final painter = tester
        .widget<CustomPaint>(find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is NarratorPainter))
        .painter! as NarratorPainter;
    expect(painter.pose.value, narratorStillPose(NarratorGesture.nod));
    await _wait(tester, clock, const Duration(milliseconds: 2400));
    expect(_state(tester).showing, isTrue);
    await _wait(tester, clock, const Duration(milliseconds: 200));
    expect(_state(tester).showing, isFalse);
    await tester.pumpWidget(_host(null, clock, still: true));
    await tester.pumpAndSettle();
  });

  testWidgets('is a picture only, hidden from screen readers', (tester) async {
    final clock = _Clock();
    await tester.pumpWidget(_host(NarratorGesture.turn, clock));
    await tester.pump();
    expect(
      find.descendant(
          of: find.byType(GestureNarrator),
          matching: find.byType(ExcludeSemantics)),
      findsOneWidget,
    );
    await tester.pumpWidget(_host(null, clock));
    await tester.pumpAndSettle();
  });
}
