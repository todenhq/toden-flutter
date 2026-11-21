import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../liveness/challenge_manager.dart';
import '../liveness/direction_plan.dart';
import '../liveness/head_directions.dart';
import '../liveness/ready_pause.dart';
import '../liveness/face_detection.dart';
import '../liveness/flash_challenge.dart';
import '../liveness/flash_detector.dart';
import '../liveness/flash_outcome.dart';
import '../liveness/flash_ready_gate.dart';
import '../liveness/flash_timeline.dart';
import '../liveness/face_continuity.dart';
import '../liveness/selfie_pick.dart' show SelfieFace;
import '../liveness/selfie_review.dart' show SelfieScene;
import '../liveness/selfie_shutter.dart' show SelfieGuidance;
import '../liveness/liveness_types.dart';
import '../liveness/capture_pose.dart';
import '../liveness/face_window.dart';
import '../liveness/passive_hold.dart';
import '../liveness/prompt_timeline.dart';
import '../liveness/response_watch.dart';
import '../liveness/sharpest_still.dart';
import '../services/image_service.dart';
import 'verification_provider.dart';
import '../utils/journey_client.dart' show recordJourneyEvent, livenessFailureDetail;

part 'liveness_provider.g.dart';

// ─── Liveness state ───────────────────────────────────────────────────────────

class LivenessState {
  final LivenessPhase phase;

  /// Instruction text shown to the user for the current challenge.
  final String instruction;

  /// Number of challenges completed so far.
  final int completedCount;

  /// Total challenges selected for this session.
  final int totalCount;

  /// Seconds remaining for the active challenge before timeout.
  final int timeoutRemaining;

  /// Whether a face is currently detected in the frame.
  final bool faceDetected;

  /// The challenge type currently being attempted, or null when not in a
  /// challenge phase. The gesture narrator acts it out.
  final LivenessChallenge? activeChallenge;

  /// Base64-encoded JPEG selfie captured after all challenges pass.
  /// Only non-null when [phase] == [LivenessPhase.complete].
  final String? selfieBase64;

  /// The camera frame the selfie was cut from, for the full-screen review
  /// (liveness/selfie_review.dart). Null when the selfie is a whole frame of
  /// its own (a fallback still) or the frame could not be kept. Never uploaded.
  final SelfieScene? selfieScene;

  final String? error;

  /// Distance guidance — mirrors the web SDK's position check.
  ///   'too_far'   → face width < 0.28 → "Move closer"
  ///   'too_close' → face width > 0.7  → "Move further away"
  ///   'off_centre' → full screen only: the face is beside the window
  ///   null        → correct distance
  /// Checked per-frame during positioning and challenge phases.
  /// Blocks challenge advancement when not null during positioning.
  final String? positionGuidance;

  /// True for a brief moment when the user performs a DIFFERENT gesture than the
  /// one requested (e.g. turning during a nod challenge). Drives the red-border +
  /// "Wrong gesture" feedback, mirroring the web SDK.
  final bool wrongGesture;

  /// True when more than one face is in frame. The challenge is paused and the
  /// user is asked to ensure only their face is visible (quality + anti-spoof).
  /// Mirrors the web SDK.
  final bool multipleFaces;

  /// Lighting guidance — null when lighting is acceptable, otherwise 'dark' or
  /// 'bright'. Blocks challenge start / auto-capture while non-null, mirroring
  /// the web SDK's lighting gate.
  final String? lightingGuidance;

  /// Flash-only "hold still" progress, 0..1 across the pre-flash dwell. 0 in
  /// gesture mode and whenever the hold hasn't started. Drives a subtle
  /// getting-ready ring so the flash never feels like it jumps out.
  final double flashReadyProgress;

  /// How far through the ready pause before the first gesture, 0..1
  /// (liveness/ready_pause.dart). Fills the positioning part of the line.
  final double readyProgress;

  /// Counts each time the person has held a head direction the wrong way:
  /// the narrator shows the way again when it changes. Never a failure.
  final int wrongWayCount;

  /// The head directions this run asks for, in order; empty for any other
  /// gesture set. The line round the window is four sides when it is not.
  final List<LivenessChallenge> directions;

  const LivenessState({
    this.phase = LivenessPhase.loading,
    this.instruction = '',
    this.completedCount = 0,
    this.totalCount = 0,
    this.timeoutRemaining = 0,
    this.faceDetected = false,
    this.activeChallenge,
    this.selfieBase64,
    this.selfieScene,
    this.error,
    this.positionGuidance,
    this.wrongGesture = false,
    this.multipleFaces = false,
    this.lightingGuidance,
    this.flashReadyProgress = 0,
    this.readyProgress = 0,
    this.wrongWayCount = 0,
    this.directions = const [],
  });

  double get progress =>
      totalCount > 0 ? completedCount / totalCount : 0.0;

  bool get isComplete => phase == LivenessPhase.complete;
  bool get isFailed => phase == LivenessPhase.failed;

