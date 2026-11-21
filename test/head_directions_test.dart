import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/liveness/challenge_manager.dart';
import 'package:toden_flutter/src/liveness/direction_plan.dart';
import 'package:toden_flutter/src/liveness/face_detection.dart';
import 'package:toden_flutter/src/liveness/flash_challenge.dart';
import 'package:toden_flutter/src/liveness/flash_detector.dart';
import 'package:toden_flutter/src/liveness/head_directions.dart';
import 'package:toden_flutter/src/liveness/liveness_types.dart';
import 'package:toden_flutter/src/liveness/ready_pause.dart';

// ─── Head directions ─────────────────────────────────────────────────────────
//
// The web SDK's gesture-detector/directions.test.ts, challenge-manager.test.ts
// (pickDirections, planChallenges), direction-plan.test.ts and
// ready-pause.test.ts, in this SDK's units (the detectors' angles in degrees).

LivenessFaceData _face({double yaw = 0, double pitch = 0}) => LivenessFaceData(
      headEulerAngleX: pitch,
      headEulerAngleY: yaw,
      headEulerAngleZ: 0,
      smilingProbability: 0,
      leftEyeOpenProbability: 1,
      rightEyeOpenProbability: 1,
      faceSizeRatio: 0.4,
    );

const _turns = {LivenessChallenge.turnLeft, LivenessChallenge.turnRight};

