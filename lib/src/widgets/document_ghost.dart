import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/document_guide.dart';
import '../config/document_specimen.dart';

// ─── The sample document in the capture guide ─────────────────────────────────
//
// Shown for a few seconds when the camera opens, so the person sees what to hold
// up and which way round: a passport with PASSPORT written on it and its
// machine-readable lines inside the frame, a licence with its categories, the
// back of a card with what the back carries. The commonest passport mistake is
// cropping those lines off the bottom edge, which auto-capture then refuses.
//
// It sits exactly on documentGuideRect, the function the overlay and the
// post-shutter crop share, so the three cannot disagree about where the document
// goes. The drawing itself is config/document_specimen.dart. The timing mirrors
// the React Native SDK's DocumentGhost.
//
// Between the two sides of a card it is also the turn-over: mounted with
// [DocumentGhost.turnFrom], it shows the side just taken and turns over, in
// its place in the frame and at its size, to the side asked for next, then
// stays for that side's scan (user, 2026-11-18: a separate card turning over a
// dimmed camera, with the frame gone until it ended, did not read as one
// movement). The web SDK's DocumentGhost `turnFrom` and `holding`.

/// How long the side just taken is shown before it turns, and the turn.
const Duration kGhostTurnDelay = Duration(milliseconds: 600);
const Duration kGhostTurn = Duration(milliseconds: 800);

/// How long the camera waits for the card to be turned over: time to read the
/// line, turn the document over and bring it back into frame. Nothing to tap
/// (user, 2026-11-16): the person's hands are full.
const Duration kTurnOverHold = Duration(seconds: 5);

/// When it starts to leave if nothing is framed: long enough to read it, find
/// the document and bring it up to the camera.
const Duration kDocumentGhostDuration = Duration(seconds: 5);

/// A document in frame brings that forward, but never before it has been read.
const Duration kDocumentGhostMinimum = Duration(seconds: 2);

/// Slow on purpose, so it melts away over the camera rather than blinking off
/// while the person is still lining their document up with it.
const Duration kDocumentGhostFade = Duration(milliseconds: 1600);

/// See-through, so the sample guides the person without hiding the camera: they
/// have to see their own document arrive behind it.
const double kDocumentGhostOpacity = 0.6;

const Duration _fadeIn = Duration(milliseconds: 300);

String get _sans => defaultTargetPlatform == TargetPlatform.iOS
    ? 'Helvetica Neue'
    : 'sans-serif';
String get _mono =>
    defaultTargetPlatform == TargetPlatform.iOS ? 'Menlo' : 'monospace';

/// What to draw: the ID in hand, and the side the camera is asking for.
class DocumentSpecimenSubject {
  final String? idType;
  final String title;
  final String? country;

  /// The country's ISO-2 code: a few IDs are drawn as that country's own card.
  final String? countryCode;
  final SpecimenSide side;

  const DocumentSpecimenSubject({
    required this.idType,
    required this.title,
    required this.country,
    required this.side,
    this.countryCode,
  });
}

/// One face of the document, ready for [SvgPicture.string].
String specimenSvg(
  DocumentSpecimenSubject subject,
  SpecimenSide side,
  double aspect,
  Color accent,
) =>
    documentSpecimen(SpecimenInput(
      kind: specimenKind(subject.idType, subject.countryCode),
      title: subject.title,
      country: subject.country,
      side: side,
      aspect: aspect,
      accent:
          '#${(accent.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
      sans: _sans,
      mono: _mono,
    ));

class DocumentGhost extends StatefulWidget {
  /// Guide aspect (width / height): a card and a passport page differ.
  final double aspect;

  /// The free band an upright guide fills (config/document_guide.dart). Null
  /// for a landscape guide, which ignores it.
  final DocumentGuideBand? band;
  final Color accent;
  final DocumentSpecimenSubject subject;

