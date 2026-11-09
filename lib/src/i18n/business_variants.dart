// The texts a SCOPED business workflow shows in place of a person's
// (config/scope.dart isScopedBusiness), each standing in for a base text.
//
// Mirrors the web SDK's i18n/business-variants.ts (keys and wording) and the
// React Native SDK's src/i18n/business-variants.ts: keep the three in step.
// They are not customisable on their own (the shared list is capped), so an
// org's own words for the base text apply to the business version too, and
// only a workflow that left the base alone reads the default below. Kept apart
// from kDefaultTexts, which holds customisable keys only.

/// Business variant key to its default wording (the web SDK's, byte for byte).
const Map<String, String> kBusinessVariantTexts = {
  'welcome.title.address.business': 'Business Address Verification',
  'welcome.title.questionnaire.business': 'A Few Questions About Your Business',
  'welcome.title.contact.business': 'Confirm Your Business Contact Details',
  'welcome.description.address.business':
      "We're required to confirm where your business operates, and we'll guide you at every step.",
  'welcome.description.questionnaire.business':
      'A few questions keep your business details up to date.',
  'welcome.description.contact.business':
      "We need to re-confirm your business's email address and phone number. This takes a minute and is secure.",
  'welcome.process.addressPin.business': 'Verify your business premises',
  'welcome.process.addressDetails.business': 'Add the details that help us find the premises',
  'welcome.process.contactScope.business':
      "Confirm your business's contact details with a one-time code",
  'welcome.process.proofOfAddress.business': "Upload a document showing your business's address",
  'welcome.process.questions.business': 'Answer a few short questions about your business',
  'contact.email.title.business': 'Verify your business email',
  'contact.email.intro.business':
      "We'll send a one-time code to confirm this email address belongs to your business.",
  'contact.email.label.business': 'Business email address',
  'contact.email.footer.business': 'We only use this to verify your business.',
  'contact.phone.title.business': 'Verify your business phone number',
  'contact.phone.intro.business':
      "We'll send a one-time code by {channel} to confirm this number belongs to your business.",
  'contact.phone.label.business': 'Business phone number',
  'questionnaire.title.business': 'A few questions about your business',
  'questionnaire.description.business':
      'This information is required for compliance and helps keep your business account safe.',
  'proofOfAddress.description.business':
      "Upload a document that shows your business's name and address, issued within the last {days} days.",
  'proofOfAddress.description.noName.business':
      "Upload a document that shows your business's address, issued within the last {days} days.",
  'proofOfAddress.country.residence.business': 'Your business is in',
  'result.success.description.address.business':
      "Your business address verification has been submitted. You'll be notified of the result.",
  'result.success.description.questionnaire.business':
      "Your answers about your business have been submitted. You'll be notified of the result.",
  'result.success.description.contact.business':
      "Your business contact verification has been submitted. You'll be notified of the result.",
};

const String _suffix = '.business';

/// The base text a variant stands in for: its key without `.business`.
String? businessVariantBase(String key) => kBusinessVariantTexts.containsKey(key)
    ? key.substring(0, key.length - _suffix.length)
    : null;

/// The key itself, or its business variant on a scoped business workflow.
String businessKey(String key, bool scopedBusiness) {
  final variant = '$key$_suffix';
  return scopedBusiness && kBusinessVariantTexts.containsKey(variant) ? variant : key;
}
