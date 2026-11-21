import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../liveness/narrator_pose.dart';

// ─── The gesture narrator's drawing ───────────────────────────────────────────
//
// A face icon in a 100 by 100 square, drawn as Apple draws its face
// recognition face (user, 2026-11-17): a round head filling the square, two
// eyes, a nose and a mouth, in flat solid white lines with no edge or shadow
// round them. The features are kept to the head, so in a turn or a nod they
// slide round it as on a ball and go out of sight at its edge rather than over
// it, and the head turns with them: its outline narrows and leans the way it
// goes. The numbers are the web SDK's GestureNarrator's, so the icon is the
// same drawing on every SDK.

/// The face's lines: white, the colour of the line round the window, and solid
/// where that line is at 70%, because this sits ON the face and 70% white
/// washed out over a lit forehead (web NARRATOR_COLOUR, 2026-11-18). It was the
/// workflow's colour until then.
const Color kNarratorColour = Color(0xFFFFFFFF);

const double _headR = 44;

/// Inside the head's line: where the features may show.
const double _faceInset = 3.5;

/// How much the head's outline narrows at the end of a turn, and flattens at
/// the end of a nod, and how far it leans that way.
const double _headTurnNarrow = 0.1;
const double _headNodFlatten = 0.06;
const double _headTurnLean = 3;
const double _headNodLean = 2.5;

/// The features were drawn for a smaller face, so they are scaled to this head
/// and centred on it, at the same line weight.
const double _featuresScale = 1.15;
const List<double> _eyesAt = [37, 63];
const double _eyeY = 40;

/// Which side of the face each eye is on: the left one, then the right.
const List<double> _eyeSide = [-1, 1];

/// How far the eyes travel in their look, in the drawing's units.
const double _lookX = 3.2;
const double _lookY = 2.6;

/// The line's weight, a little heavier than the set's so it holds over a busy
/// camera picture (user, 2026-11-17).
const double kNarratorLine = 6.5;

/// How visible a shut eye's lid is: it shows only as the eye closes.
double narratorLidOpacity(double open) =>
    ((0.45 - open) / 0.35).clamp(0.0, 1.0).toDouble();

/// The head's outline in a pose, inset by [inset] for the features' clip.
Rect narratorHead(NarratorPose pose, [double inset = 0]) {
  final rx = _headR * (1 - _headTurnNarrow * pose.across.abs()) - inset;
  final ry = _headR * (1 - _headNodFlatten * pose.down.abs()) - inset;
  return Rect.fromCenter(
    center: Offset(50 + pose.across * _headTurnLean, 50 + pose.down * _headNodLean),
    width: rx * 2,
    height: ry * 2,
  );
}

class NarratorPainter extends CustomPainter {
  NarratorPainter({required this.pose, this.color = kNarratorColour})
      : super(repaint: pose);

  /// The pose to draw; the painter repaints itself as it changes.
  final ValueListenable<NarratorPose> pose;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = pose.value;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = kNarratorLine
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    canvas.drawOval(narratorHead(p), line);

    // The features, clipped to the inside of the head.
    canvas.save();
    canvas.clipPath(Path()..addOval(narratorHead(p, _faceInset)));
    canvas.translate(50, 50);
    canvas.scale(_featuresScale);
    canvas.translate(-50, -54);
    final features = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = kNarratorLine / _featuresScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Across and down, drawn together as a face turning away.
    final squeeze = 1 - 0.2 * p.across.abs();
    canvas.save();
    canvas.translate(50 + p.across * 11, p.down * 8);
    canvas.scale(squeeze, 1);
    canvas.translate(-50, 0);

    final lid = Paint()
      ..color = color.withValues(alpha: color.a * narratorLidOpacity(p.eyes))
      ..style = PaintingStyle.stroke
      ..strokeWidth = features.strokeWidth
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < _eyesAt.length; i++) {
      // Each eye looks ahead of the head. The one on the far side of a turn is
      // foreshortened and the near one grows; both shorten as the face tips
      // away.
      final ex = _eyesAt[i] + p.lookX * _lookX;
      final ey = _eyeY + p.lookY * _lookY;
      final depth = (1 - 0.24 * p.across * _eyeSide[i]) * (1 - 0.2 * p.down.abs());
      final h = 4.5 * p.eyes * depth;
      canvas.drawLine(Offset(ex, ey - h), Offset(ex, ey + h), features);
      if (lid.color.a > 0) {
        canvas.drawLine(Offset(ex - 4.5, ey), Offset(ex + 4.5, ey), lid);
      }
    }

    // The nose stands out from the face, so it moves further in a turn, and
    // rises a little with a smile. Its hook points the way the face turns and
    // it lengthens as the face tips down.
    final tip = 54 + 3 * p.down;
    final hook = -4.5 + 8 * math.max(0, p.across) - 1.5 * math.max(0, -p.across);
    final nose = Path()
      ..moveTo(50, 37)
      ..lineTo(50, tip)
      ..quadraticBezierTo(50, tip + 4, 50 + hook, tip + 4);
    canvas.drawPath(
        nose.shift(Offset(p.across * 5, p.down * 2 - p.smile * 1.5)), features);

    // The mouth, foreshortened on the side the face turns away to. It sits
    // lower on the face, so it moves a little less than the eyes in a nod.
    final end = 68 - 3 * p.smile;
    final reach = 13 + 4 * p.smile;
    final left = reach * (1 + 0.16 * p.across);
    final right = reach * (1 - 0.16 * p.across);
    final mouth = Path()
      ..moveTo(50 - left, end)
      ..quadraticBezierTo(
          50 + (left - right) / 2, 74 + 9 * p.smile, 50 + right, end);
    canvas.drawPath(mouth.shift(Offset(0, -p.down * 1.5)), features);

    canvas.restore();
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(NarratorPainter old) =>
      old.pose != pose || old.color != color;
}
