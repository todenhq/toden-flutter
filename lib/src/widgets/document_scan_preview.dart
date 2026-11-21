import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../config/document_scan_timeline.dart';
import '../config/document_specimen.dart';
import '../config/theme.dart';
import 'document_ghost.dart';
import 'document_scan_preview_parts.dart';
import 'preview_tick.dart';

// ─── A picture of the document scan ───────────────────────────────────────────
//
// For the screen that comes before it: the document the person chose, within
// the camera's frame marks with no backdrop of its own (it sits in the
// screen's tinted box), drawn with the same sample the camera's guide shows
// (config/document_specimen.dart, through widgets/document_ghost.dart), so the
// two screens show the same thing. The loop is in
// config/document_scan_timeline.dart: read, tick, and for two sides, a turn.
//
// A picture: hidden from screen readers (the words beside it say what happens
// next) and, for a person who has asked for less motion, the front of the
// document in its frame, still. No cartoon person on documents. A port of the
// web SDK's DocumentScanPreview.

/// The specimen's own corner, as a share of its width (rx 40 on 1000).
const double _kCorner = 0.04;

/// Room between the document and the frame marks, either side and above and
/// below: enough for the marks to sit clear of it, no more.
const double _kRoomX = 20;
const double _kRoomY = 22;

/// The document's width bounds. Between them it takes all the room it has.
const double _kMinWidth = 180;
const double _kMaxWidth = 340;

/// Before there is a width to go on (an unbounded parent).
const double _kFirstWidth = 270;

class DocumentScanPreview extends StatefulWidget {
  const DocumentScanPreview({
    super.key,
    required this.subject,
    required this.aspect,
    required this.twoSided,
    required this.accent,
    this.width,
  });

  /// The document the person chose: its ID type, name and country.
  final DocumentSpecimenSubject subject;

  /// Its shape, width over height (config/document_guide.dart).
  final double aspect;

  /// Its details are on both sides, so it turns over to be read again.
  final bool twoSided;

  /// The workflow's colour, which the sample is printed in.
  final Color accent;

  /// The document's width. Left out, it takes the room it has.
  final double? width;

  @override
  State<DocumentScanPreview> createState() => _DocumentScanPreviewState();
}

class _DocumentScanPreviewState extends State<DocumentScanPreview>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final _frame = ValueNotifier<DocumentScanFrame>(_stillFrame);

  static const _stillFrame = DocumentScanFrame(
    opacity: 1,
    scale: 1,
    band: 0,
    bandOpacity: 0,
    passed: false,
    turn: 0,
    lift: 0,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      if (_ticker.isActive) _ticker.stop();
      _frame.value = _stillFrame;
    } else if (!_ticker.isActive) {
      _frame.value = documentScanFrameAt(0, twoSided: widget.twoSided);
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    _frame.value = documentScanFrameAt(elapsed.inMicroseconds / 1e6,
        twoSided: widget.twoSided);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.myazaColors.primary;
    return ExcludeSemantics(
      child: LayoutBuilder(builder: (context, constraints) {
        final room = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _kFirstWidth + _kRoomX * 2;
        final docWidth = (widget.width ??
                (room - _kRoomX * 2).clamp(_kMinWidth, _kMaxWidth).toDouble())
            .roundToDouble();
        final docHeight = (docWidth / widget.aspect).roundToDouble();
        final radius =
            BorderRadius.circular((docWidth * _kCorner).roundToDouble());
        final frameWidth = docWidth + _kRoomX * 2;
        final frameHeight = docHeight + _kRoomY * 2;
        final docRect = Rect.fromLTWH(_kRoomX, _kRoomY, docWidth, docHeight);
        // Both faces stay mounted, so turning over never waits on a load.
        final front = ScanPreviewFace(
          svg: specimenSvg(
              widget.subject, SpecimenSide.front, widget.aspect, widget.accent),
          radius: radius,
          frame: _frame,
          width: docWidth,
        );
        final back = widget.twoSided
            ? ScanPreviewFace(
                svg: specimenSvg(widget.subject, SpecimenSide.back,
                    widget.aspect, widget.accent),
                radius: radius,
                frame: _frame,
                width: docWidth,
              )
            : null;
        return Center(
          child: SizedBox(
            key: const ValueKey('document-scan-frame'),
            width: frameWidth,
            height: frameHeight,
            child: ValueListenableBuilder<DocumentScanFrame>(
              valueListenable: _frame,
              builder: (context, frame, _) {
                final angle = math.pi * frame.turn;
                final showingBack = back != null &&
                    (frame.turn % 2) > 0.5 &&
                    (frame.turn % 2) < 1.5;
                final lift = 1 + 0.04 * frame.lift;
                final turned = Matrix4.identity()
                  ..setEntry(3, 2, 1 / 900)
                  ..rotateY(showingBack ? angle - math.pi : angle)
                  ..multiply(Matrix4.diagonal3Values(lift, lift, 1));
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: frame.opacity,
                        child: Transform.scale(
                          scale: frame.scale,
                          child: Stack(children: [
                            Positioned.fromRect(
                              rect: docRect,
                              child: Transform(
                                alignment: Alignment.center,
                                transform: turned,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Offstage(
                                        offstage: showingBack, child: front),
                                    if (back != null)
                                      Offstage(
                                          offstage: !showingBack, child: back),
                                  ],
                                ),
                              ),
                            ),
                            Positioned.fromRect(
                              rect: docRect,
                              child: ScanPreviewBand(
                                  frame: frame,
                                  height: docHeight,
                                  radius: radius),
                            ),
                          ]),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter:
                              ScanFrameMarks(primary.withValues(alpha: 0.7)),
                        ),
                      ),
                    ),
                    Positioned.fromRect(
                      rect: docRect,
                      child: PreviewPassCover(on: frame.passed, radius: radius),
                    ),
                    Positioned.fill(child: PreviewTick(on: frame.passed)),
                  ],
                );
              },
            ),
          ),
        );
      }),
    );
  }
}