  LivenessState copyWith({
    LivenessPhase? phase,
    String? instruction,
    int? completedCount,
    int? totalCount,
    int? timeoutRemaining,
    bool? faceDetected,
    LivenessChallenge? activeChallenge,
    bool clearActiveChallenge = false,
    String? selfieBase64,
    SelfieScene? selfieScene,
    String? error,
    String? positionGuidance,
    bool clearPositionGuidance = false,
    bool? wrongGesture,
    bool? multipleFaces,
    String? lightingGuidance,
    bool clearLightingGuidance = false,
    double? flashReadyProgress,
    double? readyProgress,
    int? wrongWayCount,
    List<LivenessChallenge>? directions,
  }) =>
      LivenessState(
        phase: phase ?? this.phase,
        instruction: instruction ?? this.instruction,
        completedCount: completedCount ?? this.completedCount,
        totalCount: totalCount ?? this.totalCount,
        timeoutRemaining: timeoutRemaining ?? this.timeoutRemaining,
        faceDetected: faceDetected ?? this.faceDetected,
        activeChallenge: clearActiveChallenge
            ? null
            : (activeChallenge ?? this.activeChallenge),
        selfieBase64: selfieBase64 ?? this.selfieBase64,
        selfieScene: selfieScene ?? this.selfieScene,
        error: error, // explicit null clears error
        positionGuidance:
            clearPositionGuidance ? null : (positionGuidance ?? this.positionGuidance),
        wrongGesture: wrongGesture ?? this.wrongGesture,
        multipleFaces: multipleFaces ?? this.multipleFaces,
        lightingGuidance: clearLightingGuidance
            ? null
            : (lightingGuidance ?? this.lightingGuidance),
        flashReadyProgress: flashReadyProgress ?? this.flashReadyProgress,
        readyProgress: readyProgress ?? this.readyProgress,
        wrongWayCount: wrongWayCount ?? this.wrongWayCount,
        directions: directions ?? this.directions,
      );
}

// ─── Liveness notifier ────────────────────────────────────────────────────────

@riverpod
class LivenessNotifier extends _$LivenessNotifier {
  late ChallengeManager _manager;

  Timer? _timeoutTimer;

  // Gesture signal histories — raw angle / probability ring buffers.
  // Not stored in state to avoid unnecessary rebuilds on every frame.
  final List<double> _xHistory = [];   // headEulerAngleX for nod detection
  final List<double> _earHistory = []; // eye open probability for blink
  static const int _historySize = 20;

  /// Passive Liveness: how long the face has held still in position.
  final _hold = PassiveHold();

  /// Shown once a flash-only face is framed + lit and the pre-flash hold begins.
  /// Doubles as the photosensitivity heads-up before the colours appear.
  static const String _kFlashHoldInstruction =
      'Hold still. The screen will flash briefly';

  bool _challengeProcessing = false;

  /// Tracks that the face performing the challenges is the face still in frame.
  /// Liveness without it proves a live human was present, not WHICH human.
  final _continuity = FaceContinuityGuard();

  /// Set when a second face appears at any point from the first challenge
  /// onwards, INCLUDING during capture. The flash runs in the capturing phase,
  /// so a guard that stops at capture stops exactly where the measurement that
  /// matters happens.
  bool _integrityBroken = false;

  /// True once the session can no longer vouch for who is in frame. The screen
  /// reads it to abort the flash rather than finish measuring a stranger.
  bool get integrityBroken => _integrityBroken;

  /// Counts breaks in the live run: a continuity jump, a face back after a
  /// gap, a restart. The screen clears the selfie it has chosen so far when
  /// this moves (liveness/selfie_pick.dart): the selfie must come from one
  /// unbroken run.
  int _runGeneration = 0;
  int get runGeneration => _runGeneration;

  // Flash-only liveness: the pre-flash "hold still" gate (positioned + lit for a
  // dwell). Null in gesture / both modes, whose challenges already provide the
  // framing feedback loop. See FlashReadyGate.
  FlashReadyGate? _flashGate;

  /// Whether the flash occupies a slot in the progress indicator.
  bool _flashIsStep = false;

  /// A flash-only check whose flash could not be measured switched to gesture
  /// challenges (flash_outcome.dart). The screen reads it so the capture that
  /// follows those gestures does not run the flash a second time, and the
  /// claim reports that both methods ran.
  bool _fellBackToGestures = false;
  bool get fellBackToGestures => _fellBackToGestures;

  /// Whether the person is doing anything with their face (response_watch.dart).
  /// The gesture narrator comes back to show a gesture only to someone who has
  /// stopped responding.
  final ResponseWatch _responseWatch = ResponseWatch();

  /// When the person last did anything with their face, on
  /// [responseClockMs] (0 for never). A getter, not state: it changes on
  /// almost every frame and the narrator reads it on a timer.
  int get respondedAt => _responseWatch.respondedAt;

  /// When each prompt appeared and passed, for the claim (prompt_timeline.dart).
  final PromptTimeline _prompts = PromptTimeline();

  /// The prompts' times against the recording, or null with no recording.
  List<Map<String, Object>>? get promptTimes => _prompts.report(recordingStart());

  /// The prompts this session's manager ran, in order (for the liveness claim).
  List<LivenessChallenge> get challengesRun =>
      [for (final c in _manager.selectedChallenges) c.type];

  /// Total steps shown to the user: the gestures, plus the flash when it runs.
  int get _displayTotal => _manager.totalCount + (_flashIsStep ? 1 : 0);

  // Whether the brightness sampler has produced at least one real reading.
  // Until it has, "no lighting warning" means UNKNOWN, not confirmed-good — so
  // the flash gate must not treat an unmeasured dim room as acceptable.
  bool _lightingSampled = false;

  // ── Head directions ────────────────────────────────────────────────────────

  /// What each attempt of this run asks Core for: head directions or classic
  /// gestures, in gestures or both, and the flash colours whenever a flash
  /// runs (a flash-only check asks for colours alone). Null asks nothing
  /// (passive, or a gestures-only integration pool with no gesture Core can
  /// plan).
  PlanRequest? _planRequest;

