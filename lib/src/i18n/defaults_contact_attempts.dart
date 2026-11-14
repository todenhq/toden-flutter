// A contact code used up, and the session the server declines for it
// (config/session_declined.dart): the primary action that sends a new code,
// and the declined screen's titles and bodies, including the one for a
// liveness check that ran out of attempts (config/liveness_attempts.dart).
//
// The KEYS and wording are the web SDK's (i18n/groups/contact-code.ts and
// general.ts). They are not in the shared customisable-texts vectors yet, so
// they sit apart from kDefaultTexts (which holds the shared keys only) and
// resolveText reads them as a fallback. When the vectors gain them, move them
// into the customisable defaults in the same change.

const Map<String, String> kContactAttemptsTexts = {
  'contact.code.sendNew': 'Send a new code',
  'contact.declined.email.title': "We couldn't verify your email address",
  'contact.declined.phone.title': "We couldn't verify your phone number",
  'contact.declined.description':
      'The code was entered incorrectly too many times, so this verification '
          'has ended. Contact the organisation that sent it if you need help.',
  'liveness.declined.title': "We couldn't verify your face",
  'liveness.declined.description':
      'The face check did not succeed in the attempts allowed, so this '
          'verification has ended. Contact the organisation that sent it if '
          'you need help.',
  'general.sessionDeclined.title': 'This verification has ended',
  'general.sessionDeclined.description':
      'This verification has ended. Contact the organisation that sent it if '
          'you need help.',
};
