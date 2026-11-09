import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/photo_mode.dart';
import '../widgets/media_source_sheet.dart';
import 'photo_camera.dart';

// ─── Picking a document file ─────────────────────────────────────────────────
//
// The three native sources (photo library, camera, Files) reduced to one
// result, shared by every screen that asks for a document: business documents
// and supporting documents today, and whatever asks next.
//
// Shared rather than copied because both callers want the SAME three sources,
// the same allowed extensions and the same friendly filename. This is
// mechanical (image_picker + file_picker), not a rule — but a second copy is
// still a second thing to fix when a platform quirk turns up.

const _kAllowedExtensions = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];

/// A file the applicant picked, ready to upload.
class PickedDocument {
  const PickedDocument({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
    this.previewPath,
  });

  final Uint8List bytes;
  final String mimeType;
  final String fileName;

  /// Local temp path of the picked image, for the slot thumbnail. Null for a
  /// file picked from Files (which may be a PDF we cannot render).
  final String? previewPath;
}

/// The outcome of one pick. Both fields null = the applicant cancelled, which
/// is not a failure and must not paint an error.
class DocumentPickResult {
  const DocumentPickResult({this.file, this.error});

  final PickedDocument? file;
  final String? error;

  static const cancelled = DocumentPickResult();
}

String documentMimeFor(String? extension) => switch (extension?.toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      _ => 'image/jpeg',
    };

/// Shows the source sheet, then picks. [slotKey] names the file on an image
/// pick — a FRIENDLY name, not the picker's temp junk: iOS's image_picker
/// names its copy `image_picker_<UUID>.png` (the photo library does not expose
/// the original), which reads as noise on the uploaded card. The slot key says
/// what the file IS — `incorporation_certificate.jpg`.
///
/// [source] skips the sheet: a document the workflow wants photographed there
/// and then opens the camera directly.
///
/// The camera is the SDK's own (screens/photo_camera.dart), titled
/// [cameraTitle]. Its Upload opens this same sheet without the camera, since
/// they have just come from it; [cameraUpload] false hides Upload (a document
/// the workflow wants photographed now).
Future<DocumentPickResult> pickDocument(
  BuildContext context, {
  required String slotKey,
  MediaSource? source,
  bool allowCamera = true,
  String cameraTitle = '',
  bool cameraUpload = true,
}) async {
  source ??= await showMediaSourceSheet(context, allowCamera: allowCamera);
  if (source == null) return DocumentPickResult.cancelled;
  switch (source) {
    case MediaSource.photoLibrary:
      return _pickImage(ImageSource.gallery, slotKey);
    case MediaSource.files:
      return _pickFile();
    case MediaSource.camera:
      if (!context.mounted) return DocumentPickResult.cancelled;
      final shot = await openPhotoCamera(
        context,
        title: cameraTitle,
        instruction: PhotoCopy.fitDocument,
        allowUpload: cameraUpload,
      );
      switch (shot.exit) {
        case PhotoCameraExit.cancelled:
          return DocumentPickResult.cancelled;
        case PhotoCameraExit.photo:
          return _readImage(shot.photo!, slotKey);
        case PhotoCameraExit.upload:
          if (!context.mounted) return DocumentPickResult.cancelled;
          final instead =
              await showMediaSourceSheet(context, allowCamera: false);
          return switch (instead) {
            MediaSource.photoLibrary => _pickImage(ImageSource.gallery, slotKey),
            MediaSource.files => _pickFile(),
            _ => DocumentPickResult.cancelled,
          };
      }
  }
}

Future<DocumentPickResult> _pickImage(ImageSource source, String slotKey) async {
  final XFile? picked;
  try {
    picked = await ImagePicker().pickImage(source: source, imageQuality: 90);
  } catch (_) {
    return const DocumentPickResult(error: _kPhotoReadError);
  }
  if (picked == null) return DocumentPickResult.cancelled;
  return _readImage(picked, slotKey);
}

const String _kPhotoReadError = 'Could not read that photo. Please try another.';

/// A picked or taken photo, as the upload wants it.
Future<DocumentPickResult> _readImage(XFile picked, String slotKey) async {
  try {
    final bytes = await picked.readAsBytes();
    final ext = picked.name.split('.').lastOrNull ?? 'jpg';
    return DocumentPickResult(
      file: PickedDocument(
        bytes: bytes,
        mimeType: documentMimeFor(ext),
        fileName: '$slotKey.${ext.toLowerCase()}',
        previewPath: picked.path,
      ),
    );
  } catch (_) {
    return const DocumentPickResult(error: _kPhotoReadError);
  }
}

/// Files — the only source that can supply a PDF.
Future<DocumentPickResult> _pickFile() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _kAllowedExtensions,
      withData: true,
    );
    final file = result?.files.firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return DocumentPickResult.cancelled;
    return DocumentPickResult(
      file: PickedDocument(
        bytes: bytes,
        mimeType: documentMimeFor(file.extension),
        fileName: file.name,
      ),
    );
  } catch (_) {
    return const DocumentPickResult(
      error: 'Could not read that file. Please try another.',
    );
  }
}
