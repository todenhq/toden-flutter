import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/document_scan_timeline.dart';
import '../config/theme.dart';

// ─── The parts of the document scan's picture ─────────────────────────────────
//
// The document's face, the band of light that reads it and the camera's frame
// marks, for widgets/document_scan_preview.dart.

/// The band of light: a soft trail above a bright edge.
const double _kTrail = 32;
const double _kEdge = 2;

/// One face of the document: the sample on white, as a document is, and the
/// light it catches as it turns.
class ScanPreviewFace extends StatelessWidget {
  const ScanPreviewFace({
    super.key,
    required this.svg,
    required this.radius,
    required this.frame,
    required this.width,
  });

  final String svg;
  final BorderRadius radius;
  final ValueNotifier<DocumentScanFrame> frame;
  final double width;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            offset: Offset(0, 10),
            blurRadius: 24,
            spreadRadius: -8,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SvgPicture.string(svg, fit: BoxFit.fill),
            ValueListenableBuilder<DocumentScanFrame>(
              valueListenable: frame,
              builder: (context, f, _) {
                if (f.lift <= 0) return const SizedBox.shrink();
                // The web's glint: a bright stripe in a background two and a
                // half times as wide, slid from 130% to -30% across.
                final turning = f.turn % 1;
                final at = (130 - 160 * turning) / 100;
                return Stack(clipBehavior: Clip.none, children: [
                  Positioned(
                    left: -1.5 * width * at,
                    top: 0,
                    bottom: 0,
                    width: width * 2.5,
                    child: Opacity(
                      opacity: (0.9 * f.lift).clamp(0.0, 1.0),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(-1, -0.27),
                            end: Alignment(1, 0.27),
                            stops: [0.38, 0.5, 0.62],
                            colors: [
                              Color(0x00FFFFFF),
                              Color(0x99FFFFFF),
                              Color(0x00FFFFFF),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The band of light that reads it, inside its edges.
class ScanPreviewBand extends StatelessWidget {
  const ScanPreviewBand(
      {super.key,
      required this.frame,
      required this.height,
      required this.radius});

  final DocumentScanFrame frame;
  final double height;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    if (frame.bandOpacity <= 0) return const SizedBox.shrink();
    const success = UiColors.success;
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned(
            left: 0,
            right: 0,
            top: frame.band * height - _kTrail - _kEdge,
            height: _kTrail + _kEdge,
            child: Opacity(
              opacity: frame.bandOpacity.clamp(0.0, 1.0),
              child: Column(children: [
                Container(
                  height: _kTrail,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        success.withValues(alpha: 0),
                        success.withValues(alpha: 0.28),
                      ],
                    ),
                  ),
                ),
                Container(
                  height: _kEdge,
                  decoration: const BoxDecoration(
                    color: success,
                    boxShadow: [
                      BoxShadow(
                          color: success, blurRadius: 10, spreadRadius: 2),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The camera's frame marks, as the viewfinder draws them: four corners, 20
/// across, 6 in from the edge, on a 9 radius.
class ScanFrameMarks extends CustomPainter {
  const ScanFrameMarks(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 6.0;
    const side = 20.0;
    const stroke = 2.5;
    const r = 9 - stroke / 2;
    const e = inset + stroke / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final corner = Path()
      ..moveTo(e, inset + side)
      ..lineTo(e, e + r)
      ..arcToPoint(const Offset(e + r, e), radius: const Radius.circular(r))
      ..lineTo(inset + side, e);
    for (var quarter = 0; quarter < 4; quarter++) {
      canvas.save();
      // Each corner is the first, turned to its own corner of the frame.
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(quarter * math.pi / 2);
      final w = quarter.isEven ? size.width : size.height;
      final h = quarter.isEven ? size.height : size.width;
      canvas.translate(-w / 2, -h / 2);
      canvas.drawPath(corner, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ScanFrameMarks old) => old.color != color;
}
