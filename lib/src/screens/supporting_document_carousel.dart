import 'package:flutter/material.dart';

import '../config/supporting_documents.dart';
import '../i18n/text_scope.dart';
import 'business_document_entrance.dart';
import 'business_document_group_row.dart';
import 'business_document_tucked_stack.dart';

// ─── The supporting documents as a vertical carousel ─────────────────────────
//
// The same stacking as the business documents (business_document_carousel):
// the open document's card in front, the next tucked behind it at the top and
// the previous at the bottom (tap it to change it), with a thin edge beyond
// each when there are more that way. The cards themselves are unchanged.
//
// MIRRORS the web SDK's SupportingDocumentsStep stack. Keep the two in step.

class SupportingDocumentCarousel extends StatelessWidget {
  const SupportingDocumentCarousel({
    super.key,
    required this.slots,
    required this.index,
    required this.heldBy,
    required this.direction,
    required this.onOpen,
    required this.open,
  });

  final List<ResolvedSupportingDocument> slots;
  final int index;

  /// What a document holds, for its tucked card: null when it holds nothing.
  final String? Function(ResolvedSupportingDocument slot) heldBy;

  /// 1 after moving forward, -1 after moving back, 0 before the first move.
  final int direction;
  final ValueChanged<int> onOpen;

  /// The open document's card.
  final Widget open;

  @override
  Widget build(BuildContext context) {
    final t = context.verificationText;
    final slot = slots[index];
    final next = index + 1 < slots.length ? slots[index + 1] : null;
    final previous = index > 0 ? slots[index - 1] : null;
    final moreAhead = index + 2 < slots.length;

    Widget tucked(String key, Widget child) => BusinessDocumentEntrance(
        key: ValueKey(key), direction: direction, slide: false, child: child);

    return TuckedStack(
      children: [
        if (moreAhead)
          const TuckedSlot(child: BusinessDocumentGroupEdge(top: true)),
        if (next != null)
          TuckedSlot(
            overlap: moreAhead ? 4 : 0,
            layer: 1,
            child: tucked(
              'ahead-$index',
              TuckedDocumentRow(
                title: next.label,
                number: index + 2,
                done: heldBy(next) != null,
                detail: next.description ??
                    t(next.required
                        ? 'supportingDocuments.card.required'
                        : 'supportingDocuments.card.optional'),
              ),
            ),
          ),
        TuckedSlot(
          overlap: next != null ? kBusinessDocumentTuck : 0,
          layer: 2,
          child: BusinessDocumentEntrance(
            key: ValueKey('open-${slot.key}'),
            direction: direction,
            child: open,
          ),
        ),
        if (previous != null)
          TuckedSlot(
            overlap: kBusinessDocumentTuck,
            layer: 1,
            child: tucked(
              'behind-$index',
              TuckedDocumentRow(
                title: previous.label,
                number: index,
                done: heldBy(previous) != null,
                detail: heldBy(previous) ?? t('business.documents.skipped'),
                onOpen: () => onOpen(index - 1),
              ),
            ),
          ),
        if (index >= 2)
          const TuckedSlot(
              overlap: 4, child: BusinessDocumentGroupEdge(top: false)),
      ],
    );
  }
}
