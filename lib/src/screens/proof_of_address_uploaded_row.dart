import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../i18n/text_scope.dart';
import '../widgets/country_flag.dart';
import '../widgets/document_review_side.dart' show DocumentReviewZoom, ReviewSide;
import '../widgets/icons/icons.dart';

// ─── Proof of Address — the uploaded card ─────────────────────────────────────
//
// After the upload: the person's own document as a page, tilted and ticked,
// with what it is, where it is from, and Replace / Remove. Tapping an image
// page opens it full screen (the document review's zoom, Replace to hand).
// The preview renders the in-memory bytes from the picker; a PDF (the SDK
// ships no PDF renderer) and a restored upload show a document page instead.
// Mirrors the web SDK's steps/PoaUploadedCard and the RN twin.

class PoaUploadedCard extends StatelessWidget {
  final String? fileName;
  final String typeLabel;
  final Uint8List? previewBytes;
  final bool isPdf;

  /// The country the document is from, its flag before the kind.
  final String? country;

  final VoidCallback onReplace;
  final VoidCallback onRemove;

  const PoaUploadedCard({
    super.key,
    required this.fileName,
    required this.typeLabel,
    required this.previewBytes,
    required this.isPdf,
    required this.onReplace,
    required this.onRemove,
    this.country,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final t = context.verificationText;
    final name = (fileName?.trim().isNotEmpty ?? false) ? fileName! : typeLabel;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(UiRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          PoaPage(
            bytes: isPdf ? null : previewBytes,
            isPdf: isPdf,
            label: typeLabel,
            onReplace: onReplace,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t('proofOfAddress.uploaded'),
                  style: text.bodySmall.copyWith(
                    color: UiColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.label.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (country != null) ...[
                      UiCountryFlag(country: country, size: 16),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        typeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall.copyWith(color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Action(
                      icon: UiIcons.rotateCcw,
                      label: t('proofOfAddress.replace'),
                      outlined: true,
                      onTap: onReplace,
                    ),
                    _Action(
                      icon: UiIcons.x,
                      label: t('proofOfAddress.remove'),
                      outlined: false,
                      onTap: onRemove,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill action: Replace (outlined) or Remove (quiet). 32 tall, its touch
/// area padded out to the 44pt minimum.
class _Action extends StatelessWidget {
  final UiIconData icon;
  final String label;
  final bool outlined;
  final VoidCallback onTap;

  const _Action({
    required this.icon,
    required this.label,
    required this.outlined,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final fg = outlined ? colors.textDark : colors.textSecondary;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(UiRadius.full),
      side: outlined ? BorderSide(color: colors.border) : BorderSide.none,
    );
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Material(
          color: Colors.transparent,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UiIcon(icon, size: 14, color: fg),
                  const SizedBox(width: 6),
                  Text(label, style: text.bodySmall.copyWith(color: fg, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The uploaded document as a page: tilted, ticked, and, for an image,
/// tappable to see it full size.
class PoaPage extends StatelessWidget {
  final Uint8List? bytes;
  final bool isPdf;
  final String label;
  final VoidCallback? onReplace;

  const PoaPage({
    super.key,
    required this.bytes,
    required this.isPdf,
    required this.label,
    this.onReplace,
  });

  static const double width = 116;
  static const double height = 150;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final data = bytes;

    final placeholder = Container(
      color: const Color(0xFFF9FAFB),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const UiIcon(UiIcons.fileText, size: 32, color: Color(0xFF6B7280)),
          if (isPdf) ...[
            const SizedBox(height: 6),
            const Text(
              'PDF',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ],
      ),
    );

    final page = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: data == null
            ? placeholder
            : Image.memory(
                data,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => placeholder,
              ),
      ),
    );

    final ticked = Stack(
      clipBehavior: Clip.none,
      children: [
        page,
        Positioned(
          right: -8,
          bottom: -8,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: UiColors.success,
              shape: BoxShape.circle,
              border: Border.all(color: colors.background, width: 4),
            ),
            child: const UiIcon(UiIcons.check, size: 14, color: Colors.white),
          ),
        ),
      ],
    );

    final tilted = Transform.rotate(angle: -0.035, child: ticked);
    if (data == null) return tilted;
    return Semantics(
      button: true,
      label: 'Preview $label',
      child: GestureDetector(
        onTap: () => _zoom(context, data),
        child: tilted,
      ),
    );
  }

  void _zoom(BuildContext context, Uint8List data) {
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      // The zoom paints its own near-black field; the same colour runs under
      // the system bars, and Material gives its text a style to inherit.
      pageBuilder: (routeContext, _, __) => Material(
        color: const Color(0xF20A0A12),
        child: SafeArea(
          child: DocumentReviewZoom(
          side: ReviewSide(key: const ValueKey('poa'), label: label, bytes: data),
          isBusy: false,
          uploadOnly: true,
          onClose: () => Navigator.of(routeContext).pop(),
          onRetake: () {
            Navigator.of(routeContext).pop();
            onReplace?.call();
          },
          ),
        ),
      ),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }
}
