import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/business_application.dart';
import '../config/business_document_groups.dart';
import '../config/theme.dart';
import '../config/upload_limits.dart';
import '../i18n/text_scope.dart';
import '../providers/business_documents_provider.dart';
import '../providers/verification_provider.dart';
import '../services/api_service.dart';
import '../widgets/ui_button.dart';
import 'business_document_carousel.dart';
import 'business_document_group_panel.dart';
import 'document_pick.dart';

part 'business_documents_pick.dart';

// ─── Business documents screen, one GROUP at a time ──────────────────────────
//
// The documents an organisation ticks in one group are alternatives, so the
// applicant uploads ONE per group and never says which it is: the upload names
// its group and the server recognises the document. The groups are a vertical
// carousel: the open group's card in front, the next group's card tucked behind
// it at the top (what it will ask for) and the previous group's at the bottom
// (its file, or Skipped; tap it to change it), with a thin edge beyond each
// when there are more groups that way. Continue brings the next card down into
// the middle; Back brings the previous one up. The last group moves on through
// the flow. A live region names the group just opened. An optional group can be skipped. The flow's back arrow
// walks the groups before leaving the step (it reads
// businessDocumentGroupIndexProvider, which this screen owns).
//
// Each file uploads immediately (type `business_document`) and is stored in
// flow state with its group; the uploads ride the business /verify submission
// as `business.documents: [{ group, mediaId }]`.
//
// MIRRORS the web SDK's BusinessDocumentsStep. Keep the two in step.

class BusinessDocumentsScreen extends ConsumerStatefulWidget {
  final void Function(Object error)? onError;
  const BusinessDocumentsScreen({super.key, this.onError});

  @override
  ConsumerState<BusinessDocumentsScreen> createState() =>
      _BusinessDocumentsScreenState();
}

class _BusinessDocumentsScreenState
    extends ConsumerState<BusinessDocumentsScreen> {
  /// The group whose file is uploading.
  String? _uploadingKey;
  String? _error;

  // In-memory previews by group, for the uploaded card (lost on remount: the
  // card then falls back to the record's previewPath; the mediaId is what
  // matters).
  final Map<String, Uint8List> _previews = {};
  final Set<String> _pdfKeys = {};

  // Until the first frame lands, the open group is worked out from the uploads
  // (the first group with nothing in it); after that the provider holds it, so
  // an upload landing does not move the applicant on by itself.
  bool _pinned = false;

  /// 1 after moving forward, -1 after moving back, 0 before the first move (so
  /// the step's own entrance is not doubled).
  int _direction = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(businessDocumentGroupIndexProvider.notifier).state =
          firstOpenGroupIndex(
              _groups(), ref.read(kYCNotifierProvider).businessDocuments);
      setState(() => _pinned = true);
    });
  }

  List<BusinessDocumentGroup> _groups() => businessDocumentGroups(
      ref.read(verificationConfigProvider).business, context.verificationText);

  void _rebuild(VoidCallback fn) => setState(fn);

  void _open(int index) {
    setState(() => _error = null);
    ref.read(businessDocumentGroupIndexProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.verificationText;
    final groups = businessDocumentGroups(
        ref.watch(verificationConfigProvider).business, t);
    final uploads = ref.watch(kYCNotifierProvider).businessDocuments;
    final stored = ref.watch(businessDocumentGroupIndexProvider);
    final wanted = _pinned ? stored : firstOpenGroupIndex(groups, uploads);
    final index = groups.isEmpty ? 0 : wanted.clamp(0, groups.length - 1);
    // Another group opened (here or by the flow's back arrow): note which way,
    // for the entrance, and drop the old one's error.
    ref.listen(businessDocumentGroupIndexProvider, (prev, next) {
      if (!_pinned || prev == null || prev == next) return;
      setState(() {
        _direction = next > prev ? 1 : -1;
        _error = null;
      });
    });

    final group = groups.isEmpty ? null : groups[index];
    final uploaded = group == null ? null : groupUpload(group, uploads);
    final canContinue = group == null || canLeaveGroup(group, uploads);
    final skip = group != null && uploaded == null && canContinue;

    void next() {
      if (index < groups.length - 1) {
        _open(index + 1);
      } else {
        ref.read(kYCNotifierProvider.notifier).nextStep();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The step HEADER carries the description (flow_step_meta.dart).
        if (group != null) ...[
          // Read out when the open group changes ("2 of 4: Ownership").
          Semantics(
            liveRegion: true,
            container: true,
            label:
                '${t('business.documents.progress', vars: {'current': index + 1, 'total': groups.length})}: ${group.title}',
            child: const SizedBox.shrink(),
          ),
          BusinessDocumentCarousel(
            groups: groups,
            index: index,
            uploads: uploads,
            direction: _direction,
            onOpen: _open,
            open: BusinessDocumentGroupPanel(
              group: group,
              index: index,
              total: groups.length,
              uploaded: uploaded,
              uploading: _uploadingKey == group.key,
              error: _error,
              previewBytes: _previews[group.key],
              isPdf: _pdfKeys.contains(group.key),
              onChoose: () => _pick(group),
              onRemove: () => _remove(group),
            ),
          ),
        ],
        const SizedBox(height: UiSpacing.lg),
        skip
            ? UiButton.outline(
                label: t('business.documents.skip'),
                onPressed: _uploadingKey == null ? next : null,
              )
            : UiButton(
                // Next while groups are still to come, Continue on the last.
                label: t(index < groups.length - 1
                    ? 'business.documents.next'
                    : 'common.continue'),
                onPressed: canContinue && _uploadingKey == null ? next : null,
              ),
      ],
    );
  }
}
