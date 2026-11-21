import 'package:crypto/crypto.dart';

import '../presence/presence_report_proof.dart' show boundChallenge;
import '../services/device_attestation.dart';
import '../services/device_intel_platform.dart';

// ─── Signed capture: the platform's proof over the uploaded selfie and video ──
//
// The app hashes the exact bytes it uploads for the selfie, the liveness video
// and, on an iPhone with a Face ID camera, its depth frame
// (liveness/depth_frame.dart), writes the digest text below over those hashes, and asks the platform
// (App Attest on iPhone, Play Integrity on Android) to sign
// SHA-256(challenge || SHA-256(digest)), the same binding a presence report
// uses. Core hashes each upload as it arrives and checks both agree before it
// checks the signature, so a verified proof means these files came from the
// genuine app on a genuine device. Best-effort: anything that cannot be proved
// (a simulator, no Play Integrity project, an error, the time budget) is left
// off and the verification goes without it.
//
// `captureDigestText` is the wire contract, mirrored by kyc-core
// (lib/liveness-capture/signed-capture.ts) and the React Native SDK. All share
// one test vector: change it in every copy in the same commit, or no capture
// ever verifies.

/// The uploads a signed capture covers, in the digest's order.
const kSignedCaptureSlots = ['selfie', 'livenessVideo', 'livenessDepth'];

/// The slots with a line in every digest, empty when not sent. The depth
/// frame came later (2026-11-19) and adds its line only when one was sent, so
/// a proof without one reads exactly as it did before.
const _alwaysListedSlots = ['selfie', 'livenessVideo'];

/// Lowercase hex SHA-256 of [bytes]: what Core records for an upload.
String uploadSha256(List<int> bytes) => sha256.convert(bytes).toString();

/// An upload's hash, kept with the media id the upload came back as.
typedef UploadHash = ({String mediaId, String sha256});

/// The hashes to sign, by slot: only those whose media id is still the one
/// the verification sends ([sent]), so a retake or a restored session can
/// never sign a file the verification does not name.
Map<String, String> signableUploads({
  required Map<String, String?> sent,
  required Map<String, UploadHash> uploaded,
}) =>
    {
      for (final MapEntry(key: slot, value: upload) in uploaded.entries)
        if (sent[slot] == upload.mediaId) slot: upload.sha256,
    };

/// The text the platform's proof covers: one line per upload, empty for a
/// selfie or video that was not sent; the depth frame's line only when sent.
String captureDigestText(Map<String, String> media) {
  final depth = media['livenessDepth'] ?? '';
  return [
    'toden-capture-v1',
    for (final slot in _alwaysListedSlots)
      '$slot:${(media[slot] ?? '').toLowerCase()}',
    if (depth.isNotEmpty) 'livenessDepth:${depth.toLowerCase()}',
  ].join('\n');
}

/// `integrity.captureProof` for the verification, or null when there is
/// nothing to sign or the platform gave no proof. Never throws; bounded by
/// [budget] like every other attestation.
Future<Map<String, dynamic>?> signCapture({
  required Map<String, String> media,
  required String? platform,
  required DeviceIntelPlatform native,
  required ChallengeFetcher fetchChallenge,
  String? cloudProjectNumber,
  Duration budget = kAttestationBudget,
}) async {
  final signed = {
    for (final slot in kSignedCaptureSlots)
      if (media[slot] != null) slot: media[slot]!.toLowerCase(),
  };
  if (signed.isEmpty) return null;
  final digestText = captureDigestText(signed);
  final attestation = await collectAttestation(
    platform: platform,
    native: native,
    fetchChallenge: fetchChallenge,
    cloudProjectNumber: cloudProjectNumber,
    budget: budget,
    bindChallenge: (challenge) => boundChallenge(challenge, digestText),
  );
  if (attestation == null) return null;
  return {'media': signed, 'attestation': attestation};
}
