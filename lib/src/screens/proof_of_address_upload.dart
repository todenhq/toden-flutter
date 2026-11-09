part of 'proof_of_address_screen.dart';

// ─── Proof of Address — uploading, failing, removing ─────────────────────────
//
// The screen's upload lifecycle, split out of the screen (200-line rule). A
// part rather than a helper because every operation reads and writes the
// screen's own private state (`_uploading`, `_fileName`, the preview) and
// reports through its `ref` and `widget`.

extension _PoaUploadOps on _ProofOfAddressScreenState {
  /// "Take a photo": the SDK's own rear camera, straight away. Its Upload is
  /// the step's own, and is left out when the workflow wants the camera.
  Future<void> _takePhoto() async {
    _rebuild(() => _error = null);
    final shot = await openPhotoCamera(
      context,
      title: context.verificationText('proofOfAddress.title'),
      instruction: PhotoCopy.fitDocument,
      allowUpload: _cfg.capture != PoaCapture.camera,
    );
    if (!mounted) return;
    switch (shot.exit) {
      case PhotoCameraExit.cancelled:
        return;
      case PhotoCameraExit.upload:
        await _pickFile();
      case PhotoCameraExit.photo:
        await _pickFrom(() => readPoaImage(shot.photo!));
    }
  }

  /// "Upload a file": a PDF or an image. The native file picker opens the
  /// Files app only, so the photo library is offered beside it (the web's
  /// file input gets that choice from the browser).
  Future<void> _pickFile() async {
    _rebuild(() => _error = null);
    final source = await showMediaSourceSheet(context, allowCamera: false);
    if (source == null || !mounted) return;
    await _pickFrom(() => source == MediaSource.files
        ? pickPoaFile()
        : pickPoaImage(ImageSource.gallery));
  }

  Future<void> _pickFrom(Future<PoaPick?> Function() pick) async {
    _rebuild(() => _error = null);
    try {
      final picked = await pick();
      if (picked == null || !mounted) return; // cancelled
      await _upload(picked.bytes, picked.mime, picked.name);
    } on PoaPickException catch (e) {
      _failUpload(e.message);
    }
  }

  Future<void> _upload(Uint8List bytes, String mime, String name) async {
    final sizeError = uploadSizeError(mime, bytes.length);
    if (sizeError != null) {
      _failUpload(sizeError);
      return;
    }
    final isPdf = mime == 'application/pdf';
    _rebuild(() {
      _uploading = true;
      _fileName = name;
      _previewIsPdf = isPdf;
      // Only images are renderable; a PDF falls back to the document tile.
      _previewBytes = isPdf ? null : bytes;
    });
    try {
      final api = ref.read(kYCNotifierProvider.notifier).api;
      final mediaId = await api.upload(bytes, mime, MediaType.proofOfAddress);
      if (!mounted) return;
      ref
          .read(kYCNotifierProvider.notifier)
          .setProofOfAddress(mediaId, _type.key);
      _rebuild(() => _uploading = false);
    } on VerificationApiException catch (e) {
      _failUpload(e.message ?? 'Upload failed. Please try again.');
      widget.onError?.call(e);
    } catch (e) {
      _failUpload('Upload failed. Please try again.');
    }
  }

  void _failUpload(String message) {
    if (!mounted) return;
    _rebuild(() {
      _uploading = false;
      _fileName = null;
      _previewBytes = null;
      _previewIsPdf = false;
      _error = message;
    });
  }

  void _remove() {
    ref.read(kYCNotifierProvider.notifier).clearProofOfAddress();
    _rebuild(() {
      _fileName = null;
      _previewBytes = null;
      _previewIsPdf = false;
      _error = null;
    });
  }
}
