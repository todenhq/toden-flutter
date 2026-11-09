import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import 'document_corners.dart';

/// One analysed frame's text: the recognized lines, plus the normalised (0..1)
/// box they occupy when the platform could report it. The box is the only
/// geometry ML Kit offers — it has no rectangle detector — and stands in for
/// "how much of the frame the document's print covers".
class RecognizedFrame {
  final List<String> lines;
  final Rect? bounds;

  /// The document's corners from the native border detector, when found.
  final DocumentQuad? quad;

  /// True when the native side ran the corner detector on this frame, so a
  /// null [quad] means "no document" rather than "cannot tell".
  final bool quadSupported;

  /// Upright pixel size of the analysed frame.
  final Size frameSize;

  /// Extra clockwise quarter turns the text was read at (0 for the ordinary
  /// upright read; 1 or 3 for a turned NIN slip, see [NativeDocumentCamera
  /// .setTextTurns]). [bounds] are mapped back into the upright frame either
  /// way.
  final int turn;

  const RecognizedFrame(
    this.lines,
    this.bounds, {
    this.quad,
    this.quadSupported = false,
    this.frameSize = Size.zero,
    this.turn = 0,
  });

  static const empty = RecognizedFrame(<String>[], null);
}

/// Dart client for the **Android-native** document camera (CameraX).
///
/// On Android the Flutter camera plugin has to run Preview + ImageAnalysis +
/// VideoCapture together on the document step, which exceeds the CameraX
/// use-case cap on many devices: stream resolutions get downgraded (a soft
/// preview), every still tears the recording down and reconfigures the surface
/// (stutter, and a sideways flash to hide), and the plugin's preview widget
/// re-rotates itself off the accelerometer. This camera instead runs ONE native
/// session — Preview + ImageAnalysis + ImageCapture — with the side clip encoded
/// off the analysis frames, exactly as [NativeLivenessRecorder] does for
/// liveness.
///
/// The native side renders the preview into a Flutter texture; show [textureId]
/// with `NativeCameraPreview`. Recognized text lines arrive via the [start]
/// callback and drive the Dart-side auto-capture gate — every framing and MRZ
/// decision stays in Dart.
///
/// iOS does NOT use this — its plugin preview is stable and rotation-correct.
class NativeDocumentCamera {
  static const MethodChannel _method =
      MethodChannel('kyc_sdk_flutter/document_camera');
  static const EventChannel _textEvents =
      EventChannel('kyc_sdk_flutter/document_camera/text');

  int? _textureId;
  StreamSubscription<dynamic>? _textSub;

  /// The Flutter texture id for the camera preview (valid after [start]).
  int? get textureId => _textureId;

  /// Sensor rotation (degrees). Reported for diagnostics — the preview texture
  /// already arrives upright, so nothing rotates it.
  int rotationDegrees = 0;

  /// Preview buffer size in the sensor's native (landscape) orientation.
  int previewWidth = 0;
  int previewHeight = 0;

  /// Starts the camera + preview + analysis. Returns the preview texture id.
  /// [onText] receives each analysed frame's recognized text (empty when
  /// nothing was read).
  ///
  /// [analyze] false is the in-SDK photo camera: preview, torch and still
  /// only. The native side binds no frame analysis, so no text, corners or
  /// clip, and [onText] is never called. A native build too old to know the
  /// flag analyses anyway, which nothing here listens to.
  Future<int> start({
    void Function(RecognizedFrame)? onText,
    bool analyze = true,
  }) async {
    final info = await _method.invokeMapMethod<String, dynamic>(
      'start',
      analyze ? null : const {'analyze': false},
    );
    final id = (info?['textureId'] as num?)?.toInt() ?? -1;
    _textureId = id;
    rotationDegrees = (info?['rotation'] as num?)?.toInt() ?? 0;
    previewWidth = (info?['previewWidth'] as num?)?.toInt() ?? 0;
    previewHeight = (info?['previewHeight'] as num?)?.toInt() ?? 0;

    if (analyze && onText != null) {
      _textSub = _textEvents.receiveBroadcastStream().listen(
        (event) =>
            onText(event is Map ? parseFrame(event) : RecognizedFrame.empty),
        onError: (_) => onText(RecognizedFrame.empty),
      );
    }

    return id;
  }

  /// Begins recording the clip for the side being captured. Cheap — it touches
  /// no camera state, so switching sides or retaking never restarts the session.
  /// [audio] adds a sound track; the native side leaves it out if the
  /// microphone cannot be used.
  Future<void> startRecording({bool audio = false}) =>
      _method.invokeMethod<void>('startRecording', {'audio': audio});

  /// Stops recording; returns the recorded MP4 path, or null.
  Future<String?> stopRecording() =>
      _method.invokeMethod<String>('stopRecording');

  /// Whether the device has a flash unit to use as a torch.
  Future<bool> hasTorch() async =>
      await _method.invokeMethod<bool>('hasTorch') ?? false;

  /// Switches the torch on/off.
  Future<void> setTorch(bool enabled) =>
      _method.invokeMethod<void>('setTorch', {'enabled': enabled});

  /// Sets the extra clockwise quarter turns the text reader cycles through, one
  /// per analysed frame: `[0]` for the ordinary upright read, `[3, 1]` to
  /// alternate for a turned NIN slip, `[3]` once a turn has identified it
  /// (config/document_turn.dart). Each frame reports the turn it was read at.
  ///
  /// Returns false when this build's native side cannot (an app still running
  /// an older native build): its frames keep coming, read upright, so every
  /// other document keeps its auto-capture.
  Future<bool> setTextTurns(List<int> turns) async {
    try {
      await _method.invokeMethod<void>('setTextTurns', {'turns': turns});
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Takes the OCR-grade still, returned upright (the rotation is baked into
  /// the pixels natively, so there is no EXIF for the crop to misread).
  /// Returns null if the capture failed — the caller lets the user retake.
  Future<Uint8List?> captureStill({int quality = 95}) =>
      _method.invokeMethod<Uint8List>('captureStill', {'quality': quality});

  @visibleForTesting
  static RecognizedFrame parseFrame(Map<dynamic, dynamic> m) {
    final lines = (m['lines'] as List?)?.whereType<String>().toList(
              growable: false,
            ) ??
        const <String>[];
    final b = m['bounds'];
    Rect? bounds;
    if (b is List && b.length == 4) {
      final v = b.map((e) => (e as num).toDouble()).toList(growable: false);
      bounds = Rect.fromLTRB(v[0], v[1], v[2], v[3]);
    }
    final fw = (m['frameW'] as num?)?.toDouble() ?? 0;
    final fh = (m['frameH'] as num?)?.toDouble() ?? 0;
    return RecognizedFrame(
      lines,
      bounds,
      quad: DocumentQuad.fromList(m['quad']),
      quadSupported: m['quadSupported'] == true,
      frameSize: Size(fw, fh),
      turn: (m['turn'] as num?)?.toInt() ?? 0,
    );
  }

  /// Tears down the camera + analysis + texture.
  Future<void> dispose() async {
    await _textSub?.cancel();
    _textSub = null;
    try {
      await _method.invokeMethod<void>('dispose');
    } catch (_) {
      // best-effort
    }
    _textureId = null;
  }
}
