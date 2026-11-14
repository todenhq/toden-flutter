import '../i18n/translate.dart' show TextFn, defaultTextFn;
import '../providers/verification_state.dart' show VerificationStep;
import '../services/api_service.dart' show VerificationApiException;

// ─── A declined session ──────────────────────────────────────────────────────
//
// The server can decline a session outright. Two rules do it: a workflow
// whose email or phone step sets `declineOnLastAttempt` declines the session
// when the applicant uses up a code, and `POST /contact/check` answers 409
// `{ error: 'session_declined', reasonCode: 'contact_attempts_exceeded',
// message }`; a workflow with `maxLivenessAttempts` declines it when the
// liveness check fails that many times, and `POST /liveness/failed` answers
// the same with `reasonCode: 'liveness_attempts_exceeded'`
// (config/liveness_attempts.dart). From then on every request on that
// session (session start and resume, progress saves, `/verify`, the contact
// endpoints) answers 409 with the same shape.
//
// Exactly parallel to a cancelled session (config/session_cancelled.dart):
// retrying can never succeed, so no path may read it as "try again". Every
// path routes to ONE terminal screen with only Close, and the integrator's
// onError hears `session_declined` once. Pure, so each decision is testable
// without a network.

/// The server's error token, and the SDK's public error code for it.
const String kSessionDeclinedCode = 'session_declined';

/// The reason a contact step gives when its code ran out of attempts.
const String kContactAttemptsExceeded = 'contact_attempts_exceeded';

/// The reason a session gives when the liveness check failed too many times.
const String kLivenessAttemptsExceeded = 'liveness_attempts_exceeded';

// The words, by key (i18n/defaults_contact_attempts.dart holds the wording,
// keyed as the web SDK keys it, read through the flow's text function).

/// The title when the step that ended the session is not known.
const String kSessionEndedTitleKey = 'general.sessionDeclined.title';

/// The body for any other declined session without a server message.
const String kSessionDeclinedMessageKey = 'general.sessionDeclined.description';

/// The titles for a code used up on the email or phone step.
const String kEmailDeclinedTitleKey = 'contact.declined.email.title';
const String kPhoneDeclinedTitleKey = 'contact.declined.phone.title';

/// The body for a used-up code, when the server sent no message of its own.
const String kContactAttemptsExceededMessageKey = 'contact.declined.description';

/// The title and default body when the liveness check ran out of attempts.
const String kLivenessDeclinedTitleKey = 'liveness.declined.title';
const String kLivenessDeclinedMessageKey = 'liveness.declined.description';

/// What the declined screen shows.
class SessionDeclined {
  final String title;
  final String message;

  /// The server's `reasonCode`, when it sent one.
  final String? reasonCode;

  const SessionDeclined({required this.title, required this.message, this.reasonCode});

  @override
  bool operator ==(Object other) =>
      other is SessionDeclined &&
      other.title == title &&
      other.message == message &&
      other.reasonCode == reasonCode;

  @override
  int get hashCode => Object.hash(title, message, reasonCode);
}

/// Whether [error] is the server refusing a declined session.
bool isSessionDeclinedError(Object? error) =>
    error is VerificationApiException && error.error == kSessionDeclinedCode;

/// The words for a declined session. [channel] is `email` | `phone` when the
/// step that ended it is known, else null. [t] is the flow's text function.
SessionDeclined describeSessionDeclined({
  String? reasonCode,
  String? channel,
  String? serverMessage,
  TextFn t = defaultTextFn,
}) {
  final keys = _declinedKeys(reasonCode, channel);
  final trimmed = serverMessage?.trim();
  final message = (trimmed != null && trimmed.isNotEmpty) ? trimmed : t(keys.message);
  return SessionDeclined(title: t(keys.title), message: message, reasonCode: reasonCode);
}

/// The title and default body keys for a declined session's reason. The
/// liveness reason names its own step whatever step the applicant is on.
({String title, String message}) _declinedKeys(String? reasonCode, String? channel) =>
    switch (reasonCode) {
      kLivenessAttemptsExceeded => (
          title: kLivenessDeclinedTitleKey,
          message: kLivenessDeclinedMessageKey,
        ),
      kContactAttemptsExceeded => (
          title: switch (channel) {
            'email' => kEmailDeclinedTitleKey,
            'phone' => kPhoneDeclinedTitleKey,
            _ => kSessionEndedTitleKey,
          },
          message: kContactAttemptsExceededMessageKey,
        ),
      _ => (title: kSessionEndedTitleKey, message: kSessionDeclinedMessageKey),
    };

/// The declined screen's words for [error], or null when it is anything else.
SessionDeclined? sessionDeclinedFor(
  Object? error, {
  String? channel,
  TextFn t = defaultTextFn,
}) {
  if (!isSessionDeclinedError(error)) return null;
  final e = error as VerificationApiException;
  final reason = e.details?['reasonCode'];
  return describeSessionDeclined(
    reasonCode: reason is String ? reason : null,
    channel: channel,
    serverMessage: e.message,
    t: t,
  );
}

/// The contact channel a step collects, or null for any other step: how a
/// refusal that arrives off the contact step itself still names the channel
/// when the applicant is on one.
String? contactChannelOf(VerificationStep step) => switch (step) {
      VerificationStep.contactEmail => 'email',
      VerificationStep.contactPhone => 'phone',
      _ => null,
    };
