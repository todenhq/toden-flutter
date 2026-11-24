import 'dart:async';

import '../config/verification_config.dart';
import 'background_presence.dart';
import 'presence_device_registration.dart';
import 'presence_reporter.dart';
import 'presence_store.dart';
import 'user_token.dart';

// ─── What the SDK does ON ITS OWN when a presence flow is submitted ─────────
//
// Until this existed, every observation depended on the host app calling
// AddressPresence.report() or BackgroundPresence.enable() itself,
// and companies that wired up the flow and not those calls got watches stuck
// at 0 days / 0 nights until they lapsed (production, 2026-09-28).
//
//   1. Background monitoring, ON unless the workflow sets
//      `presence.background: false`: the SDK asks for the "always" location
//      permission and arms the native geofence, so the phone reports stays
//      with the app closed. The primer told the person this prompt was coming.
//      It needs the host's background-location declarations (manifest and
//      Info.plist); without them it degrades to the foreground tier.
//   2. The first report: the person is standing at the address they just
//      pinned, so the watch gets its first day (and night, when submitted at
//      night) with nothing for the host to do. The reporter waits for the
//      watch the server mints seconds after the submission.
//
// Later days without background monitoring still need the host's reporter on
// app open. Fire-and-forget by contract: never awaited by the flow, never
// throws, and a host that also makes these calls is harmless.
// Mirrors the RN SDK's presence/auto-report.ts — keep the two in lockstep.

/// Whether a submitted flow should make the SDK's own presence calls.
bool shouldAutoReportPresence(VerificationConfig config) {
  if (config.addressCollection?.presenceEnabled != true) return false;
  final userId = config.userId;
  return userId != null && userId.trim().isNotEmpty;
}

/// Background monitoring is on unless the workflow turns it off.
bool wantsBackgroundPresence(VerificationConfig config) =>
    shouldAutoReportPresence(config) && config.addressCollection?.presenceBackground != false;

/// Stores the 202's presenceToken beside the pin. Only for a flow that saved a
/// pin: the 202 of any address capture carries a token, and one from a flow
/// with presence off must not replace the token of a check still running.
///
/// With a user-token provider, the phone's presence device is registered now
/// too (presence_device_registration.dart), in the background: the flow never
/// waits for it.
Future<void> keepPresenceToken(VerificationConfig config, String? token, {RegisterDeviceFn? register}) async {
  if (!shouldAutoReportPresence(config)) return;
  await savePresenceToken(config.userId!, token);
  if (token == null || token.isEmpty) return;
  unawaited((register ?? registerPresenceDevice)(
    apiKey: config.apiKey,
    externalUserId: config.userId!,
    presenceToken: token,
    devUrl: config.devUrl,
    getUserToken: config.getUserToken,
  ));
}

typedef RegisterDeviceFn = Future<String> Function({
  required String apiKey,
  required String externalUserId,
  required String presenceToken,
  String? devUrl,
  TodenUserTokenProvider? getUserToken,
  PresenceChannelInvoke? invoke,
});

typedef PresenceReportFn = Future<PresenceReportResult> Function({
  required String apiKey,
  required String externalUserId,
  String? devUrl,
});

typedef BackgroundEnableFn = Future<EnableBackgroundResult> Function({
  required String apiKey,
  required String externalUserId,
  String? devUrl,
});

class AutoReportOutcome {
  final EnableBackgroundResult? background;
  final PresenceReportResult? report;
  const AutoReportOutcome(this.background, this.report);
}

Future<AutoReportOutcome?> autoReportPresence(
  VerificationConfig config, {
  PresenceReportFn? report,
  BackgroundEnableFn? enableBackground,
  // false when the "allow all the time" screen makes the ask itself
  // (screens/background_ask_screen.dart): only the report runs here.
  bool askForBackground = true,
}) async {
  if (!shouldAutoReportPresence(config)) return null;
  final userId = config.userId!;
  // The SDK's own calls carry the config's user-token provider, if any.
  final doReport = report ??
      ({required String apiKey, required String externalUserId, String? devUrl}) => AddressPresence.report(
          apiKey: apiKey, externalUserId: externalUserId, devUrl: devUrl, getUserToken: config.getUserToken);
  final doEnable = enableBackground ??
      ({required String apiKey, required String externalUserId, String? devUrl}) => BackgroundPresence.enable(
          apiKey: apiKey, externalUserId: externalUserId, devUrl: devUrl, getUserToken: config.getUserToken);
  // Background first: its permission prompt belongs on the success screen,
  // not a minute later when the report has finished waiting for the watch.
  EnableBackgroundResult? background;
  if (askForBackground && wantsBackgroundPresence(config)) {
    try {
      background = await doEnable(apiKey: config.apiKey, externalUserId: userId, devUrl: config.devUrl);
    } catch (_) {
      background = null;
    }
  }
  PresenceReportResult? reported;
  try {
    reported = await doReport(apiKey: config.apiKey, externalUserId: userId, devUrl: config.devUrl);
  } catch (_) {
    reported = null;
  }
  return AutoReportOutcome(background, reported);
}
