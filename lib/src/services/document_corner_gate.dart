import 'dart:ui' show Rect, Size;

import 'document_corners.dart';
import 'document_framing_gate.dart';

// ─── Corner gate (the capture screen's state for the corners rule) ────────────
//
// Holds what the corner detector last said, so both the auto-capture gates and
// the manual shutter can ask one question: may a photo be taken now?
//
// A device without a corner detector (Android on the camera-plugin fallback, a
// detector that errored) must never be stranded, so the rule only BLOCKS once
// the detector has shown it works. Until then, and whenever a frame could not
// be read, capture behaves exactly as it did before corners existed.

enum CornerDetectorState {
  /// No frame has been read with corners yet (or the last one failed).
  unknown,

  /// The detector reports corners: the rule applies.
  available,

  /// This device has no corner detector.
  unavailable,
}

class DocumentCornerGate {
  CornerDetectorState _state = CornerDetectorState.unknown;
  DocumentCornersProblem? _problem = DocumentCornersProblem.noDocument;
  DocumentQuad? _passingQuad;
  Size? _passingFrame;

  CornerDetectorState get state => _state;

  /// The latest frame's problem; meaningful only while [state] is available.
  DocumentCornersProblem? get problem => _problem;

  /// True when the corners rule forbids a photo right now.
  bool get blocksCapture =>
      _state == CornerDetectorState.available && _problem != null;

  /// What to tell the user while [blocksCapture], else null.
  DocumentHint? get hint {
    if (!blocksCapture) return null;
    return switch (_problem!) {
      DocumentCornersProblem.noDocument => DocumentHint.placeInFrame,
      DocumentCornersProblem.cornerCutOff => DocumentHint.fitCorners,
      DocumentCornersProblem.tooClose => DocumentHint.spaceAround,
    };
  }

  /// The quad to crop the photo to: the latest frame's, and only when it
  /// passed. Null means "crop to the guide", the old behaviour.
  DocumentQuad? get cropQuad =>
      _state == CornerDetectorState.available && _problem == null
          ? _passingQuad
          : null;

  /// Upright pixel size of the frame [cropQuad] was measured in.
  Size? get cropFrame => cropQuad == null ? null : _passingFrame;

  /// Feeds one analysed frame. [frame] is its upright pixel size; [visible]
  /// the part of it the preview shows (see [visibleFrameRegion]); [guide] the
  /// drawn guide in the same space (see [guideInFrame]), when it should bound
  /// the document's size. Returns whether anything the screen shows changed.
  bool update(
    DocumentQuad? quad, {
    required Size frame,
    required Rect visible,
    Rect? guide,
  }) {
    final before = (_state, _problem);
    _state = CornerDetectorState.available;
    var problem = cornersProblem(quad, visible);
    // Corners in view are not enough when the shape found is far bigger than
    // the guide: the document itself is running off the picture and the
    // corners are a box printed on it. As the React Native SDK's judgeCorners.
    if (problem == null && quad != null && guide != null && exceedsGuide(quad, guide)) {
      problem = DocumentCornersProblem.tooClose;
    }
    _problem = problem;
    _passingQuad = _problem == null ? quad : null;
    _passingFrame = _problem == null ? frame : null;
    return before != (_state, _problem);
  }

  /// A frame whose corners could not be read. Before the detector has ever
  /// answered, stop blocking until one can. Once it has, one failed frame is
  /// not a reason to drop the rule: the last verdict stands, as in the React
  /// Native SDK. Dropping it let the shutter take a cut-off document in the
  /// gap.
  bool markUnknown() {
    if (_state == CornerDetectorState.available) return false;
    return _set(CornerDetectorState.unknown);
  }

  /// The device has no corner detector at all.
  bool markUnavailable() => _set(CornerDetectorState.unavailable);

  /// Next side or a retake: forget the last frame, keep what the device can do.
  void reset() {
    _problem = DocumentCornersProblem.noDocument;
    _passingQuad = null;
    _passingFrame = null;
  }

  bool _set(CornerDetectorState next) {
    if (_state == CornerDetectorState.unavailable) return false; // final
    final changed = _state != next;
    _state = next;
    _passingQuad = null;
    _passingFrame = null;
    return changed;
  }

  /// Applies the rule to a gate's verdict: a frame the gate would hold or
  /// shoot is held back while the corners fail, with the corner hint, and the
  /// gate's dwell restarts so it is measured with the corners in view.
  DocumentGuidance apply(DocumentGuidance guidance, {required void Function() resetDwell}) {
    final cornerHint = hint;
    if (cornerHint == null) return guidance;
    if (guidance.framing != DocumentFraming.holding &&
        guidance.framing != DocumentFraming.ready) {
      return guidance;
    }
    resetDwell();
    return DocumentGuidance(DocumentFraming.adjust, cornerHint);
  }
}
