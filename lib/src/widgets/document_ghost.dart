import 'dart:async';

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
  final SpecimenSide side;

  const DocumentSpecimenSubject({
    required this.idType,
    required this.title,
    required this.country,
    required this.side,
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
      kind: specimenKind(subject.idType),
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
  });

  @override
  State<DocumentGhost> createState() => _DocumentGhostState();
}

class _DocumentGhostState extends State<DocumentGhost> {
  final Stopwatch _shown = Stopwatch()..start();
  Timer? _hold;
  Timer? _early;
  bool _arrived = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _hold = Timer(kDocumentGhostDuration, _leave);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _arrived = true);
    });
    _watchDocument();
  }

  @override
  void didUpdateWidget(DocumentGhost old) {
    super.didUpdateWidget(old);
    if (old.documentFound != widget.documentFound) _watchDocument();
  }

  void _watchDocument() {
    _early?.cancel();
    if (!widget.documentFound) return;
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
    super.dispose();
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
                  child: SvgPicture.string(
                    specimenSvg(widget.subject, widget.subject.side,
                        widget.aspect, widget.accent),
                    fit: BoxFit.fill,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
