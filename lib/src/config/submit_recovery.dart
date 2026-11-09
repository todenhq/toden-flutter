import '../providers/verification_state.dart' show VerificationStep;

// ─── Going back from a refused submission ────────────────────────────────────
//
// A refused submission used to end on an error with only Close, while its own
// message said "go back and upload them". Closing lost the application. Most
// refusals are about something the applicant can fix (a missing document, a
// required field), so the error screen offers Go back to the step that owns it,
// and the flow resubmits when they return to the end.

/// The step that owns each refusal the server names. Add-only.
const Map<String, VerificationStep> _stepForCode = {
  'missing_documents': VerificationStep.businessDocuments,
  'missing_company_info': VerificationStep.businessDetails,
  'key_people_required': VerificationStep.businessKeyPeople,
  'missing_supporting_documents': VerificationStep.supportingDocuments,
  'questionnaire_invalid': VerificationStep.questionnaire,
  'proof_of_address_required': VerificationStep.proofOfAddress,
  'address_collection_required': VerificationStep.addressCollection,
  'missing_address_fields': VerificationStep.addressCollection,
  // A saved address the server could not take (spent or expired grant, or a
  // presence verdict too old for this check): pick again, or enter one.
  'address_book_reuse_invalid': VerificationStep.addressCollection,
  'address_book_reuse_stale': VerificationStep.addressCollection,
};

/// Refusals of a picked saved address, which the flow recovers from in place by
/// returning to the address book step rather than ending on an error.
const Set<String> kAddressBookReuseRefusals = {
  'address_book_reuse_invalid',
  'address_book_reuse_stale',
};

/// A capture the server could not accept, by the key it names.
const Map<String, VerificationStep> _stepForMediaKey = {
  'documentFront': VerificationStep.documentCapture,
  'documentBack': VerificationStep.documentCapture,
  'selfie': VerificationStep.liveness,
  'livenessVideo': VerificationStep.liveness,
  'proofOfAddress': VerificationStep.proofOfAddress,
  'addressPhoto': VerificationStep.addressEntrance,
};

/// Refusals going back cannot fix: nothing the applicant entered is wrong.
const Set<String> _notRecoverable = {
  'invalid_api_key',
  'insufficient_credits',
  'feature_disabled',
  'business_not_approved',
  'rate_limited',
  // Nothing anybody entered can undo a cancellation; only an admin can.
  'session_cancelled',
};

/// Where Go back should land for a refusal, or null when going back cannot
/// help. A named step is used only when this flow contains it; anything else
/// lands on the last step before submission, so the applicant can still walk
/// back through what they entered.
VerificationStep? recoveryStepFor(
  String serverCode,
  List<VerificationStep> order, {
  String? mediaKey,
}) {
  if (_notRecoverable.contains(serverCode)) return null;
  final named = _stepForCode[serverCode] ??
      (serverCode == 'invalid_media' && mediaKey != null ? _stepForMediaKey[mediaKey] : null);
  if (named != null && order.contains(named)) return named;
  final end = order.indexOf(VerificationStep.submitted);
  if (end > 0) return order[end - 1];
  return null;
}
