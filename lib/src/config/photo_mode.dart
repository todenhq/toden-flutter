// ─── Photo mode: the full-screen document camera's look without the scan ────
//
// The decisions the in-SDK "take a photo" camera (screens/photo_camera.dart)
// makes, kept free of widgets so they can be tested on their own. Photo mode
// has no auto-capture, no corner, framing or text gate and no live
// instruction: the shutter is always enabled and takes the photo as it is.
//
// Mirrors the React Native SDK's components/viewfinder/photoMode.ts.

import 'package:flutter/foundation.dart' show TargetPlatform;

/// Photo mode's own words. Hard-coded beside the scan's camera captions
/// (widgets/immersive_controls.dart's "Upload", "Light"): a catalogue key
/// would have to be added to the shared customisable-texts contract, which
/// every SDK must match.
abstract final class PhotoCopy {
  /// The upload button's screen-reader hint: the photo may not be of a
  /// document.
  static const String uploadHint =
      'Choose a photo instead of using the camera.';

  /// The instruction for a document photo.
  static const String fitDocument = 'Fit the whole document in view';

  /// The entrance photo's title and instruction.
  static const String entranceTitle = 'Entrance photo';
  static const String fitEntrance =
      'Fit the door and the house number in the frame';

  /// Shown when the camera permission was refused.
  static const String permissionDenied =
      'Camera access is required to take this photo. Please allow camera access, or upload a photo instead.';
  static const String permissionDeniedNoUpload =
      'Camera access is required to take this photo. Please allow camera access to continue.';
}

/// What photo mode hands the bottom row for the shutter: nothing ever holds
/// it. No gate (disabledReason), no dwell ring (progress), never shown busy.
/// A second tap while a capture is in flight is dropped by the camera's own
/// guard, not by disabling the button.
abstract final class PhotoShutter {
  static const bool busy = false;
  static const double progress = 0;
  static const String? disabledReason = null;
}

/// What is drawn over the preview besides the top bar and the bottom row.
class PhotoOverlayParts {
  /// The caller's optional instruction, shown as a neutral pill.
  final String? hint;

  /// A plain frame of this aspect (width / height), only when asked for.
  final double? guideAspect;

  const PhotoOverlayParts({this.hint, this.guideAspect});

  factory PhotoOverlayParts.of({String? instruction, double? guideAspect}) {
    final trimmed = instruction?.trim();
    return PhotoOverlayParts(
      hint: trimmed == null || trimmed.isEmpty ? null : trimmed,
      guideAspect: guideAspect != null && guideAspect > 0 ? guideAspect : null,
    );
  }
}

/// JPEG quality of the photo handed back, the `imageQuality: 90` the callers
/// gave image_picker, so what they size-check and upload reads as it did.
const int kPhotoJpegQuality = 90;

/// Which camera drives photo mode's feed and still.
enum PhotoCameraSource {
  /// The SDK's own CameraX camera, the one the scan uses on Android, started
  /// with its frame analysis off (services/native_document_camera.dart). Its
  /// preview texture is upright and cover-fit from the first frame.
  native,

  /// The Flutter camera plugin. iOS's camera, and Android's fallback when the
  /// native camera cannot start.
  plugin,
}

/// Android takes the native camera: the plugin's preview there is drawn from
/// the raw texture on the assumption that the engine has turned it upright,
/// which some phones (the Galaxy S24) never do, so the feed showed sideways and
/// stretched while the photo came out right. iOS keeps the plugin, which is
/// stable there.
PhotoCameraSource photoCameraSourceFor(TargetPlatform platform) =>
    platform == TargetPlatform.android
        ? PhotoCameraSource.native
        : PhotoCameraSource.plugin;
