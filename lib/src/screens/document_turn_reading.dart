import 'dart:async';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../config/document_turn.dart';
import '../services/native_document_camera.dart';
import '../services/text_recognition.dart';

/// The document camera's side of turning a NIN slip upright on a phone held
/// upright (config/document_turn.dart): whether the guide is turned, which
/// extra quarter turn the text reader uses, and which way to turn the photo
/// back once it is taken.
///
/// Kept out of the screen so the screen only asks it three questions: read
/// this frame, should this frame count, and how far to turn the capture.
class DocumentTurnReading {
  final DocumentTurnReader _reader = DocumentTurnReader();
  bool _turned = false;

  // This build's native side has no turned read (an older native build): read
  // upright for the rest of the screen, so auto-capture still runs for every
  // other document and the shutter still works for the slip.
  bool _turnedReadUnavailable = false;
  List<int>? _sentNativeTurns;

  /// True while the guide stands upright.
  bool get turned => _turned;

  /// Decides whether a document of [documentAspect] is turned in a viewfinder
  /// of [view]. Returns true when that changed, so the caller can update what
  /// depends on it (the framing gate's expected shape).
  bool update(double documentAspect, Size view) {
    final next = view.height > 0 &&
        turnsDocument(documentAspect, view.width / view.height);
    if (next == _turned) return false;
    _turned = next;
    _reader.reset();
    return true;
  }

  /// Reads one camera frame: upright, or with the next extra quarter turn
  /// while the slip is turned. Reports the turn used (0 when read upright).
  Future<({List<String> lines, int turn})> read(
    TextRecognitionService recognizer,
    CameraImage image, {
    required int sensorOrientation,
  }) async {
    if (_turned && !_turnedReadUnavailable) {
      final turn = _reader.nextTurn();
      final lines = await recognizer.recognizeTurned(
        image,
        sensorOrientation: sensorOrientation,
        quarterTurns: turn,
      );
      if (lines != null) return (lines: lines, turn: turn);
      _turnedReadUnavailable = true;
    }
    final lines =
        await recognizer.recognize(image, sensorOrientation: sensorOrientation);
    return (lines: lines, turn: 0);
  }

  /// False for a frame read at a turn other than the one that has already
  /// identified the slip: the native camera may have one in flight from before
  /// the turn was found, and reading it as "not the document" would restart
  /// the auto-capture dwell.
  bool counts(int turn) {
    final locked = _reader.lockedTurn;
    return !_turned || locked == null || turn == locked;
  }

  /// Reports whether a frame read at [turn] identified the document. Null when
  /// the frame had nothing readable. Upright reads say nothing about a turn.
  void observe(int turn, {required bool? identified}) {
    if (turn == 0) return;
    _reader.observe(turn, identified: identified);
  }

  /// Tells the Android native camera which turns to read at, when that
  /// changed. A camera that cannot (an older native build) keeps reading
  /// upright, which is the fallback.
  void syncNative(NativeDocumentCamera? camera) {
    if (camera == null) return;
    final turns = _turned ? _reader.turns : const [0];
    if (listEquals(turns, _sentNativeTurns)) return;
    _sentNativeTurns = turns;
    unawaited(camera.setTextTurns(turns));
  }

  /// A new native camera starts reading upright: send it the turns again.
  void forgetNativeTurns() => _sentNativeTurns = null;

  /// Clockwise degrees that put the photo back to landscape: the turn that
  /// identified the slip, or the default direction (top facing right). Zero
  /// when the guide is not turned.
  int get captureUndoDegrees => _turned ? _reader.undoDegreesForCapture : 0;

  /// A new side or a retake: try both turns again.
  void reset() => _reader.reset();
}
