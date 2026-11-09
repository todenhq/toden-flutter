import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/address_collection.dart';
import '../../config/photo_mode.dart';
import '../../config/upload_limits.dart';
import '../../widgets/media_source_sheet.dart';
import '../photo_camera.dart';

// ─── Getting the entrance photo off the device ───────────────────────────────
//
// Camera or photo library only: the entrance photo is a PICTURE of a place, so
// there is no PDF or Files case. The camera is the SDK's own. Mirrors the RN
// SDK's address photo picker.

/// What came back from the picker: the bytes to upload, their type, and the
/// local path the review step renders as a preview.
class PickedAddressPhoto {
  final Uint8List bytes;
  final String mimeType;
  final String path;

  const PickedAddressPhoto(this.bytes, this.mimeType, this.path);
}

/// The result of asking for a photo: one of a pick, a refusal to explain, or
/// nothing at all (the applicant backed out, which is not an error).
class AddressPhotoPickResult {
  final PickedAddressPhoto? photo;
  final String? error;

  const AddressPhotoPickResult({this.photo, this.error});
}

String _mimeFor(String? name) =>
    switch (name?.split('.').last.toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };

/// Ask for an entrance photo: pick a source, then read and vet the file.
///
/// "Take a photo" is the SDK's own camera (screens/photo_camera.dart); its
/// Upload is the photo library, the sheet's other option.
Future<AddressPhotoPickResult> pickAddressPhoto(BuildContext context) async {
  final source = await showMediaSourceSheet(context, allowFiles: false);
  if (source == null) return const AddressPhotoPickResult();
  if (source == MediaSource.camera) {
    if (!context.mounted) return const AddressPhotoPickResult();
    final shot = await openPhotoCamera(
      context,
      title: PhotoCopy.entranceTitle,
      instruction: PhotoCopy.fitEntrance,
    );
    switch (shot.exit) {
      case PhotoCameraExit.cancelled:
        return const AddressPhotoPickResult();
      case PhotoCameraExit.photo:
        return _vet(shot.photo!);
      case PhotoCameraExit.upload:
        return _pickFromLibrary();
    }
  }
  return _pickFromLibrary();
}

Future<AddressPhotoPickResult> _pickFromLibrary() async {
  final XFile? picked;
  try {
    picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 90);
  } catch (_) {
    return const AddressPhotoPickResult(error: _kPhotoReadError);
  }
  if (picked == null) return const AddressPhotoPickResult();
  return _vet(picked);
}

const String _kPhotoReadError = 'Could not read that photo. Please try another.';

/// Reads a picked or taken photo and checks it is one we take.
Future<AddressPhotoPickResult> _vet(XFile picked) async {
  try {
    final bytes = await picked.readAsBytes();
    final mime = picked.mimeType ?? _mimeFor(picked.name);
    // The picker's media filter is advisory on some platforms, so what came
    // back is re-checked rather than trusted.
    if (!isAcceptedAddressPhotoMimeType(mime)) {
      return const AddressPhotoPickResult(
          error: 'Please upload a photo (JPEG, PNG or WebP).');
    }
    if (bytes.length > kImageMaxBytes) {
      return const AddressPhotoPickResult(
          error: 'Photo is too large (max 5 MB).');
    }
    return AddressPhotoPickResult(
        photo: PickedAddressPhoto(bytes, mime, picked.path));
  } catch (_) {
    return const AddressPhotoPickResult(error: _kPhotoReadError);
  }
}
