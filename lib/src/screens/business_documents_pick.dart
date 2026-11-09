part of 'business_documents_screen.dart';

// ─── Business documents: picking, uploading and removing a group's file ──────
//
// The picking itself is shared (document_pick.dart) so every screen that asks
// for a document offers the same three sources. What stays here is the part that
// reads this screen's own state (`mounted`, the previews, the error), which is
// why it is a `part` rather than a helper.
//
// The upload names its GROUP: the applicant never says which document it is,
// and the server recognises it from its text. Until then its `type` is the
// group's first document. A group holds one document, so an upload replaces
// whatever the group held.

extension _BusinessDocumentPickOps on _BusinessDocumentsScreenState {
  /// Picks the file for [group]: the source sheet offers the photo library,
  /// the camera (the SDK's own, titled with the group) and Files.
  Future<void> _pick(BusinessDocumentGroup group) async {
    _rebuild(() => _error = null);
    final result = await pickDocument(context,
        slotKey: group.key, cameraTitle: group.title);
    if (!mounted) return;
    if (result.error != null) {
      _fail(group.key, result.error!);
      return;
    }
    final file = result.file;
    if (file == null) return; // cancelled
    await _upload(group, file);
  }

  Future<void> _upload(BusinessDocumentGroup group, PickedDocument file) async {
    final key = group.key;
    final bytes = file.bytes;
    final sizeError = uploadSizeError(file.mimeType, bytes.length);
    if (sizeError != null) {
      _fail(key, sizeError);
      return;
    }
    final isPdf = file.mimeType == 'application/pdf';
    _rebuild(() => _uploadingKey = key);
    final t = context.verificationText;
    try {
      final notifier = ref.read(kYCNotifierProvider.notifier);
      final mediaId = await notifier.api
          .upload(bytes, file.mimeType, MediaType.businessDocument);
      if (!mounted) return;
      notifier.setBusinessDocuments(withGroupUpload(
        group,
        ref.read(kYCNotifierProvider).businessDocuments,
        BusinessDocumentUpload(
          type: group.types.first.key,
          group: key,
          mediaId: mediaId,
          fileName: file.fileName,
          size: bytes.length,
          // On the record, so the thumbnail survives leaving the step:
          // screen-local preview state dies with the widget.
          previewPath: file.previewPath,
          isPdf: isPdf,
        ),
      ));
      // Read it for the people it names, so the key-people step opens with
      // them. In the background: the applicant carries on meanwhile.
      unawaited(notifier.readDocumentPeople(group, mediaId));
      _rebuild(() {
        _uploadingKey = null;
        _forget(key);
        if (isPdf) {
          _pdfKeys.add(key);
        } else {
          _previews[key] = bytes;
        }
      });
    } on VerificationApiException catch (e) {
      _fail(key, e.message ?? t('business.documents.errorUpload'));
      widget.onError?.call(e);
    } catch (_) {
      _fail(key, t('business.documents.errorUpload'));
    }
  }

  void _forget(String key) {
    _previews.remove(key);
    _pdfKeys.remove(key);
  }

  void _fail(String key, String message) {
    if (!mounted) return;
    // The group keeps whatever it held: a failed replacement is not a removal.
    _rebuild(() {
      _uploadingKey = null;
      _error = message;
    });
  }

  void _remove(BusinessDocumentGroup group) {
    final notifier = ref.read(kYCNotifierProvider.notifier);
    _rebuild(() {
      _error = null;
      _forget(group.key);
    });
    notifier.setBusinessDocuments(withoutGroupUpload(
        group, ref.read(kYCNotifierProvider).businessDocuments));
  }
}
