import 'face_detection.dart';
import 'selfie_pick.dart';

// ─── The best selfie seen so far in one liveness run ─────────────────────────
//
// Rules in selfie_pick.dart. The screen offers the frames it analyses, during
// the gestures (a share of them) and every frame of the final capture. A
// frame that faces the camera with the eyes open and the face close enough is
// kept if it beats the one held; the screen keeps that frame's pixels (the
// [T] it hands over). A broken run (a continuity jump or a face that came back
// after a gap) clears it: the selfie must come from the same unbroken live run
// as the gestures. The Flutter mirror of the web SDK's lib/selfie-candidates.ts,
// plus one rule of its own: the face must have held still for a moment
// (SelfieSteadiness), or a frame from mid-movement can be kept smeared.

/// Why a frame was or was not kept, so the capture can say what to fix.
enum SelfieVerdict { kept, worse, turned, far, eyes, moving }

/// A kept frame: what the screen held of it, where the face is, its score.
class SelfieCandidate<T> {
  final T frame;
  final SelfieFace face;
  final double score;
  const SelfieCandidate(this.frame, this.face, this.score);
}

class SelfieCandidates<T> {
  SelfieCandidates({required bool poseZeroFromRun})
      : _zero = SelfieAngleZero(fromRun: poseZeroFromRun);

  final SelfieAngleZero _zero;
  final SelfieSteadiness _steady = SelfieSteadiness();
  SelfieCandidate<T>? _best;

  /// The best selfie so far.
  SelfieCandidate<T>? get best => _best;

  /// Forget the selfie held (and the resting pose), for a broken run.
  void clear() {
    _best = null;
    _zero.clear();
    _steady.clear();
  }

  /// Every analysed face, so the resting pose (iPhone) follows the run and
  /// the next frame judged knows whether the face has held still.
  void observe(LivenessFaceData face, {DateTime? at}) {
    _zero.add(face);
    _steady.add(face, at ?? DateTime.now());
  }

  /// The verdict on one frame, without keeping anything. [face] is the one
  /// last [observe]d: steadiness is the run's, not the frame's.
  SelfieVerdict judge(LivenessFaceData face, SelfieFace inStill, int frameWidth, int frameHeight) {
    final pose = SelfiePose.of(face, pitchZero: _zero.pitch, rollZero: _zero.roll);
    if (!isFrontal(pose)) return SelfieVerdict.turned;
    if (selfieFrame(inStill, frameWidth, frameHeight) == null) return SelfieVerdict.far;
    if (!eyesOpen(face)) return SelfieVerdict.eyes;
    if (!_steady.steady) return SelfieVerdict.moving;
    return SelfieVerdict.worse;
  }

  /// Offer one analysed frame. [sharpness] measures the frame's selfie region
  /// (null where the frame never reaches Dart); [grab] keeps the frame and is
  /// called only when it beats the one held. [admit] false judges the frame
  /// without keeping it (a source that cannot afford to grab every better
  /// frame).
  SelfieVerdict consider(
    LivenessFaceData face, {
    required SelfieFace inStill,
    required int frameWidth,
    required int frameHeight,
    required T Function() grab,
    double? Function(PixelRect rect)? sharpness,
    bool admit = true,
  }) {
    final verdict = judge(face, inStill, frameWidth, frameHeight);
    if (verdict != SelfieVerdict.worse) return verdict;
    final pose = SelfiePose.of(face, pitchZero: _zero.pitch, rollZero: _zero.roll);
    final rect = selfieFrame(inStill, frameWidth, frameHeight)!;
    final score = selfieScore(pose, sharpness?.call(rect));
    final held = _best;
    if (!admit || (held != null && held.score >= score)) return SelfieVerdict.worse;
    _best = SelfieCandidate(grab(), inStill, score);
    return SelfieVerdict.kept;
  }
}
