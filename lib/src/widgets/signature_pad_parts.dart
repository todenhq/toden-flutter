import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'icons/icons.dart';

// ─── The small controls around the signature pad ─────────────────────────────
//
// Each is a 1:1 copy of the web SDK's SignaturePad markup, sizes included, so
// the pad looks the same on a phone as in a browser. Change one here and
// change the web and React Native ones with it.

const Color _kPillInk = Color(0xFF262626); // neutral-800
const Color _kPillBorder = Color(0xFFD4D4D4); // neutral-300

/// The Expand / Collapse pill in the corner of the pad.
///
/// Small to look at (28 high, 11pt); the 8pt of padding around it is tap area,
/// the web's `before:-inset-2`. Always dark on the white pad, in both themes.
class SignatureExpandPill extends StatelessWidget {
  const SignatureExpandPill({
    super.key,
    required this.expanded,
    required this.onTap,
  });

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SignaturePill(
        icon: expanded ? UiIcons.minimize2 : UiIcons.maximize2,
        label: expanded ? 'Collapse' : 'Expand',
        semanticsLabel: expanded
            ? 'Collapse the signature box'
            : 'Expand the signature box',
        onTap: onTap,
      );
}

/// A small white pill in a corner of the pad (Expand, Clear): always dark on
/// the white pad, whatever the flow's theme. Small to look at; the padding
/// round it keeps the tap area generous.
class SignaturePill extends StatelessWidget {
  const SignaturePill({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.onTap,
  });

  final UiIconData icon;
  final String label;
  final String semanticsLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticsLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: ShapeDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                shape:
                    const StadiumBorder(side: BorderSide(color: _kPillBorder)),
                shadows: const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    offset: Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UiIcon(icon, size: 12, color: _kPillInk),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: text.bodySmall.copyWith(
                      fontSize: 11,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: _kPillInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet text action in the primary colour: Clear, and "upload instead".
///
/// The web's `min-h-11 px-3 text-xs font-medium text-primary`, half opacity
/// when it cannot be used. Material's own disabled grey nearly vanished on a
/// dark card.
class SignatureTextAction extends StatelessWidget {
  const SignatureTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.fullWidth = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool fullWidth;

  /// Drawn before the label, in the same colour.
  final UiIconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: Size(fullWidth ? double.infinity : 0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: colors.primary,
          disabledForegroundColor: colors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: text.bodySmall.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: icon == null
            ? Text(label, textAlign: TextAlign.center)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UiIcon(icon, size: 14, color: colors.primary),
                  const SizedBox(width: 4),
                  Text(label),
                ],
              ),
      ),
    );
  }
}
