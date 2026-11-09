import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/icons/icons.dart';
import '../widgets/ui_spinner.dart';

// ─── The uploaded business document's thumbnail and size ────────────────────
//
// What was actually picked, shown back so a wrong photo from the camera roll
// is caught before submitting. A PDF, or a preview the OS purged, falls back
// to a file tile. MIRRORS the web SDK's UploadedFileThumb in DocumentDropZone.

/// "2.3 MB" / "240 KB" for the uploaded card; null when the size is unknown.
String? businessDocumentSizeLabel(int? bytes) => bytes == null
    ? null
    : bytes >= 1024 * 1024
        ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(bytes / 1024).round().clamp(1, 1023)} KB';

class BusinessDocumentThumb extends StatelessWidget {
  const BusinessDocumentThumb({
    super.key,
    required this.uploading,
    required this.bytes,
    required this.path,
    required this.isPdf,
  });

  final bool uploading;
  final Uint8List? bytes;
  final String? path;
  final bool isPdf;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    const size = 48.0;
    final tile = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(UiRadius.xs),
      ),
      child: uploading
          ? const SizedBox(
              width: 18, height: 18, child: UiSpinner(strokeWidth: 2))
          : UiIcon(UiIcons.fileText, size: 20, color: colors.textSecondary),
    );
    if (uploading || isPdf) return tile;
    final Widget? image = bytes != null
        ? Image.memory(bytes!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => tile)
        : path != null
            // The OS may have purged the temp file: fall back to the tile.
            ? Image.file(File(path!),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => tile)
            : null;
    if (image == null) return tile;
    return ClipRRect(
        borderRadius: BorderRadius.circular(UiRadius.xs), child: image);
  }
}
