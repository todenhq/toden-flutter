import 'package:flutter/material.dart';

import '../config/business_document_groups.dart';
import '../config/theme.dart';
import '../i18n/text_scope.dart';
import '../widgets/icons/icons.dart';
import '../utils/display_file_name.dart';
import 'business_document_parts.dart';

// ─── A neighbouring group's card, tucked behind the open one ─────────────────
//
// Like the next card on a vertical carousel: inset and muted, with only one
// edge showing. The next group sits above (its top showing; not a control, as a
// group still ahead cannot be opened yet: it lists what it will ask for and
// reads as one note) and the previous group below (its bottom showing; tapping
// it reopens the group to change it, and it shows the file it holds or that it
// was skipped). The open card overlaps the hidden edge by
// [kBusinessDocumentTuck], so each card keeps extra padding on that side.
//
// MIRRORS the web SDK's steps/business-documents/GroupRow. Keep the two in
// step.

/// How far the open card overlaps each tucked card.
const double kBusinessDocumentTuck = 12;

/// A tucked card's muted fill, made opaque so nothing behind shows through.
Color businessDocumentTuckedFill(BuildContext context, double alpha) {
  final colors = context.myazaColors;
  return Color.alphaBlend(
      colors.backgroundSecondary.withValues(alpha: alpha), colors.background);
}

/// A business document group as a tucked card (see [TuckedDocumentRow]).
class BusinessDocumentGroupRow extends StatelessWidget {
  const BusinessDocumentGroupRow({
    super.key,
    required this.group,
    required this.number,
    this.fileName,
    this.onOpen,
  });

  final BusinessDocumentGroup group;
  final int number;

  /// The file the group holds ('' when restored without a name); null when it
  /// has none.
  final String? fileName;

  /// Present for the previous group (below the open card) only.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.verificationText;
    // A file named by a random id, or restored without a name, reads Uploaded;
    // only a group with no file at all reads Skipped.
    final detail = onOpen == null
        ? group.types.map((x) => x.label).join(', ')
        : fileName == null
            ? t('business.documents.skipped')
            : displayFileName(fileName) ?? t('business.documents.uploaded');
    return TuckedDocumentRow(
      title: group.title,
      number: number,
      done: fileName != null,
      detail: detail,
      onOpen: onOpen,
    );
  }
}

/// The tucked card itself, shared by the business documents' groups and the
/// supporting documents.
class TuckedDocumentRow extends StatelessWidget {
  const TuckedDocumentRow({
    super.key,
    required this.title,
    required this.number,
    required this.done,
    required this.detail,
    this.onOpen,
  });

  final String title;
  final int number;

  /// It holds something: shows the tick on its number.
  final bool done;

  /// The line under the title: what it asks for, or what it holds.
  final String detail;

  /// Present for the previous card (below the open one) only.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final t = context.verificationText;
    final previous = onOpen != null;
    final next = t('business.documents.status.next');
    final change = t('business.documents.change');
    final radius = Radius.circular(UiRadius.sm);
    // The hidden edge is under the open card, so its border never shows.
    final shape = RoundedRectangleBorder(
      side: BorderSide(color: colors.border.withValues(alpha: 0.7)),
      borderRadius: previous
          ? BorderRadius.vertical(bottom: radius)
          : BorderRadius.vertical(top: radius),
    );

    final row = Padding(
      padding:
          EdgeInsets.fromLTRB(14, previous ? 20 : 10, 14, previous ? 10 : 20),
      child: Row(
        children: [
          BusinessDocumentNumber(number: number, done: done, onMuted: true),
          const SizedBox(width: UiSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.label.copyWith(
                              color: colors.textDark.withValues(alpha: 0.8))),
                    ),
                    if (!previous) ...[
                      const SizedBox(width: UiSpacing.sm),
                      BusinessDocumentPill(
                          label: next, small: true, onMuted: true),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        text.bodySmall.copyWith(color: colors.textSecondary)),
              ],
            ),
          ),
          if (previous) ...[
            const SizedBox(width: UiSpacing.sm),
            Text(change,
                style: text.bodySmall.copyWith(
                    color: colors.primary, fontWeight: FontWeight.w500)),
            UiIcon(UiIcons.chevronRight, size: 14, color: colors.primary),
          ],
        ],
      ),
    );

    final card = Material(
      color: businessDocumentTuckedFill(context, 0.5),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: previous ? InkWell(onTap: onOpen, child: row) : row,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: UiSpacing.sm + 4),
      child: Semantics(
        button: previous,
        container: true,
        onTap: onOpen,
        label: previous ? '$title. $detail. $change' : '$next: $title. $detail',
        excludeSemantics: true,
        child: card,
      ),
    );
  }
}

/// A thin edge of a card further back, so the carousel shows there are more
/// groups that way. Inset 24 each side, 10 high, its hidden edge under the
/// card in front of it.
class BusinessDocumentGroupEdge extends StatelessWidget {
  const BusinessDocumentGroupEdge({super.key, required this.top});

  final bool top;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final radius = Radius.circular(UiRadius.xs);
    return ExcludeSemantics(
      child: Container(
        height: 10,
        margin: const EdgeInsets.symmetric(horizontal: UiSpacing.lg),
        decoration: BoxDecoration(
          color: businessDocumentTuckedFill(context, 0.3),
          border: Border.all(color: colors.border.withValues(alpha: 0.5)),
          borderRadius: top
              ? BorderRadius.vertical(top: radius)
              : BorderRadius.vertical(bottom: radius),
        ),
      ),
    );
  }
}