  /// The integration's own challenge pool, for the classic plan's prompts.
  List<ChallengeConfig>? _challengePool;

  /// Frames of the asked direction, and of its opposite (head_directions.dart).
  final DirectionWatch _directionWatch = DirectionWatch();

  /// Where the person's pitch rests, taken as they hold still before the first
  /// gesture: looking up and down are measured against it.
  double? _restPitch;

  /// Core's plan for the current attempt (liveness/direction_plan.dart). One
  /// request per attempt; an answer for an earlier attempt is ignored.
  DirectionPlanStatus _planStatus = DirectionPlanStatus.none;
  int _planAskedAt = 0;
  int _planAttempt = 0;
  String? _planId;
  List<ChallengeConfig>? _planned;
  List<FlashColor>? _plannedFlash;

  /// Set once the first instruction of the attempt has been given: a plan
  /// that arrives after it is not used, so the directions never change once
  /// asking has begun.
  bool _challengeStarted = false;

  /// When the face first held in place, for the ready pause; null while it is
  /// not in place.
  int? _readyAt;

  bool _disposed = false;

  /// The clock the ready pause and the plan's wait run on, in milliseconds.
  @visibleForTesting
  int Function() clock = responseClockMs;

  /// The head-direction plan Core picked for this attempt, when its
  /// directions are the ones asked; null when the SDK picked its own.
  String? get directionPlanId => _planId;

  /// The flash colours Core picked for this attempt, in its order; null when
  /// no usable plan came in time, and the SDK then picks its own (which Core
  /// records as unplanned).
  List<FlashColor>? get plannedFlash => _plannedFlash;

  /// The head directions this run asks for, in order (empty otherwise).
  List<LivenessChallenge> get _runDirections => [
        for (final c in _manager.selectedChallenges)
          if (isDirectionChallenge(c.type)) c.type,
      ];

