import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/icons/icons.dart';

/// The glyph's ink on the light warning tint: amber-800, 6.3:1 on warningBg.
/// The warning yellow itself is 1.5:1 there, too faint to see.
const Color _amber800 = Color(0xFF92400E);

/// The failed check's second line: "1 attempt left." or "2 attempts left."
/// (config/liveness_attempts.dart), as a small warning under the red message.
///
/// A slim pill on the warning tint with a warning glyph, the words in the body
/// colour rather than red, so it reads as a heads-up and not a second error;
/// the reason stays the first thing read and Try Again the next. The same
/// notice as the web and React Native SDKs. The glyph is decorative: the words
/// are what a screen reader reads.
class LivenessAttemptsLeft extends StatelessWidget {
  const LivenessAttemptsLeft({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final isDark = colors.background.computeLuminance() < 0.5;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: colors.warningBg,
          borderRadius: BorderRadius.circular(UiRadius.full),
          border: Border.all(color: UiColors.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            UiIcon(
              UiIcons.triangleAlert,
              size: 14,
              color: isDark ? UiColors.warning : _amber800,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: context.myazaText.bodySmall.copyWith(
                  color: colors.textDark,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
