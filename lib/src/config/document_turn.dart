// ─── Turning a long document upright on a phone held upright ──────────────────
//
// A NIN slip is 2.07 times as long as it is tall. Framed landscape on a phone
// held upright, the frame is limited by the screen's width and the slip comes
// out small; turned upright it uses the screen's height between the camera's
// top controls and its bottom bar, which gives the slip's small print about
// 1.3 times the detail each way on a typical phone (about 1.6 times the pixels).
//
// The same rule is mirrored in the React Native SDK (capture/documentTurn.ts)
// and the web SDK (document-turn.ts): change all three together.
//
// Pure, so the rule and the reader's alternation are unit-tested.

/// Documents at least this long are turned upright. Only the NIN slip today.
const double kTurnMinAspect = 1.8;

/// The slip is shown turned a quarter clockwise: its top edge faces the RIGHT
/// of the screen. Reading it upright then takes three more clockwise quarter
/// turns, and so does putting the captured photo back the right way up.
const int kDefaultReadTurn = 3;

/// True when a document of [documentAspect] (width / height) is turned upright
/// in a camera view of [viewAspect]. Only a view taller than it is wide turns:
/// a tablet or a phone held sideways keeps the landscape frame.
bool turnsDocument(double documentAspect, double viewAspect) =>
    documentAspect >= kTurnMinAspect && viewAspect > 0 && viewAspect < 1;

/// The guide's on-screen width over height: upright when turned.
double screenGuideAspect(double documentAspect, bool turned) =>
    turned ? 1 / documentAspect : documentAspect;

/// The crop box for a picked photo, shaped as the camera guide would be: the
/// document camera fills the screen, so on a screen taller than wide a NIN
/// slip stands upright here too. A [turned] crop is turned back to landscape
/// ([undoDegrees]) before it is stored, as an upright capture is.
({double aspect, bool turned}) documentCropGuide(
    double documentAspect, double screenAspect) {
  final turned = turnsDocument(documentAspect, screenAspect);
  return (aspect: screenGuideAspect(documentAspect, turned), turned: turned);
}

/// Clockwise degrees that turn a capture of the upright frame back into a
/// landscape document. [readTurn] is the extra clockwise quarter turns that let
/// the text reader read the document (1 or 3); without one, the default
/// direction is assumed. The server copes with a wrong guess: it detects how a
/// page is rotated.
int undoDegrees(int? readTurn) {
  final turn = readTurn == 1 || readTurn == 3 ? readTurn! : kDefaultReadTurn;
  return turn * 90;
}

/// How many frames read at the remembered turn may fail to identify the
/// document before the reader goes back to trying both turns. Two, so one
/// blurred frame does not throw away a turn that worked.
const int kTurnLockMisses = 2;

/// Which extra quarter turn to read the next frame at, while the document is
/// turned.
///
/// The person may turn the slip either way, so until a frame identifies the
/// document the reader ALTERNATES between three quarter turns (the direction
/// the sample shows) and one. A turn that identifies the document is kept, so
/// a steady hand is not read wrong every other frame (which would keep the
/// auto-capture dwell from ever completing), and it is remembered to put the
/// photo back the right way up.
class DocumentTurnReader {
  int? _locked;
  int? _identifiedTurn;
  int _misses = 0;
  int _next = 0;

  /// The turns being tried, in order: the remembered one alone, or both.
  List<int> get turns =>
      _locked == null ? const [kDefaultReadTurn, 1] : [_locked!];

  /// The turn that last read a frame identifying the document, if any.
  int? get identifiedTurn => _identifiedTurn;

  /// The remembered turn, while one is held. Frames read at another turn
  /// (one already in flight when the turn was found) are stale.
  int? get lockedTurn => _locked;

  /// The turn to read the next frame at.
  int nextTurn() {
    final candidates = turns;
    final turn = candidates[_next % candidates.length];
    _next++;
    return turn;
  }

  /// Reports how a frame read at [turn] went. [identified] is null when the
  /// frame had nothing readable, which says nothing about the turn.
  void observe(int turn, {required bool? identified}) {
    if (identified == null) return;
    if (identified) {
      _locked = turn;
      _identifiedTurn = turn;
      _misses = 0;
      return;
    }
    if (_locked != null && turn == _locked) {
      _misses++;
      if (_misses >= kTurnLockMisses) {
        _locked = null;
        _misses = 0;
        _next = 0;
      }
    }
  }

  /// Clockwise degrees that put the captured photo back the right way up.
  int get undoDegreesForCapture => undoDegrees(_identifiedTurn);

  /// Forgets everything: a new side, a retake, or another document.
  void reset() {
    _locked = null;
    _identifiedTurn = null;
    _misses = 0;
    _next = 0;
  }
}
