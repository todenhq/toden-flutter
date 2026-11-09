import 'package:flutter/material.dart';

import '../config/document_people.dart';
import '../config/theme.dart';
import 'icons/icons.dart';
import 'ui_spinner.dart';

/// What the company documents did for this list, at the top of the key-people
/// step: still being read (after the applicant chose to carry on), or the
/// people they named, filled in and waiting for an email each. The "found"
/// card is deliberately loud, a tinted card with a title, because it is the
/// reason the applicant has less to type and the thing they must act on.
/// Announced politely. Mirrors the web and React Native SDKs'
/// KeyPeopleDocumentsNote.
class KeyPeopleDocumentsNote extends StatelessWidget {
  const KeyPeopleDocumentsNote(
      {super.key, required this.reading, required this.added, this.kept = 0});

  /// A document is still being read for its people.
  final bool reading;

  /// How many people the documents named.
  final int added;

  /// People kept from a removed document because the applicant had changed
  /// them.
  final int kept;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    if (kept > 0 && !reading && added == 0) {
      final note = documentPeopleKeptNote(kept);
      return Semantics(
        liveRegion: true,
        label: note,
        excludeSemantics: true,
        child: Container(
          margin: const EdgeInsets.only(bottom: UiSpacing.md),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.warningBg,
            borderRadius: BorderRadius.circular(UiRadius.md),
            border: Border.all(color: UiColors.warning),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            UiIcon(UiIcons.fileText, size: 20, color: colors.textDark),
            const SizedBox(width: 12),
            Expanded(
              child: Text(note,
                  style: text.bodySmall.copyWith(color: colors.textDark)),
            ),
          ]),
        ),
      );
    }
    if (reading) {
      return Semantics(
        liveRegion: true,
        label: kDocumentPeopleReadingNote,
        excludeSemantics: true,
        child: Container(
          margin: const EdgeInsets.only(bottom: UiSpacing.md),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(UiRadius.md),
            border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            SizedBox(
                width: 20, height: 20, child: UiSpinner(color: colors.primary)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(kDocumentPeopleReadingNote,
                  style: text.bodySmall.copyWith(color: colors.textDark)),
            ),
          ]),
        ),
      );
    }
    final title = documentPeopleFoundTitle(added);
    final body = documentPeopleAddedNote(added);
    return Semantics(
      liveRegion: true,
      label: '$title. $body',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: UiSpacing.md),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(UiRadius.md),
          border: Border.all(
              color: colors.primary.withValues(alpha: 0.45), width: 1.5),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(UiRadius.sm),
            ),
            child: UiIcon(UiIcons.fileText, size: 20, color: colors.onPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(title,
                      style: text.heading3.copyWith(color: colors.textDark)),
                ),
                const SizedBox(width: 6),
                UiIcon(UiIcons.sparkles, size: 16, color: colors.primary),
              ]),
              const SizedBox(height: 4),
              Text(body,
                  style: text.bodySmall.copyWith(color: colors.textDark)),
            ]),
          ),
        ]),
      ),
    );
  }
}
