import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/theme.dart';
import 'ui_button.dart';
import 'pulse_ring.dart';
import 'ready_primer_content.dart';
import '../i18n/text_scope.dart';
import '../i18n/translate.dart' show defaultText;
import 'icons/icons.dart';

/// "Here's what happens next" screen, shown once before a capture step opens
/// the camera.
///
/// It exists because the camera used to appear unannounced: a user who doesn't
/// know their ID or their face is about to be photographed fumbles the first
/// attempt, and a retake costs more than a sentence of warning.
///
/// A port of the web SDK's ReadyPrimer — same minimal single-column shape (one
/// hero, at most three expectations, one primary action) and the same copy, so
/// the flow reads identically whichever SDK the org embeds.
///
/// It sits BEFORE [CameraPermissionPrimingView]: first what we're about to do,
/// then the OS prompt. Two asks in a row, each with a reason, never a surprise.
class ReadyPrimer extends StatelessWidget {
  const ReadyPrimer({
    super.key,
    required this.content,
    required this.onReady,
    this.buttonLabel,
  });

  final ReadyContent content;
  final VoidCallback onReady;

  /// Null = the `primer.readyButton` text.
  final String? buttonLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final t = context.verificationText;

    final vars = content.textVars;
    // A workflow's own words always show. The stock ones are left out where
    // the content says the screen already says them (ownTitleOnly,
    // ownBodyOnly): the picture, or the step's heading above.
    String own(String key, bool ownOnly) {
      final written = t(key, vars: vars);
      return ownOnly && written == defaultText(key, vars: vars) ? '' : written;
    }

    final heading = own(content.titleKey, content.ownTitleOnly);
    final description = own(content.bodyKey, content.ownBodyOnly);
    final hero = content.hero;
    // The liveness picture stands on the page by itself: its own window is
    // its frame, and a tinted box round it would be a frame round a frame. A
    // glyph keeps the box, which gives it something to sit on, and so does
    // the document's picture (heroBoxed; user, 2026-11-16).
    final boxed = hero == null || content.heroBoxed;

    // TOP-ALIGNED, like the web. The sheet body guarantees the child at least
    // the viewport height, so a Center here parked the whole primer in the
    // middle of the sheet and left a dead band under the step indicator.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: UiSpacing.md),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero. Whatever moves here (the ring, or the step's own picture)
            // is the ONLY looping element on the screen; more than one
            // competing animation reads as noise.
            Container(
              padding: !boxed
                  ? const EdgeInsets.fromLTRB(8, 8, 8, 4) // px-2 pt-2 pb-1
                  : hero != null
                      ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
                      : const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
              decoration: boxed
                  ? BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.05),
                      border: Border.all(
                          color: colors.primary.withValues(alpha: 0.15)),
                      borderRadius: BorderRadius.circular(UiRadius.lg),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  hero ??
                      // Ring behind the glyph — the web's `animate-pulse-ring`.
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const PulseRing(),
                            Container(
                              width: 64, // h-16 w-16
                              height: 64,
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: UiIcon(content.icon,
                                  size: 28, color: colors.primary), // h-7 w-7
                            ),
                          ],
                        ),
                      ),
                  if (heading.isNotEmpty || description.isNotEmpty)
                    const SizedBox(height: UiSpacing.md), // gap-4
                  if (heading.isNotEmpty)
                    Text(heading,
                        style: text.heading3, textAlign: TextAlign.center),
                  if (heading.isNotEmpty && description.isNotEmpty)
                    const SizedBox(height: 6), // space-y-1.5
                  if (description.isNotEmpty)
                    Text(
                      description,
                      style:
                          text.bodySmall.copyWith(color: colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20), // space-y-5

            // Expectations — same row idiom as the consent screen's
            // "during this process we will" list.
            for (final item in content.checklist) ...[
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(UiRadius.xs),
                    ),
                    child: UiIcon(item.icon, size: 18, color: colors.primary),
                  ),
                  const SizedBox(width: 12), // gap-3
                  Expanded(
                    child: Text(t(item.labelKey, vars: vars),
                        style: text.bodyMedium),
                  ),
                ],
              ),
              const SizedBox(height: 12), // space-y-3
            ],

            const SizedBox(height: 8),
            // One primary action. UiButton already clears the 44pt minimum.
            UiButton(
                label: buttonLabel ?? t('primer.readyButton'),
                onPressed: onReady),
          ],
        ),
    ).animate().fadeIn(duration: 250.ms);
  }
}
