import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/business_application.dart';
import '../config/business_document_groups.dart';
import '../config/theme.dart';
import '../i18n/text_scope.dart';
import 'business_document_parts.dart';
import 'business_document_upload_card.dart';

// ─── The business document group being filled now: the open card ────────────
//
// Its number, title, Required/Optional pill and position ("2 of 4"), the
// documents it accepts (any one of them) as a short list with how recent each
// must be on its own line, then the one upload. There is nothing to choose:
// the server recognises the document from its own text.
//
// MIRRORS the web SDK's steps/business-documents/GroupPanel. Keep the two in
// step.

class BusinessDocumentGroupPanel extends StatelessWidget {
  const BusinessDocumentGroupPanel({
    super.key,
    required this.group,
    required this.index,
    required this.total,
    required this.uploaded,
    required this.uploading,
    required this.error,
    required this.previewBytes,
    required this.isPdf,
    required this.onChoose,
    required this.onRemove,
  });

  final BusinessDocumentGroup group;

  /// Its position among the groups, from 0.
  final int index;

  /// How many groups there are.
  final int total;

  /// The upload that fills the group, if any.
  final BusinessDocumentUpload? uploaded;
  final bool uploading;
  final String? error;
  final Uint8List? previewBytes;
  final bool isPdf;
  final VoidCallback onChoose;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final t = context.verificationText;
    final several = group.types.length > 1;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            BusinessDocumentNumber(number: index + 1, open: true),
            const SizedBox(width: UiSpacing.sm + 4),
            Expanded(
              child: Wrap(
                spacing: UiSpacing.sm,
                runSpacing: UiSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    header: true,
                    child: Text(group.title, style: text.heading3),
                  ),
                  BusinessDocumentPill(
                    label: t(group.required
                        ? 'business.documents.status.required'
                        : 'business.documents.status.optional'),
                    tinted: group.required,
                  ),
                ],
              ),
            ),
            if (total > 1) ...[
              const SizedBox(width: UiSpacing.sm),
              Text(
                t('business.documents.progress',
                    vars: {'current': index + 1, 'total': total}),
                style: text.bodySmall.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: UiSpacing.md),
        Text(
          t(several
              ? 'business.documents.accepts'
              : 'business.documents.acceptsOne'),
          style: text.bodySmall.copyWith(
              color: colors.textSecondary, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: UiSpacing.sm),
        BusinessDocumentAcceptedList(types: group.types),
        const SizedBox(height: UiSpacing.md),
        BusinessDocumentUploadCard(
          title: group.title,
          uploaded: uploaded,
          uploading: uploading,
          error: error,
          previewBytes: previewBytes,
          isPdf: isPdf,
          onChoose: onChoose,
          onRemove: onRemove,
        ),
      ],
    );

    // The one card that is open, between the compact rows of its neighbours.
    return Container(
      padding: const EdgeInsets.all(UiSpacing.md),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(UiRadius.md),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73070330),
            offset: Offset(0, 10),
            blurRadius: 30,
            spreadRadius: -18,
          ),
        ],
      ),
      child: body,
    );
  }
}
