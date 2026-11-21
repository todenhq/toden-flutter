import '../i18n/translate.dart' show TextFn;

// ─── Liveness challenge types ─────────────────────────────────────────────────

// `hold` is Passive Liveness: hold still and look at the camera. It passes on
// its own after a steady moment, and the server's liveness model does the
// judging. Never part of the random gesture pool. Each value's `name` is its
// wire name in the liveness claim (`integrity.liveness.challenges`).
//
// The head directions (the `directions` gesture set) each ask for one way:
// turnLeft, turnRight, lookUp, lookDown. Left and right are the PERSON's own,
// which on the mirrored preview are the screen's left and right too.
enum LivenessChallenge {
  nod,
  turn,
  blink,
  smile,
  hold,
  turnLeft,
  turnRight,
  lookUp,
  lookDown,
}

/// Which gestures the camera asks for (`livenessGestureSet`):
///
///   directions  two to four of turn left, turn right, look up and look down
///               (`livenessDirectionCount`, 3 unless set), always with a head
///               turn, in an order picked for the session.
///   classic     two or three of nod, turn, blink and smile.
///
/// Unset is `classic`, so a workflow saved before the setting keeps what it
/// had. The web SDK's liveness/types.ts.
const String kGestureSetDirections = 'directions';

/// The four head directions, in the pool's order.
const List<LivenessChallenge> kDirectionChallenges = [
  LivenessChallenge.turnLeft,
  LivenessChallenge.turnRight,
  LivenessChallenge.lookUp,
  LivenessChallenge.lookDown,
];

/// Whether [type] is one of the head directions.
bool isDirectionChallenge(LivenessChallenge? type) =>
    type != null && kDirectionChallenges.contains(type);

/// The head direction with this wire name, or null.
LivenessChallenge? directionFromName(Object? name) {
  for (final d in kDirectionChallenges) {
    if (d.name == name) return d;
  }
  return null;
}

// ─── Liveness phase state machine ─────────────────────────────────────────────

enum LivenessPhase {
  loading,         // Initializing camera + ML Kit
  positioning,     // "Position your face in the circle"
  challenge,       // Active gesture challenge
  challengePassed, // Brief green flash
  capturing,       // Auto-capturing selfie
  complete,        // All done, selfie stored
  failed,          // Timeout or face lost
}

// ─── Challenge config ─────────────────────────────────────────────────────────

class ChallengeConfig {
  final LivenessChallenge type;
  final String instruction;
  final int timeoutSeconds;

  const ChallengeConfig({
    required this.type,
    required this.instruction,
    required this.timeoutSeconds,
  });
}

// ─── Default challenge pool (same as web SDK) ─────────────────────────────────

const List<ChallengeConfig> kDefaultChallengePool = [
  ChallengeConfig(
    type: LivenessChallenge.nod,
    instruction: 'Nod your head',
    timeoutSeconds: 8,
  ),
  ChallengeConfig(
    type: LivenessChallenge.turn,
    instruction: 'Turn your head',
    timeoutSeconds: 8,
  ),
  ChallengeConfig(
    type: LivenessChallenge.blink,
    instruction: 'Blink your eyes',
    timeoutSeconds: 6,
  ),
  ChallengeConfig(
    type: LivenessChallenge.smile,
    instruction: 'Smile',
    timeoutSeconds: 6,
  ),
];

/// The head directions set's four movements, with the web SDK's wording. A run
/// asks for two to four of them (challenge_manager.dart pickDirections).
const List<ChallengeConfig> kDirectionPool = [
  ChallengeConfig(
    type: LivenessChallenge.turnLeft,
    instruction: 'Turn your head to the left',
    timeoutSeconds: 8,
  ),
  ChallengeConfig(
    type: LivenessChallenge.turnRight,
    instruction: 'Turn your head to the right',
    timeoutSeconds: 8,
  ),
  ChallengeConfig(
    type: LivenessChallenge.lookUp,
    instruction: 'Look up',
    timeoutSeconds: 8,
  ),
  ChallengeConfig(
    type: LivenessChallenge.lookDown,
    instruction: 'Look down',
    timeoutSeconds: 8,
  ),
];

/// Passive Liveness (`livenessMode: 'passive'`): the ONE prompt. The face holds
/// still in the circle for about two seconds (liveness/passive_hold.dart); the
/// recording and the selfie go to the server, where the liveness model decides.
const ChallengeConfig kHoldChallenge = ChallengeConfig(
  type: LivenessChallenge.hold,
  instruction: 'Hold still and look at the camera',
  timeoutSeconds: 10,
);

// ─── Customisable instructions ────────────────────────────────────────────────
//
// The positioning prompt and the default challenges are catalogue texts (see
// i18n/), so a workflow may reword them. The notifier keeps setting this SDK's
// wording; the screen swaps it for the workflow's at display (and speech)
// time. A consumer's own challenge pool has no key and reads as written.
const Map<String, String> kPresenceInstructionKeys = {
  'Position your face in the circle': 'presence.position.placeFace',
  'Nod your head': 'presence.challenge.nod',
  'Turn your head': 'presence.challenge.turn',
  'Blink your eyes': 'presence.challenge.blink',
  'Smile': 'presence.challenge.smile',
  'Hold still and look at the camera': 'presence.challenge.hold',
  // The head directions. Keyed by the web SDK but not customisable there, so
  // their defaults sit with the guidance lines (defaults_presence_guidance.dart).
  'Turn your head to the left': 'presence.challenge.turnLeft',
  'Turn your head to the right': 'presence.challenge.turnRight',
  'Look up': 'presence.challenge.lookUp',
  'Look down': 'presence.challenge.lookDown',
  // The final capture's guidance (selfie_shutter.dart). Not customisable: the
  // defaults are in i18n/defaults_presence_guidance.dart.
  'Look straight at the camera': 'presence.position.lookStraight',
  'Move closer': 'presence.position.moveCloser',
  'Hold still': 'presence.position.holdStill',
};

/// [raw] as the workflow words it, when it is one of the keyed instructions.
String presenceInstruction(String raw, TextFn t) {
  final key = kPresenceInstructionKeys[raw];
  return key == null ? raw : t(key);
}
