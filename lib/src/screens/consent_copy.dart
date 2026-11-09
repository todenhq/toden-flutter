import '../i18n/translate.dart';

// ─── The consent screen's title and description ───────────────────────────────
//
// Every text comes from the catalogue's `welcome` group, keyed by the screen's
// variant: the KYB application, a scope, a scoped business workflow, or none
// (the base text). Mirrors the web SDK's steps/consent-copy.ts: change both
// together.

/// Scope to the key suffix its title and description use.
const Map<String, String> _kScopeKeys = {
  'address': 'address',
  'biometric-authentication': 'faceCheck',
  'biometric-enrollment': 'faceEnrolment',
  'questionnaire': 'questionnaire',
  'contact': 'contact',
};

/// The screen's variant for keyed copy, or null for the base text.
String? _variant({required bool isBusiness, required String? scope, required bool scopedBusiness}) {
  if (isBusiness) return 'business';
  final key = _kScopeKeys[scope];
  return key != null && scopedBusiness ? '$key.business' : key;
}

/// The title. An older `consent.title` ([legacy]) wins over every variant.
String consentTitle(
  TextFn t, {
  required bool isBusiness,
  required String? scope,
  bool scopedBusiness = false,
  String? firstName,
  String? legacy,
}) {
  final v = _variant(isBusiness: isBusiness, scope: scope, scopedBusiness: scopedBusiness);
  final key = (firstName?.isNotEmpty ?? false)
      ? 'welcome.title.named'
      : v != null
          ? 'welcome.title.$v'
          : 'welcome.title';
  return t(key, legacy: legacy);
}

/// The description, then how long the flow takes ("It takes about 3
/// minutes."), a sentence of its own: the description is customisable and
/// customisable texts carry no values. The face and contact screens already
/// say how long they take, so they get no second sentence. An older
/// `consent.description` ([legacy]) wins over every variant.
String consentDescription(
  TextFn t, {
  required bool isBusiness,
  required String? scope,
  bool scopedBusiness = false,
  String? legacy,
  int? minutes,
}) {
  final v = _variant(isBusiness: isBusiness, scope: scope, scopedBusiness: scopedBusiness);
  final text = t(v != null ? 'welcome.description.$v' : 'welcome.description', legacy: legacy);
  if (minutes == null || RegExp(r'^(faceCheck|faceEnrolment|contact)').hasMatch(v ?? '')) {
    return text;
  }
  final time = minutes <= 1
      ? t('welcome.time.minute')
      : t('welcome.time.minutes', vars: {'minutes': minutes});
  return '$text $time';
}
