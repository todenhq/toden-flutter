import 'package:flutter/material.dart';

import '../config/proof_of_address.dart';
import '../config/theme.dart';
import '../i18n/text_scope.dart';
import '../widgets/icons/icons.dart';
import '../widgets/ui_spinner.dart';

export 'proof_of_address_uploaded_row.dart';

// ─── Proof of Address — how the document comes in ────────────────────────────
//
// As the workflow's `proofOfAddress.capture` says: take a photo, upload a file
// (a PDF or an image, from the photo library or Files), or both side by side
// (the default). While the upload runs the tiles give way to one progress
// row; after it, the uploaded card (proof_of_address_uploaded_row.dart).
// Mirrors the web SDK's steps/PoaUploadActions and the RN twin.

class PoaUploadActions extends StatelessWidget {
  final PoaCapture capture;
  final bool uploading;
  final VoidCallback onCamera;
  final VoidCallback onFile;

  const PoaUploadActions({
    super.key,
    required this.capture,
    required this.uploading,
    required this.onCamera,
    required this.onFile,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final t = context.verificationText;

    if (uploading) {
      return Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(UiRadius.md),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: UiSpinner(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(colors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Text(t('proofOfAddress.uploading'), style: text.label),
            ],
          ),
        ),
      );
    }

    final camera = capture != PoaCapture.file
        ? _Tile(
            primary: true,
            icon: UiIcons.camera,
            title: t('proofOfAddress.action.camera'),
            hint: t('proofOfAddress.action.cameraHint'),
            onTap: onCamera,
          )
        : null;
    final file = capture != PoaCapture.camera
        ? _Tile(
            primary: false,
            // Alone, the file tile is a row rather than a square.
            inline: capture == PoaCapture.file,
            icon: UiIcons.upload,
            title: t('proofOfAddress.action.file'),
            hint: t('proofOfAddress.action.fileHint'),
            onTap: onFile,
          )
        : null;

    if (camera != null && file != null) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: camera),
            const SizedBox(width: 10),
            Expanded(child: file),
          ],
        ),
      );
    }
    return camera ?? file!;
  }
}

class _Tile extends StatefulWidget {
  final bool primary;
  final bool inline;
  final UiIconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

  const _Tile({
    required this.primary,
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
    this.inline = false,
  });

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final primary = widget.primary;
    final radius = BorderRadius.circular(UiRadius.md);
    final fg = primary ? colors.onPrimary : colors.textDark;

    final badge = Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: primary
            ? Colors.white.withValues(alpha: 0.15)
            : colors.primary.withValues(alpha: 0.10),
      ),
      child: UiIcon(widget.icon, size: 18, color: primary ? fg : colors.primary),
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title,
            style: text.label.copyWith(color: fg, fontWeight: FontWeight.w600)),
        Text(
          widget.hint,
          style: text.bodySmall.copyWith(
            color: primary ? fg.withValues(alpha: 0.8) : colors.textSecondary,
          ),
        ),
      ],
    );

    final body = widget.inline
        ? Row(children: [badge, const SizedBox(width: 12), Expanded(child: words)])
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [badge, const SizedBox(height: 12), words],
          );

    // A small press-in, as the web tile's active:scale-[0.98]; none when the
    // platform asks for less motion.
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      button: true,
      label: '${widget.title}. ${widget.hint}',
      excludeSemantics: true,
      child: AnimatedScale(
        scale: _pressed && !reduce ? 0.98 : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Container(
          constraints: BoxConstraints(minHeight: widget.inline ? 0 : 88),
          decoration: BoxDecoration(
            color: primary ? colors.primary : colors.background,
            borderRadius: radius,
            border: primary ? null : Border.all(color: colors.border),
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: radius,
              onTap: widget.onTap,
              onHighlightChanged: (down) => setState(() => _pressed = down),
              child: Padding(padding: const EdgeInsets.all(14), child: body),
            ),
          ),
        ),
      ),
    );
  }
}
