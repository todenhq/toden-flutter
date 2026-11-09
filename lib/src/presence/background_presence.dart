import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/resolve_url.dart';
import 'always_location.dart';
import 'presence_report_proof.dart';
import 'presence_store.dart';

export 'always_location.dart';

// ─── The BACKGROUND presence tier — native geofencing ────────────────────────
//
// The OS wakes the app on fence crossings around the stored pin: entries stamp
// a timestamp, exits fold the dwell span into per-day aggregates and flush
// them, all natively so it works with the app killed. Only derived day records
// ever leave the phone, the same privacy floor as the foreground tier.
//
// Permissions are requested HERE in Dart (geolocator's documented two-step:
// while-in-use first, then the escalation to "always"); the native side never
// prompts. The host must declare the background-location entries itself
// (Android manifest + iOS Info.plist), because that declaration changes an
// app's store review posture and the decision belongs to the host, made
// knowingly. Mirrors the RN SDK's presence/background.ts.

/// The fence radius, in metres. The server credits a fix as at-address within
/// max(250, accuracy, capped 1km) — see kyc-core address-intel/presence — and
/// the RN tier registers the same 250. Keep the three in lockstep.
const int kGeofenceRadiusMeters = 250;

enum BackgroundPresenceReason {
  started,
  noPin,
  permissionDenied,
  backgroundDenied,
  unavailable,
}

class EnableBackgroundResult {
  final bool started;
  final BackgroundPresenceReason reason;

  /// On a refusal: false when the OS answered without showing a prompt, which
  /// leaves Settings as the only way forward.
  final bool osPrompted;
  const EnableBackgroundResult(this.started, this.reason, {this.osPrompted = true});
}

/// Whether the host should send the person to Settings: the OS refused without
/// asking, so there was no answer of theirs to respect.
bool needsSettings(EnableBackgroundResult? result) {
  if (result == null || result.osPrompted) return false;
  return result.reason == BackgroundPresenceReason.permissionDenied ||
      result.reason == BackgroundPresenceReason.backgroundDenied;
}

/// Where a tap on "turn on" leads.
enum AllowNext { on, off, offer }

/// [AllowNext.offer] keeps the screen and offers Settings as the person's own
/// choice. Settings is never opened for them: the signal behind `osPrompted`
/// has read "no prompt" with the prompt on screen, and a prompt blocks touches,
/// so a button is harmless behind one where a jump to Settings is not.
AllowNext afterAllow(EnableBackgroundResult? result) {
  if (result?.started == true) return AllowNext.on;
  return needsSettings(result) ? AllowNext.offer : AllowNext.off;
}

class BackgroundPresence {
  BackgroundPresence._();

  static const MethodChannel _channel = MethodChannel('kyc_sdk_flutter/presence');

  /// Arms the native geofence for [externalUserId]'s stored pin. Asks for the
  /// location permissions on the way (while-in-use, then always). Never
  /// throws; every refusal comes back as a reason.
  static Future<EnableBackgroundResult> enable({
    required String apiKey,
    required String externalUserId,
    String? devUrl,
  }) async {
    final pin = await loadPresencePin(externalUserId);
    if (pin == null) {
      return const EnableBackgroundResult(false, BackgroundPresenceReason.noPin);
    }
    final answer = await requestAlwaysLocation();
    final permission = answer.permission;
    if (permission == null) {
      return const EnableBackgroundResult(false, BackgroundPresenceReason.unavailable);
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return EnableBackgroundResult(
          false, BackgroundPresenceReason.permissionDenied, osPrompted: answer.osPrompted);
    }
    if (permission != LocationPermission.always) {
      return EnableBackgroundResult(
          false, BackgroundPresenceReason.backgroundDenied, osPrompted: answer.osPrompted);
    }
    try {
      final base = resolveBaseUrl(apiKey, devUrl: devUrl);
      final ok = await _channel.invokeMethod<bool>('enablePresence', {
        if (pin.presenceToken != null) 'presenceToken': pin.presenceToken,
        'lat': pin.lat,
        'lng': pin.lng,
        'radius': kGeofenceRadiusMeters,
        'baseUrl': base,
        'apiKey': apiKey,
        'externalUserId': externalUserId,
        'playIntegrityProject': pin.playIntegrityProject,
        'emulator': await runningOnEmulator(),
      });
      return ok == true
          ? const EnableBackgroundResult(true, BackgroundPresenceReason.started)
          : const EnableBackgroundResult(false, BackgroundPresenceReason.unavailable);
    } catch (_) {
      // MissingPluginException included: a host without the native side
      // simply has no background tier.
      return const EnableBackgroundResult(false, BackgroundPresenceReason.unavailable);
    }
  }

  /// Removes the native geofence and clears the stored reporter config.
  static Future<void> disable() async {
    try {
      await _channel.invokeMethod<void>('disablePresence');
    } catch (_) {
      // Best-effort by contract.
    }
  }

  /// A "still here" check-in from an inside reading the foreground reporter
  /// already took on app open. The native side records the running stay now
  /// rather than when the person leaves, so someone who hardly leaves home
  /// still earns background evidence. A no-op unless the background tier is
  /// armed; iOS confirms with its own region state. Never throws.
  static Future<void> checkIn({
    required double lat,
    required double lng,
    double? accuracy,
    required DateTime at,
    bool mocked = false,
  }) async {
    try {
      await _channel.invokeMethod<bool>('presenceCheckIn', {
        'lat': lat,
        'lng': lng,
        if (accuracy != null) 'accuracy': accuracy,
        'timestamp': at.millisecondsSinceEpoch,
        'mocked': mocked,
      });
    } catch (_) {
      // Best-effort by contract.
    }
  }

  /// Whether the native geofence is registered right now.
  static Future<bool> isArmed() async {
    try {
      return await _channel.invokeMethod<bool>('isPresenceArmed') == true;
    } catch (_) {
      return false;
    }
  }
}
