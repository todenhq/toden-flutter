import 'package:flutter/material.dart';

import '../config/business_document_groups.dart';
import '../config/theme.dart';
import '../i18n/text_scope.dart';
import '../widgets/icons/icons.dart';

// ─── Small pieces of the business document group carousel ────────────────────
//
// The number circle (a tick once a group holds its document), the pill
// (Required / Optional / Next) and the short list of accepted documents.
// MIRRORS the matching spans in the web SDK's steps/business-documents/
// GroupPanel and GroupRow.

/// A group's number in a circle: tinted on the open card, plain on a tucked
/// card ([onMuted]). A tucked card whose group holds its document keeps its
/// number, with a small success tick on the bottom-right corner, so the count
/// stays visible.
class BusinessDocumentNumber extends StatelessWidget {
  const BusinessDocumentNumber({
    super.key,
    required this.number,
    this.open = false,
    this.done = false,
    this.onMuted = false,
  });

  final int number;
  final bool open;
  final bool done;
  final bool onMuted;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final circle = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: open
            ? colors.primary.withValues(alpha: 0.1)
            : onMuted
                ? colors.background
                : colors.backgroundSecondary,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: text.bodySmall.copyWith(
          color: open ? colors.primary : colors.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: open ? 14 : 12,
        ),
      ),
    );
    return ExcludeSemantics(
      child: !done
          ? circle
          : Stack(
              clipBehavior: Clip.none,
              children: [
                circle,
                Positioned(
                  right: -6,
                  bottom: -4,
                  child: Container(
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: UiColors.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.background, width: 2),
                    ),
                    child: const UiIcon(UiIcons.check,
                        size: 9, color: Colors.white),
                  ),
                ),
              ],
            ),
    );
  }
}

/// A small rounded label: tinted for a required group, muted otherwise.
class BusinessDocumentPill extends StatelessWidget {
  const BusinessDocumentPill({
    super.key,
    required this.label,
    this.tinted = false,
    this.small = false,
    this.onMuted = false,
  });

  final String label;
  final bool tinted;
  final bool small;

  /// On a tucked card's muted fill: drawn on the page colour instead.
  final bool onMuted;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: UiSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: tinted
            ? colors.primary.withValues(alpha: 0.1)
            : onMuted
                ? colors.background
                : colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(UiRadius.full),
      ),
      child: Text(
        label,
        style: text.bodySmall.copyWith(
          color: tinted ? colors.primary : colors.textSecondary,
          fontWeight: FontWeight.w500,
          fontSize: small ? 11 : null,
        ),
      ),
    );
  }
}

/// The documents a group accepts, one per line, each with how recent it must
/// be on its own line beneath.
class BusinessDocumentAcceptedList extends StatelessWidget {
  const BusinessDocumentAcceptedList({super.key, required this.types});

  final List<BusinessDocumentGroupType> types;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < types.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : UiSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: UiIcon(UiIcons.fileText,
                      size: 14, color: colors.textSecondary),
                ),
                const SizedBox(width: UiSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(types[i].label,
                          style:
                              text.bodyMedium.copyWith(color: colors.textDark)),
                      if (types[i].maxAgeMonths case final months?)
                        Text(
                          context.verificationText(
                              'business.documents.validity',
                              vars: {'months': months}),
                          style: text.bodySmall
                              .copyWith(color: colors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
