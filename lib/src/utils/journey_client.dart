import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../services/api_service.dart' show kSdkVersion;
import '../config/document_capture_check.dart' show CaptureProblemKind;
import 'step_log.dart';

// The SDK and device facts the drop-off journey carries (`stepLog.client`):
// which SDK, which platform and OS version, phone or tablet. No identifiers:
// never a model name, a device id or anything the applicant set. Mirrors the
// web SDK's and the React Native SDK's journey client.

/// The OS version as major.minor at most ("17.2", "15").
@visibleForTesting
String? majorMinor(String? version) {
  if (version == null) return null;
  final m = RegExp(r'(\d+)(?:\.(\d+))?').firstMatch(version);
  if (m == null) return null;
  return m.group(2) == null ? m.group(1) : '${m.group(1)}.${m.group(2)}';
}

/// What can be told at once, without a plugin call.
Map<String, dynamic> baseJourneyClient() {
  final ios = !kIsWeb && Platform.isIOS;
  final android = !kIsWeb && Platform.isAndroid;
  return {
    'sdk': 'flutter',
    'version': kSdkVersion,
    'platform': ios ? 'ios' : android ? 'android' : 'web',
    if (ios) 'os': 'iOS',
    if (android) 'os': 'Android',
  };
}

/// Sets the client on the step log at once, then adds the OS version and the
/// form factor once the device plugin answers. Never throws.
Future<void> recordJourneyClient() async {
  final base = baseJourneyClient();
  StepLog.setClient(base);
  try {
    if (kIsWeb) return;
    final plugin = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final i = await plugin.iosInfo;
      StepLog.setClient({
        ...base,
        if (majorMinor(i.systemVersion) != null) 'osVersion': majorMinor(i.systemVersion),
        'formFactor': i.model.toLowerCase().contains('ipad') ? 'tablet' : 'phone',
      });
    } else if (Platform.isAndroid) {
      final a = await plugin.androidInfo;
      StepLog.setClient({
        ...base,
        if (majorMinor(a.version.release) != null) 'osVersion': majorMinor(a.version.release),
        'formFactor': _androidFormFactor(),
      });
    }
  } catch (_) {
    // No plugin (a test, an old embedding): the base client stands.
  }
}

/// A tablet by the screen's shortest side, the way Android itself draws the line.
String _androidFormFactor() {
  try {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return 'phone';
    final view = views.first;
    final shortest = view.physicalSize.shortestSide / view.devicePixelRatio;
    return shortest >= 600 ? 'tablet' : 'phone';
  } catch (_) {
    return 'phone';
  }
}

/// Records a journey event without ever failing the caller.
void recordJourneyEvent(String code, {String? detail}) {
  try {
    StepLog.recordEvent(code, detail: detail);
  } catch (_) {}
}

/// Why a camera would not start, as the journey names it: another app holding
/// it, no camera at all, or anything else.
String cameraFailureDetail(String code, String? description) {
  final text = '$code ${description ?? ''}'.toLowerCase();
  if (text.contains('in use') || text.contains('inuse') || text.contains('busy') || text.contains('maxcamerasinuse')) {
    return 'in_use';
  }
  if (text.contains('not found') || text.contains('notfound') || text.contains('no camera') || text.contains('nocamera')) {
    return 'not_found';
  }
  return 'other';
}

/// The journey's name for an upload, by the media type it was sent as; null
/// for uploads that run in the background without the applicant (the silent
/// frames, the depth frame), whose failure stops no one.
String? uploadDetail(String mediaType) {
  if (mediaType == 'silent_capture' || mediaType == 'liveness_depth') return null;
  if (mediaType.contains('video')) return 'video';
  if (mediaType.startsWith('document') || mediaType == 'business_document') return 'document';
  if (mediaType == 'selfie') return 'selfie';
  if (mediaType.contains('supporting')) return 'supporting_document';
  if (mediaType.contains('proof_of_address') || mediaType == 'poa') return 'proof_of_address';
  return 'other';
}

/// Why a liveness attempt failed, as the journey names it, from the error the
/// liveness state carries (providers/liveness_provider.dart).
String livenessFailureDetail(String? error, {bool multipleFaces = false}) {
  if (multipleFaces) return 'multiple_faces';
  return switch (error) {
    'face_swap' => 'face_changed',
    'face_lost' => 'no_face',
    'Challenge timed out' => 'timeout',
    _ => 'other',
  };
}

/// A document photo the capture check sent back, as the journey names it.
String captureRejectionDetail(CaptureProblemKind kind) => switch (kind) {
      CaptureProblemKind.notComplete => 'cut_off',
      CaptureProblemKind.noFace => 'other',
      CaptureProblemKind.noBarcode => 'other',
    };

/// A failed chip read, as the journey names it; null for the applicant
/// cancelling the read themselves, which is no failure.
String? nfcFailureDetail(String code, String message) {
  if (code == 'cancelled') return null;
  if (code == 'unavailable') return 'not_supported';
  if (code == 'auth_failed') return 'access_denied';
  if (message.toLowerCase().contains('timeout')) return 'timeout';
  if (code == 'tag_lost' || code == 'read_failed') return 'read_error';
  return 'other';
}

/// The applicant closing the flow. Not after it was submitted: closing the
/// finished screen is the end of a journey, not a drop-off.
void recordFlowClosed() {
  if (StepLog.currentStep == 'submitted') return;
  recordJourneyEvent('flow_closed');
}
