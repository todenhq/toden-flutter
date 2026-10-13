// ─── Consent and success screen content ──────────────────────────────────────
//
// Split from verification_config.dart (200-line rule); re-exported from there.

/// Overrides for the consent (welcome) screen copy. Both fields support
/// `{firstName}` / `{lastName}` tokens, replaced with the values from
/// [VerificationConfig.userData] (empty string when absent).
class VerificationConsentContent {
  /// Heading. Defaults to `Welcome, {firstName}` when a first name is known,
  /// otherwise `Identity Verification`.
  final String? title;

  /// Sub-text under the heading. Defaults to the built-in regulatory copy.
  final String? description;

  const VerificationConsentContent({this.title, this.description});

  factory VerificationConsentContent.fromJson(Map<String, dynamic> json) =>
      VerificationConsentContent(
        title: json['title'] as String?,
        description: json['description'] as String?,
      );
}

// ─── Success screen content ──────────────────────────────────────────────────

/// Overrides for the success (submitted) screen copy. Both fields support
/// `{firstName}` / `{lastName}` tokens, replaced with the values from
/// [VerificationConfig.userData] (empty string when absent).
class VerificationSuccessContent {
  /// Heading. Defaults to `Verification Submitted!`.
  final String? title;

  /// Sub-text under the heading. Defaults to the built-in "submitted for
  /// review" copy.
  final String? description;

  const VerificationSuccessContent({this.title, this.description});

  factory VerificationSuccessContent.fromJson(Map<String, dynamic> json) =>
      VerificationSuccessContent(
        title: json['title'] as String?,
        description: json['description'] as String?,
      );
}
