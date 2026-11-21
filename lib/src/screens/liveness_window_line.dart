import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

// ─── The window's line ────────────────────────────────────────────────────────
//
// The line round the liveness camera's window, which fills as the test goes,
// in equal parts with a small gap between them. Drawn by the camera itself and
// by the picture of it on the screen before (widgets/gesture_preview.dart), so
// the two lines are one drawing.
//
// On the full-screen camera it runs a little way OUTSIDE the window, with a
// clear gap between the two, as Apple's face recognition ring does: the line
// reads as a ring round the face rather than as the cutout's own edge, and it
// is heavier than the frame's other lines so it reads over a busy picture
// (web WindowRing, user 2026-11-17).

/// The full-screen line's weight.
const double kRingStroke = 6;

/// The clear gap between the window's edge and the inside of the line.
const double kRingGap = 7;

/// How far the line's centre sits outside the window.
const double kRingOutset = kRingGap + kRingStroke / 2;

/// Gap between two parts, along the line. The ends are round, so what is seen
/// is this less one stroke width: 6 with the line at 6.
const double kRingSegmentGap = 12;

/// The window's outline in [rect], clockwise from twelve o'clock: a circle in
/// the sheet, a tall shape with round ends when full screen. Both are two half
/// circles joined by straight sides (of no length, for the circle).
Path windowOutline(Rect rect) {
  final r = rect.width / 2;
  final top = Rect.fromLTWH(rect.left, rect.top, rect.width, rect.width);
  final bottom =
      Rect.fromLTWH(rect.left, rect.bottom - rect.width, rect.width, rect.width);
  return Path()
    ..moveTo(rect.center.dx, rect.top)
    ..arcTo(top, -math.pi / 2, math.pi / 2, false)
    ..lineTo(rect.right, rect.bottom - r)
    ..arcTo(bottom, 0, math.pi, false)
    ..lineTo(rect.left, rect.top + r)
    ..arcTo(top, math.pi, math.pi / 2, false);
}

/// The outline the line's centre follows for a window of [size], [outset]
/// outside it (negative pulls it in).
Rect lineRect(Size size, double outset) =>
    (Offset.zero & size).inflate(outset);

/// A solid arc sweeping clockwise from the top as the test fills.
class LivenessWindowLinePainter extends CustomPainter {
  final ValueListenable<double> progress;
  final ValueListenable<Color> color;

  // `repaint` is what lets the ring move without a single widget rebuild: the
  // painter re-paints itself when either notifier changes.
  LivenessWindowLinePainter(
    this.progress,
    this.color, {
    this.fixed,
    this.track,
    this.segments = 1,
    this.outside = false,
  }) : super(repaint: Listenable.merge([progress, color]));

  /// Drawn under the arc, all the way round, when the frame has no border of
  /// its own to be the track.
  final Color? track;

  /// Equal parts with a small gap between them. One part is an unbroken line.
  final int segments;

  /// One colour for the whole test, in place of the phase colour.
  final Color? fixed;

  /// The full-screen line: [kRingStroke] wide, [kRingGap] outside the window
  /// (it paints outside its box). Otherwise the frame's own border.
  final bool outside;

  /// Gap between two parts of the border line, along it.
  static const double _gap = 9;

