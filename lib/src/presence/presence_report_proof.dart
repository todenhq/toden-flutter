import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';

import '../services/api_service.dart' show DeviceChallenge;
import '../services/device_attestation.dart';
import '../services/device_intel_platform.dart';
import '../services/device_signals.dart';
import '../services/fingerprint_service.dart';

// ─── Proving a presence report ───────────────────────────────────────────────
//
// The server only counts a report from the phone the check was started on, and
// from a phone that can attest it wants the platform's proof over these exact
// contents, so a report cannot be scripted or edited on the way out.
// Best-effort: anything that cannot be proved is left off and the report goes.
//
// `reportDigestText` is the wire contract, mirrored by kyc-core
// (lib/address-intel/presence/report-proof.ts), the React Native SDK and this
// plugin's Kotlin and Swift background paths. All share one test vector:
// change it in every copy in the same commit, or no report ever verifies.

class ReportObservation {
  final String day;
  final String source;
  final int dwellMinutes;
  final bool nightPresent;
  final int samples;
  final bool mockLocation;
  final bool emulator;

  const ReportObservation({
    required this.day,
    required this.source,
    required this.dwellMinutes,
    required this.nightPresent,
    required this.samples,
    this.mockLocation = false,
    this.emulator = false,
  });

  Map<String, dynamic> toJson() => {
        'day': day,
        'source': source,
        'dwellMinutes': dwellMinutes,
        'nightPresent': nightPresent,
        'samples': samples,
        if (mockLocation || emulator)
          'integrity': {
            if (mockLocation) 'mockLocation': true,
            if (emulator) 'emulator': true,
          },
      };
}

String reportDigestText({
  required String externalUserId,
  String? stableId,
  String? deviceId,
  required List<ReportObservation> observations,
}) {
  int flag(bool v) => v ? 1 : 0;
  return [
    'toden-presence-report-v1',
    externalUserId,
    stableId ?? '',
    deviceId ?? '',
    ...observations.map((o) => [
          o.day,
          o.source,
          o.dwellMinutes,
          flag(o.nightPresent),
          o.samples,
          flag(o.mockLocation),
          flag(o.emulator),
        ].join('|')),
  ].join('\n');
}

/// SHA-256(challenge || digest): what the platform is asked to sign.
List<int> boundChallenge(List<int> challenge, String digestText) {
  final digest = sha256.convert(utf8.encode(digestText)).bytes;
  return sha256.convert([...challenge, ...digest]).bytes;
}

/// False on a real phone and when it cannot be told: only the OS's own "this
/// is a simulator" counts.
Future<bool> runningOnEmulator() async {
  try {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) return !(await info.androidInfo).isPhysicalDevice;
    if (Platform.isIOS) return !(await info.iosInfo).isPhysicalDevice;
  } catch (_) {
    // Unknown is not an emulator.
  }
  return false;
}

/// `device` and `attestation` for the report body; missing parts are omitted.
Future<Map<String, dynamic>> reportProof({
  required Dio dio,
  required String externalUserId,
  required List<ReportObservation> observations,
  String? playIntegrityProject,
}) async {
  final deviceId = await FingerprintService.instance.persistentDeviceId();
  final stableId = await DeviceSignals.instance.stableId();
  final digestText = reportDigestText(
    externalUserId: externalUserId,
    stableId: stableId,
    deviceId: deviceId,
    observations: observations,
  );
  final attestation = await collectAttestation(
    platform: Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : null),
    native: const MethodChannelDeviceIntel(),
    cloudProjectNumber: playIntegrityProject,
    bindChallenge: (challenge) => boundChallenge(challenge, digestText),
    fetchChallenge: ({required String platform, String? keyId}) async {
      try {
        final response = await dio.post<Map<String, dynamic>>('/api/v1/device/challenge', data: {
          'platform': platform,
          if (keyId != null) 'keyId': keyId,
        });
        return DeviceChallenge.fromJson(response.data);
      } catch (_) {
        return null;
      }
    },
  );
  return {
    if (deviceId != null || stableId != null)
      'device': {
        if (deviceId != null) 'deviceId': deviceId,
        if (stableId != null) 'stableId': stableId,
      },
    if (attestation != null) 'attestation': attestation,
  };
}
