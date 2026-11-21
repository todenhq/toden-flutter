// The liveness capture's guidance lines that the web SDK keys but does not
// make customisable (i18n/groups/presence-capture.ts): keys and wording byte
// for byte. Kept apart from kDefaultTexts, which holds customisable keys only;
// resolveText reads them as a fallback. The screen shows them through
// liveness_types.dart's kPresenceInstructionKeys.

const Map<String, String> kPresenceGuidanceTexts = {
  'presence.position.lookStraight': 'Look straight at the camera',
  'presence.position.moveCloser': 'Move closer',
  'presence.position.holdStill': 'Hold still',
  // The head directions gesture set's four instructions.
  'presence.challenge.turnLeft': 'Turn your head to the left',
  'presence.challenge.turnRight': 'Turn your head to the right',
  'presence.challenge.lookUp': 'Look up',
  'presence.challenge.lookDown': 'Look down',
};
