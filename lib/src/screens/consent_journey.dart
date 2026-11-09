import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/icons/icons.dart';
import '../widgets/staggered_reveal.dart';
import 'consent_process_steps.dart';

// ─── What the flow will do ────────────────────────────────────────────────────
//
// An inset grouped list: a quiet heading over one card of rows, each a small
// icon tile and a line of text, hairlines between, no numbers or counts. The
// rows rise in one after another (reduced motion: at once). The card carries
// a soft shadow on a dark sheet only; on a light one the tint is enough.
// Mirrors the web SDK's steps/ConsentJourney.

class ConsentJourney extends StatelessWidget {
  final String heading;
  final List<ConsentProcessStep> steps;

  const ConsentJourney({super.key, required this.heading, required this.steps});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final dark = colors.background.computeLuminance() < 0.5;

    final rows = <Widget>[
      for (var i = 0; i < steps.length; i++)
        DecoratedBox(
          decoration: BoxDecoration(
            border: i == 0
                ? null
                : Border(
                    top: BorderSide(color: colors.border.withValues(alpha: 0.6), width: 1),
                  ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: UiIcon(steps[i].icon, size: 16, color: colors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    steps[i].label,
                    style: text.label.copyWith(
                      height: 1.375,
                      color: colors.textDark.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ];

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: colors.backgroundSecondary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(UiRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Semantics(
                header: true,
                child: Text(
                  heading,
                  style: text.bodySmall.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(12),
                boxShadow: dark
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: StaggeredReveal(interval: const Duration(milliseconds: 45), children: rows),
            ),
          ],
        ),
      ),
    );
  }
}
