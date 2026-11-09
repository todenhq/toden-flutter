import 'package:flutter/material.dart';

import '../config/brand.dart' show brandMarkColor;

// ─── Toden's mark, the split-shield T ────────────────────────────────────────
//
// Drawn, not shipped as an asset: the bar and the shield's left half in the
// ink, its right half in Toden's purple. The web SDK's TodenMark
// (components/TodenWordmark.tsx, viewBox 12 10 76 82), path for path.

/// Toden's purple, the shield's right half.
const Color kTodenAccent = Color(0xFF5645F5);

/// A step lighter, where the ink is the light tone (a dark background).
const Color kTodenAccentOnDark = Color(0xFF8F83FA);

/// The colours the footer draws the mark in on [background]: the ink chosen
/// for contrast against it (brand.dart), and the purple a step lighter when
/// that ink is the light tone. The web SDK's lib/use-toden-mark-colours.ts.
({Color ink, Color accent}) todenMarkColours(Color background) {
  final ink = brandMarkColor(background);
  return (ink: ink, accent: ink.computeLuminance() > 0.5 ? kTodenAccentOnDark : kTodenAccent);
}

class TodenMark extends StatelessWidget {
  final double size;
  final Color ink;
  final Color accent;

  const TodenMark({
    super.key,
    required this.size,
    required this.ink,
    this.accent = kTodenAccent,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _TodenMarkPainter(ink, accent)),
      );
}

class _TodenMarkPainter extends CustomPainter {
  _TodenMarkPainter(this.ink, this.accent);
  final Color ink;
  final Color accent;

  // The viewBox: 76 wide, 82 tall, from (12, 10).
  static const double _vbX = 12;
  static const double _vbY = 10;
  static const double _vbW = 76;
  static const double _vbH = 82;

  @override
  void paint(Canvas canvas, Size size) {
    // Contain, centred, as an SVG's default preserveAspectRatio does.
    final scale = (size.width / _vbW) < (size.height / _vbH) ? size.width / _vbW : size.height / _vbH;
    canvas.save();
    canvas.translate(
      (size.width - _vbW * scale) / 2 - _vbX * scale,
      (size.height - _vbH * scale) / 2 - _vbY * scale,
    );
    canvas.scale(scale);

    final inkPaint = Paint()..color = ink;
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(15, 12, 70, 13), const Radius.circular(6.5)),
      inkPaint,
    );
    // M35 35H47.5V90C39 83 30 74 30 58V40A5 5 0 0 1 35 35Z
    final left = Path()
      ..moveTo(35, 35)
      ..lineTo(47.5, 35)
      ..lineTo(47.5, 90)
      ..cubicTo(39, 83, 30, 74, 30, 58)
      ..lineTo(30, 40)
      ..arcToPoint(const Offset(35, 35), radius: const Radius.circular(5))
      ..close();
    canvas.drawPath(left, inkPaint);
    // M52.5 35H65A5 5 0 0 1 70 40V58C70 74 61 83 52.5 90Z
    final right = Path()
      ..moveTo(52.5, 35)
      ..lineTo(65, 35)
      ..arcToPoint(const Offset(70, 40), radius: const Radius.circular(5))
      ..lineTo(70, 58)
      ..cubicTo(70, 74, 61, 83, 52.5, 90)
      ..close();
    canvas.drawPath(right, Paint()..color = accent);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TodenMarkPainter old) => old.ink != ink || old.accent != accent;
}
