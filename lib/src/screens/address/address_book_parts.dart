import 'package:flutter/material.dart';

import '../../config/address_book.dart';
import '../../config/theme.dart';
import '../../i18n/text_scope.dart';
import '../../widgets/icons/icons.dart';

// ─── The saved address sheets' pieces ────────────────────────────────────────
//
// Shared with the address book step. Mirrors the React Native SDK's
// AddressBookParts: each choice carries an icon and a word, never colour alone.

/// A sheet's opening: its icon, title and one line of why, centred.
class AddressBookSheetHeading extends StatelessWidget {
  final UiIconData icon;
  final String title;
  final String description;

  const AddressBookSheetHeading({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: colors.primary50, shape: BoxShape.circle),
        child: UiIcon(icon, size: 24, color: colors.primary),
      ),
      const SizedBox(height: 12),
      Semantics(
        header: true,
        child: Text(title, textAlign: TextAlign.center, style: text.heading3),
      ),
      const SizedBox(height: UiSpacing.xs),
      Text(description,
          textAlign: TextAlign.center, style: text.bodyMedium.copyWith(color: colors.textSecondary)),
    ]);
  }
}

/// The sheet's error line, announced when it appears. Nothing when no error.
class AddressBookError extends StatelessWidget {
  final String? message;

  const AddressBookError(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final error = message;
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: UiSpacing.sm),
      child: Semantics(
        liveRegion: true,
        child: Text(error,
            textAlign: TextAlign.center,
            style: context.myazaText.bodySmall.copyWith(color: UiColors.error)),
      ),
    );
  }
}

/// The saved addresses as a single-choice list.
class SavedAddressList extends StatelessWidget {
  final List<SavedAddress> addresses;
  final String? selected;
  final ValueChanged<String> onSelect;

  const SavedAddressList({
    super.key,
    required this.addresses,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final t = context.verificationText;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final a in addresses) ...[
        Semantics(
          inMutuallyExclusiveGroup: true,
          checked: a.entryId == selected,
          child: InkWell(
            onTap: () => onSelect(a.entryId),
            borderRadius: BorderRadius.circular(UiRadius.md),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: UiSpacing.md, vertical: 12),
              decoration: BoxDecoration(
                color: a.entryId == selected ? colors.primary50 : colors.background,
                border: Border.all(color: a.entryId == selected ? colors.primary : colors.border),
                borderRadius: BorderRadius.circular(UiRadius.md),
              ),
              child: Row(children: [
                UiIcon(UiIcons.mapPin,
                    size: 20, color: a.entryId == selected ? colors.primary : colors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      _line(a),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium.copyWith(fontWeight: FontWeight.w500),
                    ),
                    if (a.presenceStatus == 'verified')
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const UiIcon(UiIcons.mapPinCheck, size: 14, color: UiColors.success),
                          const SizedBox(width: UiSpacing.xs),
                          Text(t('address.book.presence.verified'),
                              style: text.bodySmall.copyWith(color: UiColors.success)),
                        ]),
                      ),
                  ]),
                ),
                if (a.entryId == selected)
                  UiIcon(UiIcons.circleCheck, size: 20, color: colors.primary),
              ]),
            ),
          ),
        ),
        const SizedBox(height: UiSpacing.sm),
      ],
    ]);
  }

  static String _line(SavedAddress a) {
    final line = savedAddressLine(label: a.label, area: a.area);
    return line.isNotEmpty ? line : (a.countryCode ?? '');
  }
}

/// The saved address already picked (returning to this step).
class ChosenSavedAddress extends StatelessWidget {
  final AddressBookReuse chosen;
  const ChosenSavedAddress({super.key, required this.chosen});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      padding: const EdgeInsets.all(UiSpacing.md),
      decoration: BoxDecoration(
        color: colors.primary50,
        border: Border.all(color: colors.primary200),
        borderRadius: BorderRadius.circular(UiRadius.lg),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colors.primary100,
            borderRadius: BorderRadius.circular(UiRadius.full),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            UiIcon(UiIcons.bookUser, size: 12, color: colors.primary),
            const SizedBox(width: 6),
            Text(context.verificationText('address.book.chosen.badge').toUpperCase(),
                style: text.bodySmall.copyWith(
                  color: colors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                )),
          ]),
        ),
        const SizedBox(height: UiSpacing.sm),
        Text(savedAddressLine(label: chosen.label, area: chosen.area),
            style: text.body.copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
