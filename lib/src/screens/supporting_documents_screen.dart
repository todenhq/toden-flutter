import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/signature.dart';
import '../config/supporting_documents.dart';
import '../config/theme.dart';
import '../config/upload_limits.dart';
import '../providers/verification_provider.dart';
import '../providers/step_order.dart';
import '../services/api_service.dart';
import '../widgets/ui_button.dart';
import 'document_pick.dart';
import 'supporting_document_card.dart';
import 'supporting_document_carousel.dart';
import '../providers/business_documents_provider.dart';
import '../utils/display_file_name.dart';
import '../widgets/media_source_sheet.dart';
import '../i18n/text_scope.dart';

// ─── Supporting documents screen ──────────────────────────────────────────────
//
// Artefacts the organisation keeps ON FILE, each one named by the org with its
// own guidance. These are NOT the identity evidence this verification is
// decided on: by the time the applicant reaches this screen they have already
// been checked against the government record, so a document that cannot be
// read costs them nothing. The server records it and the verification stands
// on the lookup.
//
// WHICH documents are asked for depends on the ID they picked — a document may
// exist only because they used a particular ID — so the screen is only in the
// step order when that resolution produced something (step_order.dart).
//
// Each card names the values that will be read off that document, because a
// supporting document is whatever the organisation called it: a slot with a
// title alone says nothing about what handing it over is FOR.
//
// The sources and the Continue rule are the business-documents screen's, 1:1,
// so uploading a document feels the same everywhere in the flow.

class SupportingDocumentsScreen extends ConsumerStatefulWidget {
  final void Function(Object error)? onError;
  const SupportingDocumentsScreen({super.key, this.onError});

  @override
  ConsumerState<SupportingDocumentsScreen> createState() =>
      _SupportingDocumentsScreenState();
}

