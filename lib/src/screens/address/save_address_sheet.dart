import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/address_book.dart';
import '../../config/address_flow.dart';
import '../../config/theme.dart';
import '../../i18n/text_scope.dart';
import '../../providers/verification_provider.dart';
import '../../widgets/check_card.dart' show UiCheckBox;
import '../../widgets/icons/icons.dart';
import '../../widgets/themed_sheet.dart';
import '../../widgets/ui_button.dart';
import 'address_book_parts.dart';

/// Asked once the person confirms their address: keep it in their Toden address
/// book? Saving is their choice, so nothing happens until they answer. The
/// entrance photo is part of a saved address and the sheet says so; the
/// directions stay a choice of their own. Answers true once they chose; closing
/// it (X, swipe, backdrop) keeps them on the review. Mirrors the React Native
/// SDK's SaveAddressSheet.
Future<bool> askToSaveAddress(BuildContext context) async =>
    await showUiSheet<bool>(
      context,
      isScrollControlled: true,
      builder: (_) => const SaveAddressSheet(),
    ) ==
    true;

class SaveAddressSheet extends ConsumerStatefulWidget {
  const SaveAddressSheet({super.key});

  @override
  ConsumerState<SaveAddressSheet> createState() => _SaveAddressSheetState();
}

class _SaveAddressSheetState extends ConsumerState<SaveAddressSheet> {
  bool _withDirections = false;

  void _decide(bool save) {
    ref.read(kYCNotifierProvider.notifier).setAddressBookSave(
        save ? AddressBookSaveChoice(save: true, photo: true, directions: _withDirections) : kNoSave);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kYCNotifierProvider);
    final address = state.address;
    final hasPhoto = state.mediaIds.addressPhoto != null;
    final preview = state.addressPhotoPreview?.trim() ?? '';
    final hasDirections = address?.directions.trim().isNotEmpty == true;
    final colors = context.myazaColors;
    final text = context.myazaText;
    final t = context.verificationText;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(UiSpacing.lg, UiSpacing.xs, UiSpacing.lg, UiSpacing.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AddressBookSheetHeading(
          icon: UiIcons.bookUser,
          title: t('address.book.save.title'),
          description: t('address.book.save.description'),
        ),
        const SizedBox(height: UiSpacing.md),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(UiRadius.md),
          ),
          child: Row(children: [
            if (preview.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(UiRadius.sm),
                child: Image.file(File(preview),
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    semanticLabel: t('address.book.save.photo'),
                    errorBuilder: (_, __, ___) => UiIcon(UiIcons.mapPin, size: 20, color: colors.primary)),
              )
            else
              UiIcon(UiIcons.mapPin, size: 20, color: colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(address == null ? '' : displayAddressLine(address),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                if (hasPhoto) ...[
                  const SizedBox(height: 2),
                  Text(t('address.book.save.photo'), style: text.bodySmall.copyWith(color: colors.textSecondary)),
                ],
              ]),
            ),
          ]),
        ),
        if (hasDirections)
          Padding(
            padding: const EdgeInsets.only(top: UiSpacing.sm),
            child: Semantics(
              checked: _withDirections,
              child: InkWell(
                onTap: () => setState(() => _withDirections = !_withDirections),
                borderRadius: BorderRadius.circular(UiRadius.xs),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(children: [
                    UiCheckBox(checked: _withDirections),
                    const SizedBox(width: 12),
                    Expanded(child: Text(t('address.book.save.directions'), style: text.bodyMedium)),
                  ]),
                ),
              ),
            ),
          ),
        const SizedBox(height: UiSpacing.md),
        UiButton(label: t('address.book.save.confirm'), onPressed: () => _decide(true)),
        const SizedBox(height: UiSpacing.sm),
        UiButton.ghost(label: t('address.book.save.skip'), onPressed: () => _decide(false)),
      ]),
    );
  }
}
