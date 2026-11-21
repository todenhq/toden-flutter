import 'package:flutter/foundation.dart' show ValueNotifier, listEquals;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/theme.dart';
import '../liveness/capture_ring.dart' show advanceTarget, easeToward;
import '../liveness/gesture_preview_timeline.dart';
import '../liveness/toon_face.dart';
import '../liveness/toon_shades.dart';
import '../screens/liveness_cutout.dart' show kLivenessCutoutAspect;
import '../screens/liveness_window_line.dart';
import 'preview_tick.dart';

// ─── A small picture of the liveness camera ───────────────────────────────────
//
// For the screen that comes before it: the camera's own window with its line
// round it, and in it a cartoon person doing what the camera may ask for
// (turn, nod, blink, smile). The line is cut into four parts and one fills
// green with each gesture, as it does in the camera, and each gesture ends as
// it does there: a light green cover over the window and a tick
// (liveness/gesture_preview_timeline.dart has the timings).
//
// The turn and the nod slide the face across the head (the hair less, the
// outline narrowing a touch), which reads as the head turning; the blink and
// the smile swap in the character's own drawings of them.
//
// Painted in shades of the workflow's own colour, skin, hair and clothes
// alike, so the person has no skin colour and stands for anyone
// (liveness/toon_shades.dart). A picture: hidden from screen readers (the words
// beside it say what happens next) and still, at rest, for a person who has
// asked for less motion. The character is "Toon Head" by Johan Melin,
// CC BY 4.0, with short hair of our own (liveness/toon_face.dart). A port of
// the web SDK's GesturePreview.

const int _kLineParts = 4;
/// How far the line reaches past the window: it runs OUTSIDE it, a clear gap
/// away, as on the camera (liveness_window_line.dart, the web's and React
/// Native's WindowRing, which their primers reuse).
const double _kLineReach = kRingOutset + kRingStroke / 2;

class GesturePreview extends StatefulWidget {
  const GesturePreview({
    super.key,
    this.gestures = kAllPreviewGestures,
    this.width = 176,
  });

  /// The gestures to run through, round and round. None: it comes in and
  /// holds still, as a passive check asks, and the line closes as it does.
  final List<PreviewGesture> gestures;

  /// The width of the window.
  final double width;

  @override
  State<GesturePreview> createState() => _GesturePreviewState();
}

class _GesturePreviewState extends State<GesturePreview>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final _frame = ValueNotifier<PreviewFrame>(previewFrameAt(const [], 0));
  final _line = ValueNotifier<double>(0);
  final _lineColour = ValueNotifier<Color>(UiColors.success);
  double _lineTarget = 0;
  Duration _last = Duration.zero;
  int _round = 0;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still && (_ticker.isActive || still)) return;
    _still = still;
    if (still) {
      if (_ticker.isActive) _ticker.stop();
      _frame.value = const PreviewFrame(
        opacity: 1,
        scale: 1,
        pose: kPreviewRest,
        progress: 0,
        passed: false,
        round: 0,
      );
      _line.value = 0;
    } else {
      _restart();
    }
  }

  void _restart() {
    if (_ticker.isActive) _ticker.stop();
    _last = Duration.zero;
    _lineTarget = 0;
    _line.value = 0;
    _round = 0;
    _frame.value = previewFrameAt(widget.gestures, 0);
    _ticker.start();
  }

  @override
  void didUpdateWidget(GesturePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.gestures, widget.gestures) && !_still) _restart();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    final frame = previewFrameAt(widget.gestures, elapsed.inMicroseconds / 1e6);
    // Each time round, the line starts again from nothing.
    if (frame.round != _round) {
      _round = frame.round;
      _lineTarget = 0;
      _line.value = 0;
    }
    _lineTarget = advanceTarget(_lineTarget, frame.progress);
    _line.value = easeToward(_line.value, _lineTarget, dt);
    _frame.value = frame;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _line.dispose();
    _lineColour.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.myazaColors.primary;
    final shades = toonShades(primary);
    final width = widget.width;
    final height = (width * kLivenessCutoutAspect).roundToDouble();
    // Wider than the window and dropped a little, so the face fills it and
    // the shoulders run off its bottom edge, as in the camera.
    final drawing = (width * 1.36).roundToDouble();
    final unit = drawing / kToonSide;
    SvgPicture part(String name) => SvgPicture.string(
          toonPartSvg(name, shades),
          width: drawing,
          height: drawing,
        );
    // Built once per build; the frames only move and swap them.
    final back = part('back');
    final hairBehind = part('hairBehind');
    final head = part('head');
    final brows = part('brows');
    final eyesOpen = part('eyesOpen');
    final eyesShut = part('eyesShut');
    final eyesHappy = part('eyesHappy');
    final mouthRest = part('mouthRest');
    final mouthSmile = part('mouthSmile');
    final hair = part('hair');

    // An SVG `translate(x y) scale(sx 1)` in the drawing's units.
    Widget moved(Widget child, {double x = 0, double y = 0, double sx = 1}) =>
        Transform(
          transform: Matrix4(
            sx, 0, 0, 0, //
            0, 1, 0, 0, //
            0, 0, 1, 0, //
            x * unit, y * unit, 0, 1,
          ),
          child: child,
        );
    // Every part stays mounted, so swapping one in never waits on a load.
    Widget shown(bool on, Widget child) =>
        Offstage(offstage: !on, child: child);

    return ExcludeSemantics(
      child: SizedBox(
        width: width + _kLineReach * 2,
        height: height + _kLineReach * 2,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(_kLineReach),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(width / 2),
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: cameraRoom(primary)),
                  child: ValueListenableBuilder<PreviewFrame>(
                    valueListenable: _frame,
                    builder: (context, frame, _) {
                      final pose = frame.pose;
                      final x = pose.across * kPreviewTurnSlide;
                      final y = pose.down * kPreviewNodSlide;
                      // The head narrows a touch as it turns away, and drops
                      // a little in a nod.
                      final narrow = 1 - 0.035 * pose.across.abs();
                      final person = Stack(
                        clipBehavior: Clip.none,
                        children: [
                          back,
                          // The back of the head goes the other way, which
                          // is what makes it turn.
                          moved(hairBehind, x: -x * 0.2, y: y * 0.1),
                          moved(head,
                              x: kToonSide / 2 * (1 - narrow),
                              y: y * 0.15,
                              sx: narrow),
                          moved(
                            Stack(children: [
                              shown(!pose.smile, mouthRest),
                              shown(pose.smile, mouthSmile),
                              shown(!pose.shut && !pose.smile, eyesOpen),
                              shown(pose.shut, eyesShut),
                              shown(pose.smile, eyesHappy),
                              brows,
                            ]),
                            x: x,
                            y: y,
                          ),
                          moved(hair, x: x * 0.35, y: y * 0.4),
                        ],
                      );
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Opacity(
                            opacity: frame.opacity.clamp(0.0, 1.0),
                            child: Transform.scale(
                              scale: frame.scale,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned(
                                    left: (width - drawing) / 2,
                                    top: (height - drawing) / 2 + drawing * 0.1,
                                    width: drawing,
                                    height: drawing,
                                    child: person,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          PreviewPassCover(on: frame.passed),
                          PreviewTick(on: frame.passed),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            // Over the window itself; the painter draws outside it.
            Padding(
              padding: const EdgeInsets.all(_kLineReach),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: LivenessWindowLinePainter(
                    _line,
                    _lineColour,
                    fixed: UiColors.success,
                    track: primary.withValues(alpha: 0.55),
                    segments: _kLineParts,
                    outside: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
