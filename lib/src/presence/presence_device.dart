import 'dart:io' show HttpDate;

import 'presence_report_proof.dart';

// ─── The presence device's rules, pure (user token design rev 4, §6b, §14) ───
//
// After an address verification answers 202, the phone makes a P-256 key the
// OS will never export (Secure Enclave, Android Keystore) and registers its
// public half with Toden. From then on native background code gets its own
// 1-hour presence token by signing a timestamped request, and every queued day
// is sealed with that key, so a late report still counts for its own day.
//
// Dart registers the device (presence_device_registration.dart); the refresh
// and the seals are native (PresenceDevice.swift, PresenceDevice.kt). The
// shared vectors (test/presence_seal_vectors.json) pin these rules in all four
// languages, the RN SDK's device-rules.ts included.

/// At most one refresh per device in this long.
const int kPresenceRefreshIntervalMillis = 30 * 60 * 1000;

/// After 409 `no_live_watch` (a pending device or a dormant chain).
const int kPresenceBackOffMillis = 6 * 60 * 60 * 1000;

/// The DER prefix that turns a 65-byte X9.63 P-256 point into an SPKI.
const String kP256SpkiPrefixHex =
    '3059301306072a8648ce3d020106082a8648ce3d030107034200';

String presenceRegistrationText(
        String externalUserId, String publicKey, int signedAt) =>
    'toden-presence-device-v1\n$externalUserId\n$publicKey\n$signedAt';

String presenceRefreshText(
        String deviceId, String externalUserId, int signedAt) =>
    'toden-presence-refresh-v1\n$deviceId\n$externalUserId\n$signedAt';

/// The seal signs the observation's report-digest row, exactly as it is posted.
String presenceSealText(String deviceId, String externalUserId,
        ReportObservation observation, int observedAtMillis) =>
    'toden-presence-seal-v1\n$deviceId\n$externalUserId\n${reportDigestRow(observation)}\n$observedAtMillis';

/// The next `signedAt`: the corrected clock, but always after the last one
/// sent, because the server takes only a strictly increasing value per device.
int nextSignedAt(int correctedNow, int? lastSent) => lastSent == null
    ? correctedNow
    : (correctedNow > lastSent ? correctedNow : lastSent + 1);

/// Server minus device, from a response's Date header; null keeps the offset.
int? clockOffsetFrom(String? date, int deviceNowMillis) {
  if (date == null || date.isEmpty) return null;
  try {
    return HttpDate.parse(date).millisecondsSinceEpoch - deviceNowMillis;
  } catch (_) {
    return null;
  }
}

enum PresenceRegistrationOutcome {
  registered,
  refused,
  limit,
  deleteKey,
  retryClock,
  keep
}

enum PresenceRefreshOutcome {
  store,
  deleteKey,
  retryClock,
  retrySignedAt,
  backOff,
  keep
}

PresenceRegistrationOutcome presenceRegistrationOutcome(
    int? status, String? code) {
  if (status == 201 || status == 200) {
    return PresenceRegistrationOutcome.registered;
  }
  if (status == 403 && code == 'device_registration_refused') {
    return PresenceRegistrationOutcome.refused;
  }
  if (status == 422 && code == 'device_not_genuine') {
    return PresenceRegistrationOutcome.refused;
  }
  if (status == 409 && code == 'presence_device_limit') {
    return PresenceRegistrationOutcome.limit;
  }
  if (status == 403 && code == 'presence_device_invalid') {
    return PresenceRegistrationOutcome.deleteKey;
  }
  if (status == 422 && code == 'invalid_device_key') {
    return PresenceRegistrationOutcome.deleteKey;
  }
  if (status == 400 && code == 'clock_skew') {
    return PresenceRegistrationOutcome.retryClock;
  }
  return PresenceRegistrationOutcome.keep;
}

/// What a refresh answer means. The code decides; only 403
/// `presence_device_invalid` ends the key.
PresenceRefreshOutcome presenceRefreshOutcome(int? status, String? code) {
  if (status == 201 || status == 200) return PresenceRefreshOutcome.store;
  if (status == 403 && code == 'presence_device_invalid') {
    return PresenceRefreshOutcome.deleteKey;
  }
  if (status == 400 && code == 'clock_skew') {
    return PresenceRefreshOutcome.retryClock;
  }
  if (status == 409 && code == 'stale_signed_at') {
    return PresenceRefreshOutcome.retrySignedAt;
  }
  if (status == 409 && code == 'no_live_watch') {
    return PresenceRefreshOutcome.backOff;
  }
  return PresenceRefreshOutcome.keep;
}

/// Whether background code may ask for a new token now.
bool presenceRefreshDue(int nowMillis, int? lastRefreshAt, int? backOffUntil) {
  if (backOffUntil != null && nowMillis < backOffUntil) return false;
  return lastRefreshAt == null ||
      nowMillis - lastRefreshAt >= kPresenceRefreshIntervalMillis;
}

/// The days a 2xx may take off the queue: on a watch held past its deadline,
/// only the days up to the deadline (a reviewer's extension may still let the
/// later ones count).
List<String> removableAfterSend(
        List<String> sentDays, String? heldDeadlineDay) =>
    heldDeadlineDay == null
        ? List.of(sentDays)
        : sentDays.where((d) => d.compareTo(heldDeadlineDay) <= 0).toList();

/// The error code of a JSON error answer (v1 envelope or flat).
String? presenceErrorCode(Object? body) {
  if (body is! Map) return null;
  final error = body['error'];
  final code =
      error is Map ? error['code'] : (error is String ? error : body['code']);
  return code is String ? code : null;
}
