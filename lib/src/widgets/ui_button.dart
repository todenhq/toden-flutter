import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'ui_spinner.dart';

// ─── Variants ─────────────────────────────────────────────────────────────────

enum UiButtonVariant { primary, outline, ghost, destructive }

// ─── Button ───────────────────────────────────────────────────────────────────

class UiButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final UiButtonVariant variant;
  final bool isLoading;
  final bool fullWidth;
  final Widget? leadingIcon;

  /// Overrides the variant's label colour, for a quieter secondary action.
  final Color? labelColor;

  const UiButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = UiButtonVariant.primary,
    this.isLoading = false,
    this.fullWidth = true,
    this.leadingIcon,
    this.labelColor,
  });

  // ── Convenience constructors ───────────────────────────────────────────────

  const UiButton.outline({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.fullWidth = true,
    this.leadingIcon,
    this.labelColor,
  }) : variant = UiButtonVariant.outline;

  const UiButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.fullWidth = true,
    this.leadingIcon,
    this.labelColor,
  }) : variant = UiButtonVariant.ghost;

  const UiButton.destructive({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.fullWidth = true,
    this.leadingIcon,
    this.labelColor,
  }) : variant = UiButtonVariant.destructive;

  // ── Style helpers (context-aware) ──────────────────────────────────────────

  // Not `const`: UiRadius scales with appearance.borderRadius, so this is
  // resolved per build rather than frozen at compile time.
  static BorderRadius get _radius =>
      BorderRadius.all(Radius.circular(UiRadius.sm));

  Color _bg(UiColorScheme colors) => switch (variant) {
        UiButtonVariant.primary     => colors.primary,
        UiButtonVariant.destructive => UiColors.error,
        _                              => Colors.transparent,
      };

  Color _fg(UiColorScheme colors) => switch (variant) {
        UiButtonVariant.primary     => colors.onPrimary,
        UiButtonVariant.destructive => Colors.white,
        UiButtonVariant.outline     => colors.primary,
        UiButtonVariant.ghost       => colors.primary,
      };

  Color _disabledBg(UiColorScheme colors) => switch (variant) {
        UiButtonVariant.primary     => colors.primary.withValues(alpha: 0.5),
        UiButtonVariant.destructive => UiColors.error.withValues(alpha: 0.5),
        _                              => Colors.transparent,
      };

  BorderSide? _border(UiColorScheme colors) => switch (variant) {
        UiButtonVariant.outline =>
          BorderSide(color: colors.primary, width: 1.5),
        _ => null,
      };

  BorderSide? _disabledBorder(UiColorScheme colors) => switch (variant) {
        UiButtonVariant.outline =>
          BorderSide(color: colors.primary.withValues(alpha: 0.4), width: 1.5),
        _ => null,
      };

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text   = context.myazaText;

    final isDisabled = onPressed == null || isLoading;
    final fg = labelColor ?? _fg(colors);
    final effectiveFg = isDisabled ? fg.withValues(alpha: 0.5) : fg;
    final bg = _bg(colors);

    final shape = RoundedRectangleBorder(
      borderRadius: _radius,
      side: (isDisabled ? _disabledBorder(colors) : _border(colors)) ?? BorderSide.none,
    );

    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: isLoading
          ? SizedBox(
              key: const ValueKey('loading'),
              width: 20,
              height: 20,
              child: UiSpinner(
                strokeWidth: 2,
                color: effectiveFg,
              ),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leadingIcon != null) ...[
                  IconTheme(
                    data: IconThemeData(color: effectiveFg, size: 18),
                    child: leadingIcon!,
                  ),
                  const SizedBox(width: 8),
                ],
                // Shrink-to-fit, like the RN button's adjustsFontSizeToFit: a
                // long label ("Confirm details & continue") on a narrow screen
                // or under a wide brand font must scale, never clip — a button
                // label truncated by a branding choice reads as a bug.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: text.button.copyWith(color: effectiveFg),
                    ),
                  ),
                ),
              ],
            ),
    );

    final buttonStyle = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return _disabledBg(colors);
        if (states.contains(WidgetState.pressed)) {
          return bg == Colors.transparent
              ? colors.primary.withValues(alpha: 0.06)
              : bg.withValues(alpha: 0.88);
        }
        return bg;
      }),
      foregroundColor: WidgetStateProperty.all(effectiveFg),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return fg.withValues(alpha: 0.08);
        }
        return null;
      }),
      shape: WidgetStateProperty.all(shape),
      elevation: WidgetStateProperty.all(0),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: UiSpacing.md),
      ),
      minimumSize: WidgetStateProperty.all(
        Size(fullWidth ? double.infinity : 0, UiSizing.buttonHeight),
      ),
    );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: UiSizing.buttonHeight,
      child: ElevatedButton(
        onPressed: isDisabled ? null : onPressed,
        style: buttonStyle,
        child: child,
      ),
    );
  }
}
