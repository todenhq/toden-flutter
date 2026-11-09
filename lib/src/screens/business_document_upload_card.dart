import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/business_application.dart';
import '../config/theme.dart';
import '../config/upload_limits.dart';
import '../i18n/text_scope.dart';
import '../utils/display_file_name.dart';
import '../widgets/dashed_border.dart';
import '../widgets/icons/icons.dart';
import '../widgets/ui_spinner.dart';
import 'business_document_thumb.dart';
import 'business_document_uploaded_status.dart';

// ─── The one upload a business document group needs ──────────────────────────
//
// Empty, the whole tall dashed area is the one control ("Tap to choose a file";
// the source sheet offers the photo library, the camera and Files), so Continue
// is the only primary button. Filled, the file with Replace and Remove.
//
// MIRRORS the web SDK's steps/business-documents/DocumentDropZone.

class BusinessDocumentUploadCard extends StatelessWidget {
  const BusinessDocumentUploadCard({
    super.key,
    required this.title,
    required this.uploaded,
    required this.uploading,
    required this.error,
    required this.previewBytes,
    required this.isPdf,
    required this.onChoose,
    required this.onRemove,
  });

  /// The group, for labels read out with the controls.
  final String title;
  final BusinessDocumentUpload? uploaded;
  final bool uploading;
  final String? error;
  final Uint8List? previewBytes;
  final bool isPdf;

  /// Choose (or replace) the file.
  final VoidCallback onChoose;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        uploaded == null ? _empty(context) : _filled(context, uploaded!),
        if (error != null) ...[
          const SizedBox(height: UiSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(error!,
                style: text.bodySmall.copyWith(color: UiColors.error)),
          ),
        ],
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final t = context.verificationText;
    final headline = t(uploading
        ? 'business.documents.uploading'
        : 'business.documents.drop.tap');
    return Semantics(
      button: true,
      enabled: !uploading,
      label: '$headline: $title',
      excludeSemantics: true,
      child: InkWell(
        onTap: uploading ? null : onChoose,
        borderRadius: BorderRadius.circular(UiRadius.sm),
        child: CustomPaint(
          painter: DashedRoundedBorder(
            color: error != null
                ? UiColors.error
                : colors.primary.withValues(alpha: 0.4),
            radius: UiRadius.sm,
            strokeWidth: 1,
          ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 176),
            padding: const EdgeInsets.symmetric(
                horizontal: UiSpacing.lg - 4, vertical: UiSpacing.xl),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(UiRadius.sm),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: uploading
                      ? SizedBox.square(
                          dimension: 20,
                          child: UiSpinner(
                              strokeWidth: 2, color: colors.primary))
                      : UiIcon(UiIcons.imageUp,
                          size: 20, color: colors.primary),
                ),
                const SizedBox(height: UiSpacing.sm + 4),
                Text(headline,
                    textAlign: TextAlign.center,
                    style: text.label.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: UiSpacing.xs),
                Text(kUploadHint,
                    textAlign: TextAlign.center,
                    style: text.bodySmall.copyWith(color: colors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filled(BuildContext context, BusinessDocumentUpload doc) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final t = context.verificationText;
    final size = businessDocumentSizeLabel(doc.size);
    return Container(
      padding: const EdgeInsets.all(UiSpacing.sm + 4),
      decoration: BoxDecoration(
        color: UiColors.success.withValues(alpha: 0.06),
        border: Border.all(color: UiColors.success.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(UiRadius.sm),
      ),
      child: Row(
        children: [
          BusinessDocumentThumb(
            uploading: uploading,
            bytes: previewBytes,
            path: doc.previewPath,
            isPdf: isPdf || doc.isPdf,
          ),
          const SizedBox(width: UiSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(displayFileName(doc.fileName) ?? title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: text.label),
                const SizedBox(height: 2),
                BusinessDocumentUploadedStatus(size: size),
              ],
            ),
          ),
          IconButton(
            onPressed: uploading ? null : onChoose,
            tooltip: '${t('business.documents.replace')}: $title',
            icon: UiIcon(UiIcons.refreshCcw,
                size: 18, color: colors.textSecondary),
          ),
          IconButton(
            onPressed: uploading ? null : onRemove,
            tooltip: '${t('business.documents.remove')}: $title',
            icon: UiIcon(UiIcons.x, size: 18, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
