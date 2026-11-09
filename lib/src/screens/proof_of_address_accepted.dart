import 'package:flutter/material.dart';

import '../config/poa_subtypes.dart';
import '../config/proof_of_address.dart';
import '../config/theme.dart';
import '../i18n/text_scope.dart';
import '../widgets/icons/icons.dart';
import '../widgets/themed_sheet.dart';
import 'proof_of_address_kinds.dart';

// ─── Proof of Address — "See accepted documents" ─────────────────────────────
//
// A link that opens every document the workflow accepts, kind by kind, with
// how recent each kind must be; the kind picked on the step is marked. What
// the document must show (name, address, how recent) is the step's own
// description, so it is not repeated. The house sheet (showUiSheet): from the
// bottom, dragged down or closed to dismiss, its body scrolling under the
// handle. Mirrors the web SDK's steps/PoaRequirements and PoaAcceptedSheet.

class PoaAcceptedLink extends StatelessWidget {
  final List<PoaDocumentType> kinds;
  final PoaDocumentType selected;
  final ProofOfAddressConfig poa;
  final String Function(PoaDocumentType) labelFor;

  const PoaAcceptedLink({
    super.key,
    required this.kinds,
    required this.selected,
    required this.poa,
    required this.labelFor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(UiRadius.xs),
          onTap: () => showPoaAcceptedSheet(
            context,
            kinds: kinds,
            selected: selected,
            poa: poa,
            labelFor: labelFor,
          ),
          child: Padding(
            // A 44pt-tall target around a 12px line.
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                UiIcon(UiIcons.info, size: 14, color: colors.primary),
                const SizedBox(width: 6),
                Text(
                  context.verificationText('proofOfAddress.accepted.open'),
                  style: text.bodySmall.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the accepted documents sheet.
Future<void> showPoaAcceptedSheet(
  BuildContext context, {
  required List<PoaDocumentType> kinds,
  required PoaDocumentType selected,
  required ProofOfAddressConfig poa,
  required String Function(PoaDocumentType) labelFor,
}) =>
    showUiSheet<void>(
      context,
      isScrollControlled: true,
      title: context.verificationText('proofOfAddress.accepted.title'),
      description: context.verificationText('proofOfAddress.accepted.description'),
      builder: (_) => PoaAcceptedSheet(
        kinds: kinds,
        selected: selected,
        poa: poa,
        labelFor: labelFor,
      ),
    );

/// The sheet's body: a title, a line, then one card per kind.
class PoaAcceptedSheet extends StatelessWidget {
  final List<PoaDocumentType> kinds;
  final PoaDocumentType selected;
  final ProofOfAddressConfig poa;
  final String Function(PoaDocumentType) labelFor;

  const PoaAcceptedSheet({
    super.key,
    required this.kinds,
    required this.selected,
    required this.poa,
    required this.labelFor,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The title and its line are in the house sheet header.
            for (final kind in kinds) ...[
              _KindCard(
                kind: kind,
                chosen: kind == selected,
                poa: poa,
                label: labelFor(kind),
              ),
              if (kind != kinds.last) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _KindCard extends StatelessWidget {
  final PoaDocumentType kind;
  final bool chosen;
  final ProofOfAddressConfig poa;
  final String label;

  const _KindCard({
    required this.kind,
    required this.chosen,
    required this.poa,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final t = context.verificationText;
    final otherLabel = poa.otherLabel?.trim();
    // The org's own name for 'other' stands alone.
    final documents = kind == PoaDocumentType.other && (otherLabel?.isNotEmpty ?? false)
        ? [otherLabel!]
        : [for (final s in acceptedPoaSubtypes(kind, poa.documentSubtypes)) t(poaSubtypeKey(s))];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: chosen ? colors.primary.withValues(alpha: 0.04) : colors.background,
        borderRadius: BorderRadius.circular(UiRadius.md),
        border: Border.all(
          color: chosen ? colors.primary.withValues(alpha: 0.4) : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: chosen ? colors.primary : colors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(UiRadius.xs),
                ),
                child: UiIcon(
                  poaTypeIcon(kind),
                  size: 16,
                  color: chosen ? colors.onPrimary : colors.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.label.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              PoaValidityChip(
                label: poaPeriodLabel(poaKindDays(poa, kind), t),
                large: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final document in documents)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: UiIcon(UiIcons.check, size: 14, color: colors.primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      document,
                      style: text.bodySmall.copyWith(color: colors.textDark, height: 1.33),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
