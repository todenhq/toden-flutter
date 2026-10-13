import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'icons/icons.dart';
import '../i18n/text_scope.dart';

// ─── The pieces of a supporting-document card ────────────────────────────────
//
// Split out of the card itself only for the file-length rule; they are that
// card's own furniture and nothing else builds them.

/// A count while the document is outstanding, and a state anybody can read
/// once it is not. One document needs no number, so it wears a document glyph.
class DocumentMarker extends StatelessWidget {
  const DocumentMarker({
    super.key,
    required this.done,
    required this.position,
    required this.total,
  });

  final bool done;
  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? colors.primary : colors.primary100,
        shape: BoxShape.circle,
      ),
      child: done
          ? UiIcon(UiIcons.check, size: 16, color: colors.onPrimary)
          : total > 1
              ? Text(
                  '$position',
                  style: text.bodySmall.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : UiIcon(UiIcons.fileText, size: 14, color: colors.primary),
    );
  }
}

/// Required or optional, in a word as well as a colour.
class DocumentStatePill extends StatelessWidget {
  const DocumentStatePill({super.key, required this.required});

  final bool required;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: UiSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: required ? colors.errorBg : colors.background,
        borderRadius: BorderRadius.circular(UiRadius.full),
      ),
      child: Text(
        context.verificationText(required
            ? 'supportingDocuments.card.required'
            : 'supportingDocuments.card.optional'),
        style: text.bodySmall.copyWith(
          color: required ? UiColors.error : colors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// What the server will take off this document, named as the author named it.
class DocumentReads extends StatelessWidget {
  const DocumentReads({super.key, required this.reads});

  final List<String> reads;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(UiSpacing.sm + 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(UiRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.verificationText('supportingDocuments.card.reads').toUpperCase(),
            style: text.bodySmall.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: UiSpacing.sm),
          Wrap(
            spacing: UiSpacing.xs + 2,
            runSpacing: UiSpacing.xs + 2,
            children: [
              for (final read in reads)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: UiSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.backgroundSecondary,
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(UiRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UiIcon(UiIcons.check, size: 12, color: colors.primary),
                      const SizedBox(width: 4),
                      Text(read, style: text.bodySmall),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
