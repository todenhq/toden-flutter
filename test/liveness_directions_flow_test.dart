import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/verification_config.dart';
import 'package:toden_flutter/src/liveness/capture_pose.dart';
import 'package:toden_flutter/src/liveness/direction_plan.dart';
import 'package:toden_flutter/src/liveness/face_detection.dart';
import 'package:toden_flutter/src/liveness/flash_ready_gate.dart';
import 'package:toden_flutter/src/liveness/liveness_types.dart';
import 'package:toden_flutter/src/providers/liveness_provider.dart';
import 'package:toden_flutter/src/providers/verification_provider.dart';

// ─── Core's gesture plan, through the liveness state machine ─────────────────
//
// The web SDK's useLiveness: the "Hold still" pause before the first gesture,
// one plan request per attempt to Core, the SDK's own pick standing in until
// the plan arrives, the plan used only if the first instruction has not been
// given, an answer for an earlier attempt ignored, and the first instruction
// waiting up to 2.5 s for a pending plan.

LivenessFaceData _face({double yaw = 0, double pitch = 0}) => LivenessFaceData(
      headEulerAngleX: pitch,
      headEulerAngleY: yaw,
      headEulerAngleZ: 0,
      smilingProbability: 0,
      leftEyeOpenProbability: 1,
      rightEyeOpenProbability: 1,
      faceSizeRatio: 0.4,
      faceCenterX: 0.5,
      faceCenterY: 0.5,
    );

const _plan = DirectionPlan(
  planId: 'clx0plan0001',
  prompts: [LivenessChallenge.lookUp, LivenessChallenge.turnRight],
);

class _Run {
  _Run({
    String gestureSet = 'directions',
    String mode = 'gestures',
    bool asks = true,
    LivenessConfig? livenessConfig,
  }) {
    container = ProviderContainer(overrides: [
      verificationConfigProvider.overrideWithValue(VerificationConfig(
        apiKey: 'pk_test_x',
        livenessGestureSet: gestureSet,
        livenessMode: mode,
        livenessConfig: livenessConfig,
      )),
      directionPlanRequestProvider.overrideWithValue(asks
          ? (plan) {
              requests.add(plan.toJson());
              final answer = Completer<DirectionPlan?>();
              answers.add(answer);
              return answer.future;
            }
          : null),
    ]);
    container.listen(livenessNotifierProvider, (_, __) {});
    notifier.clock = () => now;
  }

  late final ProviderContainer container;
  final List<Completer<DirectionPlan?>> answers = [];
  final List<Map<String, Object>> requests = [];
  int now = 0;

  LivenessNotifier get notifier =>
      container.read(livenessNotifierProvider.notifier);
  LivenessState get state => container.read(livenessNotifierProvider);

  /// One frame of [face] at [at] milliseconds.
  void frame(int at, [LivenessFaceData? face]) {
    now = at;
    notifier.processFrame(face ?? _face());
  }