  /// Ends it early, after [kDocumentGhostMinimum]: once a document is framed the
  /// guidance has done its job and would only sit on top of the thing being
  /// captured.
  final bool documentFound;

  const DocumentGhost({
    super.key,
    required this.aspect,
    this.band,
    required this.accent,
    required this.subject,
    this.documentFound = false,
    this.turnFrom,
    this.holding = false,
  });

  /// The side to turn over from, when it opens as the turn-over. Read once, at
  /// mount: it is the same sample before and after the turn.
  final SpecimenSide? turnFrom;

  /// Stays, and its timing does not start, while true: the turn-over is still
  /// on screen and nothing is being scanned yet.
  final bool holding;

  @override
  State<DocumentGhost> createState() => DocumentGhostState();
}

class DocumentGhostState extends State<DocumentGhost> {
  final Stopwatch _shown = Stopwatch()..start();
  Timer? _hold;
  Timer? _early;
  Timer? _turn;
  bool _arrived = false;
  bool _leaving = false;
  late final SpecimenSide? _from = widget.turnFrom;
  bool _turned = false;

  /// Whether the turn-over has turned to the side asked for (for tests).
  bool get turned => _turned;

  /// Whether it has begun to fade (for tests).
  bool get leaving => _leaving;

  @override
  void initState() {
    super.initState();
    _startTiming();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _arrived = true);
    });
    if (_from != null) {
      _turn = Timer(kGhostTurnDelay, () {
        if (mounted) setState(() => _turned = true);
      });
    }
    _watchDocument();
  }

  @override
  void didUpdateWidget(DocumentGhost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.holding != widget.holding) _startTiming();
    if (oldWidget.documentFound != widget.documentFound ||
        oldWidget.holding != widget.holding) {
      _watchDocument();
    }
  }

  /// Its time on screen counts from when the scan it guides starts.
  void _startTiming() {
    _hold?.cancel();
    if (widget.holding) return;
    _shown
      ..reset()
      ..start();
    _hold = Timer(kDocumentGhostDuration, _leave);
  }

  void _watchDocument() {
    _early?.cancel();
    if (!widget.documentFound || widget.holding) return;
    final wait = kDocumentGhostMinimum - _shown.elapsed;
    _early = Timer(wait.isNegative ? Duration.zero : wait, _leave);
  }

  void _leave() {
    if (mounted && !_leaving) setState(() => _leaving = true);
  }

  @override
  void dispose() {
    _hold?.cancel();
    _early?.cancel();
    _turn?.cancel();
    super.dispose();
  }

  Widget _face(SpecimenSide side) => SvgPicture.string(
        specimenSvg(widget.subject, side, widget.aspect, widget.accent),
        fit: BoxFit.fill,
      );

  /// The card turning over where it stands: the side just taken, then, edge
  /// on half way, the side asked for. Only the face towards the camera shows,
  /// as with a real card. With less motion it is the side asked for at once.
  Widget _turning() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      key: const ValueKey('document-ghost-turn'),
      tween: Tween(end: _turned || still ? 1 : 0),
      duration: still ? Duration.zero : kGhostTurn,
      curve: const Cubic(0.65, 0, 0.35, 1),
      builder: (context, turn, _) {
        final showingNext = turn >= 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0011)
            ..rotateY(math.pi * (showingNext ? turn - 1 : turn)),
          child: _face(showingNext ? widget.subject.side : _from!),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final guide = documentGuideRect(constraints.biggest, widget.aspect,
              band: widget.band);
          if (guide.isEmpty) return const SizedBox.shrink();
          return Stack(
            children: [
              Positioned.fromRect(
                rect: guide,
                child: AnimatedOpacity(
                  opacity: _arrived && !_leaving ? kDocumentGhostOpacity : 0,
                  duration: _leaving ? kDocumentGhostFade : _fadeIn,
                  curve: Curves.easeInOut,
                  child: _from == null ? _face(widget.subject.side) : _turning(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
