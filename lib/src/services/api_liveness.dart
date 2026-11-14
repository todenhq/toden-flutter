// ─── Liveness attempts API type ──────────────────────────────────────────────
//
// The answer to `POST /api/kyc/liveness/failed`, the report of one failed
// liveness check (config/liveness_attempts.dart). Split from api_service.dart
// and re-exported by it, like api_business.dart.

/// What the server said about one failed liveness check.
class LivenessFailedResponse {
  /// Whether the workflow limits liveness attempts at all. False means nothing
  /// was counted and the flow goes on exactly as before.
  final bool limited;

  /// How many failed checks are left before the session is declined, when
  /// [limited]. 0 is a rare race (the limit was reached by a report the server
  /// answered first); the flow then says nothing about tries left.
  final int? attemptsLeft;

  const LivenessFailedResponse({required this.limited, this.attemptsLeft});

  /// No limit applies: the answer to an unlimited workflow, and what a body
  /// the SDK cannot read is taken as.
  static const LivenessFailedResponse unlimited =
      LivenessFailedResponse(limited: false);

  factory LivenessFailedResponse.fromJson(Map<String, dynamic>? json) {
    if (json == null || json['limited'] != true) return unlimited;
    final left = json['attemptsLeft'];
    return LivenessFailedResponse(
      limited: true,
      attemptsLeft: left is num && left >= 0 ? left.toInt() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LivenessFailedResponse &&
      other.limited == limited &&
      other.attemptsLeft == attemptsLeft;

  @override
  int get hashCode => Object.hash(limited, attemptsLeft);
}
