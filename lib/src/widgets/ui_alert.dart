import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'icons/icons.dart';

// ─── Variant ──────────────────────────────────────────────────────────────────

enum UiAlertVariant { error, success, warning, info }

extension _UiAlertVariantStyle on UiAlertVariant {
  Color get accentColor => switch (this) {
        UiAlertVariant.error   => UiColors.error,
        UiAlertVariant.success => UiColors.success,
        UiAlertVariant.warning => UiColors.warning,
        UiAlertVariant.info    => UiColors.info,
      };

  Color bgColor(UiColorScheme colors) => switch (this) {
        UiAlertVariant.error   => colors.errorBg,
        UiAlertVariant.success => colors.successBg,
        UiAlertVariant.warning => colors.warningBg,
        UiAlertVariant.info    => colors.infoBg,
      };

  UiIconData get icon => switch (this) {
        UiAlertVariant.error   => UiIcons.circleAlert,
        UiAlertVariant.success => UiIcons.circleCheck,
        UiAlertVariant.warning => UiIcons.triangleAlert,
        UiAlertVariant.info    => UiIcons.info,
      };
}

// ─── Alert ────────────────────────────────────────────────────────────────────

class UiAlert extends StatelessWidget {
  final String title;
  final String? message;
  final UiAlertVariant variant;
  final VoidCallback? onDismiss;

  const UiAlert({
    super.key,
    required this.title,
    this.message,
    this.variant = UiAlertVariant.info,
    this.onDismiss,
  });

  const UiAlert.error({
    super.key,
    required this.title,
    this.message,
    this.onDismiss,
  }) : variant = UiAlertVariant.error;

  const UiAlert.success({
    super.key,
    required this.title,
    this.message,
    this.onDismiss,
  }) : variant = UiAlertVariant.success;

  const UiAlert.warning({
    super.key,
    required this.title,
    this.message,
    this.onDismiss,
  }) : variant = UiAlertVariant.warning;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text   = context.myazaText;
    final accent = variant.accentColor;
    final bg     = variant.bgColor(colors);

    // Drawn as the dashboard's publish advisories are: a tinted card with a
    // faint edge in the variant's colour, a round icon tile carrying the
    // meaning, the title in the foreground colour and the message one step
    // quieter. The colour sits in the icon and the edge, so the words stay
    // readable on every surface.
    final hasMessage = message != null && message!.isNotEmpty;
    return Semantics(
      liveRegion: variant == UiAlertVariant.error || variant == UiAlertVariant.warning,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(UiRadius.sm),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: UiIcon(variant.icon, size: 14, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: text.label.copyWith(
                        color: colors.textDark,
                        fontWeight: FontWeight.w600,
                        height: 20 / 14,
                      ),
                    ),
                    if (hasMessage) ...[
                      const SizedBox(height: UiSpacing.xs),
                      Text(
                        message!,
                        style: text.bodySmall.copyWith(
                          fontSize: 13,
                          height: 20 / 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (onDismiss != null) ...[
              const SizedBox(width: UiSpacing.sm),
              Semantics(
                button: true,
                label: 'Dismiss',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDismiss,
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Center(child: UiIcon(UiIcons.x, size: 16, color: colors.textSecondary)),
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
