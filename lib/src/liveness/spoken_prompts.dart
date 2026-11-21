import '../providers/liveness_provider.dart' show LivenessNotifier, LivenessState;

// ─── What the liveness step says ─────────────────────────────────────────────
//
// The words are the ones on screen, and each is a Toden voice clip's text
// (kyc-core docs/VOICE_GUIDANCE.md), so a clip can say it.

/// The line for the distance guidance ('too_far', 'too_close', 'off_centre').
String positionGuidanceText(String guidance) => switch (guidance) {
      'too_far' => 'Move closer',
      'too_close' => 'Move further away',
      'off_centre' => 'Centre your face',
      _ => '',
    };

/// The line for the lighting guidance ('dark', 'bright').
String lightingGuidanceText(String guidance) => switch (guidance) {
      'dark' => 'Move to a brighter area',
      'bright' => 'Too bright. Reduce the glare',
      _ => '',
    };

/// The phrases to say for the change from [previous] to [next], in order;
/// each one waits for the one before to finish. [shown] turns a raw
/// instruction into the words on screen (a workflow may reword it).
///
/// A second face comes first, then the lighting, then the instruction, which
/// is said whenever its text changes, not only when the phase does: the flash
/// hold, the flash retry, the final capture's guidance, the retake and the
/// gesture restored after a second face are all said. The distance guidance
/// follows when it appears or changes.
List<String> spokenPrompts(
  LivenessState? previous,
  LivenessState next,
  String Function(String raw) shown,
) {
  final phrases = <String>[];
  final lighting = next.lightingGuidance;
  final instructionChanged = previous?.phase != next.phase ||
      previous?.instruction != next.instruction;

  if (next.multipleFaces && previous?.multipleFaces != true) {
    phrases.add(LivenessNotifier.multipleFacesGuidance);
  } else if (lighting != null && previous?.lightingGuidance != lighting) {
    phrases.add(lightingGuidanceText(lighting));
  } else if (instructionChanged &&
      next.instruction.isNotEmpty &&
      !next.multipleFaces) {
    phrases.add(shown(next.instruction));
  }

  final position = next.positionGuidance;
  if (position != null &&
      previous?.positionGuidance != position &&
      !next.multipleFaces) {
    phrases.add(positionGuidanceText(position));
  }
  return [for (final phrase in phrases) if (phrase.isNotEmpty) phrase];
}
