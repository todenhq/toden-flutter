import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/liveness/capture_pose.dart';
import 'package:toden_flutter/src/liveness/flash_outcome.dart';
import 'package:toden_flutter/src/liveness/liveness_types.dart';
import 'package:toden_flutter/src/liveness/sharpest_still.dart';
import 'package:toden_flutter/src/liveness/spoken_prompts.dart';
import 'package:toden_flutter/src/liveness/voice_clips.dart';
import 'package:toden_flutter/src/providers/liveness_provider.dart';

// What the liveness step says on each change of state. The instruction is said
// whenever its text changes, not only when the phase does.

String _asWritten(String raw) => raw;

void main() {
  const challenge = LivenessState(
    phase: LivenessPhase.challenge,
    instruction: 'Nod your head',
  );

  test('a new phase says its instruction', () {
    const positioning = LivenessState(
      phase: LivenessPhase.positioning,
      instruction: 'Position your face in the circle',
    );
    expect(spokenPrompts(null, positioning, _asWritten), ['Position your face in the circle']);
    expect(spokenPrompts(positioning, challenge, _asWritten), ['Nod your head']);
  });

  test('a new instruction inside one phase is said too', () {
    const positioning = LivenessState(
      phase: LivenessPhase.positioning,
      instruction: 'Position your face in the circle',
    );
    final flashHold = positioning.copyWith(
      instruction: 'Hold still. The screen will flash briefly',
    );
    expect(spokenPrompts(positioning, flashHold, _asWritten),
        ['Hold still. The screen will flash briefly']);

    const capturing = LivenessState(phase: LivenessPhase.capturing, instruction: 'Hold still…');
    for (final line in [kFlashRetryGuidance, kRetakeInstruction, kLookStraightInstruction]) {
      expect(spokenPrompts(capturing, capturing.copyWith(instruction: line), _asWritten), [line]);
    }
  });

  test('nothing changed, nothing said', () {
    expect(spokenPrompts(challenge, challenge.copyWith(timeoutRemaining: 3), _asWritten), isEmpty);
  });

  test('an empty instruction says nothing', () {
    const complete = LivenessState(phase: LivenessPhase.complete);
    expect(spokenPrompts(challenge, complete, _asWritten), isEmpty);
  });

  test('a second face comes first, and the gesture is said again once it goes', () {
    final paused = challenge.copyWith(
      multipleFaces: true,
      instruction: LivenessNotifier.multipleFacesGuidance,
    );
    expect(spokenPrompts(challenge, paused, _asWritten), ['Make sure only your face is visible']);

    final cleared = paused.copyWith(multipleFaces: false);
    expect(spokenPrompts(paused, cleared, _asWritten), isEmpty);
    final restored = cleared.copyWith(instruction: 'Nod your head');
    expect(spokenPrompts(cleared, restored, _asWritten), ['Nod your head']);
  });

  test('lighting comes before the instruction', () {
    final dark = challenge.copyWith(
      phase: LivenessPhase.positioning,
      instruction: 'Position your face in the circle',
      lightingGuidance: 'dark',
    );
    expect(spokenPrompts(challenge, dark, _asWritten), ['Move to a brighter area']);
  });

  test('distance guidance follows when it appears', () {
    final tooFar = challenge.copyWith(positionGuidance: 'too_far');
    expect(spokenPrompts(challenge, tooFar, _asWritten), ['Move closer']);
    expect(
      spokenPrompts(null, tooFar, _asWritten),
      ['Nod your head', 'Move closer'],
    );
  });

  test('a workflow reworded instruction is said as shown', () {
    String reworded(String raw) => raw == 'Nod your head' ? 'Please nod' : raw;
    const positioning = LivenessState(phase: LivenessPhase.positioning, instruction: 'x');
    expect(spokenPrompts(positioning, challenge, reworded), ['Please nod']);
  });

  group('every default line has a Toden clip text', () {
    // The contract's phrase texts (kyc-core docs/VOICE_GUIDANCE.md).
    const clipTexts = {
      'Position your face in the circle', 'Move closer', 'Move further away',
      'Centre your face', 'Look straight at the camera', 'Hold still',
      'Make sure only your face is visible', 'Move to a brighter area',
      'Too bright. Reduce the glare', 'Nod your head', 'Turn your head',
      'Blink your eyes', 'Smile', 'Turn your head to the left',
      'Turn your head to the right', 'Look up', 'Look down',
      'Hold still and look at the camera',
      'Hold still. The screen will flash briefly', 'Good.',
      'Move away from bright light and hold still', 'Hold still, taking that again',
      "Time's up. Please try again.", "Let's start over. Please stay in frame.",
      "We couldn't confirm the check. Let's try again.",
    };
    final normalised = clipTexts.map(normaliseVoicePhrase).toSet();

    test('guidance, lighting and the capture lines', () {
      final lines = [
        for (final g in ['too_far', 'too_close', 'off_centre']) positionGuidanceText(g),
        for (final l in ['dark', 'bright']) lightingGuidanceText(l),
        kLookStraightInstruction, kMoveCloserInstruction, kHoldStillInstruction,
        kRetakeInstruction, kFlashRetryGuidance, 'Hold still…',
        LivenessNotifier.multipleFacesGuidance,
      ];
      for (final line in lines) {
        expect(normalised, contains(normaliseVoicePhrase(line)), reason: line);
      }
    });

    test('the gestures, and the instruction keys match them', () {
      for (final c in [...kDefaultChallengePool, ...kDirectionPool, kHoldChallenge]) {
        expect(clipTexts, contains(c.instruction), reason: c.type.name);
        expect(kPresenceInstructionKeys, contains(c.instruction), reason: c.type.name);
      }
      for (final text in kPresenceInstructionKeys.keys) {
        expect(clipTexts, contains(text), reason: text);
      }
    });
  });
}
