import 'package:flutter/foundation.dart' show immutable;

import 'verification_config.dart';

// ─── How a document may be captured ───────────────────────────────────────────
//
// Two workflow switches decide it: `allowDocumentScan` (the live camera with
// auto-capture) and `allowDocumentUpload` (a photo picked from the device).
// Both default to on. At least one must stay on: the server refuses to publish
// a workflow with both off, but a stored snapshot or a prop-configured mount
// can still carry that pair, and a document step with no way to provide the
// document is a dead end. So when upload is off, the camera is on, whatever
// `allowDocumentScan` says.
//
// Resolved in ONE place so the capture screen, the step header and anything
// added later can never disagree about which mode the flow is in. Mirrors the
// web and React Native SDKs' resolution.

@immutable
class DocumentCaptureMethods {
  /// The live camera (viewfinder, auto-capture, side clips).
  final bool scan;

  /// Picking a photo of each side from the device.
  final bool upload;

  const DocumentCaptureMethods({required this.scan, required this.upload});

  /// The camera is never used: each side is a picked photo.
  bool get uploadOnly => upload && !scan;

  @override
  bool operator ==(Object other) =>
      other is DocumentCaptureMethods &&
      other.scan == scan &&
      other.upload == upload;

  @override
  int get hashCode => Object.hash(scan, upload);

  @override
  String toString() => 'DocumentCaptureMethods(scan: $scan, upload: $upload)';
}

/// The effective capture methods for a pair of switches.
///
/// upload = [allowDocumentUpload]; scan = [allowDocumentScan], except that a
/// flow with upload off always scans (both off would leave no way through).
DocumentCaptureMethods documentCaptureMethods({
  required bool allowDocumentScan,
  required bool allowDocumentUpload,
}) =>
    DocumentCaptureMethods(
      scan: allowDocumentScan || !allowDocumentUpload,
      upload: allowDocumentUpload,
    );

/// [documentCaptureMethods] over a mounted (workflow-merged) config.
DocumentCaptureMethods documentCaptureMethodsFor(VerificationConfig config) =>
    documentCaptureMethods(
      allowDocumentScan: config.allowDocumentScan,
      allowDocumentUpload: config.allowDocumentUpload,
    );

// ─── After a side is captured ─────────────────────────────────────────────────
//
// The review screen is off unless `documentReview` is true: a camera scan skips
// it, because
// the scan already held the document steady and checked it was readable. An
// uploaded photo has had no such look from anyone, so it keeps the screen, and
// a side restored from an earlier visit (no source) keeps it too: only a fresh
// capture moves on by itself. Mirrors the web and React Native SDKs.

/// How a side's photo came to be. Null: restored, or not captured.
enum DocumentSideSource { camera, upload }

enum AfterDocumentCapture {
  /// Show the front before asking for the back.
  previewFront,

  /// Move straight to scanning the back.
  scanBack,

  /// Show the review screen.
  review,

  /// Upload and move on, with no review.
  handOver,
}

bool skipsDocumentReview({
  required bool documentReview,
  required List<DocumentSideSource?> sources,
}) =>
    !documentReview && sources.every((s) => s == DocumentSideSource.camera);

AfterDocumentCapture afterDocumentCapture({
  required bool documentReview,
  required bool isBack,
  required bool twoSided,
  required DocumentSideSource? front,
  required DocumentSideSource? back,
  required bool hasBack,
}) {
  final sides = twoSided ? [front, back] : [front];
  if (skipsDocumentReview(documentReview: documentReview, sources: sides)) {
    return AfterDocumentCapture.handOver;
  }
  if (isBack || !twoSided) return AfterDocumentCapture.review;
  final scanOn = !hasBack &&
      skipsDocumentReview(documentReview: documentReview, sources: [front]);
  return scanOn ? AfterDocumentCapture.scanBack : AfterDocumentCapture.previewFront;
}

/// Whether the side clips should try to record sound. Upload-only flows have
/// no clips to record into.
bool recordsDocumentAudio(VerificationConfig config) =>
    config.documentAudio && documentCaptureMethodsFor(config).scan;
