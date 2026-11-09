import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../config/capture_config.dart';
import '../liveness/face_detection.dart';
import '../liveness/selfie_candidates.dart';
import '../liveness/selfie_pick.dart';
import '../services/image_service.dart';

// ─── The selfie, chosen from the live run (screen side) ──────────────────────
//
// The liveness screen owns the frames, so it offers them here: during the
// gestures every third analysed frame, and every frame of the final capture.
// The rules are liveness/selfie_pick.dart; the best frame is held here, and
// encoded cut to the standard frame when the capture takes it.
//
//  - iOS: the analysed CameraImage is in Dart. A frame that beats the held
//    one is copied whole (one BGRA frame) and its sharpness measured.
//  - Android: the native recorder owns the camera and the frame never reaches
//    Dart, so a better frame is grabbed as the recorder's latest still (at
//    most every [_kNativeGrabGap]) and scored by its pose alone.

/// The frame a candidate keeps.
sealed class SelfieFrame {
  const SelfieFrame();
}

/// iOS: a copy of the analysed BGRA stream frame.
final class BgraSelfieFrame extends SelfieFrame {
  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;
  const BgraSelfieFrame(this.bytes, this.width, this.height, this.bytesPerRow);
}

/// Android: the recorder's still, already upright and mirrored.
final class StillSelfieFrame extends SelfieFrame {
  final Future<Uint8List?> jpeg;
  const StillSelfieFrame(this.jpeg);
}

/// The native still is a JPEG encode on the camera thread: not every frame.
const Duration _kNativeGrabGap = Duration(milliseconds: 300);

class LivenessSelfieRun {
  LivenessSelfieRun({required this.ios})
      : candidates = SelfieCandidates<SelfieFrame>(poseZeroFromRun: ios);

  final bool ios;
  final SelfieCandidates<SelfieFrame> candidates;

  int _generation = -1;
  int _offered = 0;
  DateTime? _lastGrab;

  /// The latest offered frame's verdict, and when it came.
  SelfieVerdict? lastVerdict;
  DateTime? lastVerdictAt;

  /// Clears the held selfie when the run has broken since the last frame (the
  /// liveness notifier counts breaks: a continuity jump, a face back after a
  /// gap, a restart).
  void sync(int generation) {
    if (generation == _generation) return;
    _generation = generation;
    clear();
  }

  void clear() {
    candidates.clear();
    lastVerdict = null;
    lastVerdictAt = null;
    _offered = 0;
  }

  bool _turn(bool capturing) {
    _offered++;
    return capturing || _offered % 3 == 0;
  }

  void _verdict(SelfieVerdict v) {
    lastVerdict = v;
    lastVerdictAt = DateTime.now();
  }

  /// iOS: offer the analysed frame.
  void offerBgra(LivenessFaceData face, CameraImage image, {required bool capturing}) {
    candidates.observe(face);
    if (!_turn(capturing) || image.planes.isEmpty) return;
    final plane = image.planes.first;
    _verdict(candidates.consider(
      face,
      inStill: SelfieFace.inStill(face, ios: true),
      frameWidth: image.width,
      frameHeight: image.height,
      sharpness: (rect) => bgraSharpness(plane.bytes, plane.bytesPerRow, rect),
      grab: () => BgraSelfieFrame(
        Uint8List.fromList(plane.bytes),
        image.width,
        image.height,
        plane.bytesPerRow,
      ),
    ));
  }

  /// Android: offer the recorder's analysed face; [width] x [height] is the
  /// upright frame, [grab] takes the recorder's current still.
  void offerNative(
    LivenessFaceData face, {
    required int width,
    required int height,
    required Future<Uint8List?> Function() grab,
    required bool capturing,
  }) {
    candidates.observe(face);
    if (!_turn(capturing) || width <= 0 || height <= 0) return;
    final now = DateTime.now();
    final last = _lastGrab;
    final admit = last == null || now.difference(last) >= _kNativeGrabGap;
    _verdict(candidates.consider(
      face,
      inStill: SelfieFace.inStill(face, ios: false),
      frameWidth: width,
      frameHeight: height,
      admit: admit,
      grab: () {
        _lastGrab = now;
        return StillSelfieFrame(grab());
      },
    ));
  }

  /// The best frame of the run, encoded and cut to the standard frame. Null
  /// when there is none, or it could not be encoded.
  Future<Uint8List?> encodeBest() async {
    final best = candidates.best;
    if (best == null) return null;
    return switch (best.frame) {
      BgraSelfieFrame(:final bytes, :final width, :final height, :final bytesPerRow) =>
        processSelfieFrame(
          bytes: bytes,
          width: width,
          height: height,
          bytesPerRow: bytesPerRow,
          bgra: true,
          // The iOS stream frame is already selfie-mirrored (see the screen).
          mirror: false,
          cut: best.face,
        ),
      StillSelfieFrame(:final jpeg) => () async {
          final bytes = await jpeg;
          return bytes == null ? null : processSelfieStreamStill(bytes, cut: best.face);
        }(),
    };
  }
}

/// The native recorder's still quality, as the capture path uses it.
const int kNativeSelfieQuality = CaptureConfig.selfieImageQuality;
