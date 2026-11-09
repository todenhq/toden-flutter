// Recovery from a submit refused over contact proofs. Mirrors the web SDK's
// steps/contact-recovery.ts and the RN SDK's lib/contact-recovery.ts — keep
// the three in lockstep.
//
// Contact proof tokens are SINGLE-USE and expire ~30 minutes after the OTP is
// checked, but they ride session progress and are restored on resume. A
// resumed attempt therefore carries a proof the server will (rightly)
// validate-and-drop at submit, while the contact step still shows "verified"
// — and a plain retry resubmits the same dead token forever.
//
// The 422 is recoverable in-flow: clear the stale proofs, walk the person
// back to the contact step (their data is untouched), and once re-verified
// the step routes straight back to `submitted`, which auto-submits with the
// fresh token.
import '../providers/verification_state.dart';
import '../services/api_service.dart';

/// The channels a 422 `contact_verification_required` names as missing.
List<String> expiredContactChannels(Object? err) {
  if (err is! VerificationApiException || err.error != 'contact_verification_required') {
    return const [];
  }
  final missing = err.details?['missing'];
  if (missing is! List) return const [];
  return [
    for (final c in missing)
      if (c == 'email' || c == 'phone') c as String,
  ];
}

VerificationStep contactStepFor(String channel) =>
    channel == 'email' ? VerificationStep.contactEmail : VerificationStep.contactPhone;

/// Where the step routes once this channel is verified. Null means the
/// ordinary forward walk; in recovery it returns to `submitted` (which
/// auto-submits with the fresh proof) via any OTHER still-refused channel
/// first, so the person never re-walks steps they already completed.
VerificationStep? stepAfterContactVerified({
  required bool recovery,
  required List<String> expired,
  required String channel,
}) {
  if (!recovery) return null;
  final remaining = expired.where((c) => c != channel).toList();
  return remaining.isEmpty ? VerificationStep.submitted : contactStepFor(remaining.first);
}

/// Whether [step] shows Back. The contact steps back into the step before
/// them in the order (phone into email when the flow has one, else consent;
/// email into consent), but NOT while recovering from a refused submission:
/// that walk returns to the end, and Back would strand the person at the
/// start. Mirrors the web SDK's `stepBeforeContact` and its `recovery` gate.
bool contactBackShown(VerificationStep step, List<String> expired) => switch (step) {
      VerificationStep.contactEmail => !expired.contains('email'),
      VerificationStep.contactPhone => !expired.contains('phone'),
      _ => true,
    };