  /// The frame's own border width; the arc IS the border filling in.
  static const double stroke = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value.clamp(0.0, 1.0);
    if (p <= 0 && track == null) return;
    final width = outside ? kRingStroke : stroke;
    final paint = Paint()
      ..color = fixed ?? color.value
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt; // flat ends: a border has no rounded tips
    // Centred on the border ring, which sits in the outermost `stroke` px, or
    // outside the window on the full-screen camera.
    final rect = lineRect(size, outside ? kRingOutset : -stroke / 2);
    final metric = windowOutline(rect).computeMetrics().first;
    final parts = math.max(1, segments);
    if (parts == 1 && track == null) {
      canvas.drawPath(metric.extractPath(0, metric.length * p), paint);
      return;
    }
    // In parts: each has its own stretch of the outline, the track under all
    // of them and the arc over as much as the test has earned.
    final gap = parts == 1 ? 0.0 : (outside ? kRingSegmentGap : _gap);
    final each = metric.length / parts;
    final done = metric.length * p;
    paint.strokeCap = parts == 1 ? StrokeCap.butt : StrokeCap.round;
    final under = track == null
        ? null
        : (Paint()
          ..color = track!
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = paint.strokeCap);
    for (var i = 0; i < parts; i++) {
      final from = i * each + gap / 2;
      final to = (i + 1) * each - gap / 2;
      if (under != null) canvas.drawPath(metric.extractPath(from, to), under);
      if (done > from) {
        canvas.drawPath(metric.extractPath(from, math.min(to, done)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(LivenessWindowLinePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.fixed != fixed ||
      old.track != track ||
      old.segments != segments ||
      old.outside != outside;
}

// ─── The four-sided line, for head directions ─────────────────────────────────
//
// When the test is head directions, the line round the window is four parts,
// one per side. The side the head should go to lights up, and turns green when
// the person has turned that way. When the run's directions are green they
// close into one ring, which pulses once (user, 2026-11-17). A run asks for two
// to four of the four, and the ring closes when those are done; the side no run
// asked for stays a waiting line until then. Left and right are the person's
// own, which on the mirrored picture are the screen's. A port of the web SDK's
// steps/liveness/SideRing.tsx and lib/window-segments.ts sideSegments.
//
// Kept plain (user, 2026-11-18): one line per side and nothing else round it.
//
//   waiting   a quiet white line, the same over any room
//   asked     amber and thicker: the side to turn to
//   done      green
//
// Waiting and asked differ in weight and brightness as well as colour. No tick
// on a done side (tried and removed); the tick in the window after each
// direction, the words and the voice still say a direction is done. One soft
// shadow under the whole line keeps it readable on a pale wall and a dark room
// alike. On a warning the waiting sides go red, as the line of the other tests
// does.

/// A side of the window, as the person sees it on screen.
enum WindowSide { top, right, bottom, left }

/// What a side shows.
enum SideState { idle, asked, done }

/// The side to turn to: the web's `--verification-attention`.
const Color kSideAttention = Color(0xFFFFB020);

/// A waiting side: white, quiet, readable over any room under the shadow.
const Color kSideWaiting = Color(0xB3FFFFFF);

/// The asked side is the heaviest line on screen.
const double kSideLitStroke = kRingStroke + 4;

/// The pulse when the ring closes: how far it grows as it fades, and how long.
const double kSidePulseGrow = 1.07;
const Duration kSidePulse = Duration(milliseconds: 850);

/// Side changes ease over this.
const Duration kSideEase = Duration(milliseconds: 300);

/// The outline [rect] in four equal parts, one per SIDE of the window: each is
/// centred on its side, so the gaps fall at the window's four shoulders rather
/// than at twelve, three, six and nine o'clock.
Map<WindowSide, Path> sideSegments(Rect rect, {double gap = kRingSegmentGap}) {
  final metric = windowOutline(rect).computeMetrics().first;
  final total = metric.length;
  final each = total / 4;
  final g = gap >= each ? 0.0 : gap;
  Path part(int i) {
    final from = (i - 0.5) * each + g / 2;
    final to = (i + 0.5) * each - g / 2;
    // The top side starts before twelve o'clock, where the outline begins: it
    // is the end of the outline, then its beginning.
    if (from < 0) {
      return metric.extractPath(from + total, total)
        ..extendWithPath(_head(metric, to), Offset.zero);
    }
    return metric.extractPath(from, to);
  }

  return {
    WindowSide.top: part(0),
    WindowSide.right: part(1),
    WindowSide.bottom: part(2),
    WindowSide.left: part(3),
  };
}

Path _head(PathMetric metric, double to) => metric.extractPath(0, to);

/// What each side shows, from the side asked for and those done. Done wins: a
/// side that is green stays green.
Map<WindowSide, SideState> sideStates(
  WindowSide? asked,
  Iterable<WindowSide> done,
) {
  final out = {for (final side in WindowSide.values) side: SideState.idle};
  if (asked != null) out[asked] = SideState.asked;
  for (final side in done) {
    out[side] = SideState.done;
  }
  return out;
}

/// The four-sided line round a window of its own box's size, painted
/// [kRingOutset] outside it. [asked] lights its side; [done] are green; once
/// every one of [run] is done the line closes into one green ring and pulses
/// once. [warning] turns the waiting sides that colour.
class LivenessSideLine extends StatefulWidget {
  const LivenessSideLine({
    super.key,
    required this.asked,
    required this.done,
    required this.run,
    this.warning,
    this.green = const Color(0xFF16A34A),
  });

  final WindowSide? asked;
  final List<WindowSide> done;

  /// The sides this run asks for. The side no run asks for stays waiting until
  /// the whole ring closes green.
  final List<WindowSide> run;

  /// Red on a warning; null while all is well.
  final Color? warning;

  /// The flow's success colour.
  final Color green;

  /// Whether every side of [run] is done.
  bool get closed => run.isNotEmpty && run.every(done.contains);

  @override
  State<LivenessSideLine> createState() => _LivenessSideLineState();
}

class _LivenessSideLineState extends State<LivenessSideLine>
    with TickerProviderStateMixin {
  late final AnimationController _ease =
      AnimationController(vsync: this, duration: kSideEase, value: 1);
  late final AnimationController _closing = AnimationController(
    vsync: this,
    duration: kSideEase,
    value: widget.closed ? 1 : 0,
  );
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: kSidePulse);

  late Map<WindowSide, ({Color color, double width})> _from = _look();
  late Map<WindowSide, ({Color color, double width})> _to = _from;

  Map<WindowSide, ({Color color, double width})> _look() {
    final states = sideStates(widget.asked, widget.done);
    final waiting = widget.warning ?? kSideWaiting;
    return {
      for (final side in WindowSide.values)
        side: switch (states[side]!) {
          SideState.done => (color: widget.green, width: kRingStroke),
          SideState.asked => (color: kSideAttention, width: kSideLitStroke),
          SideState.idle => (color: waiting, width: kRingStroke),
        },
    };
  }

  @override
  void didUpdateWidget(LivenessSideLine old) {
    super.didUpdateWidget(old);
    final next = _look();
    if (!_same(next, _to)) {
      _from = _current();
      _to = next;
      _ease.forward(from: 0);
    }
    if (widget.closed != old.closed) {
      if (widget.closed) {
        _closing.forward();
        // One pulse as the sides close into a ring; none with less motion.
        if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
          _pulse.forward(from: 0);
        }
      } else {
        _closing.value = 0;
        _pulse.value = 0;
      }
    }
  }

  bool _same(Map<WindowSide, ({Color color, double width})> a,
          Map<WindowSide, ({Color color, double width})> b) =>
      WindowSide.values.every((s) => a[s] == b[s]);

  Map<WindowSide, ({Color color, double width})> _current() {
    final t = Curves.easeOut.transform(_ease.value);
    return {
      for (final side in WindowSide.values)
        side: (
          color: Color.lerp(_from[side]!.color, _to[side]!.color, t)!,
          width: _from[side]!.width + (_to[side]!.width - _from[side]!.width) * t,
        ),
    };
  }

  @override
  void dispose() {
    _ease.dispose();
    _closing.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _SideLinePainter(
            look: _current,
            closing: _closing,
            pulse: _pulse,
            green: widget.green,
            repaint: Listenable.merge([_ease, _closing, _pulse]),
          ),
        ),
      ),
    );
  }
}

