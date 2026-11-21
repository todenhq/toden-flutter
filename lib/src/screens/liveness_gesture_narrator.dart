import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../liveness/liveness_types.dart';
import '../liveness/narrator_pose.dart';
import '../liveness/response_watch.dart';
import '../providers/liveness_provider.dart';
import 'liveness_narrator_painter.dart';

// ─── The gesture narrator ─────────────────────────────────────────────────────
//
// A face icon, in the manner of a phone's face unlock, that pops up in the
// camera's window, acts out the gesture being asked for once, and goes. It
// works like a hint in a game: quick to come, quicker to go, so it is out of
// the way before the person moves.
//
// It comes back to show again only to someone who is not responding: nothing
// done with their face for a while (liveness/response_watch.dart), never on a
// plain timer. A person who is trying, and has not got it yet, is left to it.
// The screen gives it no gesture while the person is asked to move into place,
// for the flash or the hold, once the gesture has landed, or on a failure.
//
// The words above the window say the same, so it is hidden from screen
// readers. With less motion asked for it does not move: it shows the pose that
// says the gesture, then fades. A workflow can switch it off
// (`livenessGestureGuide: false`). A port of the web SDK's GestureNarrator.

/// How long the person may do nothing before it shows them again.
const Duration kNarratorPatience = Duration(seconds: 5);

/// How often it looks to see whether they have gone quiet.
const Duration kNarratorLookEvery = Duration(milliseconds: 400);

/// How long the still pose stays, with less motion asked for.
const Duration kNarratorStill = Duration(milliseconds: 2500);

/// Its side, as a share of the window's width.
const double kNarratorSize = 0.6;

const Duration _appearFade = Duration(milliseconds: 200);
const Duration _appearScale = Duration(milliseconds: 380);
const Duration _leave = Duration(milliseconds: 180);
const Duration _fadeOnly = Duration(milliseconds: 260);
const Curve _overshoot = Cubic(0.34, 1.4, 0.64, 1);
const double _scaleFrom = 0.86;

/// The gesture the narrator acts out, or null for it to go. It acts out a
/// gesture while it is being asked for and goes once it lands. Neither the
/// flash nor the passive hold has a gesture, it keeps out of the way while the
/// person is asked to move into place (or back into view, or alone), and a
/// workflow can switch it off ([enabled], `livenessGestureGuide`). A wrong
/// gesture is not a reason to go: that is when it helps.
NarratorGesture? narratedGestureFor(LivenessState state,
    {required bool enabled}) {
  if (!enabled || state.phase != LivenessPhase.challenge) return null;
  final outOfPlace = state.positionGuidance != null ||
      state.multipleFaces ||
      !state.faceDetected;
  if (outOfPlace) return null;
  return narratorGestureFor(state.activeChallenge);
}

class GestureNarrator extends StatefulWidget {
  const GestureNarrator({
    super.key,
    required this.gesture,
    required this.respondedAt,
    required this.windowWidth,
    this.showAgain = 0,
    this.now = responseClockMs,
  });

  /// The gesture to act out, or null for it to go.
  final NarratorGesture? gesture;

  /// When the person last did anything with their face, on [now]'s clock (0
  /// for never). Read on a timer, never in build.
  final int Function() respondedAt;

  /// The width of the camera's window, which it is sized to.
  final double windowWidth;

  /// Changes each time it should act the gesture out again now, without
  /// waiting for the person to go quiet: they held a head direction the wrong
  /// way (LivenessState.wrongWayCount).
  final int showAgain;

  /// The clock, in milliseconds. The response watch's own by default.
  final int Function() now;

  @override
  State<GestureNarrator> createState() => GestureNarratorState();
}

