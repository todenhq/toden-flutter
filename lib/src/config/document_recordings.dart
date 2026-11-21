import 'dart:typed_data';

// Each document side's still and its recording, kept as ONE pair.
//
// The server compares each still with the recording of the same side to catch
// an injected capture, so a recording from a different capture than its still
// is a wrong answer, not just untidy evidence. Continue clears every document
// media id first, then sets each side's still and recording from this capture
// only. A retake with no recording (a gallery photo, a clip that would not
// compress or upload) therefore submits no recording rather than the earlier
// capture's, and a back left from a two-sided ID picked earlier is not
// submitted beside a one-sided one.
//
// Kept apart from the screen so the pairing is tested without a camera
// (test/document_recordings_test.dart).

/// One side as Continue uploads it.
class DocumentSideUpload {
  const DocumentSideUpload({
    required this.side,
    required this.still,
    required this.recording,
  });

  /// 'front' or 'back'.
  final String side;
  final Uint8List still;

  /// This capture's own recording, or null when it has none.
  final String? recording;
}

/// Uploads each side's still, then its own recording.
///
/// [clearDocumentMedia] runs before anything is uploaded. [uploadStill] throws
/// when a still cannot be uploaded (Continue shows the error); a recording is
/// best-effort, so [uploadRecording] answers null when it is skipped or fails.
/// Stops quietly, returning false, as soon as [active] says the screen has gone.
Future<bool> uploadDocumentSides({
  required List<DocumentSideUpload> sides,
  required void Function() clearDocumentMedia,
  required Future<String> Function(DocumentSideUpload side) uploadStill,
  required Future<String?> Function(DocumentSideUpload side, String path)
      uploadRecording,
  required void Function(String side, String mediaId) onStill,
  required void Function(String side, String mediaId) onRecording,
  required bool Function() active,
}) async {
  clearDocumentMedia();
  for (final side in sides) {
    final stillId = await uploadStill(side);
    if (!active()) return false;
    onStill(side.side, stillId);
    final recording = side.recording;
    if (recording == null) continue;
    final String? recordingId;
    try {
      recordingId = await uploadRecording(side, recording);
    } catch (_) {
      continue; // best-effort
    }
    if (!active()) return false;
    if (recordingId != null) onRecording(side.side, recordingId);
  }
  return true;
}

// ─── A recording long enough to be checked ───────────────────────────────────
//
// The server reads a side's recording twice a second and needs three readings
// to compare the photo with it; a shorter recording is "not checked", which
// lets an injected side through unexamined (4 of 11 two-sided captures on the
// back, measured 2026-11-21). So no photo of a side is taken until its
// recording has run this long: auto-capture stays unarmed and the shutter
// waits out the remainder. Here the back's clip already starts with the
// turn-over, so the wait is not added to it.
//
// Mirrors the web SDK's lib/document-recordings.ts and React Native's
// lib/documentRecordings.ts.

/// The least a side's recording runs before its photo is taken.
const Duration kMinRecorded = Duration(milliseconds: 2200);

/// How much longer the photo must wait for its recording: nothing once it has
/// run long enough, or when nothing is recording ([startedAt] is null), so a
/// device that cannot record keeps nobody waiting.
Duration recordingShortBy(DateTime? startedAt, DateTime now) {
  if (startedAt == null) return Duration.zero;
  final left = kMinRecorded - now.difference(startedAt);
  return left.isNegative ? Duration.zero : left;
}
