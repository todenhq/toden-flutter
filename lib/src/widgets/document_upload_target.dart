import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'dashed_border.dart';
import 'icons/icons.dart';
import '../i18n/text_scope.dart';
import 'ui_spinner.dart';

// ─── The upload-only tap target ───────────────────────────────────────────────
//
// The dashed card an upload-only document side is made of (see
// DocumentUploadOnlyView). The card is the whole control and there is no
// button beside it: a screen whose only job is to open the photo picker does
// not need one, and the primary line at the bottom of the card says what a tap
// does. Split from the view per the 200-line rule.

class DocumentUploadTarget extends StatelessWidget {
  final String idTypeLabel;
  final bool isBack;

  /// Document aspect, so the card is the shape of what is expected.
  final double aspect;

  /// A pick is being prepared: the card spins and ignores taps.
  final bool isBusy;

  /// The last pick could not be used: the border turns red.
  final bool hasError;

  final VoidCallback onPick;

  const DocumentUploadTarget({
    super.key,
    required this.idTypeLabel,
    required this.isBack,
    required this.aspect,
    required this.isBusy,
    required this.hasError,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final side = isBack ? 'back' : 'front';

    return Semantics(
      button: true,
      enabled: !isBusy,
      label: isBusy ? 'Preparing your photo' : 'Choose a photo of the $side',
      excludeSemantics: true,
      child: InkWell(
        onTap: isBusy ? null : onPick,
        borderRadius: BorderRadius.circular(UiRadius.md),
        child: CustomPaint(
          painter: DashedRoundedBorder(
            color: hasError ? UiColors.error : colors.primary200,
            radius: UiRadius.md,
            strokeWidth: 2,
          ),
          child: AspectRatio(
            aspectRatio: aspect,
            child: Padding(
              padding: const EdgeInsets.all(UiSpacing.md),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: colors.primary50,
                      shape: BoxShape.circle,
                    ),
                    child: isBusy
                        ? Padding(
                            padding: const EdgeInsets.all(15),
                            child: UiSpinner(
                                strokeWidth: 2, color: colors.primary),
                          )
                        : UiIcon(UiIcons.imageUp,
                            size: 24, color: colors.primary),
                  ),
                  const SizedBox(height: UiSpacing.sm),
                  Text(
                    isBack
                        ? 'Back of your $idTypeLabel'
                        : 'Front of your $idTypeLabel',
                    style: text.label.copyWith(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isBusy
                        ? 'Preparing your photo…'
                        : context.verificationText('uploadDocument.upload.hint'),
                    style: text.bodySmall.copyWith(color: colors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: UiSpacing.sm),
                  // Kept in the layout while busy so the card keeps its height.
                  Visibility(
                    visible: !isBusy,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        UiIcon(UiIcons.upload,
                            size: 16, color: colors.primary),
                        const SizedBox(width: 6),
                        Text(
                          context.verificationText('uploadDocument.upload.tapToChoose'),
                          style: text.label.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        UiIcon(UiIcons.chevronRight,
                            size: 16, color: colors.primary),
                      ],
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
