import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'document_upload_target.dart';
import 'ui_alert.dart';
import 'icons/icons.dart';
import '../i18n/text_scope.dart';

// ─── Upload-only document side ────────────────────────────────────────────────
//
// One side of the document step when the workflow turns the camera off
// (`allowDocumentScan: false`): no viewfinder, no permission prompt, just the
// tap target (DocumentUploadTarget) and three tips. There is no picker button:
// the card is the control. Stateless on purpose: the screen owns the pick
// (crop, compress, preview, review, upload) and its busy/error state, so this
// cannot drift from the camera path.

const kDocumentUploadTargetKey = ValueKey('kyc.upload.target');

class DocumentUploadOnlyView extends StatelessWidget {
  final String idTypeLabel;

  /// Which side is being asked for. Only ever true on a two-sided ID.
  final bool isBack;

  /// Document aspect, so the tap target is the shape of what is expected.
  final double aspect;

  /// A pick is being prepared (cropped and compressed). Disables the picker.
  final bool isBusy;

  /// Why the last pick could not be used, shown above the tap target.
  final String? error;
  final VoidCallback? onDismissError;

  final VoidCallback onPick;

  /// Sits above the tap target (the screen's required-document pill).
  final Widget? header;

  const DocumentUploadOnlyView({
    super.key,
    required this.idTypeLabel,
    required this.isBack,
    required this.aspect,
    required this.isBusy,
    required this.onPick,
    this.error,
    this.onDismissError,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) ...[
          header!,
          const SizedBox(height: UiSpacing.md),
        ],
        Expanded(
          child: SingleChildScrollView(
            // Clear of the home indicator, read from the view for the reason
            // DocumentReview gives: an ancestor may have removed the padding.
            padding: EdgeInsets.only(
              bottom:
                  MediaQueryData.fromView(View.of(context)).viewPadding.bottom +
                      UiSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null) ...[
                  UiAlert(
                    variant: UiAlertVariant.error,
                    title: "Couldn't use that photo",
                    message: error!,
                    onDismiss: onDismissError,
                  ),
                  const SizedBox(height: UiSpacing.sm),
                ],
                DocumentUploadTarget(
                  key: kDocumentUploadTargetKey,
                  idTypeLabel: idTypeLabel,
                  isBack: isBack,
                  aspect: aspect,
                  isBusy: isBusy,
                  hasError: error != null,
                  onPick: onPick,
                ),
                const SizedBox(height: UiSpacing.lg),
                const _Tip(UiIcons.scan, 'uploadDocument.upload.tip1'),
                const _Tip(UiIcons.sun, 'uploadDocument.upload.tip2'),
                const _Tip(UiIcons.type, 'uploadDocument.upload.tip3'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tip extends StatelessWidget {
  final UiIconData icon;

  /// Text key of the tip (a catalogue text).
  final String label;

  const _Tip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: UiSpacing.sm),
      child: Row(
        children: [
          UiIcon(icon, size: 16, color: colors.primary),
          const SizedBox(width: UiSpacing.sm),
          Expanded(
            child: Text(
              context.verificationText(label),
              style: context.myazaText.bodySmall
                  .copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
