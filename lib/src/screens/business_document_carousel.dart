import 'package:flutter/material.dart';

import '../config/business_application.dart';
import '../config/business_document_groups.dart';
import 'business_document_entrance.dart';
import 'business_document_group_row.dart';
import 'business_document_tucked_stack.dart';

// ─── The business document groups as a vertical carousel ─────────────────────
//
// The open group's card in front, painted over both neighbours; the next
// group's card tucked behind it at the top and the previous group's at the
// bottom (tap it to change it), each overlapped [kBusinessDocumentTuck] by the
// open card; and a thin edge beyond each when there are more groups that way.
// Continue brings the next card down into the middle; Back brings the previous
// one up. The tucked cards fade in afresh on every move.
//
// MIRRORS the web SDK's steps/business-documents/GroupStack. Keep the two in
// step.

class BusinessDocumentCarousel extends StatelessWidget {
  const BusinessDocumentCarousel({
    super.key,
    required this.groups,
    required this.index,
    required this.uploads,
    required this.direction,
    required this.onOpen,
    required this.open,
  });

  final List<BusinessDocumentGroup> groups;
  final int index;
  final List<BusinessDocumentUpload> uploads;

  /// 1 after moving forward, -1 after moving back, 0 before the first move.
  final int direction;
  final ValueChanged<int> onOpen;

  /// The open group's card.
  final Widget open;

  @override
  Widget build(BuildContext context) {
    final group = groups[index];
    final next = index + 1 < groups.length ? groups[index + 1] : null;
    final previous = index > 0 ? groups[index - 1] : null;
    final moreAhead = index + 2 < groups.length;

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
            child: tucked('ahead-$index',
                BusinessDocumentGroupRow(group: next, number: index + 2)),
          ),
        TuckedSlot(
          overlap: next != null ? kBusinessDocumentTuck : 0,
          layer: 2,
          child: BusinessDocumentEntrance(
            key: ValueKey('open-${group.key}'),
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
              BusinessDocumentGroupRow(
                group: previous,
                number: index,
                fileName: groupUpload(previous, uploads)?.fileName,
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
