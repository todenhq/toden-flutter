import '../services/api_service.dart' show LivenessFailedResponse;
import 'session_declined.dart' show isSessionDeclinedError;

// ─── A limit on liveness attempts ────────────────────────────────────────────
//
// A workflow can set `maxLivenessAttempts` (1 to 3, or `false` for no limit;
// absent means 3, on by default, as the server reads it), as
// Didit's "Maximum liveness attempts" does. The check runs on the phone, so
// the server only knows of a failure when the SDK reports it: each failed
// check (the panel with "Time's up. Let's try again." and Try Again) is posted
// once to `POST /api/kyc/liveness/failed`, never retried. The server counts
// them per attempt and answers:
//
//   200 { limited: false }                 no limit; nothing changes
//   200 { limited: true, attemptsLeft: n } the panel says how many are left
//   409 session_declined                   reason liveness_attempts_exceeded:
//                                          the flow ends on the declined screen
//
// Anything else (no network, another refusal) is ignored: Try Again works as
// it always has, and the report never holds it up. Pure, so each decision is
// testable without a camera or a network.

/// The limit a workflow has when it leaves the setting out.
const int defaultLivenessAttempts = 3;

/// The workflow's `maxLivenessAttempts`, or null when it turns the limit off
/// (`false`). A value above 3 reads as 3. Absent, or unreadable, it is the
/// default of 3: the server decides in the end, so reporting a failure it does
/// not count costs one request and changes nothing.
int? maxLivenessAttemptsFrom(Object? raw) {
  if (raw == false) return null;
  if (raw is! num || raw != raw.roundToDouble() || raw < 1) {
    return defaultLivenessAttempts;
  }
  return raw > defaultLivenessAttempts ? defaultLivenessAttempts : raw.toInt();
}

/// The line under the failed check's message: "1 attempt left." or
/// "2 attempts left.", or null when there is nothing to say (no limit, or the
/// rare answer of 0 left).
String? livenessAttemptsLeftLine(LivenessFailedResponse? answer) {
  final left = answer?.attemptsLeft;
  if (answer == null || !answer.limited || left == null || left < 1) {
    return null;
  }
  return left == 1 ? '1 attempt left.' : '$left attempts left.';
}

/// Reports one failed check when the workflow limits attempts, and answers
/// the line the failed panel shows, or null for none. [report] makes the call;
/// [onDeclined] hears a `session_declined` refusal, which ends the flow. Every
/// other failure is swallowed. With no limit ([maxAttempts] null) nothing is
/// reported.
Future<String?> reportFailedLivenessCheck({
  required int? maxAttempts,
  required Future<LivenessFailedResponse> Function() report,
  required void Function(Object error) onDeclined,
}) async {
  if (maxAttempts == null) return null;
  try {
    return livenessAttemptsLeftLine(await report());
  } catch (e) {
    if (isSessionDeclinedError(e)) onDeclined(e);
    return null;
  }
}
