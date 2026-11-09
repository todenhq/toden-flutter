// The consent screen's texts that the web SDK keys but does not make
// customisable (i18n/groups/welcome.ts): the named, business and scope
// variants of the title and description, the time sentence and the redo
// note's title. Keys and wording byte for byte. Kept apart from kDefaultTexts,
// which holds customisable keys only; resolveText reads them as a fallback.
// A scoped business workflow's own variants are in business_variants.dart.

const Map<String, String> kWelcomeVariantTexts = {
  'welcome.redo.title': 'A few things to redo',
  'welcome.title.named': 'Welcome, {firstName}',
  'welcome.title.business': 'Business Verification',
  'welcome.title.address': 'Address Verification',
  'welcome.title.faceCheck': 'Face Check',
  'welcome.title.faceEnrolment': 'Face Enrolment',
  'welcome.title.questionnaire': 'A Few Questions',
  'welcome.title.contact': 'Confirm Your Contact Details',
  'welcome.description.business':
      "We're required to confirm your business, and we'll guide you at every step.",
  'welcome.description.address':
      "We're required to confirm your home address, and we'll guide you at every step.",
  'welcome.description.faceCheck':
      'A quick face check confirms it is really you. This takes a few seconds and is secure.',
  'welcome.description.faceEnrolment':
      'A quick selfie sets up face checks for next time, so you will not have to prove your identity again. This takes a few seconds and is secure.',
  'welcome.description.questionnaire': 'A few questions keep your account details up to date.',
  'welcome.description.contact':
      'We need to re-confirm the email address and phone number on your account. This takes a minute and is secure.',
  // The time the flow takes, a sentence of its own: the description is
  // customisable, and customisable texts carry no values.
  'welcome.time.minute': 'It takes about a minute.',
  'welcome.time.minutes': 'It takes about {minutes} minutes.',
};
