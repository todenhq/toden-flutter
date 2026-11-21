import 'dart:math' as math;

// ─── The document intro's picture, frame by frame ─────────────────────────────
//
// The document the person chose, in the camera's frame marks
// (widgets/document_scan_preview.dart). A band of light passes down it as it is
// read, then a light green cover and a tick say it worked. A document with two
// sides then turns over, catching the light as it turns, its back is read the
// same way, and it turns back to start again. A passport page, or any
// one-sided document, is read again after a rest. It comes in once.
//
// Pure: everything the picture shows at a moment, from the seconds since it
// started. The numbers are the web SDK's DocumentScanPreview's.

/// How the loop runs, in seconds.
const double kScanSeconds = 1.6;
const double kScanPass = 0.8;
const double kScanRest = 0.25;
const double kScanFlip = 0.75;

/// One side: read it, the tick, a beat, turn it over.
const double kScanSide = kScanSeconds + kScanPass + kScanRest + kScanFlip;

/// How long it takes to come in, once.
const double kScanComingIn = 0.5;

double _ease(double t) =>
    t <= 0 ? 0 : (t >= 1 ? 1 : (1 - math.cos(math.pi * t)) / 2);

class DocumentScanFrame {
  const DocumentScanFrame({
    required this.opacity,
    required this.scale,
    required this.band,
    required this.bandOpacity,
    required this.passed,
    required this.turn,
    required this.lift,
  });

  /// Coming in.
  final double opacity;
  final double scale;

  /// Where the band of light's bright edge is, 0 (top) to 1 (bottom).
  final double band;
  final double bandOpacity;

  /// The cover and the tick are up.
  final bool passed;

  /// How far it has turned, in half turns: 0 the front, 1 the back, 2 the
  /// front again.
  final double turn;

  /// How far it rises as it turns, 0 to 1, at its most when edge on. The
  /// light it catches follows it.
  final double lift;
}

/// The picture [seconds] after it started.
DocumentScanFrame documentScanFrameAt(double seconds,
    {required bool twoSided}) {
  // Coming in, once.
  final arriving = math.min(1.0, seconds / kScanComingIn);
  final clock = math.max(0.0, seconds - kScanComingIn);
  final double t;
  var turn = 0.0;
  var lift = 0.0;
  if (!twoSided) {
    t = clock % (kScanSeconds + kScanPass + kScanRest * 3);
  } else {
    final at = clock % (kScanSide * 2);
    final onBack = at >= kScanSide;
    t = at - (onBack ? kScanSide : 0);
    // Then it turns over, catching the light as it goes.
    final turning =
        _ease((t - kScanSeconds - kScanPass - kScanRest) / kScanFlip);
    turn = (onBack ? 1 : 0) + turning;
    lift = math.sin(math.pi * turning);
  }
  final reading = t >= 0 && t < kScanSeconds;
  return DocumentScanFrame(
    opacity: arriving,
    scale: 0.94 + 0.06 * _ease(arriving),
    band: _ease(t / kScanSeconds),
    bandOpacity: reading
        ? math.min(1.0, math.min(t / 0.18, (kScanSeconds - t) / 0.18))
        : 0,
    passed: t >= kScanSeconds && t < kScanSeconds + kScanPass,
    turn: turn,
    lift: lift,
  );
}
