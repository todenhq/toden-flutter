import 'dart:math' as math;

// ─── The ready pause ──────────────────────────────────────────────────────────
//
// Once the face is in place, a beat of "Hold still" before the first gesture
// is asked for, so the person has settled and is listening when it comes,
// rather than hearing it the instant they got into the window (user,
// 2026-11-17). Timed, not counted in frames, so a slow phone pauses as long.
// Moving out of place starts it again (the caller clears `readyAt`). A port of
// the web SDK's liveness/ready-pause.ts; times are milliseconds on the
// caller's clock.

const Duration kReadyPause = Duration(milliseconds: 1500);

/// One frame of a face held in place: when the pause began (null to start it
/// now), and whether to ask for the first gesture now.
({int? readyAt, bool go}) readyPauseStep(int? readyAt, int now) {
  if (readyAt == null) return (readyAt: now, go: false);
  if (now - readyAt < kReadyPause.inMilliseconds) {
    return (readyAt: readyAt, go: false);
  }
  return (readyAt: null, go: true);
}

/// How far through the pause it is, 0 to 1: 0 while the face is not yet in
/// place.
double readyPauseShare(int? readyAt, int now) {
  if (readyAt == null) return 0;
  return math
      .max(0, math.min(1, (now - readyAt) / kReadyPause.inMilliseconds))
      .toDouble();
}
