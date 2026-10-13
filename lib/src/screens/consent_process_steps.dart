import '../config/business.dart';
import '../config/business_application.dart';
import '../config/verification_config.dart';
import '../config/supporting_documents.dart';
import '../i18n/translate.dart';
import '../widgets/icons/icons.dart';

// The consent screen's "during this process we will" list, split from
// consent_screen.dart (200-line rule). Each line is a catalogue text, so a
// workflow may reword it; the NFC line has no catalogue key and keeps this
// SDK's wording.

class ConsentProcessStep {
  final UiIconData icon;
  final String label;
  const ConsentProcessStep(this.icon, this.label);
}

/// What this flow ACTUALLY does, in the order it runs. Each line is gated on
/// the feature that asks for it, and skipped where a scope's own bullet
/// already covers the same step.
List<ConsentProcessStep> consentProcessSteps(
  VerificationConfig config, {
  required bool isBusiness,
  required String? scope,
  required TextFn t,
}) {
  ConsentProcessStep step(UiIconData icon, String key) =>
      ConsentProcessStep(icon, t(key));
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
    ] else ...[
      step(UiIcons.badgeCheck, 'welcome.process.verifyId'),
      step(UiIcons.userRound, 'welcome.process.personalInfo'),
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
      step(UiIcons.scanLine, 'welcome.process.captureDocument'),
    // Chip-capable IDs additionally read the NFC chip; no catalogue key.
    if (full && (config.nfc?.enabled ?? false))
      const ConsentProcessStep(
        UiIcons.nfc,
        'Scan your document’s security chip (NFC)',
      ),
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
