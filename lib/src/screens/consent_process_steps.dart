import 'dart:math' as math;

import '../config/business.dart';
import '../config/business_application.dart';
import '../config/document_capture_methods.dart';
import '../config/verification_config.dart';
import '../config/supporting_documents.dart';
import '../i18n/business_variants.dart';
import '../i18n/translate.dart';
import '../widgets/icons/icons.dart';

// The consent screen's "during this process we will" list, split from
// consent_screen.dart (200-line rule), with how long each step takes for the
// time sentence. Mirrors the web SDK's steps/consent-copy.ts. Each line is a catalogue text, so a
// workflow may reword it; the NFC line has no catalogue key and keeps this
// SDK's wording.

class ConsentProcessStep {
  final UiIconData icon;
  final String label;

  /// About how long the step takes a person, for the screen's time estimate.
  final int seconds;
  const ConsentProcessStep(this.icon, this.label, [this.seconds = kStepSecondsDefault]);
}

/// A step with no estimate of its own counts as half a minute.
const int kStepSecondsDefault = 30;

/// About how long each step takes, in seconds: typing a number is quick, a
/// document scan or a selfie is a minute or under, gathering a company's
/// people or papers is longer. Estimates for the time sentence, not
/// measurements. The web SDK's STEP_SECONDS (steps/consent-copy.ts): change
/// both together.
const Map<String, int> kStepSeconds = {
  'welcome.process.verifyId': 30,
  'welcome.process.captureDocument': 60,
  'welcome.process.uploadDocument': 45,
  'welcome.process.selfie': 45,
  'welcome.process.faceSelfie': 45,
  'welcome.process.faceMatch': 10,
  'welcome.process.faceEnrol': 10,
  'welcome.process.addressPin': 45,
  'welcome.process.addressDetails': 30,
  'welcome.process.addressMap': 45,
  'welcome.process.proofOfAddress': 60,
  'welcome.process.supportingDocuments': 60,
  'welcome.process.questions': 60,
  'welcome.process.contactScope': 60,
  'welcome.process.contactEmail': 45,
  'welcome.process.contactPhone': 45,
  'welcome.process.contactEmailAndPhone': 90,
  'welcome.process.businessDetails': 90,
  'welcome.process.businessRegistry': 20,
  'welcome.process.keyPeople': 120,
  'welcome.process.businessDocuments': 120,
  'welcome.process.applicant': 150,
};

/// The whole flow's time, in whole minutes rounded up, at least one.
int consentMinutes(List<ConsentProcessStep> steps) {
  final seconds = steps.fold<int>(0, (sum, s) => sum + s.seconds);
  return math.max(1, (seconds / 60).ceil());
}

/// What this flow ACTUALLY does, in the order it runs. Each line is gated on
/// the feature that asks for it, and skipped where a scope's own bullet
/// already covers the same step.
List<ConsentProcessStep> consentProcessSteps(
  VerificationConfig config, {
  required bool isBusiness,
  required String? scope,
  required TextFn t,
  /// A SCOPED business workflow: the scope's bullets, worded for the company.
  bool scopedBusiness = false,
}) {
  ConsentProcessStep step(UiIconData icon, String key) => ConsentProcessStep(
        icon,
        t(businessKey(key, scopedBusiness)),
        kStepSeconds[key] ?? kStepSecondsDefault,
      );
  final WorkflowBusinessConfig? business = config.business;
  final hasEmail = config.emailVerification?.enabled ?? false;
  final hasPhone = config.phoneVerification?.enabled ?? false;
  final full = !isBusiness && scope == null;

  return [
    // A KYB flow lists its application steps, never the identity rows.
    if (isBusiness) ...[
      step(UiIcons.building2, 'welcome.process.businessDetails'),
      step(UiIcons.badgeCheck, 'welcome.process.businessRegistry'),
    ] else if (scope == 'address') ...[
      // NOT a fixed pair: the scope verifies an address by the pin, by a
      // document, or by both. The document's own bullet comes further down.
      if (config.addressCollection?.enabled ?? false) ...[
        step(UiIcons.mapPinHouse, 'welcome.process.addressPin'),
        step(UiIcons.badgeCheck, 'welcome.process.addressDetails'),
      ],
    ] else if (scope == 'biometric-authentication' ||
        scope == 'biometric-enrollment') ...[
      step(UiIcons.scanFace, 'welcome.process.faceSelfie'),
      step(
        UiIcons.badgeCheck,
        scope == 'biometric-authentication'
            ? 'welcome.process.faceMatch'
            : 'welcome.process.faceEnrol',
      ),
    ] else if (scope == 'questionnaire') ...[
      step(UiIcons.badgeCheck, 'welcome.process.questions'),
    ] else if (scope == 'contact') ...[
      step(UiIcons.lock, 'welcome.process.contactScope'),
    ],
    // On the CONTACT scope the catalogue bullet already says this.
    if (scope != 'contact' && (hasEmail || hasPhone))
      step(
        UiIcons.lock,
        hasEmail && hasPhone
            ? 'welcome.process.contactEmailAndPhone'
            : hasEmail
                ? 'welcome.process.contactEmail'
                : 'welcome.process.contactPhone',
      ),
    if (full && config.enableDocumentCapture)
      documentCaptureMethodsFor(config).scan
          ? step(UiIcons.scanLine, 'welcome.process.captureDocument')
          : step(UiIcons.imageUp, 'welcome.process.uploadDocument'),
    // Chip-capable IDs additionally read the NFC chip; no catalogue key.
    if (full && (config.nfc?.enabled ?? false))
      const ConsentProcessStep(
        UiIcons.nfc,
        'Scan your document’s security chip (NFC)',
      ),
    // The ID is checked once it is in hand: after the scan, before the selfie.
    if (full) step(UiIcons.badgeCheck, 'welcome.process.verifyId'),
    if (full && config.enableSelfie)
      step(UiIcons.scanFace, 'welcome.process.selfie'),
    // `mayAsk`, NOT the step-order predicate: consent runs before an ID is
    // picked, so every scoped document would otherwise go undisclosed.
    if (!isBusiness && mayAskSupportingDocuments(config.supportingDocuments))
      step(UiIcons.fileText, 'welcome.process.supportingDocuments'),
    if (!isBusiness && (config.proofOfAddress?.enabled ?? false))
      step(UiIcons.fileText, 'welcome.process.proofOfAddress'),
    if (scope != 'address' && (config.addressCollection?.enabled ?? false))
      step(UiIcons.mapPinHouse, 'welcome.process.addressMap'),
    // The step-order predicate: a disabled questionnaire is never promised.
    if (scope != 'questionnaire' && (config.questionnaire?.isActive ?? false))
      step(UiIcons.badgeCheck, 'welcome.process.questions'),
    if (isBusiness && hasKeyPeopleCollection(business))
      step(UiIcons.usersRound, 'welcome.process.keyPeople'),
    if (isBusiness && hasBusinessDocumentsStep(business))
      step(UiIcons.fileText, 'welcome.process.businessDocuments'),
    if (isBusiness && hasApplicantVerification(business))
      step(UiIcons.scanFace, 'welcome.process.applicant'),
  ];
}