  void dispose() => container.dispose();
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// Holds a face in place through the flash gate's dwell, which runs on the
/// wall clock, with frames close enough that the face never reads as gone.
/// Every frame is at [at] on the plan's clock.
Future<void> _holdForFlash(_Run run, int at) async {
  final until = DateTime.now().add(kFlashReadyDwell);
  while (DateTime.now().isBefore(until)) {
    run.frame(at);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  run.frame(at);
}

void main() {
  test('holds still for a moment before the first gesture', () {
    final run = _Run(asks: false);
    addTearDown(run.dispose);
    run.notifier.startDetection();
    run.frame(0);
    expect(run.state.phase, LivenessPhase.positioning);
    expect(run.state.instruction, kHoldStillInstruction);
    run.frame(1000);
    expect(run.state.phase, LivenessPhase.positioning);
    expect(run.state.readyProgress, closeTo(2 / 3, 0.02));
    run.frame(1500);
    expect(run.state.phase, LivenessPhase.challenge);
    expect(isDirectionChallenge(run.state.activeChallenge), isTrue);
    expect(run.notifier.directionPlanId, isNull);
  });

  test("moving out of place starts the pause again", () {
    final run = _Run(asks: false);
    addTearDown(run.dispose);
    run.notifier.startDetection();
    run.frame(0);
    run.frame(1200, _face().copyWithSize(0.26)); // too far: out of place
    expect(run.state.instruction, isNot(kHoldStillInstruction));
    run.frame(1300);
    run.frame(2700);
    expect(run.state.phase, LivenessPhase.positioning);
    run.frame(2800);
    expect(run.state.phase, LivenessPhase.challenge);
  });

  test("asks Core once per attempt, and asks exactly its directions in its order",
      () async {
    final run = _Run();
    addTearDown(run.dispose);
    run.notifier.startDetection();
    expect(run.requests, [
      {'count': 3, 'set': 'directions'},
    ]);
    run.answers.single.complete(_plan);
    await _settle();
    expect(run.state.directions, _plan.prompts);
    run.frame(0);
    run.frame(1500);
    expect(run.state.activeChallenge, LivenessChallenge.lookUp);
    expect(run.notifier.directionPlanId, 'clx0plan0001');
    expect(run.notifier.challengesRun, _plan.prompts);
  });

  test('the first instruction waits for a pending plan, then takes it', () async {
    final run = _Run();
    addTearDown(run.dispose);
    run.notifier.startDetection();
    run.frame(0);
    run.frame(1600); // the pause is over, but the plan is on its way
    expect(run.state.phase, LivenessPhase.positioning);
    expect(run.state.instruction, kHoldStillInstruction);
    run.answers.single.complete(_plan);
    await _settle();
    run.frame(1700);
    run.frame(3200);
    expect(run.state.activeChallenge, LivenessChallenge.lookUp);
    expect(run.notifier.directionPlanId, 'clx0plan0001');
  });

  test('without an answer in 2.5 s the SDK picks its own and names no plan',
      () async {
    final run = _Run();
    addTearDown(run.dispose);
    run.notifier.startDetection();
    run.frame(0);
    run.frame(1500); // waits: 1.5 s of 2.5
    run.frame(1600);
    run.frame(3100); // past 2.5 s
    expect(run.state.phase, LivenessPhase.challenge);
    final own = run.notifier.challengesRun;
    // The plan arrives late: the directions never change once asking began.
    run.answers.single.complete(_plan);
    await _settle();
    expect(run.notifier.challengesRun, own);
    expect(run.notifier.directionPlanId, isNull);
  });

  test("Core with no plan (an older Core) leaves the SDK's pick, unnamed",
      () async {
    final run = _Run();
    addTearDown(run.dispose);
    run.notifier.startDetection();
    run.answers.single.complete(null);
    await _settle();
    run.frame(0);
    run.frame(1500);
    expect(run.state.phase, LivenessPhase.challenge);
    expect(run.notifier.directionPlanId, isNull);
  });

  test('an answer for an earlier attempt is ignored; a retry asks again',
      () async {
    final run = _Run();
    addTearDown(run.dispose);
    run.notifier.startDetection();
    run.notifier.reset();
    expect(run.answers, hasLength(2));
    run.answers.first.complete(_plan);
    await _settle();
    expect(run.notifier.directionPlanId, isNull);
    const second = DirectionPlan(
      planId: 'clx0plan0002',
      prompts: [LivenessChallenge.turnLeft, LivenessChallenge.lookDown],
    );
    run.answers.last.complete(second);
    await _settle();
    expect(run.state.directions, second.prompts);
    expect(run.notifier.directionPlanId, 'clx0plan0002');
  });

  test('classic gestures ask Core too, and ask exactly its plan in its order',
      () async {
    final run = _Run(gestureSet: 'classic');
    addTearDown(run.dispose);
    run.notifier.startDetection();
    expect(run.requests, [
      {'count': 2, 'set': 'classic'},
    ]);
    run.answers.single.complete(const DirectionPlan(
      planId: 'cm3plan0002',
      prompts: [LivenessChallenge.smile, LivenessChallenge.turn],
    ));
    await _settle();
    expect(run.state.directions, isEmpty);
    run.frame(0);
    run.frame(1500);
    expect(run.state.activeChallenge, LivenessChallenge.smile);
    expect(run.notifier.directionPlanId, 'cm3plan0002');
    expect(run.notifier.challengesRun,
        [LivenessChallenge.smile, LivenessChallenge.turn]);
  });

  test("a classic request carries the integration's count and pool", () {
    final run = _Run(
      gestureSet: 'classic',
      mode: 'both',
      livenessConfig: const LivenessConfig(
        challengeCount: 3,
        challengePool: [
          ChallengeConfig(
            type: LivenessChallenge.blink,
            instruction: 'Blink your eyes',
            timeoutSeconds: 6,
          ),
          ChallengeConfig(
            type: LivenessChallenge.turn,
            instruction: 'Turn your head',
            timeoutSeconds: 8,
          ),
        ],
      ),
    );
    addTearDown(run.dispose);
    run.notifier.startDetection();
    expect(run.requests, [
      {
        'count': 3,
        'set': 'classic',
        'pool': ['turn', 'blink'],
        'flash': 4,
      },
    ]);
  });

  test('a passive check asks Core for nothing', () {
    final run = _Run(mode: 'passive');
    addTearDown(run.dispose);
    run.notifier.startDetection();
    expect(run.requests, isEmpty);
  });

  test('a flash-only check asks Core for colours alone, and keeps its gestures',
      () async {
    final run = _Run(mode: 'flash');
    addTearDown(run.dispose);
    run.notifier.startDetection();
    expect(run.requests, [
      {'set': 'none', 'flash': 4},
    ]);
    run.answers.single.complete(const DirectionPlan(
      planId: 'cm3plan0005',
      prompts: [],
      flash: ['cyan', 'red', 'blue', 'green'],
    ));
    await _settle();
    expect(run.notifier.plannedFlash!.map((c) => c.name),
        ['cyan', 'red', 'blue', 'green']);
    // The claim names the plan, even with no gestures in it.
    expect(run.notifier.directionPlanId, 'cm3plan0005');
    expect(run.notifier.challengesRun, isEmpty);
  });

  test('Dual Check asks for the colours beside the gestures, and shows them',
      () async {
    final run = _Run(mode: 'both');
    addTearDown(run.dispose);
    run.notifier.startDetection();
    expect(run.requests, [
      {'count': 3, 'set': 'directions', 'flash': 4},
    ]);
    run.answers.single.complete(const DirectionPlan(
      planId: 'clx0plan0003',
      prompts: [LivenessChallenge.lookUp, LivenessChallenge.turnRight],
      flash: ['red', 'blue', 'green', 'cyan'],
    ));
    await _settle();
    expect(run.state.directions, _plan.prompts);
    expect(run.notifier.plannedFlash!.map((c) => c.name),
        ['red', 'blue', 'green', 'cyan']);
  });

  test('a classic pool with nothing Core can plan still asks for the colours',
      () {
    final run = _Run(
      gestureSet: 'classic',
      mode: 'both',
      livenessConfig: const LivenessConfig(challengePool: [kHoldChallenge]),
    );
    addTearDown(run.dispose);
    run.notifier.startDetection();
    expect(run.requests, [
      {'set': 'none', 'flash': 4},
    ]);
  });

  test('no plan: no colours named, and the SDK picks its own', () async {
    final run = _Run(mode: 'flash');
    addTearDown(run.dispose);
    run.notifier.startDetection();
    run.answers.single.complete(null);
    await _settle();
    expect(run.notifier.plannedFlash, isNull);
    expect(run.notifier.directionPlanId, isNull);
  });

  test("a flash-only flash waits for a pending plan, and shows Core's colours",
      () async {
    final run = _Run(mode: 'flash');
    addTearDown(run.dispose);
    run.notifier.startDetection();
    run.notifier.setLightingGuidance(null); // lighting measured
    await _holdForFlash(run, 100); // held long enough, but the plan is on its way
    expect(run.state.phase, LivenessPhase.positioning);
    run.answers.single.complete(const DirectionPlan(
      planId: 'cm3plan0005',
      prompts: [],
      flash: ['cyan', 'red'],
    ));
    await _settle();
    run.frame(200);
    expect(run.state.phase, LivenessPhase.capturing);
    expect(run.notifier.plannedFlash!.map((c) => c.name), ['cyan', 'red']);
    expect(run.notifier.directionPlanId, 'cm3plan0005');
  });

  test('a plan that lands after the flash began is not used', () async {
    final run = _Run(mode: 'flash');
    addTearDown(run.dispose);
    run.notifier.startDetection();
    run.notifier.setLightingGuidance(null);
    await _holdForFlash(run, 3000); // past the 2.5 s wait
    expect(run.state.phase, LivenessPhase.capturing);
    run.answers.single.complete(const DirectionPlan(
      planId: 'cm3plan0005',
      prompts: [],
      flash: ['cyan', 'red'],
    ));
    await _settle();
    expect(run.notifier.plannedFlash, isNull);
    expect(run.notifier.directionPlanId, isNull);
  });

  test('a direction lands after a few frames; the wrong way only shows the way again',
      () async {
    final run = _Run();
    addTearDown(run.dispose);
    run.notifier.startDetection();
    run.answers.single.complete(_plan);
    await _settle();
    run.frame(0);
    run.frame(1500);
    expect(run.state.activeChallenge, LivenessChallenge.lookUp);

    // Looking down instead, for a second: not a failure, not a red warning.
    for (var i = 0; i < 31; i++) {
      run.frame(1600 + i * 33, _face(pitch: -20));
    }
    expect(run.state.phase, LivenessPhase.challenge);
    expect(run.state.wrongGesture, isFalse);
    expect(run.state.wrongWayCount, 1);

    for (var i = 0; i < 4; i++) {
      run.frame(3000 + i * 33, _face(pitch: 20));
    }
    expect(run.state.phase, LivenessPhase.challengePassed);
    expect(run.state.completedCount, 1);
  });
}

extension on LivenessFaceData {
  LivenessFaceData copyWithSize(double size) => LivenessFaceData(
        headEulerAngleX: headEulerAngleX,
        headEulerAngleY: headEulerAngleY,
        headEulerAngleZ: headEulerAngleZ,
        smilingProbability: smilingProbability,
        leftEyeOpenProbability: leftEyeOpenProbability,
        rightEyeOpenProbability: rightEyeOpenProbability,
        faceSizeRatio: size,
        faceCenterX: faceCenterX,
        faceCenterY: faceCenterY,
      );
}
