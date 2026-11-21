import 'face_detection.dart';

// ─── Whether the person is responding to a gesture ───────────────────────────
//
// Doing anything with their face that an attempt at one would.
//
// The gesture narrator shows a gesture and then goes. It comes back only for
// someone who is not responding, so it has to tell a person who is trying (and
// should be left to it) from one who is waiting to be shown again. A gesture
// landing is not enough to go on: a nod takes a moment to land, and a person
// half way through one is plainly responding.
//
// Four things are watched: where the head points across (a turn), up and down
// (a nod), how much they smile, and how open the eyes are (a blink). A port of
// the web SDK's liveness/response-watch.ts. The web measures the face mesh's
// points as shares of the face's size; the native detectors here report the
// head's angles and the smile and eye probabilities directly, which do not
// depend on the distance from the camera either, so the thresholds are in
// those units: degrees for the head, 0 to 1 for the smile and the eyes.

/// How far each measure (turn, nod, smile, eyes) has to change to count as the
/// person doing something. Well clear of the detector's own jitter, well under
/// a real attempt (a turn is judged at 25 degrees, a smile at 0.7).
const List<double> kResponseNoticed = [6, 5, 0.25, 0.3];

/// How fast the resting face is re-learnt, per frame, from a person who is
/// only drifting.
const double kResponseSettling = 0.05;

/// The clock the watch and the narrator share: milliseconds since the SDK
/// first asked, never going backwards.
final Stopwatch _clock = Stopwatch()..start();
int responseClockMs() => _clock.elapsedMilliseconds;

List<double> _measures(LivenessFaceData face) => [
      face.headEulerAngleY,
      face.headEulerAngleX,
      face.smilingProbability,
      face.eyeAverageOpenProbability,
    ];

class ResponseWatch {
  List<double>? _resting;
  int _last = 0;

  /// When the person last did something, on the clock [seen] was given; 0 for
  /// never.
  int get respondedAt => _last;

  /// One frame of the face, at [now].
  void seen(LivenessFaceData face, int now) {
    final next = _measures(face);
    final resting = _resting;
    if (resting == null) {
      _resting = next;
      return;
    }
    for (var k = 0; k < next.length; k++) {
      if ((next[k] - resting[k]).abs() > kResponseNoticed[k]) {
        _last = now;
        // Where they are now is what the next move is measured from.
        _resting = next;
        return;
      }
    }
    for (var k = 0; k < resting.length; k++) {
      resting[k] += (next[k] - resting[k]) * kResponseSettling;
    }
  }

  /// A new face, or a new attempt: nothing is known of it yet.
  void reset() {
    _resting = null;
    _last = 0;
  }
}