class _SupportingDocumentsScreenState
    extends ConsumerState<SupportingDocumentsScreen> {
  String? _uploadingKey;
  final Map<String, String> _errors = {};

  // In-memory previews for tap-to-check (lost on remount — the row then
  // degrades to the plain uploaded state; the mediaId is what matters).
  final Map<String, Uint8List> _previews = {};
  final Set<String> _pdfKeys = {};

  // One document at a time, stacked like the business documents. The open
  // index lives in a provider because the flow's back arrow walks it too.
  bool _pinned = false;

  /// 1 after moving forward, -1 after moving back, 0 before the first move.
  int _direction = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(supportingDocumentIndexProvider.notifier).state = _firstOpen();
      setState(() => _pinned = true);
    });
  }

  // The first document still to provide, so the step opens on it.
  int _firstOpen() {
    final config = ref.read(verificationConfigProvider);
    final state = ref.read(kYCNotifierProvider);
    final slots = resolveSupportingDocuments(
        config.supportingDocuments, verifiedIdComposites(config, state));
    final first = slots.indexWhere(
        (s) => !state.supportingDocuments.any((u) => u.type == s.key));
    return first == -1 ? 0 : first;
  }

  void _open(int index) {
    ref.read(supportingDocumentIndexProvider.notifier).state = index;
  }

  /// A camera document skips the source sheet and opens the camera, with no
  /// Upload in it: the workflow wants it photographed now.
  /// A file document leaves the camera out of the sheet.
  Future<void> _pick(String key,
      {bool camera = false,
      bool allowCamera = true,
      String label = ''}) async {
    setState(() => _errors.remove(key));
    final result = await pickDocument(context,
        slotKey: key,
        source: camera ? MediaSource.camera : null,
        allowCamera: allowCamera,
        cameraTitle: label,
        cameraUpload: !camera);
    if (!mounted) return;
    if (result.error != null) {
      _fail(key, result.error!);
      return;
    }
    final file = result.file;
    if (file == null) return; // cancelled
    await _upload(key, file);
  }

  Future<void> _upload(String key, PickedDocument file) async {
    final sizeError = uploadSizeError(file.mimeType, file.bytes.length);
    if (sizeError != null) {
      _fail(key, sizeError);
      return;
    }
    final isPdf = file.mimeType == 'application/pdf';
    setState(() {
      _uploadingKey = key;
      _previews.remove(key);
      _pdfKeys.remove(key);
      if (isPdf) {
        _pdfKeys.add(key);
      } else {
        _previews[key] = file.bytes;
      }
    });
    try {
      final notifier = ref.read(kYCNotifierProvider.notifier);
      final mediaId = await notifier.api
          .upload(file.bytes, file.mimeType, MediaType.supportingDocument);
      if (!mounted) return;
      notifier.setSupportingDocument(
        SupportingDocumentUpload(
          type: key,
          mediaId: mediaId,
          fileName: file.fileName,
          previewPath: file.previewPath,
          isPdf: isPdf,
          method: 'uploaded',
        ),
      );
      setState(() => _uploadingKey = null);
    } on VerificationApiException catch (e) {
      _fail(key, e.message ?? 'Upload failed. Please try again.');
      widget.onError?.call(e);
    } catch (_) {
      _fail(key, 'Upload failed. Please try again.');
    }
  }

  Future<void> _sign(
      ResolvedSupportingDocument slot, SignatureDrawing drawing) async {
    const empty = 'Please sign in the box first.';
    const failed =
        'Your signature could not be saved. Please check your connection and try again.';
    final key = slot.key;
    if (!drawing.hasSignature) {
      _fail(key, empty);
      return;
    }
    setState(() {
      _errors.remove(key);
      _uploadingKey = key;
    });
    try {
      final notifier = ref.read(kYCNotifierProvider.notifier);
      final mediaId = await notifier.api.uploadSignature(drawing);
      if (!mounted) return;
      notifier.setSupportingDocument(
        SupportingDocumentUpload(
          type: key,
          mediaId: mediaId,
          fileName: slot.label,
          method: 'drawn',
        ),
      );
      setState(() => _uploadingKey = null);
    } on VerificationApiException catch (e) {
      _fail(key, e.error == 'signature_empty' ? empty : failed);
      widget.onError?.call(e);
    } catch (_) {
      _fail(key, failed);
    }
  }

  void _fail(String key, String message) {
    if (!mounted) return;
    setState(() {
      _uploadingKey = null;
      _previews.remove(key);
      _pdfKeys.remove(key);
      _errors[key] = message;
    });
  }

  void _remove(String key) {
    setState(() {
      _previews.remove(key);
      _pdfKeys.remove(key);
      _errors.remove(key);
    });
    ref.read(kYCNotifierProvider.notifier).removeSupportingDocument(key);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(verificationConfigProvider);
    final state = ref.watch(kYCNotifierProvider);
    final slots = resolveSupportingDocuments(
      config.supportingDocuments,
      verifiedIdComposites(config, state),
    );
    final uploads = state.supportingDocuments;

    SupportingDocumentUpload? uploadFor(String key) {
      for (final u in uploads) {
        if (u.type == key) return u;
      }
      return null;
    }

    final requiredComplete =
        slots.every((s) => !s.required || uploadFor(s.key) != null);
    final stored = ref.watch(supportingDocumentIndexProvider);
    final wanted = _pinned ? stored : _firstOpen();
    final index = slots.isEmpty ? 0 : wanted.clamp(0, slots.length - 1);
    // Another document opened (here or by the flow's back arrow): note which
    // way, for the entrance.
    ref.listen(supportingDocumentIndexProvider, (prev, next) {
      if (!_pinned || prev == null || prev == next) return;
      setState(() => _direction = next > prev ? 1 : -1);
    });
    final slot = slots.isEmpty ? null : slots[index];
    final last = index >= slots.length - 1;
    final provided = slot == null || uploadFor(slot.key) != null;
    final blocked = (slot != null && slot.required && !provided) ||
        (last && !requiredComplete) ||
        _uploadingKey != null;

    // What a tucked card says it holds, or null when it holds nothing.
    String? heldBy(ResolvedSupportingDocument s) {
      final upload = uploadFor(s.key);
      if (upload == null) return null;
      if (upload.method == 'drawn') return 'Signed on screen';
      return displayFileName(upload.fileName) ??
          context.verificationText('business.documents.uploaded');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (slot != null)
          SupportingDocumentCarousel(
            slots: slots,
            index: index,
            heldBy: heldBy,
            direction: _direction,
            onOpen: _open,
            open: SupportingDocumentCard(
              position: index + 1,
              total: slots.length,
              label: slot.label,
              description: slot.description,
              required: slot.required,
              reads: slot.reads,
              fileName: uploadFor(slot.key)?.fileName,
              previewBytes: _previews[slot.key],
              previewPath: uploadFor(slot.key)?.previewPath,
              isPdf: _pdfKeys.contains(slot.key) ||
                  (uploadFor(slot.key)?.isPdf ?? false),
              uploading: _uploadingKey == slot.key,
              error: _errors[slot.key],
              capture: slot.capture,
              drawn: uploadFor(slot.key)?.method == 'drawn',
              onSign: (drawing) => _sign(slot, drawing),
              onTap: () => _pick(slot.key,
                  camera: slot.capture == SupportingDocumentCapture.camera,
                  allowCamera: slot.capture != SupportingDocumentCapture.file,
                  label: slot.label),
              onRemove: () => _remove(slot.key),
            ),
          ),
        const SizedBox(height: UiSpacing.lg),
        UiButton(
          label: context.verificationText(
              slot != null && !slot.required && !provided
                  ? 'common.skip'
                  : 'common.continue'),
          onPressed: blocked
              ? null
              : () => last
                  ? ref.read(kYCNotifierProvider.notifier).nextStep()
                  : _open(index + 1),
        ),
      ],
    );
  }
}