class _SideLinePainter extends CustomPainter {
  _SideLinePainter({
    required this.look,
    required this.closing,
    required this.pulse,
    required this.green,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Map<WindowSide, ({Color color, double width})> Function() look;
  final Animation<double> closing;
  final Animation<double> pulse;
  final Color green;

  /// A close, firm shadow and a wider soft one: the first keeps a white line
  /// readable on a pale wall, the second lifts every line off the picture.
  /// The web's drop-shadow(0 0 1px) and drop-shadow(0 1px 3px), as sigmas.
  static final Paint _firm = Paint()
    ..color = const Color(0x80000000)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5);
  static final Paint _soft = Paint()
    ..color = const Color(0x40000000)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = lineRect(size, kRingOutset);
    final sides = sideSegments(rect);
    final now = look();
    final closed = closing.value;
    final whole = windowOutline(rect);

    void shadowed(Path path, double width) {
      canvas.drawPath(path.shift(const Offset(0, 1)), _soft..strokeWidth = width);
      canvas.drawPath(path, _firm..strokeWidth = width);
    }

    // One shadow under the whole line.
    for (final side in WindowSide.values) {
      shadowed(sides[side]!, now[side]!.width);
    }
    for (final side in WindowSide.values) {
      canvas.drawPath(
        sides[side]!,
        Paint()
          ..color = now[side]!.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = now[side]!.width
          ..strokeCap = StrokeCap.round,
      );
    }
    // The run's directions done: the gaps close, and the ring pulses once.
    if (closed > 0) {
      canvas.drawPath(
        whole,
        Paint()
          ..color = green.withValues(alpha: green.a * closed)
          ..style = PaintingStyle.stroke
          ..strokeWidth = kRingStroke,
      );
    }
    final p = pulse.value;
    if (p > 0 && p < 1) {
      final t = const Cubic(0.22, 1, 0.36, 1).transform(p);
      final grow = 1 + (kSidePulseGrow - 1) * t;
      final centre = rect.center;
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.scale(grow);
      canvas.translate(-centre.dx, -centre.dy);
      canvas.drawPath(
        whole,
        Paint()
          ..color = green.withValues(alpha: 0.75 * (1 - t))
          ..style = PaintingStyle.stroke
          ..strokeWidth = kRingStroke,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SideLinePainter old) => true;
}
