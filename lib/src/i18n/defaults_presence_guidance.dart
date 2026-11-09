// The liveness capture's guidance lines that the web SDK keys but does not
// make customisable (i18n/groups/presence-capture.ts): keys and wording byte
// for byte. Kept apart from kDefaultTexts, which holds customisable keys only;
// resolveText reads them as a fallback. The screen shows them through
// liveness_types.dart's kPresenceInstructionKeys.

const Map<String, String> kPresenceGuidanceTexts = {
  'presence.position.lookStraight': 'Kindly look straight at the camera',
  'presence.position.moveCloser': 'Kindly move closer',
  'presence.position.holdStill': 'Kindly hold still',
};
