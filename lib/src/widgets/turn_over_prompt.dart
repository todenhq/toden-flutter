import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/document_guide.dart';
import '../config/document_specimen.dart';
import 'document_ghost.dart';
import 'ui_button.dart';

/// How long the camera waits: time to read this, turn the document over and
/// bring it back into frame.
const Duration kTurnOverHold = Duration(seconds: 5);
const Duration _flipDelay = Duration(milliseconds: 700);
const Duration _flip = Duration(milliseconds: 800);

/// "Now turn it over."
///
/// With the review screen off, nothing stands between the front's shutter and
/// the back's camera: the person is still holding the front up, and auto-capture
/// shoots it a second time. So the camera waits behind this, showing the
/// document turning from its front to its back exactly where it has to be held.
/// It ends by itself, so nobody has to reach for the screen with their hands
/// full, and the button lets anyone quicker move on.
class TurnOverPrompt extends StatelessWidget {
  final double aspect;

  /// The free band an upright guide fills (config/document_guide.dart). Null
  /// for a landscape guide, which ignores it.
  final DocumentGuideBand? band;
  final Color accent;
  final DocumentSpecimenSubject subject;
  final VoidCallback onDone;

  const TurnOverPrompt({
    super.key,
    required this.aspect,
    this.band,
    required this.accent,
    required this.subject,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final description = 'Hold the back of your ${subject.title} inside the frame.';
    final total = _flipDelay + _flip;
    return Semantics(
      liveRegion: true,
      label: 'Now turn it over. $description',
      child: ColoredBox(
        color: const Color(0xB8040218),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final guide = documentGuideRect(constraints.biggest, aspect, band: band);
            return Stack(
              children: [
                Positioned(
                  left: 24,
                  right: 24,
                  top: math.max(16, guide.top - 56),
                  child: const Text(
                    'Now turn it over',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: guide,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: still ? 1 : 0, end: 1),
                    duration: total,
                    curve: Interval(
                      _flipDelay.inMilliseconds / total.inMilliseconds,
                      1,
                      curve: Curves.easeInOutCubic,
                    ),
                    builder: (context, turn, _) {
                      // Each face is shown for its half of the turn, swapped
                      // when the card is edge-on.
                      final showingBack = turn >= 0.5;
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0011)
                          ..rotateY(math.pi * (showingBack ? turn - 1 : turn)),
                        child: SvgPicture.string(
                          specimenSvg(
                            subject,
                            showingBack ? SpecimenSide.back : SpecimenSide.front,
                            aspect,
                            accent,
                          ),
                          fit: BoxFit.fill,
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  top: guide.bottom + 24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 24),
                      UiButton(label: "I've turned it over", onPressed: onDone),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
