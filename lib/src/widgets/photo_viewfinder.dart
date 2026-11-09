import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../config/document_guide.dart' show documentGuideRect;
import '../config/immersive_layout.dart';
import '../config/photo_mode.dart';
import '../config/theme.dart';
import '../i18n/text_scope.dart';
import 'document_plugin_preview.dart';
import 'icons/icons.dart';
import 'immersive_controls.dart';
import 'immersive_glass.dart';
import 'native_camera_preview.dart';

/// The guide frame photo mode draws when a caller asks for one.
const kPhotoGuideKey = ValueKey('kyc.photo.guide');

/// A photo, not a scan: the full-screen document camera's top bar and bottom
/// row over a plain back-camera preview. No auto-capture, no corner, framing or
/// text gate, no live instruction and no guide unless the caller asks for one.
/// The shutter is always enabled; the camera drops a tap that lands while a
/// still is already being taken.
///
/// Mirrors the React Native SDK's components/viewfinder/PhotoViewfinder.tsx.
class PhotoViewfinder extends StatelessWidget {
  /// The Flutter camera-plugin controller. Null until the camera has started,
  /// and on Android's native camera.
  final CameraController? controller;

  /// Android's native camera (the scan's): its preview texture and buffer
  /// size. Drawn in place of [controller] when set.
  final int? nativeTextureId;
  final int nativePreviewW;
  final int nativePreviewH;
  final bool isLoading;
  final String? error;

  /// What is being photographed, in the top bar's centre pill.
  final String title;

  /// An optional neutral instruction under the top bar. Never changes live.
  final String? instruction;

  /// A plain frame of this aspect (width / height). None unless asked for.
  final double? guideAspect;

  final VoidCallback onCapture;
  final VoidCallback onBack;

  /// The flow's close. Null hides the X (closing is turned off).
  final VoidCallback? onClose;

  /// The caller's own library or file picker. Null hides the button.
  final VoidCallback? onUpload;

  final bool torchOn;
  final VoidCallback? onToggleTorch;

  const PhotoViewfinder({
    super.key,
    required this.controller,
    this.nativeTextureId,
    this.nativePreviewW = 0,
    this.nativePreviewH = 0,
    required this.isLoading,
    required this.error,
    required this.title,
    this.instruction,
    this.guideAspect,
    required this.onCapture,
    required this.onBack,
    this.onClose,
    this.onUpload,
    this.torchOn = false,
    this.onToggleTorch,
  });

  @override
  Widget build(BuildContext context) {
    // From the view, as the scan reads them: the feed runs under the bars.
    final insets = MediaQueryData.fromView(View.of(context)).viewPadding;
    final overlay = PhotoOverlayParts.of(
        instruction: instruction, guideAspect: guideAspect);
    final aspect = overlay.guideAspect;

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildFeed(),
        if (aspect != null)
          Positioned.fill(
            child: IgnorePointer(
              child: LayoutBuilder(builder: (context, constraints) {
                final rect = documentGuideRect(constraints.biggest, aspect);
                return Stack(children: [
                  Positioned.fromRect(
                    rect: rect,
                    child: Container(
                      key: kPhotoGuideKey,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(UiRadius.lg),
                        border:
                            Border.all(color: ImmersiveGlass.caption, width: 2),
                      ),
                    ),
                  ),
                ]);
              }),
            ),
          ),
        Positioned(
          key: kDocumentTopBarKey,
          top: immersiveTopBarTop(insets.top),
          left: 0,
          right: 0,
          height: kImmersiveTopBarHeight,
          child: ImmersiveTopBar(
            onBack: onBack,
            country: null,
            documentLabel: title,
            onClose: onClose,
          ),
        ),
        if (overlay.hint != null)
          Positioned(
            top: immersiveHintTop(insets.top),
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: FractionallySizedBox(
                widthFactor: 0.88,
                child: Center(
                  child: ImmersiveHintPill(
                    key: kDocumentHintKey,
                    text: overlay.hint!,
                    tone: ImmersiveHintTone.neutral,
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: kImmersiveSideMargin,
          right: kImmersiveSideMargin,
          bottom: insets.bottom + kImmersiveBottomOffset,
          height: kImmersiveBottomRowHeight,
          child: ImmersiveBottomRow(
            onUpload: onUpload,
            uploadLabel:
                context.verificationText('uploadDocument.camera.uploadInstead'),
            uploadHint: PhotoCopy.uploadHint,
            onCapture: onCapture,
            busy: PhotoShutter.busy,
            progress: PhotoShutter.progress,
            disabledReason: PhotoShutter.disabledReason,
            shutterIcon: UiIcons.camera,
            torchOn: torchOn,
            onToggleTorch: onToggleTorch,
          ),
        ),
      ],
    );
  }

  Widget _buildFeed() {
    final textureId = nativeTextureId;
    if (textureId != null) {
      return NativeCameraPreview(
        textureId: textureId,
        bufferWidth: nativePreviewW,
        bufferHeight: nativePreviewH,
      );
    }
    final ctrl = controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      return DocumentPluginPreview(ctrl);
    }
    return ImmersiveViewfinderPlaceholder(isLoading: isLoading, error: error);
  }
}
