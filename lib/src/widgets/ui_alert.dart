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

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(UiRadius.sm),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Colored left accent bar ──────────────────────────────────────
            Container(width: 4, color: accent),

            // ── Content ──────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: UiSpacing.md,
                  vertical: UiSpacing.sm + 2,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UiIcon(variant.icon, size: 18, color: accent),
                    const SizedBox(width: UiSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: text.label.copyWith(color: accent),
                          ),
                          if (message != null && message!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              message!,
                              style: text.bodySmall.copyWith(
                                color: accent.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (onDismiss != null) ...[
                      const SizedBox(width: UiSpacing.sm),
                      GestureDetector(
                        onTap: onDismiss,
                        child: UiIcon(UiIcons.x, size: 16, color: accent),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
