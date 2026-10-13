import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../config/upload_limits.dart';
import '../widgets/dashed_border.dart';
import '../widgets/icons/icons.dart';
import '../widgets/ui_spinner.dart';

// ─── One business-document upload slot ────────────────────────────────────────
//
// A tap target per configured document type: empty it invites a pick, filled it
// shows a thumbnail of what was actually picked plus a remove button. Showing
// the file back matters — it's the only way a user catches "wrong photo from
// the camera roll" before submitting.
//
// PDFs get a document tile instead of a thumbnail (the SDK ships no PDF
// renderer). Mirrors the web SDK's BusinessDocumentSlot.

class BusinessDocumentSlot extends StatelessWidget {
  final String label;

  /// Guidance the organisation wrote: which document, and what it has to show.
  /// Optional because the business-documents step names a fixed catalogue the
  /// applicant already recognises; a supporting document is whatever the org
  /// called it, so this is often the only thing that makes it findable.
  final String? description;
  final bool required;
  final String? fileName;

  /// Bytes of the picked file, kept for the thumbnail. Null for PDFs or when
  /// nothing has been picked yet.
  final Uint8List? previewBytes;

  /// Local temp path of the picked image — the record-persisted fallback that
  /// survives leaving the step after [previewBytes] (screen state) is gone.
  final String? previewPath;
  final bool isPdf;

  final bool uploading;
  final String? error;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  /// The slot sits inside a card that already names the document, so it drops
  /// the title, the asterisk and the guidance rather than saying them twice.
  final bool compact;

  const BusinessDocumentSlot({
    super.key,
    required this.label,
    required this.required,
    this.description,
    required this.fileName,
    required this.uploading,
    this.previewBytes,
    this.previewPath,
    this.isPdf = false,
    this.error,
    this.onTap,
    this.onRemove,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final done = fileName != null && !uploading;
    final hasError = error != null;

    // Mirrors the web SDK's BusinessDocumentSlot exactly: EMPTY is a 2px
    // DASHED rounded-xl tap target (upload glyph · label with a red * ·
    // the shared upload hint); FILLED is a solid muted card with the
    // file's preview/name, the slot label beneath, Replace, and remove.
    final Widget inner;
    if (done) {
      inner = Container(
        padding: const EdgeInsets.all(UiSpacing.md),
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          border: Border.all(
            color: hasError ? UiColors.error : colors.border,
          ),
          borderRadius: BorderRadius.circular(UiRadius.sm),
        ),
        child: Row(
          children: [
            _Leading(
              done: done,
              uploading: uploading,
              previewBytes: previewBytes,
              previewPath: previewPath,
              isPdf: isPdf,
            ),
            const SizedBox(width: UiSpacing.sm + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName!,
                    style: text.label.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style:
                          text.bodySmall.copyWith(color: colors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Breathing room so a truncated file name never crowds the CTA.
            const SizedBox(width: UiSpacing.sm + 4),
            // Whole-row tap re-picks too; the explicit label matches web.
            Text(
              'Replace',
              style: text.bodySmall.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove $label',
                icon: UiIcon(UiIcons.x,
                    size: 18, color: colors.textSecondary),
              ),
          ],
        ),
      );
    } else {
      inner = CustomPaint(
        painter: DashedRoundedBorder(
          color: hasError ? UiColors.error : colors.border,
          radius: UiRadius.sm,
          strokeWidth: 2,
        ),
        child: Container(
          padding: const EdgeInsets.all(UiSpacing.md),
          child: Row(
            children: [
              if (uploading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: UiSpinner(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                )
              else
                UiIcon(UiIcons.upload, size: 20, color: colors.textMuted),
              const SizedBox(width: UiSpacing.sm + 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: compact
                              ? 'Upload ${label.toLowerCase()}'
                              : label,
                          style: text.label
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (required && !compact)
                          TextSpan(
                            text: ' *',
                            style: text.label
                                .copyWith(color: UiColors.error),
                          ),
                      ]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (description != null && !uploading && !compact) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        style: text.bodySmall
                            .copyWith(color: colors.textDark.withValues(alpha: 0.75)),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      uploading ? 'Uploading…' : kUploadHint,
                      style: text.bodySmall
                          .copyWith(color: colors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : UiSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: uploading ? null : onTap,
            borderRadius: BorderRadius.circular(UiRadius.sm),
            child: inner,
          ),
          if (hasError) ...[
            const SizedBox(height: UiSpacing.xs),
            Text(error!,
                style: text.bodySmall.copyWith(color: UiColors.error)),
          ],
        ],
      ),
    );
  }
}

class _Leading extends StatelessWidget {
  final bool done;
  final bool uploading;
  final Uint8List? previewBytes;
  final String? previewPath;
  final bool isPdf;

  const _Leading({
    required this.done,
    required this.uploading,
    required this.previewBytes,
    required this.previewPath,
    required this.isPdf,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    // Web parity: UploadedFileThumb is h-12 w-12 rounded-lg (48 / radius 8).
    const size = 48.0;

    if (uploading) {
      return const SizedBox(
        width: size,
        height: size,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: UiSpinner(strokeWidth: 2),
          ),
        ),
      );
    }

    if (done && previewBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(UiRadius.xs),
        child: Image.memory(
          previewBytes!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // A picker can hand back bytes Flutter can't decode (HEIC on some
          // devices); fall back to the tile rather than throwing in build.
          errorBuilder: (_, __, ___) =>
              _Tile(icon: UiIcons.fileText, colors: colors),
        ),
      );
    }

    // Screen-state bytes are gone (the step was left and re-entered) — the
    // record-persisted temp path still renders the same thumbnail.
    if (done && previewPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(UiRadius.xs),
        child: Image.file(
          File(previewPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          // The OS may have purged the temp file — degrade to the check tile.
          errorBuilder: (_, __, ___) =>
              _Tile(icon: UiIcons.check, colors: colors, tinted: true),
        ),
      );
    }

    return _Tile(
      icon: done
          ? (isPdf ? UiIcons.fileText : UiIcons.check)
          : UiIcons.upload,
      colors: colors,
      tinted: done,
    );
  }
}

class _Tile extends StatelessWidget {
  final UiIconData icon;
  final UiColorScheme colors;
  final bool tinted;

  const _Tile({required this.icon, required this.colors, this.tinted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: tinted ? colors.primary100 : colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(UiRadius.sm),
      ),
      child: UiIcon(icon,
          size: 20, color: tinted ? colors.primary : colors.textSecondary),
    );
  }
}
