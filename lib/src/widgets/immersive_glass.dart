import 'package:flutter/painting.dart';

import '../config/capture_hints.dart' show documentHintIsAction;
import '../services/document_framing_gate.dart';

// ─── The glass under every full-screen camera control ────────────────────────
//
// The one surface every control over the full-screen camera sits on: a dark
// glass with a hairline edge. Flat rather than blurred so the back button, the
// pills and the bottom buttons read as one set over any scene.
//
// Mirrors the React Native SDK's components/viewfinder/immersiveGlass.ts.

abstract final class ImmersiveGlass {
  /// rgba(12,14,22,0.62)
  static const Color fill = Color.fromRGBO(12, 14, 22, 0.62);

  /// The fill while pressed: a background change only, never a layout shift.
  static const Color pressed = Color.fromRGBO(12, 14, 22, 0.82);

  /// rgba(255,255,255,0.14)
  static const Color border = Color.fromRGBO(255, 255, 255, 0.14);

  static const Color text = Color(0xFFFFFFFF);

  /// Captions under the side buttons: white at 85%.
  static const Color caption = Color.fromRGBO(255, 255, 255, 0.85);
}

/// The colour of the instruction's status icon.
enum ImmersiveHintTone { neutral, action, ready, warning }

/// Sorts the capture gate's current hint into a tone, from states the gate
/// already reports; it decides nothing new. [blocked] is the corner gate
/// holding the shutter.
ImmersiveHintTone immersiveHintTone({
  required DocumentHint hint,
  required DocumentFraming framing,
  bool? hintIsAction,
  required bool blocked,
}) {
  if (blocked) return ImmersiveHintTone.action;
  if (hint == DocumentHint.moreLight ||
      hint == DocumentHint.wrongDocument ||
      framing == DocumentFraming.wrongShape) {
    return ImmersiveHintTone.warning;
  }
  if (framing == DocumentFraming.holding ||
      framing == DocumentFraming.ready ||
      hint == DocumentHint.holdStill ||
      hint == DocumentHint.captured) {
    return ImmersiveHintTone.ready;
  }
  return (hintIsAction ?? documentHintIsAction(hint))
      ? ImmersiveHintTone.action
      : ImmersiveHintTone.neutral;
}

/// The brand colour lifted towards white (35%) so it reads on the dark glass.
/// Each channel is rounded as the React Native SDK's mixHex rounds it.
Color primaryOnDark(Color primary) {
  int mix(int c) => (c + (255 - c) * 0.35).round();
  final argb = primary.toARGB32();
  return Color.fromARGB(
    (argb >> 24) & 0xFF,
    mix((argb >> 16) & 0xFF),
    mix((argb >> 8) & 0xFF),
    mix(argb & 0xFF),
  );
}
