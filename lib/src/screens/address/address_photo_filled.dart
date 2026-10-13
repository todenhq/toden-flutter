import 'dart:io';

import 'package:flutter/material.dart';

import '../../config/theme.dart';
import 'address_photo_dropzone.dart';
import '../../widgets/icons/icons.dart';

/// The picked entrance photo at full width, its controls as pills over the
/// image. Split from the dropzone per the 200-line rule. Web's exact pills,
/// which RN draws too: the tag top-left is `text-[11px] font-semibold
/// uppercase tracking-wider text-primary` with a 12px check; Replace and
/// Remove are `px-3 py-1.5 text-xs font-medium` with 14px icons, on a 90%
/// background with a soft shadow.
class AddressPhotoFilled extends StatelessWidget {
  final AddressPhotoDropzone parent;
  const AddressPhotoFilled(this.parent, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final path = parent.previewPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(UiRadius.md),
      child: Stack(
        children: [
          if (path != null && path.isNotEmpty)
            Image.file(File(path),
                height: kAddressPhotoZoneHeight, width: double.infinity, fit: BoxFit.cover)
          else
            // A restored session holds the uploaded mediaId but not the bytes,
            // so the state is stated rather than faked with a broken image.
            Container(
              height: kAddressPhotoZoneHeight,
              width: double.infinity,
              alignment: Alignment.center,
              color: colors.backgroundSecondary,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const UiIcon(UiIcons.circleCheck,
                      size: 32, color: UiColors.success),
                  const SizedBox(height: UiSpacing.sm),
                  Text('Entrance photo added',
                      style: text.label.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          const Positioned(left: 12, top: 12, child: _TagPill()),
          Positioned(
            right: 12,
            bottom: 12,
            child: Row(
              children: [
                _ActionPill(
                  icon: UiIcons.refreshCcw,
                  label: 'Replace',
                  onTap: parent.onPick,
                ),
                const SizedBox(width: UiSpacing.sm),
                _ActionPill(
                  icon: UiIcons.x,
                  label: 'Remove',
                  semanticsLabel: 'Remove photo',
                  onTap: parent.onRemove,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _pillDecoration(UiColorScheme colors) => BoxDecoration(
      color: colors.background.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(UiRadius.full),
      boxShadow: [
        BoxShadow(
          color: colors.textDark.withValues(alpha: 0.12),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );

/// "ENTRANCE PHOTO", the check that says it is in.
class _TagPill extends StatelessWidget {
  const _TagPill();

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: _pillDecoration(colors),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UiIcon(UiIcons.circleCheck, size: 12, color: colors.primary),
          const SizedBox(width: 6),
          Text(
            'ENTRANCE PHOTO',
            style: text.bodySmall.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: colors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final UiIconData icon;
  final String label;
  final String? semanticsLabel;
  final VoidCallback onTap;

  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: DecoratedBox(
        decoration: _pillDecoration(colors),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(UiRadius.full),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(UiRadius.full),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UiIcon(icon, size: 14, color: colors.textDark),
                  const SizedBox(width: 6),
                  Text(label,
                      style: text.bodySmall.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.textDark,
                      )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
