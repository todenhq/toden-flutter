import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'country_flag.dart';

// ─── One country in the dial-code sheet ──────────────────────────────────────
//
// Extracted from dial_code_picker.dart (200-line rule) and shared by the
// pinned geo row and the alphabetical ones, so the two cannot drift apart:
// they are the same control in two positions, and the pinned one only differs
// by carrying a tag and a hairline beneath it. Mirrors the RN DialCodeRow.
//
// Drawn as the web sheet draws its options (CountrySummarySelect): a 44px
// rounded row, a 20px flag, the current answer filled rather than ticked.

class DialCodeRow extends StatelessWidget {
  final String iso;
  final String name;

  /// The dialling code without its '+'; empty hides the trailing column.
  final String dial;
  final bool isSelected;

  /// Tags a pinned row ("Selected", "Your location").
  final String? badge;
  final VoidCallback onTap;

  const DialCodeRow({
    super.key,
    required this.iso,
    required this.name,
    required this.dial,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final radius = BorderRadius.circular(UiRadius.xs);
    return Material(
      color: isSelected ? colors.backgroundSecondary : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        highlightColor: colors.backgroundSecondary,
        splashColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                UiCountryFlag(country: iso, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.body.copyWith(
                            color: colors.textDark,
                            fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 10),
                        _RowTag(label: badge!, onFill: isSelected),
                      ],
                    ],
                  ),
                ),
                if (dial.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Text('+$dial',
                      style: text.bodyMedium.copyWith(color: colors.textSecondary)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The web's small uppercase tag. Its fill is the muted surface on a plain row
/// and the sheet's own colour on the filled one, so it stands off either.
class _RowTag extends StatelessWidget {
  final String label;
  final bool onFill;
  const _RowTag({required this.label, required this.onFill});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: onFill ? colors.background : colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(UiRadius.full),
      ),
      child: Text(
        label.toUpperCase(),
        style: text.bodySmall.copyWith(
          fontSize: 10,
          height: 1.4,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.25,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

/// A region label between grouped rows — the web sheet's header (11px,
/// uppercase, tracked wide), so the pickers read as one control.
class DialCodeRegionHeader extends StatelessWidget {
  final String region;
  const DialCodeRegionHeader({super.key, required this.region});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Semantics(
        header: true,
        child: Text(
          region.toUpperCase(),
          style: text.bodySmall.copyWith(
            fontSize: 11,
            height: 16 / 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// The hairline under the pinned rows, separating them from the regions.
class DialCodeDivider extends StatelessWidget {
  const DialCodeDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: context.myazaColors.border,
      ),
    );
  }
}
