import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../presence/presence_background_allow_steps.dart';
import 'icons/icons.dart';

// The pieces of the "allow all the time" screen. Mirrors the React Native SDK's
// screens/BackgroundAskParts.tsx; keep the two in lockstep.

class AskReason {
  const AskReason(this.icon, this.title, this.caption, {this.done = false});

  final UiIconData icon;
  final String title;
  final String caption;

  /// Already done: a check in place of the icon (the chip intro's photo page).
  final bool done;
}

/// An icon in two soft rings. The radar (the area around the address being
/// watched) by default; the chip intro (nfc_intro_view.dart) shows the NFC
/// phone.
class AskHero extends StatelessWidget {
  const AskHero({super.key, this.icon = UiIcons.radar});

  final UiIconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.18), shape: BoxShape.circle),
        alignment: Alignment.center,
        child: UiIcon(icon, size: 26, color: colors.primary),
      ),
    );
  }
}

/// The reasons as one grouped card, so they read as a single answer.
class AskReasons extends StatelessWidget {
  const AskReasons({super.key, required this.reasons});

  final List<AskReason> reasons;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return ClipRRect(
      borderRadius: BorderRadius.circular(UiRadius.lg),
      child: ColoredBox(
        color: colors.backgroundSecondary,
        child: Column(
          children: [
            for (var i = 0; i < reasons.length; i++) ...[
              if (i > 0) Divider(height: 0.5, thickness: 0.5, color: colors.border),
              Semantics(
                label: '${reasons[i].title}. ${reasons[i].caption}'
                    '${reasons[i].done ? ' Done.' : ''}',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.all(UiSpacing.md),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: (reasons[i].done ? UiColors.success : colors.primary)
                              .withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: reasons[i].done
                            ? const UiIcon(UiIcons.circleCheck, size: 20, color: UiColors.success)
                            : UiIcon(reasons[i].icon, size: 20, color: colors.primary),
                      ),
                      const SizedBox(width: UiSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reasons[i].title,
                              style: text.heading3.copyWith(color: colors.textDark),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              reasons[i].caption,
                              style: text.bodySmall.copyWith(color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the phone will ask next and the words to tap. The prompt is roughly a
/// one-time chance, so this is an instruction, not a footnote. It shares the
/// reasons' row shape and draws no options: anything resembling a control here
/// reads as a choice to make on this screen.
class AskNextStep extends StatelessWidget {
  const AskNextStep({super.key, required this.steps});

  final AllowSteps steps;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Semantics(
      label: '${steps.lead} ${steps.tap}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(UiSpacing.md),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(UiRadius.lg),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: UiIcon(UiIcons.smartphone, size: 20, color: colors.primary),
            ),
            const SizedBox(width: UiSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(steps.lead, style: text.bodySmall.copyWith(color: colors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(steps.tap, style: text.heading3.copyWith(color: colors.textDark)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
