import 'package:flutter/material.dart';

import '../config/ownership_pending.dart';
import '../config/theme.dart';
import 'icons/icons.dart';

/// Shareholders the register has not sent yet (config/ownership_pending.dart).
///
/// One quiet line, icon and words, announced politely: on the key-people step
/// it says owners can still be added by hand, and on the success screen it says
/// their invite links are coming. Mirrors the web and React Native SDKs'
/// KeyPeopleOwnershipNote.
class KeyPeopleOwnershipNote extends StatelessWidget {
  const KeyPeopleOwnershipNote({super.key, required this.submitted});

  /// True on the success screen, false on the key-people step.
  final bool submitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final words =
        submitted ? kOwnershipPendingSubmittedNote : kOwnershipPendingStepNote;
    return Semantics(
      liveRegion: true,
      label: words,
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(top: UiSpacing.sm + 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          borderRadius: BorderRadius.circular(UiRadius.md),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: UiIcon(UiIcons.info, size: 16, color: colors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                words,
                style: text.bodySmall.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
