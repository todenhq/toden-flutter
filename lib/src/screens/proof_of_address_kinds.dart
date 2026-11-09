import 'package:flutter/material.dart';

import '../config/poa_subtypes.dart';
import '../config/proof_of_address.dart';
import '../config/theme.dart';
import '../i18n/text_scope.dart';
import '../widgets/icons/icons.dart';

// ─── Proof of Address — the document kind ─────────────────────────────────────
//
// One row per kind with its documents in a short phrase and how recent it
// must be. The applicant picks the KIND; which document within it they
// uploaded (a water bill, a lease) the server's reader recognises (user
// decision 2026-11-07). One kind is picked because one document is uploaded:
// a radio group, with no heading (the kinds' names say what the choice is).
// Locked once a file is attached, so the kind cannot drift from the document
// already uploaded.
//
// The org's own name for the 'other' kind stands alone, without the generic
// documents under it: "Council tax letter" is not an insurance policy.
// Mirrors the web SDK's steps/PoaAcceptedDocuments and the RN twin.

/// One glyph per kind, the SAME names the web and RN maps carry.
UiIconData poaTypeIcon(PoaDocumentType type) => switch (type) {
      PoaDocumentType.utilityBill => UiIcons.zap,
      PoaDocumentType.bankStatement => UiIcons.landmark,
      PoaDocumentType.tenancyAgreement => UiIcons.house,
      PoaDocumentType.governmentDocument => UiIcons.stamp,
      PoaDocumentType.other => UiIcons.fileText,
    };

/// A kind's validity, as a small chip: a calendar and "3 months".
class PoaValidityChip extends StatelessWidget {
  final String label;

  /// The sheet's chip is a size up from the list's.
  final bool large;

  const PoaValidityChip({super.key, required this.label, this.large = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 8 : 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(UiRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UiIcon(UiIcons.calendar, size: large ? 12 : 10, color: colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: text.bodySmall.copyWith(
              fontSize: large ? 11 : 10,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class PoaKindList extends StatelessWidget {
  final List<PoaDocumentType> kinds;
  final PoaDocumentType value;
  final ValueChanged<PoaDocumentType> onChanged;
  final bool enabled;
  final ProofOfAddressConfig poa;
  final String Function(PoaDocumentType) labelFor;

  /// The flow's text language, which joins each kind's documents with its
  /// own "or".
  final String? language;

  const PoaKindList({
    super.key,
    required this.kinds,
    required this.value,
    required this.onChanged,
    required this.poa,
    required this.labelFor,
    this.enabled = true,
    this.language,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final radius = BorderRadius.circular(UiRadius.md);
    return Container(
      decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: colors.border)),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final kind in kinds) ...[
              _KindRow(
                key: ValueKey(kind),
                kind: kind,
                checked: kind == value,
                enabled: enabled,
                poa: poa,
                label: labelFor(kind),
                language: language,
                onTap: () => onChanged(kind),
              ),
              if (kind != kinds.last) Divider(height: 1, thickness: 1, color: colors.border),
            ],
          ],
        ),
      ),
    );
  }
}

class _KindRow extends StatelessWidget {
  final PoaDocumentType kind;
  final bool checked;
  final bool enabled;
  final ProofOfAddressConfig poa;
  final String label;
  final String? language;
  final VoidCallback onTap;

  const _KindRow({
    super.key,
    required this.kind,
    required this.checked,
    required this.enabled,
    required this.poa,
    required this.label,
    required this.onTap,
    this.language,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final t = context.verificationText;
    final renamedOther = kind == PoaDocumentType.other &&
        (poa.otherLabel?.trim().isNotEmpty ?? false);
    final summary = renamedOther
        ? null
        : poaKindSummary(kind, poa.documentSubtypes, t, language: language);
    final period = poaPeriodLabel(poaKindDays(poa, kind), t);

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _Radio(checked: checked),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: text.label.copyWith(
                    fontSize: 13,
                    height: 1.38,
                    fontWeight: checked ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                if (summary != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall.copyWith(
                      fontSize: 11,
                      height: 1.38,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          PoaValidityChip(label: period),
        ],
      ),
    );

    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: checked,
      enabled: enabled,
      button: true,
      child: Opacity(
        opacity: !enabled && !checked ? 0.5 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: checked ? colors.primary.withValues(alpha: 0.05) : colors.background,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: Stack(
                children: [
                  row,
                  // The chosen row's edge marks it, as well as its radio.
                  if (checked)
                    Positioned(
                      left: 0,
                      top: 8,
                      bottom: 8,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(UiRadius.full),
                          ),
                        ),
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

/// A 16px radio: a ring, filled with a dot when checked.
class _Radio extends StatelessWidget {
  final bool checked;
  const _Radio({required this.checked});

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: checked ? colors.primary : colors.gray300, width: 1.5),
      ),
      child: AnimatedScale(
        scale: checked ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