class GestureNarratorState extends State<GestureNarrator>
    with TickerProviderStateMixin {
  late final AnimationController _opacity = AnimationController(vsync: this);
  late final AnimationController _scale =
      AnimationController.unbounded(vsync: this, value: _scaleFrom);
  late final Ticker _clock = createTicker(_onFrame);
  final ValueNotifier<NarratorPose> _pose = ValueNotifier(kNarratorRest);
  Timer? _pass;
  Timer? _looking;

  /// Whether it is on its way in or there, rather than gone.
  bool _showing = false;

  /// The gesture last shown, kept so its last pose stays while it goes.
  NarratorGesture? _drawn;

  /// Whether it is showing (for tests): on its way in or there.
  bool get showing => _showing;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    // Every gesture is shown first. After the first frame, so the reduced
    // motion setting can be read from the context.
    if (widget.gesture != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.gesture != null) _show();
      });
    }
  }

  @override
  void didUpdateWidget(GestureNarrator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Asked to show again: back at once.
    if (widget.gesture == oldWidget.gesture) {
      if (widget.showAgain != oldWidget.showAgain && widget.gesture != null) {
        _show();
      }
      return;
    }
    if (widget.gesture == null) {
      _cancelTimers();
      _hide();
    } else {
      _show();
    }
  }

  void _cancelTimers() {
    _pass?.cancel();
    _looking?.cancel();
    _pass = null;
    _looking = null;
  }

  void _show() {
    final gesture = widget.gesture;
    if (gesture == null || !mounted) return;
    _cancelTimers();
    _showing = true;
    _drawn = gesture;
    final still = _still;
    if (still) {
      _pose.value = narratorStillPose(gesture);
      _scale.value = 1;
      _opacity.animateTo(1, duration: _fadeOnly, curve: Curves.easeInOut);
    } else {
      _pose.value = kNarratorRest;
      _scale.value = _scaleFrom;
      _opacity.value = 0;
      _opacity.animateTo(1, duration: _appearFade, curve: Curves.easeOut);
      _scale.animateTo(1, duration: _appearScale, curve: _overshoot);
      if (_clock.isActive) _clock.stop();
      _clock.start();
    }
    // One pass, then it goes.
    final once = still
        ? kNarratorStill
        : Duration(milliseconds: (kNarratorSeconds[gesture]! * 1000).round());
    _pass = Timer(once, _goQuiet);
    setState(() {});
  }

  /// The pass is over: it goes, and watches for the person going quiet.
  void _goQuiet() {
    if (!mounted) return;
    _hide();
    final left = widget.now();
    _looking = Timer.periodic(kNarratorLookEvery, (_) {
      final quietSince = math.max(left, widget.respondedAt());
      if (widget.now() - quietSince >= kNarratorPatience.inMilliseconds) {
        _show();
      }
    });
  }

  void _hide() {
    _showing = false;
    // The last pose stays while it goes.
    if (_clock.isActive) _clock.stop();
    if (_still) {
      _opacity.animateTo(0, duration: _fadeOnly, curve: Curves.easeInOut);
    } else {
      _opacity.animateTo(0, duration: _leave, curve: Curves.easeIn);
      _scale.animateTo(_scaleFrom, duration: _leave, curve: Curves.easeIn);
    }
    if (mounted) setState(() {});
  }

  void _onFrame(Duration elapsed) {
    final gesture = _drawn;
    if (gesture == null) return;
    final once = kNarratorSeconds[gesture]!;
    _pose.value =
        narratorPose(gesture, math.min(elapsed.inMicroseconds / 1e6, once));
  }

  @override
  void dispose() {
    _cancelTimers();
    _clock.dispose();
    _opacity.dispose();
    _scale.dispose();
    _pose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_drawn == null) return const SizedBox.shrink();
    final side = (widget.windowWidth * kNarratorSize).roundToDouble();
    return ExcludeSemantics(
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            child: SizedBox(
              key: const ValueKey('gesture-narrator'),
              width: side,
              height: side,
              child: CustomPaint(
                // Solid white, with no edge or shadow (NarratorPainter).
                painter: NarratorPainter(pose: _pose),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
