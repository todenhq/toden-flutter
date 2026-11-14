import 'api_service.dart';

// ─── Contact-verification error copy ──────────────────────────────────────────
//
// Maps the server's `error` codes (VerificationApiException.error) for the OTP send /
// check endpoints to user-facing copy. Mirrors the web SDK's contact-errors.

/// A workflow that takes work addresses only refuses a free-provider one with
/// `invalid_destination` and this reason; an older server sends no reason.
const _corporateEmailRequired =
    'Use your work email address. Personal email services such as Gmail are '
    'not accepted here.';

String describeSendError(Object err) {
  final code = err is VerificationApiException ? err.error : null;
  if (code == 'invalid_destination' &&
      err is VerificationApiException &&
      err.details?['reason'] == 'corporate_email_required') {
    return _corporateEmailRequired;
  }
  return switch (code) {
    'invalid_destination' =>
      'That does not look valid. Please check and try again.',
    'send_rate_limited' =>
      'Too many codes requested. Please wait a while and try again.',
    'send_failed' => 'We could not send the code. Please try again.',
    'network_error' || 'timeout' =>
      'Network error. Check your connection and try again.',
    _ => 'Something went wrong. Please try again.',
  };
}

/// Shown once a code is used up: its last attempt failed, or the server
/// refuses it outright.
const kCodeUsedUpMessage = 'Too many incorrect attempts. Request a new code.';

/// How many tries the current code has left after a wrong one, when the
/// server says (`invalid_code` carries `attemptsRemaining`).
int? attemptsRemainingOf(Object? err) {
  if (err is! VerificationApiException) return null;
  final value = err.details?['attemptsRemaining'];
  return value is int ? value : null;
}

/// Whether the current code can no longer be checked: the wrong code just
/// entered was its last try (`invalid_code` with `attemptsRemaining: 0`), or
/// the server refused a further check on it (`too_many_attempts`). Only a new
/// code helps, so the step disables its field until one is sent.
bool isCodeUsedUp(Object? err) {
  if (err is! VerificationApiException) return false;
  if (err.error == 'too_many_attempts') return true;
  return err.error == 'invalid_code' && attemptsRemainingOf(err) == 0;
}

/// Whether the server refused the code itself (wrong, used up or expired), as
/// opposed to the request failing. The step clears the field for these.
bool isWrongCode(Object? err) =>
    err is VerificationApiException &&
    const {'invalid_code', 'too_many_attempts', 'challenge_expired'}
        .contains(err.error);

String describeCheckError(Object err) {
  if (isCodeUsedUp(err)) return kCodeUsedUpMessage;
  final code = err is VerificationApiException ? err.error : null;
  return switch (code) {
    'invalid_code' => 'That code is not correct. Please try again.',
    'challenge_expired' => 'This code has expired. Request a new one.',
    'challenge_not_found' =>
      'This code is no longer valid. Request a new one.',
    'network_error' || 'timeout' =>
      'Network error. Check your connection and try again.',
    _ => 'Something went wrong. Please try again.',
  };
}