  @override
  LivenessState build() {
    final config = ref.read(verificationConfigProvider);
    final livenessConfig = config.livenessConfig;

    // Flash-only liveness replaces the gesture challenges with the screen's
    // color sequence, so the state machine runs positioning → capturing and the
    // flash is performed at the capture seam (see LivenessScreen).
    final flashOnly = config.livenessMode == 'flash';
    // The flash is a step the user performs, so it occupies a slot in the
    // progress indicator. Without this the indicator claimed the check was
    // finished while its longest, most visible part was still to come — and in
    // flash-only mode it showed no steps at all, since there are no gestures.
    _flashIsStep = config.livenessMode.runsFlash;
    _flashGate = flashOnly ? FlashReadyGate() : null;
    // Passive Liveness runs the single hold prompt through the same machinery,
    // so recording, the progress ring and capture work unchanged.
    final asksGestures =
        config.livenessMode != 'flash' && config.livenessMode != 'passive';
    _challengePool = livenessConfig?.challengePool;
    // Core also picks the flash colours (2026-11-19), so a modified client
    // cannot choose colours to match a replayed recording.
    final flashCount =
        config.livenessMode.runsFlash ? config.flashSequenceLength : null;
    final flashOnlyRequest =
        flashCount == null ? null : PlanRequest.flashOnly(flashCount);
    _planRequest = !asksGestures
        ? flashOnlyRequest
        : config.livenessGestureSet == kGestureSetDirections
            ? PlanRequest.directions(
                directionCountOf(config.livenessDirectionCount),
                flash: flashCount)
            // A pool with nothing Core can plan still asks for the colours.
            : classicPlanRequest(
                    livenessConfig?.challengeCount ?? 2, _challengePool,
                    flash: flashCount) ??
                flashOnlyRequest;
    _manager = ChallengeManager.forMode(
      config.livenessMode,
      pool: livenessConfig?.challengePool,
      count: livenessConfig?.challengeCount ?? 2,
      gestureSet: config.livenessGestureSet,
      directionCount: config.livenessDirectionCount,
    );

    ref.onDispose(() {
      _disposed = true;
      _cleanup();
    });

    // Each failed attempt goes on the drop-off journey, with why it failed.
    listenSelf((previous, next) {
      if (previous?.phase != LivenessPhase.failed && next.phase == LivenessPhase.failed) {
        recordJourneyEvent('liveness_failed', detail: livenessFailureDetail(next.error, multipleFaces: next.multipleFaces));
      }
    });

    return const LivenessState();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Transitions from [LivenessPhase.loading] to [LivenessPhase.positioning].
  /// Call once the camera + ML Kit are ready.
  void startDetection() {
    if (state.phase != LivenessPhase.loading) return;
    _continuity.reset();
    _integrityBroken = false;
    _runGeneration++;
    _readyAt = null;
    _askPlan();
    state = LivenessState(
      phase: LivenessPhase.positioning,
      instruction: 'Position your face in the circle',
      totalCount: _displayTotal,
      directions: _runDirections,
    );
  }

  /// Core picks the gestures, head directions or classic, and the flash
  /// colours, one plan per attempt. The manager's own pick stands in until the
  /// plan arrives, and is replaced if the first instruction (or a flash-only
  /// check's flash) has not been given yet; that waits a moment for it
  /// ([planGateWaits]). No plan: the SDK's own pick, and no plan named.
  void _askPlan() {
    final attempt = ++_planAttempt;
    _challengeStarted = false;
    _planId = null;
    _planned = null;
    _plannedFlash = null;
    final asked = _planRequest;
    final request =
        asked == null ? null : ref.read(directionPlanRequestProvider);
    if (asked == null || request == null) {
      _planStatus = DirectionPlanStatus.none;
      return;
    }
    _planStatus = DirectionPlanStatus.pending;
    _planAskedAt = clock();
    () async {
      DirectionPlan? plan;
      try {
        plan = await request(asked);
      } catch (_) {
        plan = null;
      }
      if (_disposed || attempt != _planAttempt) return;
      if (plan == null || _challengeStarted) {
        _planStatus = DirectionPlanStatus.failed;
        return;
      }
      _plannedFlash =
          plan.flash.isEmpty ? null : flashSequenceNamed(plan.flash);
      _planId = plan.planId;
      _planStatus = DirectionPlanStatus.ready;
      // A flash-only plan names the colours alone: the gestures stand.
      if (asked.set == PlanSet.none) return;
      final planned = planChallenges(plan.prompts, pool: _challengePool);
      _manager.replaceWith(planned);
      _planned = planned;
      state = state.copyWith(
        totalCount: _displayTotal,
        directions: _runDirections,
      );
    }();
  }

  /// The flash sequence finished, so its step in the progress indicator is done.
  ///
  /// The provider cannot observe this itself — the sequence is driven by the
  /// screen, which owns the painting and the sampling — so the screen reports
  /// it. Without it the last dot would stay unfilled through a completed check.
  void markFlashStepComplete() {
    if (!_flashIsStep) return;
    if (state.completedCount >= _displayTotal) return;
    state = state.copyWith(completedCount: _displayTotal);
  }

  /// Called for every camera frame that contains a detected face.
  /// [data] is the structured face attributes from [FaceDetectorService.detect].
  void processFrame(LivenessFaceData data) {
    if (!state.faceDetected && state.phase != LivenessPhase.complete) {
      state = state.copyWith(faceDetected: true);
    }

    // More than one face — pause and ask for a single face (quality +
    // anti-spoofing). Auto-resumes when the frame returns to one face.
    if (data.faceCount > 1) {
      _onMultipleFaces();
      return;
    }
    if (state.multipleFaces) {
      _onSingleFaceRestored();
    }

    // Same face as a moment ago? Liveness proves a live human performed the
    // challenges; only continuity ties that human to the one being captured.
    switch (_continuity.update(data, DateTime.now())) {
      case FaceContinuity.substituted:
        _runGeneration++;
        _onFaceSubstituted();
        return;
      case FaceContinuity.reacquired:
        _runGeneration++;
        // Not proof of anything — people look away — but nothing vouches for
        // the returning face either, so earned progress does not cross the gap.
        _onFaceReacquired();
        return;
      case FaceContinuity.same:
        break;
    }

    _responseWatch.seen(data, responseClockMs());

    // Check face size and update position guidance on every frame.
    _checkFacePosition(data);

    switch (state.phase) {
      case LivenessPhase.positioning:
        final gate = _flashGate;
        if (gate != null) {
          _updateFlashReady(gate);
          return;
        }
        // Gesture / both / passive: once framed + lit, the ready pause, then
        // the first prompt. The challenges themselves give the feedback and
        // re-check framing. Flash-only can't rely on that (nothing follows but
        // the flash), so it runs the dwell gate above instead.
        _holdForReady(data);
        return;

      case LivenessPhase.challenge:
        if (_challengeProcessing) return;
        // Suspend gesture detection while position is wrong — the face is
        // too far or too close for reliable classification.
        if (state.positionGuidance != null) {
          _hold.reset(); // the hold restarts once the face is back
          return;
        }
        _updateHistory(data);
        _checkGesture(data);

      default:
        return;
    }
  }

  // ── Multiple faces ───────────────────────────────────────────────────────

  static const String multipleFacesGuidance =
      'Make sure only your face is visible';

  void _onMultipleFaces() {
    if (state.phase == LivenessPhase.complete ||
        state.phase == LivenessPhase.failed) {
      return;
    }
    // CAPTURING is deliberately NOT excused. The flash challenge runs in that
    // phase, so ignoring a second face there means the one measurement that
    // proves liveness is the one moment anybody may stand in frame. There is
    // no useful guidance to show mid-capture, so the session is marked broken
    // and the screen aborts the flash instead.
    if (state.phase == LivenessPhase.capturing) {
      _integrityBroken = true;
      return;
    }
    if (state.multipleFaces) return; // already paused
    // Pause the challenge timer so a second face can't run out the clock.
    _cancelTimer();
    _hold.reset();
    // The ready pause is one person holding still: it starts again.
    _readyAt = null;
    // A second face invalidates the flash hold — restart it when we're back to
    // one, rather than resuming a hold that spanned two people.
    _flashGate?.reset();
    state = state.copyWith(
      multipleFaces: true,
      instruction: multipleFacesGuidance,
      wrongGesture: false,
      flashReadyProgress: 0,
    );
  }

  /// A different face is in frame. Nothing performed so far can be attributed
  /// to whoever is there now, so the session ends rather than continuing.
  void _onFaceSubstituted() {
    if (state.phase == LivenessPhase.complete ||
        state.phase == LivenessPhase.failed) {
      return;
    }
    _integrityBroken = true;
    // Mid-capture the verdict is recorded but NOT shown. The flash paints a
    // full-screen overlay with a hole cut at the preview circle's rect,
    // measured once when the flash starts; changing the phase here re-lays out
    // the screen underneath it, the circle moves, and the hole ends up over
    // nothing. The screen aborts the flash on this flag and reports the failure
    // once the overlay is gone.
    if (state.phase == LivenessPhase.capturing) return;
    _cancelTimer();
    _flashGate?.reset();
    state = state.copyWith(
      phase: LivenessPhase.failed,
      instruction: 'Let\'s start over. Please stay in frame.',
      error: 'face_swap',
      clearActiveChallenge: true,
      clearPositionGuidance: true,
    );
  }

  /// Surfaces a failure that was detected mid-flash and deliberately withheld.
  ///
  /// Called by the screen once the flash overlay has been removed, so the
  /// re-layout happens against a plain screen rather than shifting the preview
  /// circle out from under the overlay's cutout.
  void reportIntegrityFailure() {
    if (!_integrityBroken) return;
    if (state.phase == LivenessPhase.complete) return;
    _cancelTimer();
    _flashGate?.reset();
    state = state.copyWith(
      phase: LivenessPhase.failed,
      instruction: 'Let\'s start over. Please stay in frame.',
      error: 'face_swap',
      clearActiveChallenge: true,
      clearPositionGuidance: true,
    );
  }

  /// The face came back after being away. Restart from positioning: the
  /// challenges already passed were passed by a face nothing can now vouch for.
  void _onFaceReacquired() {
    if (state.phase != LivenessPhase.challenge &&
        state.phase != LivenessPhase.positioning) {
      if (state.phase == LivenessPhase.capturing) _integrityBroken = true;
      return;
    }
    _cancelTimer();
    _flashGate?.reset();
    // Core's plan is this attempt's: the same directions start again from the
    // first, rather than a pick of the SDK's own under the plan's name.
    final planned = _planned;
    if (planned != null) {
      _manager.replaceWith(planned);
    } else {
      _manager.reset();
    }
    _readyAt = null;
    _directionWatch.reset();
    _xHistory.clear();
    _earHistory.clear();
    _hold.reset();
    _challengeProcessing = false;
    state = state.copyWith(
      phase: LivenessPhase.positioning,
      instruction: 'Position your face in the circle',
      completedCount: 0,
      clearActiveChallenge: true,
      flashReadyProgress: 0,
      readyProgress: 0,
      directions: _runDirections,
    );
  }

  void _onSingleFaceRestored() {
    final resumeChallenge = state.phase == LivenessPhase.challenge;
    state = state.copyWith(multipleFaces: false);
    if (resumeChallenge) {
      final challenge = _manager.current;
      if (challenge != null) {
        // Reset gesture history and restart the (paused) challenge timer.
        _xHistory.clear();
        _earHistory.clear();
        _hold.reset();
        _directionWatch.reset();
        _challengeProcessing = false;
        final timeout = _timeoutFor(challenge);
        state = state.copyWith(instruction: challenge.instruction);
        _startTimer(timeout);
      }
    }
  }

  // ── Lighting gate ────────────────────────────────────────────────────────

  /// Feeds live lighting quality into the state machine. [guidance] is 'dark',
  /// 'bright', or null (acceptable). While non-null during positioning, the
  /// flow won't start challenges — discouraging capture in poor light.
  void setLightingGuidance(String? guidance) {
    // The screen only calls this after a genuine brightness reading, so the
    // first call is proof lighting has been measured — which the flash gate
    // needs to tell "confirmed OK" apart from "not yet checked".
    _lightingSampled = true;
    if (guidance == state.lightingGuidance) return;
    // Lighting guidance is only meaningful before/while capturing the selfie.
    if (state.phase == LivenessPhase.complete ||
        state.phase == LivenessPhase.failed ||
        state.phase == LivenessPhase.capturing) {
      if (state.lightingGuidance != null) {
        state = state.copyWith(clearLightingGuidance: true);
      }
      return;
    }
    if (guidance == null) {
      state = state.copyWith(clearLightingGuidance: true);
    } else {
      state = state.copyWith(lightingGuidance: guidance);
    }
  }

  /// Called when a camera frame produces no faces.
  void reportNoFace() {
    _continuity.reportNoFace();
    if (!state.faceDetected) return;
    if (state.phase == LivenessPhase.complete ||
        state.phase == LivenessPhase.failed) {
      return;
    }
    // Losing the face breaks the flash hold — it must be re-earned when the
    // face returns, not resumed. (reportNoFace clears positionGuidance, which
    // would otherwise leave `framed` true with no face in the gate.)
    _flashGate?.reset();
    _hold.reset();
    _readyAt = null;
    state = state.copyWith(
      faceDetected: false,
      clearPositionGuidance: true, // no face → no distance guidance
      multipleFaces: false, // no face → certainly not multiple
      flashReadyProgress: 0,
    );
  }

  /// Normalises exposure (lifts a backlit/dark face) and encodes a sharp selfie,
  /// base64-encodes it, and transitions to [LivenessPhase.complete]. Call from
  /// the screen after taking a picture. The work runs in an isolate / on a
  /// native thread, so it doesn't block the UI isolate.
  Future<void> captureSelfie(Uint8List imageBytes, {SelfieFace? cut}) async {
    if (state.phase != LivenessPhase.capturing) return;
    // Single pass: bake orientation, cut to the standard selfie frame around
    // [cut] (liveness/selfie_pick.dart), brighten a backlit/dark face, size +
    // encode a sharp JPEG.
    final bytes = await processSelfieImage(imageBytes, cut: cut);
    _completeWithSelfie(bytes);
  }

  /// Like [captureSelfie] but for an already-enhanced/encoded JPEG (e.g. from the
  /// stream-frame fast path, where the worker already ran the selfie pipeline).
  /// Skips re-processing and just stores it.
  ///
  /// [scene] is the camera frame the selfie was cut from, for the review.
  void captureSelfieEncoded(Uint8List jpegBytes, {SelfieScene? scene}) {
    if (state.phase != LivenessPhase.capturing) return;
    _completeWithSelfie(jpegBytes, scene: scene);
  }

  void _completeWithSelfie(Uint8List jpegBytes, {SelfieScene? scene}) {
    state = state.copyWith(
      phase: LivenessPhase.complete,
      selfieBase64: base64Encode(jpegBytes),
      selfieScene: scene,
      // No line at all. The ring closing green on the same frame as the
      // shutter IS the completion signal, and the review follows within the
      // beat — narrating the upload over it said nothing the user needed.
      instruction: '',
      clearActiveChallenge: true,
      clearPositionGuidance: true,
    );
  }

  /// The flash could not be measured even after its retry, on a flash-only
  /// check: prove liveness with gesture challenges instead of passing on a
  /// flash nobody could measure.
  void startFallbackGestures() {
    final livenessConfig = ref.read(verificationConfigProvider).livenessConfig;
    _fellBackToGestures = true;
    final config = ref.read(verificationConfigProvider);
    // The workflow's gesture set, as the web SDK's pickFallbackGestures keeps
    // it. No plan is asked for: the attempt began as a flash.
    _manager = config.livenessGestureSet == kGestureSetDirections
        ? ChallengeManager.directions(count: config.livenessDirectionCount)
        : ChallengeManager(
            pool: livenessConfig?.challengePool,
            count: livenessConfig?.challengeCount ?? 2,
          );
    _restPitch = null;
    state = state.copyWith(
      totalCount: _displayTotal,
      directions: _runDirections,
    );
    _startNextChallenge();
  }

  /// Shown while an unmeasurable flash is retried.
  void showFlashRetryGuidance() {
    state = state.copyWith(instruction: kFlashRetryGuidance);
  }

  /// The flash was measured and did not match the colours emitted. Matches the
  /// web and React Native SDKs.
  void failFlash() {
    if (state.phase == LivenessPhase.complete) return;
    _cancelTimer();
    _flashGate?.reset();
    state = state.copyWith(
      phase: LivenessPhase.failed,
      instruction: 'We couldn\'t confirm the check. Let\'s try again.',
      error: 'flash_failed',
      clearActiveChallenge: true,
      clearPositionGuidance: true,
    );
  }

  /// Resets the liveness session — picks a fresh random challenge set.
  void reset() {
    _cleanup();
    // A flash-only check that fell back to gestures starts again flash-only.
    if (_fellBackToGestures) {
      _fellBackToGestures = false;
      _manager = ChallengeManager.none();
    }
    _manager.reset();
    _prompts.reset();
    _flashGate?.reset();
    // A retry starts a fresh session: whoever is in frame now becomes the
    // reference, and the previous attempt's verdict does not carry over.
    _continuity.reset();
    _integrityBroken = false;
    _runGeneration++;
    // NOT _lightingSampled — the sampler keeps running across a retry, so
    // lighting stays confirmed; re-arming it would re-introduce the warmup race.
    _xHistory.clear();
    _earHistory.clear();
    _hold.reset();
    _directionWatch.reset();
    _readyAt = null;
    _restPitch = null;
    _challengeProcessing = false;
    // A retry is a new attempt: it asks Core for a new plan.
    _askPlan();
    state = LivenessState(
      phase: LivenessPhase.positioning,
      instruction: 'Position your face in the circle',
      totalCount: _displayTotal,
      directions: _runDirections,
    );
  }

  // ── Internal: face position check ─────────────────────────────────────────
  //
  // Mirrors gesture-detector.ts checkFacePosition() from the web SDK.
  // Thresholds: < 0.28 = too far, > 0.7 = too close. 0.28 (raised from 0.2) so a
  // clearly-distant face is prompted to move closer instead of slipping through
  // — kept in lockstep with the web SDK's MIN_FACE_WIDTH.
  static const double _tooFarThreshold  = 0.28;
  static const double _tooCloseThreshold = 0.70;

  /// The full-screen camera's window onto the frame, or null in the sheet,
  /// where the circle shows the whole frame.
  FaceWindow? _faceWindow;

  /// Told by the screen when the camera takes, or gives back, the display.
  void setFaceWindow(FaceWindow? window) => _faceWindow = window;

  void _checkFacePosition(LivenessFaceData data) {
    final faceSizeRatio = data.faceSizeRatio;
    // Don't override position guidance in terminal / transition phases.
    if (state.phase == LivenessPhase.challengePassed ||
        state.phase == LivenessPhase.capturing ||
        state.phase == LivenessPhase.complete ||
        state.phase == LivenessPhase.failed) {
      return;
    }

    final String? newGuidance;
    final window = _faceWindow;
    if (window != null) {
      // Full screen: the face has to sit INSIDE the window, not merely be a
      // sensible size somewhere in the frame.
      newGuidance = faceWindowGuidance(
        window,
        faceWidth: faceSizeRatio,
        centreX: data.faceCenterX,
        centreY: data.faceCenterY,
        // A head direction moves the head off the centre on purpose too.
        moving: state.phase == LivenessPhase.challenge &&
            (_manager.current?.type == LivenessChallenge.turn ||
                _manager.current?.type == LivenessChallenge.nod ||
                isDirectionChallenge(_manager.current?.type)),
      );
    } else if (faceSizeRatio < _tooFarThreshold) {
      newGuidance = 'too_far';
    } else if (faceSizeRatio > _tooCloseThreshold) {
      newGuidance = 'too_close';
    } else {
      newGuidance = null;
    }

    if (newGuidance != state.positionGuidance) {
      if (newGuidance == null) {
        state = state.copyWith(clearPositionGuidance: true);
      } else {
        state = state.copyWith(positionGuidance: newGuidance);
      }
    }
  }

  // ── Internal: challenge transitions ───────────────────────────────────────

  /// Flash-only pre-flash gate: hold a framed + lit face for a short dwell,
  /// then flash. Keeps the "come closer / more light" guidance visible the
  /// whole time and shows a "hold still" beat, so the flash never fires off a
  /// single frame or before lighting has actually been measured.
  void _updateFlashReady(FlashReadyGate gate) {
    final framed = state.positionGuidance == null;
    final lit = state.lightingGuidance == null;
    final result = gate.update(
      framed: framed,
      lit: lit,
      lightingConfirmed: _lightingSampled,
      now: DateTime.now(),
    );

    // Ready, but Core's colours are on their way: hold a moment longer for
    // them, as the first gesture does. Once the flash begins a late plan is
    // not used, so the colours shown are always the colours named.
    if (result.ready && !planGateWaits(_planStatus, _planAskedAt, clock())) {
      _challengeStarted = true;
      state = state.copyWith(flashReadyProgress: 1);
      _startNextChallenge(); // → capturing → flash
      return;
    }

    // Only overwrite the instruction while the face is actually framed + lit;
    // otherwise leave the position/lighting guidance to speak for itself.
    final instruction = (framed && lit) ? _kFlashHoldInstruction : state.instruction;
    if (state.flashReadyProgress != result.progress ||
        state.instruction != instruction) {
      state = state.copyWith(
        flashReadyProgress: result.progress,
        instruction: instruction,
      );
    }
  }

  /// Shown when the photos just taken were soft and the SDK is taking them
  /// again by itself.
  void askToHoldForRetake() {
    if (state.phase != LivenessPhase.capturing) return;
    state = state.copyWith(instruction: kRetakeInstruction);
  }

  /// Shown while the photo waits for the face to come back to the camera
  /// after a gesture. Only during the capture, and only when it would change
  /// what is on screen.
  void askForStraightFace() {
    if (state.phase != LivenessPhase.capturing) return;
    if (state.instruction == kLookStraightInstruction) return;
    state = state.copyWith(instruction: kLookStraightInstruction);
  }

  /// Says what to fix while the final capture waits for a frame that could be
  /// the selfie (liveness/selfie_shutter.dart). Null leaves the line as it is.
  void showSelfieGuidance(SelfieGuidance? guidance) {
    if (state.phase != LivenessPhase.capturing || guidance == null) return;
    final line = switch (guidance) {
      SelfieGuidance.lookStraight => kLookStraightInstruction,
      SelfieGuidance.moveCloser => kMoveCloserInstruction,
      SelfieGuidance.holdStill => kHoldStillInstruction,
    };
    if (state.instruction == line) return;
    state = state.copyWith(instruction: line);
  }

  /// The face left the final capture for about a second: the run is broken,
  /// and the selfie may not come from whatever is held up after the gap.
  void failFaceLost() {
    if (state.phase == LivenessPhase.complete ||
        state.phase == LivenessPhase.failed) {
      return;
    }
    _cancelTimer();
    _flashGate?.reset();
    _runGeneration++;
    state = state.copyWith(
      phase: LivenessPhase.failed,
      instruction: 'Let\'s start over. Please stay in frame.',
      error: 'face_lost',
      clearActiveChallenge: true,
      clearPositionGuidance: true,
    );
  }

  /// The ready pause (liveness/ready_pause.dart): a framed, lit face holds
  /// still for a moment before the first prompt, and with gestures the first
  /// prompt waits a little longer for Core's plan. Moving out of place
  /// starts the pause again.
  void _holdForReady(LivenessFaceData data) {
    final inPlace =
        state.positionGuidance == null && state.lightingGuidance == null;
    if (!inPlace) {
      _readyAt = null;
      if (state.readyProgress != 0 ||
          state.instruction == kHoldStillInstruction) {
        state = state.copyWith(
          readyProgress: 0,
          instruction: 'Position your face in the circle',
        );
      }
      return;
    }
    final now = clock();
    final ready = readyPauseStep(_readyAt, now);
    _readyAt = ready.readyAt;
    if (!ready.go || planGateWaits(_planStatus, _planAskedAt, now)) {
      final share = ready.go ? 1.0 : readyPauseShare(_readyAt, now);
      if (state.instruction != kHoldStillInstruction ||
          (state.readyProgress - share).abs() >= 0.02) {
        state = state.copyWith(
          instruction: kHoldStillInstruction,
          readyProgress: share,
        );
      }
      return;
    }
    // Held still and facing the camera: this is the person at rest.
    _restPitch = data.headEulerAngleX;
    _challengeStarted = true;
    state = state.copyWith(readyProgress: 1);
    _startNextChallenge();
  }

  void _startNextChallenge() {
    final challenge = _manager.current;
    if (challenge == null) {
      _cancelTimer();
      state = state.copyWith(
        phase: LivenessPhase.capturing,
        instruction: 'Hold still…',
        clearActiveChallenge: true,
        clearPositionGuidance: true,
      );
      return;
    }

    final timeout = _timeoutFor(challenge);

    _prompts.shown(challenge.type.name, flashClockNow());
    _xHistory.clear();
    _earHistory.clear();
    _hold.reset();
    _directionWatch.reset();
    _challengeProcessing = false;

    state = state.copyWith(
      phase: LivenessPhase.challenge,
      instruction: challenge.instruction,
      timeoutRemaining: timeout,
      activeChallenge: challenge.type,
      clearPositionGuidance: true,
      wrongGesture: false,
    );

    _startTimer(timeout);
  }

  /// Seconds a challenge gets. The consumer's per-challenge timeout governs the
  /// gestures; the passive hold keeps its own, since it is not a gesture.
  int _timeoutFor(ChallengeConfig challenge) {
    if (challenge.type == LivenessChallenge.hold) return challenge.timeoutSeconds;
    return ref.read(verificationConfigProvider).livenessConfig?.timeoutPerChallenge ??
        challenge.timeoutSeconds;
  }

  void _checkGesture(LivenessFaceData data) {
    final challenge = _manager.current;
    if (challenge == null) return;

    // Head directions. The wrong way is never a failure and never a red
    // warning: it does not count, and after a second of it the narrator shows
    // the way again.
    if (isDirectionChallenge(challenge.type)) {
      final step = _directionWatch.update(
        challenge.type,
        data,
        _restPitch ?? data.headEulerAngleX,
      );
      if (step == DirectionStep.done) {
        _onChallengePassed();
        return;
      }
      if (step == DirectionStep.wrongWay) {
        state = state.copyWith(wrongWayCount: state.wrongWayCount + 1);
      }
      if (state.wrongGesture) state = state.copyWith(wrongGesture: false);
      return;
    }

    final detected = switch (challenge.type) {
      LivenessChallenge.nod   => detectNod(_xHistory),
      LivenessChallenge.turn  => detectTurn(data.headEulerAngleY),
      LivenessChallenge.blink => detectBlink(_earHistory),
      LivenessChallenge.smile => detectSmile(data.smilingProbability),
      // Passive Liveness: passes on its own after a steady moment in position.
      LivenessChallenge.hold => _hold.update(
          inPosition: holdFrameInPosition(data),
          now: DateTime.now(),
        ),
      // Judged above.
      LivenessChallenge.turnLeft ||
      LivenessChallenge.turnRight ||
      LivenessChallenge.lookUp ||
      LivenessChallenge.lookDown =>
        false,
    };

    if (detected) {
      _onChallengePassed();
      return;
    }

    // Wrong-gesture feedback (mirrors the web SDK): the requested gesture wasn't
    // detected, but the user is clearly doing a DIFFERENT one. Flash a red
    // border + "Wrong gesture". The "wrong" signals per challenge avoid
    // self-overlap (e.g. a turn challenge doesn't flag turning as wrong).
    final isTurning = detectTurn(data.headEulerAngleY);
    final isSmiling = detectSmile(data.smilingProbability);
    final wrong = switch (challenge.type) {
      LivenessChallenge.nod   => isTurning || isSmiling,
      LivenessChallenge.turn  => isSmiling,
      LivenessChallenge.blink => isTurning || isSmiling,
      LivenessChallenge.smile => isTurning,
      // Holding still has no wrong gesture; a turned head just delays the hold.
      LivenessChallenge.hold => false,
      LivenessChallenge.turnLeft ||
      LivenessChallenge.turnRight ||
      LivenessChallenge.lookUp ||
      LivenessChallenge.lookDown =>
        false,
    };

    if (wrong != state.wrongGesture) {
      state = state.copyWith(wrongGesture: wrong);
    }
  }

  void _onChallengePassed() {
    _challengeProcessing = true;
    _cancelTimer();
    _prompts.passed(flashClockNow());
    _manager.advance();

    state = state.copyWith(
      phase: LivenessPhase.challengePassed,
      instruction: 'Good.',
      completedCount: _manager.completedCount,
      timeoutRemaining: 0,
      clearPositionGuidance: true,
      wrongGesture: false,
    );

    Future.delayed(const Duration(milliseconds: 700), () {
      if (state.phase != LivenessPhase.challengePassed) return;
      _startNextChallenge();
    });
  }

  // ── Internal: signal history ───────────────────────────────────────────────

  void _updateHistory(LivenessFaceData data) {
    _xHistory.add(data.headEulerAngleX);
    if (_xHistory.length > _historySize) _xHistory.removeAt(0);

    _earHistory.add(data.eyeAverageOpenProbability);
    if (_earHistory.length > _historySize) _earHistory.removeAt(0);
  }

  // ── Internal: timeout timer ────────────────────────────────────────────────

  void _startTimer(int seconds) {
    _cancelTimer();
    var remaining = seconds;

    _timeoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      remaining--;
      if (remaining <= 0) {
        timer.cancel();
        _onChallengeTimeout();
      } else {
        state = state.copyWith(timeoutRemaining: remaining);
      }
    });
  }

  void _cancelTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  void _onChallengeTimeout() {
    _cancelTimer();
    state = state.copyWith(
      phase: LivenessPhase.failed,
      instruction: 'Time\'s up. Please try again.',
      error: 'Challenge timed out',
      clearActiveChallenge: true,
      clearPositionGuidance: true,
    );
  }

  // ── Internal: cleanup ──────────────────────────────────────────────────────

  void _cleanup() {
    _cancelTimer();
  }
}

/// Asks Core for one attempt's gestures, head directions or classic
/// (liveness/direction_plan.dart). Null asks nothing (the SDK picks its own).
/// Overridden in tests.
final directionPlanRequestProvider =
    Provider<Future<DirectionPlan?> Function(PlanRequest plan)?>(
  (ref) => (plan) =>
      ref.read(kYCNotifierProvider.notifier).api.livenessDirections(plan),
);
