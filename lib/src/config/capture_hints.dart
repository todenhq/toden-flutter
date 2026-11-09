import '../services/document_framing_gate.dart';

// ─── Capture hint copy ────────────────────────────────────────────────────────
//
// One instruction per rejection reason. Deliberately imperative and specific:
// the previous single message ("Align your ID within the frame") told the user
// nothing about WHICH way to move, and the commonest failure — holding the
// document too close — is the one people can't guess, because the instinct on
// "it isn't reading" is to move nearer still.
//
// Copy is document-agnostic. [label] is the ID's own name so the same strings
// serve a passport, a card or a licence without special-casing any of them.

String documentHintText(DocumentHint hint, {required String label}) {
  switch (hint) {
    case DocumentHint.searching:
      return 'Point the camera at your $label';
    case DocumentHint.moreLight:
      return 'Too dark. Move somewhere brighter';
    case DocumentHint.wrongDocument:
      // "your", not "a": an article chosen by letter misreads labels said as
      // letters or acronyms ("an SSNIT", "a NIN").
      return "That doesn't look like your $label";
    case DocumentHint.showMrz:
      return 'Include the code strip along the bottom of the page';
    case DocumentHint.moveCloser:
      return 'Move closer';
    case DocumentHint.moveBack:
      // The one users don't reach for on their own.
      return 'Move back a little. Fit the whole $label in view';
    case DocumentHint.centre:
      return 'Centre your $label in the frame';
    case DocumentHint.placeInFrame:
      return 'Place your ID inside the frame';
    case DocumentHint.fitCorners:
      return 'Fit all four corners of your ID inside the frame';
    case DocumentHint.spaceAround:
      return 'Move back a little so there is space around your ID';
    case DocumentHint.showBack:
      return "That's still the front. Turn your $label over";
    case DocumentHint.holdStill:
      return 'Hold still…';
    case DocumentHint.captured:
      return 'Got it';
  }
}

/// True when the hint is asking the user to change something, so the UI can
/// give it more weight than the neutral prompts.
bool documentHintIsAction(DocumentHint hint) =>
    hint == DocumentHint.moreLight ||
    hint == DocumentHint.wrongDocument ||
    hint == DocumentHint.showMrz ||
    hint == DocumentHint.moveCloser ||
    hint == DocumentHint.moveBack ||
    hint == DocumentHint.centre ||
    hint == DocumentHint.placeInFrame ||
    hint == DocumentHint.fitCorners ||
    hint == DocumentHint.spaceAround ||
    hint == DocumentHint.showBack;