void main() {
  group('which way the head is facing', () {
    test('facing the camera is no direction', () {
      expect(facing(_face(), 0), isNull);
      expect(facing(_face(yaw: 20, pitch: 10), 0), isNull);
    });

    test("left and right are the person's own: positive yaw is their left", () {
      expect(facing(_face(yaw: 30), 0), LivenessChallenge.turnLeft);
      expect(facing(_face(yaw: -30), 0), LivenessChallenge.turnRight);
    });

    test('up and down are measured from where the person rests', () {
      expect(facing(_face(pitch: 20), 0), LivenessChallenge.lookUp);
      expect(facing(_face(pitch: -20), 0), LivenessChallenge.lookDown);
      // A face that rests tipped back is not looking up at rest.
      expect(facing(_face(pitch: 12), 12), isNull);
      expect(facing(_face(pitch: 12 + 16), 12), LivenessChallenge.lookUp);
    });

    test('the larger movement wins: a turn with a slight dip is a turn', () {
      expect(facing(_face(yaw: 40, pitch: -16), 0), LivenessChallenge.turnLeft);
      expect(facing(_face(yaw: 26, pitch: -30), 0), LivenessChallenge.lookDown);
    });

    test('the opposite of each direction', () {
      expect(oppositeDirection(LivenessChallenge.turnLeft), LivenessChallenge.turnRight);
      expect(oppositeDirection(LivenessChallenge.lookUp), LivenessChallenge.lookDown);
    });
  });

  group('the direction watch', () {
    test('a direction must hold for a few frames, so a wobble is not taken', () {
      final watch = DirectionWatch();
      for (var i = 0; i < kDirectionHoldFrames - 1; i++) {
        expect(watch.update(LivenessChallenge.lookUp, _face(pitch: 20), 0),
            DirectionStep.waiting);
      }
      // A frame back at the middle starts the count again.
      watch.update(LivenessChallenge.lookUp, _face(), 0);
      for (var i = 0; i < kDirectionHoldFrames - 1; i++) {
        watch.update(LivenessChallenge.lookUp, _face(pitch: 20), 0);
      }
      expect(watch.update(LivenessChallenge.lookUp, _face(pitch: 20), 0),
          DirectionStep.done);
    });

    test('the wrong way is never a failure: after a second it asks to show the way again',
        () {
      final watch = DirectionWatch();
      final steps = [
        for (var i = 0; i < kWrongWayFrames + 5; i++)
          watch.update(LivenessChallenge.turnLeft, _face(yaw: -40), 0),
      ];
      expect(steps.where((s) => s == DirectionStep.wrongWay), hasLength(1));
      expect(steps, isNot(contains(DirectionStep.done)));
    });
  });

  group('pickDirections', () {
    test('always includes a head turn, and never repeats', () {
      for (var i = 0; i < 300; i++) {
        final types = [for (final c in pickDirections(3, Random(i))) c.type];
        expect(types, hasLength(3));
        expect(types.toSet(), hasLength(3));
        expect(types.any(_turns.contains), isTrue);
      }
    });

    test('takes 2 to 4, and anything else is 3', () {
      expect(pickDirections(2), hasLength(2));
      expect(pickDirections(4), hasLength(4));
      expect(pickDirections(1), hasLength(3));
      expect(pickDirections(5), hasLength(3));
      expect(directionCountOf(null), kDefaultDirectionCount);
      expect(directionCountOf(2.5), kDefaultDirectionCount);
    });

    test('two directions still carry a turn, and every direction can be picked', () {
      final seen = <LivenessChallenge>{};
      for (var i = 0; i < 300; i++) {
        final types = [for (final c in pickDirections(2, Random(i))) c.type];
        expect(types.any(_turns.contains), isTrue);
        seen.addAll(types);
      }
      expect(seen, kDirectionChallenges.toSet());
    });

    test('a run is shuffled: the first is not always the same', () {
      final firsts = {
        for (var i = 0; i < 100; i++)
          ChallengeManager.directions(random: Random(i)).current!.type,
      };
      expect(firsts.length, greaterThan(1));
    });

    test('the workflow picks the set: directions, unless flash or passive', () {
      List<LivenessChallenge> types(ChallengeManager m) =>
          [for (final c in m.selectedChallenges) c.type];
      expect(
          types(ChallengeManager.forMode('gestures',
                  gestureSet: 'directions', directionCount: 4))
              .toSet(),
          kDirectionChallenges.toSet());
      expect(types(ChallengeManager.forMode('both', gestureSet: 'directions')),
          everyElement(isIn(kDirectionChallenges)));
      expect(types(ChallengeManager.forMode('gestures', gestureSet: 'classic')),
          contains(LivenessChallenge.turn));
      expect(types(ChallengeManager.forMode('flash', gestureSet: 'directions')), isEmpty);
      expect(types(ChallengeManager.forMode('passive', gestureSet: 'directions')),
          [LivenessChallenge.hold]);
    });

    test('a reset picks a new run of directions, not classic gestures', () {
      final manager = ChallengeManager.directions(count: 2);
      for (var i = 0; i < 20; i++) {
        manager.reset();
        expect(manager.selectedChallenges, hasLength(2));
        expect(manager.selectedChallenges.map((c) => c.type),
            everyElement(isIn(kDirectionChallenges)));
      }
    });

    test("the claim names each direction by its wire name", () {
      expect(
        livenessClaimChallenges(
          mode: 'both',
          gestures: const [LivenessChallenge.lookUp, LivenessChallenge.turnLeft],
        ),
        ['lookUp', 'turnLeft', 'flash'],
      );
    });
  });

  group("Core's plan", () {
    test('a usable plan: an id, 2 to 4 distinct directions with a turn', () {
      final plan = parseDirectionPlan({
        'planId': 'clx0abc123def',
        'directions': ['lookUp', 'turnRight', 'lookDown'],
        'expiresAt': '2026-11-18T12:00:00Z',
      });
      expect(plan!.planId, 'clx0abc123def');
      expect(plan.prompts, [
        LivenessChallenge.lookUp,
        LivenessChallenge.turnRight,
        LivenessChallenge.lookDown,
      ]);
      // A Core with classic plans names the list `prompts` too.
      expect(
        parseDirectionPlan({
          'planId': 'clx0abc123def',
          'prompts': ['turnRight', 'lookUp'],
          'directions': ['turnRight', 'lookUp'],
        })!.prompts,
        [LivenessChallenge.turnRight, LivenessChallenge.lookUp],
      );
    });

    test('anything else is no plan', () {
      for (final raw in <Object?>[
        null,
        'plan',
        {'planId': 'short', 'directions': ['turnLeft', 'lookUp']},
        {'planId': 'has spaces in it', 'directions': ['turnLeft', 'lookUp']},
        {'planId': 'clx0abc123def', 'directions': ['turnLeft']},
        {'planId': 'clx0abc123def', 'directions': ['turnLeft', 'turnLeft']},
        {'planId': 'clx0abc123def', 'directions': ['lookUp', 'lookDown']},
        {'planId': 'clx0abc123def', 'directions': ['turnLeft', 'nod']},
        {
          'planId': 'clx0abc123def',
          'directions': ['turnLeft', 'turnRight', 'lookUp', 'lookDown', 'turnLeft'],
        },
      ]) {
        expect(parseDirectionPlan(raw), isNull, reason: '$raw');
      }
    });

    test('its directions in its order, nothing added', () {
      expect(
        planChallenges(const [LivenessChallenge.lookDown, LivenessChallenge.turnLeft])
            .map((c) => c.type),
        [LivenessChallenge.lookDown, LivenessChallenge.turnLeft],
      );
    });

    test('asks for the set, the count, and the pool only when classic narrows it',
        () {
      expect(const PlanRequest.directions(3).toJson(),
          {'count': 3, 'set': 'directions'});
      expect(const PlanRequest.classic(2).toJson(),
          {'count': 2, 'set': 'classic'});
      expect(
        const PlanRequest.classic(3, pool: [
          LivenessChallenge.turn,
          LivenessChallenge.blink,
        ]).toJson(),
        {
          'count': 3,
          'set': 'classic',
          'pool': ['turn', 'blink'],
        },
      );
    });

    test("the integration's pool narrows a classic request to what Core can plan",
        () {
      expect(classicPlanRequest(2, null)!.toJson(),
          {'count': 2, 'set': 'classic'});
      final narrowed = classicPlanRequest(3, [
        kDefaultChallengePool[3], // smile
        kHoldChallenge,
        kDefaultChallengePool[2], // blink
      ])!;
      expect(narrowed.pool, [LivenessChallenge.blink, LivenessChallenge.smile]);
      // Nothing Core can plan: ask for nothing, the SDK picks its own.
      expect(classicPlanRequest(2, const [kHoldChallenge]), isNull);
    });

    test('the first instruction waits up to 2.5 s for a pending plan, and no longer',
        () {
      expect(planGateWaits(DirectionPlanStatus.pending, 1000, 1000), isTrue);
      expect(planGateWaits(DirectionPlanStatus.pending, 1000, 3499), isTrue);
      expect(planGateWaits(DirectionPlanStatus.pending, 1000, 3500), isFalse);
      for (final status in [
        DirectionPlanStatus.none,
        DirectionPlanStatus.ready,
        DirectionPlanStatus.failed,
      ]) {
        expect(planGateWaits(status, 1000, 1000), isFalse);
      }
    });

    test('the claim names the plan, and only when there is one', () {
      expect(livenessIntegrityClaim(mode: 'gestures', directionPlanId: 'clx0abc123def'),
          containsPair('directionPlanId', 'clx0abc123def'));
      expect(livenessIntegrityClaim(mode: 'gestures'),
          isNot(contains('directionPlanId')));
    });
  });

  group("Core's classic plan", () {
    const classic = PlanRequest.classic(2);

    test('takes 1 to 3 distinct classic gestures, from the pool when the integration narrowed it',
        () {
      final plan = parseDirectionPlan({
        'planId': 'cm3plan0002',
        'prompts': ['smile', 'turn'],
      }, classic);
      expect(plan!.planId, 'cm3plan0002');
      expect(plan.prompts, [LivenessChallenge.smile, LivenessChallenge.turn]);
      expect(
        parseDirectionPlan({
          'planId': 'cm3plan0002',
          'prompts': ['blink'],
        }, const PlanRequest.classic(2, pool: [LivenessChallenge.blink]))!
            .prompts,
        [LivenessChallenge.blink],
      );
      for (final (raw, request) in <(Object?, PlanRequest)>[
        (
          {'planId': 'cm3plan0002', 'prompts': ['smile', 'turn']},
          const PlanRequest.classic(2, pool: [
            LivenessChallenge.turn,
            LivenessChallenge.blink,
          ]),
        ),
        ({'planId': 'cm3plan0002', 'prompts': ['turnLeft', 'lookUp']}, classic),
        ({'planId': 'cm3plan0002', 'prompts': ['turn', 'turn']}, classic),
        ({'planId': 'cm3plan0002', 'prompts': <String>[]}, classic),
        (
          {'planId': 'cm3plan0002', 'prompts': ['nod', 'blink', 'smile', 'turn']},
          classic,
        ),
        ({'planId': 'short', 'prompts': ['smile', 'turn']}, classic),
        // And a classic answer is no head-direction plan.
        (
          {'planId': 'cm3plan0002', 'prompts': ['smile', 'turn']},
          const PlanRequest.directions(3),
        ),
      ]) {
        expect(parseDirectionPlan(raw, request), isNull, reason: '$raw');
      }
    });

    test('asks exactly the classic plan, in its order', () {
      expect(
        planChallenges(const [LivenessChallenge.smile, LivenessChallenge.turn])
            .map((c) => c.type),
        [LivenessChallenge.smile, LivenessChallenge.turn],
      );
    });

    test("an integration's own wording for a gesture stands", () {
      const own = ChallengeConfig(
        type: LivenessChallenge.blink,
        instruction: 'Blink twice',
        timeoutSeconds: 9,
      );
      final planned = planChallenges(
        const [LivenessChallenge.blink, LivenessChallenge.turn],
        pool: const [own],
      );
      expect(planned.first, same(own));
      expect(planned.last.instruction, 'Turn your head');
    });
  });

  group('the flash colours Core picked', () {
    const flashOnly = PlanRequest.flashOnly(4);

    test('a flash-only check asks for colours and no gestures', () {
      expect(flashOnly.toJson(), {'set': 'none', 'flash': 4});
      expect(const PlanRequest.directions(3, flash: 4).toJson(),
          {'count': 3, 'set': 'directions', 'flash': 4});
      expect(classicPlanRequest(2, null, flash: 3)!.toJson(),
          {'count': 2, 'set': 'classic', 'flash': 3});
    });

    test('takes a flash-only plan: no gestures, the colours asked for', () {
      final plan = parseDirectionPlan({
        'planId': 'cm3plan0005',
        'prompts': <String>[],
        'flash': ['cyan', 'red', 'blue', 'green'],
      }, flashOnly)!;
      expect(plan.planId, 'cm3plan0005');
      expect(plan.prompts, isEmpty);
      expect(plan.flash, ['cyan', 'red', 'blue', 'green']);
    });

    test('carries the colours beside the gestures in Dual Check', () {
      final plan = parseDirectionPlan({
        'planId': 'cm3plan0006',
        'prompts': ['turnLeft', 'lookUp'],
        'flash': ['red', 'blue', 'green', 'cyan'],
      }, const PlanRequest.directions(2, flash: 4));
      expect(plan!.flash, ['red', 'blue', 'green', 'cyan']);
      // Not asked: none read, whatever came back.
      expect(
        parseDirectionPlan({
          'planId': 'cm3plan0006',
          'prompts': ['turnLeft', 'lookUp'],
          'flash': ['red', 'blue'],
        })!
            .flash,
        isEmpty,
      );
    });

    test('refuses a plan whose colours did not come back usable, so the SDK picks its own',
        () {
      for (final flash in <Object?>[
        null,
        ['red'],
        ['red', 'red', 'blue', 'green'],
        ['red', 'orange', 'blue', 'green'],
        ['red', 'blue'],
        'red',
      ]) {
        expect(
          parseDirectionPlan(
              {'planId': 'cm3plan0007', 'prompts': <String>[], 'flash': flash},
              flashOnly),
          isNull,
          reason: '$flash',
        );
      }
    });

    test("shows Core's colours in its order, from the palette", () {
      expect(flashSequenceNamed(['cyan', 'red'])!.map((c) => c.name),
          ['cyan', 'red']);
      expect(flashSequenceNamed(['cyan', 'orange']), isNull);
      expect(flashSequenceNamed(const []), isNull);
    });
  });

  group('the ready pause', () {
    test('starts when the face is first in place and lets go after 1.5 s', () {
      var step = readyPauseStep(null, 1000);
      expect(step, (readyAt: 1000, go: false));
      step = readyPauseStep(step.readyAt, 2499);
      expect(step.go, isFalse);
      step = readyPauseStep(step.readyAt, 2500);
      expect(step, (readyAt: null, go: true));
    });

    test('says how far through it is', () {
      expect(readyPauseShare(null, 5000), 0);
      expect(readyPauseShare(1000, 1750), closeTo(0.5, 1e-9));
      expect(readyPauseShare(1000, 9000), 1);
    });
  });
}
