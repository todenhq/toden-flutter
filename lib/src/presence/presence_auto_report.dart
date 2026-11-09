import '../config/verification_config.dart';
import 'background_presence.dart';
import 'presence_reporter.dart';
import 'presence_store.dart';

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
Future<void> keepPresenceToken(VerificationConfig config, String? token) async {
  if (shouldAutoReportPresence(config)) await savePresenceToken(config.userId!, token);
}

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
  PresenceReportFn report = AddressPresence.report,
  BackgroundEnableFn enableBackground = BackgroundPresence.enable,
  // false when the "allow all the time" screen makes the ask itself
  // (screens/background_ask_screen.dart): only the report runs here.
  bool askForBackground = true,
}) async {
  if (!shouldAutoReportPresence(config)) return null;
  final userId = config.userId!;
  // Background first: its permission prompt belongs on the success screen,
  // not a minute later when the report has finished waiting for the watch.
  EnableBackgroundResult? background;
  if (askForBackground && wantsBackgroundPresence(config)) {
    try {
      background = await enableBackground(apiKey: config.apiKey, externalUserId: userId, devUrl: config.devUrl);
    } catch (_) {
      background = null;
    }
  }
  PresenceReportResult? reported;
  try {
    reported = await report(apiKey: config.apiKey, externalUserId: userId, devUrl: config.devUrl);
  } catch (_) {
    reported = null;
  }
  return AutoReportOutcome(background, reported);
}
