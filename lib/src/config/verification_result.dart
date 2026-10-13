// ─── Result callback ─────────────────────────────────────────────────────────
//
// The verdict, on a flow that waits for it in the app (a biometric
// re-authentication on `resultDelivery: 'both'`, the default, or 'app').
// `status` is the same vocabulary `GET /api/v1/status/:id` serves; `reason`
// and `reasonCode` are the server's own, null on success. Never result data:
// scores and biodata stay behind the secret key. Mirrors the web and RN SDKs'
// `VerificationResult`.

class VerificationResult {
  final String verificationId;

  /// 'approved' | 'declined' | 'in_review' | 'error' | ... (the status vocabulary).
  final String status;
  final String? reason;
  final String? reasonCode;

  const VerificationResult({
    required this.verificationId,
    required this.status,
    this.reason,
    this.reasonCode,
  });
}
