import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'icons/icons.dart';

// The small marks on an awaiting person's card. Split from
// key_people_await_card.dart per the 200-line rule. Mirrors the RN and web
// SDKs' cards.

/// "Company": a party that completes a KYB application, not a KYC.
/// Foreground text on a bordered chip: muted-on-muted disappeared on dark themes.
class AwaitCompanyChip extends StatelessWidget {
  const AwaitCompanyChip({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(UiRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UiIcon(UiIcons.building2, size: 12, color: colors.textDark),
          const SizedBox(width: 4),
          Text(
            'Company',
            style: text.bodySmall.copyWith(color: colors.textDark, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Added from the company's own documents: says why someone the applicant
/// never typed is on the list.
class AwaitFoundInDocuments extends StatelessWidget {
  const AwaitFoundInDocuments({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          UiIcon(UiIcons.fileText, size: 13, color: colors.textSecondary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Found in your company documents',
              style: text.bodySmall.copyWith(color: colors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
