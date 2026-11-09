import 'selfie_candidates.dart';

// ─── When the final capture takes the selfie ─────────────────────────────────
//
// After the last gesture the step waits for a frame that could be the selfie
// (facing the camera, eyes open, close enough, the face held still:
// selfie_pick.dart and selfie_candidates.dart), held for a
// moment. While it waits it says what to fix. Once the person has had a fair
// chance, the best frame of the run stands in rather than holding them on the
// step. A face gone for about a second breaks the run: the selfie must come
// from the same live run as the gestures, not from whatever is held up after a
// gap. Pure, so the timings are testable. Mirrors the web SDK's capture phase
// in hooks/useLiveness.ts.

/// Usable frames in a row for this long take the shot (the web's 15 frames).
const Duration kSelfieShutterHold = Duration(milliseconds: 500);

/// After this long on the capture, the run's best frame is used.
const Duration kSelfieCaptureWait = Duration(milliseconds: 4000);

/// Guidance waits this long: most faces settle by themselves.
const Duration kSelfiePromptAfter = Duration(milliseconds: 700);

/// The face missing this long on the capture fails the run (`face_lost`).
const Duration kSelfieFaceLostAfter = Duration(milliseconds: 1000);

/// With no usable frame in the whole run after this long, the photo is taken
/// as it was before the selfie was chosen (a detector that never reports a
/// frontal face must not trap anybody on the camera).
const Duration kSelfieNoCandidateTimeout = Duration(seconds: 10);

enum SelfieShutterCall {
  /// Keep waiting.
  wait,

  /// Take the best frame of the run.
  useBest,

  /// No frame of the run qualified: take the current one, as before.
  fallback,
}

/// What the capture should ask for after [verdict], or null for nothing to fix.
enum SelfieGuidance { lookStraight, moveCloser, holdStill }

SelfieGuidance? selfieGuidanceFor(SelfieVerdict? verdict) => switch (verdict) {
      SelfieVerdict.turned => SelfieGuidance.lookStraight,
      SelfieVerdict.far => SelfieGuidance.moveCloser,
      SelfieVerdict.eyes || SelfieVerdict.moving => SelfieGuidance.holdStill,
      _ => null,
    };

class SelfieShutter {
  SelfieShutter(this.start);

  /// When the final capture began.
  final DateTime start;
  DateTime? _usableSince;

  /// One analysed frame's verdict.
  void feed(SelfieVerdict? verdict, DateTime at) {
    final usable = verdict == SelfieVerdict.kept || verdict == SelfieVerdict.worse;
    if (usable) {
      _usableSince ??= at;
    } else {
      _usableSince = null;
    }
  }

  SelfieShutterCall decide(DateTime now, {required bool hasBest}) {
    final waited = now.difference(start);
    final usable = _usableSince;
    if (hasBest && usable != null && now.difference(usable) >= kSelfieShutterHold) {
      return SelfieShutterCall.useBest;
    }
    if (hasBest && waited >= kSelfieCaptureWait) return SelfieShutterCall.useBest;
    if (!hasBest && waited >= kSelfieNoCandidateTimeout) return SelfieShutterCall.fallback;
    return SelfieShutterCall.wait;
  }

  /// Whether to say what to fix yet.
  bool shouldGuide(DateTime now) => now.difference(start) >= kSelfiePromptAfter;

  /// The face has been missing from the capture for too long.
  bool faceLost(DateTime now, DateTime? lastSeen) {
    final from = lastSeen == null || lastSeen.isBefore(start) ? start : lastSeen;
    return now.difference(from) > kSelfieFaceLostAfter;
  }
}
