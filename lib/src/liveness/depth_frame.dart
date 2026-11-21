import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

// ─── The iPhone depth frame: one reading of the face's shape ─────────────────
//
// Core (docbio/depth-sensor.ts) reads one depth frame from the Face ID
// (TrueDepth) camera and measures how far the nose stands out of the plane of
// the face: a print or a screen is flat to a millimetre, a face is not. It is
// uploaded as `liveness_depth`, sent as `mediaIds.livenessDepth` and signed
// with the selfie and the video (signed_capture.dart).
//
// The camera plugin cannot deliver depth, and a second capture session on the
// front camera while the plugin's is running would interrupt one of them. So
// the frame is taken once the plugin has let the camera go: just after the
// selfie, when the review or the hand-over has replaced the live preview. The
// native side (DepthFrame.swift) opens the TrueDepth camera on its own, takes
// one frame, converts it to millimetres and closes the camera again. Any
// camera opened meanwhile waits for it ([depthCameraFree]).
//
// iPhone only. Android, an iPhone without a Face ID camera, a refusal, a
// timeout or any error: no frame, and the verification goes without it.

/// The longest the native side keeps the TrueDepth camera open.
const Duration kDepthFrameTimeout = Duration(milliseconds: 2500);

/// One depth frame, row by row, in millimetres from the camera; 0 where the
/// sensor had no reading.
class DepthFrame {
  final int width;
  final int height;
  final Uint16List mm;

  const DepthFrame({required this.width, required this.height, required this.mm});
}

/// The native reply as a frame: `{width, height, mm}`, `mm` being the
/// readings as little-endian 16-bit values. Null for anything malformed.
DepthFrame? depthFrameFromReply(Object? reply) {
  if (reply is! Map) return null;
  final width = reply['width'];
  final height = reply['height'];
  final raw = reply['mm'];
  if (width is! int || height is! int || raw is! Uint8List) return null;
  if (width <= 0 || height <= 0 || raw.length != width * height * 2) return null;
  final data = ByteData.sublistView(raw);
  final mm = Uint16List(width * height);
  for (var i = 0; i < mm.length; i++) {
    mm[i] = data.getUint16(i * 2, Endian.little);
  }
  return DepthFrame(width: width, height: height, mm: mm);
}

/// [frame] as Core reads it: a 16-bit greyscale PNG (colour type 0, bit depth
/// 16, not interlaced). Unfiltered: the readings compress well enough without
/// a row filter, and filter 0 is the one every PNG reader handles the same.
Uint8List encodeDepthPng(DepthFrame frame) {
  // A copy of its own: fromBytes reads the buffer whole, from offset 0.
  final readings = Uint16List.fromList(frame.mm);
  final image = img.Image.fromBytes(
    width: frame.width,
    height: frame.height,
    bytes: readings.buffer,
    format: img.Format.uint16,
    numChannels: 1,
  );
  return img.PngEncoder(filter: img.PngFilter.none).encode(image);
}

/// Where the frame comes from: the platform channel in the app, a fake in
/// tests.
abstract interface class DepthCamera {
  /// One frame, or null. May throw; [captureDepthPng] contains it.
  Future<DepthFrame?> capture(Duration timeout);
}

/// The native TrueDepth reader (ios/.../DepthFrame.swift).
class MethodChannelDepthCamera implements DepthCamera {
  static const _channel = MethodChannel('kyc_sdk_flutter/depth_frame');

  const MethodChannelDepthCamera();

  @override
  Future<DepthFrame?> capture(Duration timeout) async => depthFrameFromReply(
        await _channel.invokeMethod<Object?>(
          'capture',
          {'timeoutMs': timeout.inMilliseconds},
        ),
      );
}

Future<void>? _inFlight;

/// Resolves once no depth frame is being taken, so the front camera is free,
/// or after [max] at the latest. Every camera open awaits it.
Future<void> depthCameraFree({Duration max = const Duration(seconds: 4)}) async {
  final running = _inFlight;
  if (running == null) return;
  await running.timeout(max, onTimeout: () {});
}

/// Takes one depth frame of the face and returns it as PNG bytes, or null.
/// Call only once the camera plugin has closed the front camera. Never throws.
Future<Uint8List?> captureDepthPng({
  DepthCamera camera = const MethodChannelDepthCamera(),
  bool? supported,
  Duration timeout = kDepthFrameTimeout,
}) async {
  if (!(supported ?? Platform.isIOS)) return null;
  final done = Completer<void>();
  _inFlight = done.future;
  DepthFrame? frame;
  try {
    // The native side keeps to [timeout]; this bound is for a reply that
    // never comes. Widened first: a Future<DepthFrame> refuses a null
    // from onTimeout.
    frame = await camera
        .capture(timeout)
        .then<DepthFrame?>((f) => f)
        .timeout(timeout + const Duration(seconds: 1), onTimeout: () => null);
  } catch (e) {
    if (kDebugMode) debugPrint('KYC depth frame failed: $e');
    frame = null;
  } finally {
    done.complete();
    if (identical(_inFlight, done.future)) _inFlight = null;
  }
  if (frame == null) return null;
  try {
    // Off the UI thread: the review is on screen while this runs.
    return await compute(encodeDepthPng, frame);
  } catch (e) {
    if (kDebugMode) debugPrint('KYC depth frame encode failed: $e');
    return null;
  }
}
