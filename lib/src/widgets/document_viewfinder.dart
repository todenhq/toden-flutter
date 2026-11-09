import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../config/capture_hints.dart';
import '../config/theme.dart';
import '../config/document_guide.dart';
import '../config/document_specimen.dart';
import '../config/id_types.dart' show IdTypeConfig, countryLabel;
import '../config/immersive_layout.dart';
import '../services/document_framing_gate.dart';
import 'document_ghost.dart';
import 'document_info_pill.dart';
import 'document_plugin_preview.dart';
import 'document_scan_overlay.dart';
import 'native_camera_preview.dart';
import 'immersive_controls.dart';
import 'immersive_glass.dart';
import '../i18n/text_scope.dart';

// The controls (top bar, hint pill, bottom row) are shared with photo mode
// and live in immersive_controls.dart; their keys and captions are exported
// from here too, so the scan's callers and tests read them where they always
// have.
export 'immersive_controls.dart'
    show
        kDocumentHintKey,
        kDocumentShutterKey,
        kDocumentTorchKey,
        kDocumentUploadKey,
        kDocumentTopBarKey,
        kDocumentBackKey,
        kDocumentSideBadgeKey,
        kUploadCaption,
        kTorchCaptionOff,
        kTorchCaptionOn,
        kViewfinderSpinnerSize;

/// The document camera viewfinder: live feed + guide overlay + shutter.
///
/// The feed comes from one of two sources, in order:
///   * [nativeTextureId] — Android's native CameraX camera (the normal path
///     there). Upright from the first frame, nothing to cover.
///   * [controller] — the Flutter camera plugin (iOS, and Android's fallback),
///     rendered through [DocumentPluginPreview] with its rotation workarounds.
class DocumentViewfinder extends StatelessWidget {
  /// Flutter camera-plugin controller — iOS, or the Android fallback.
  final CameraController? controller;

  /// Android native camera texture + its buffer size (null off that path).
  final int? nativeTextureId;
  final int nativePreviewW;
  final int nativePreviewH;

  final bool isLoading;
  final String? error;
  final bool isBack;
  final bool isProcessing;
  final double guideAspect;

  /// The free band between the top controls and the bottom bar, which an
  /// upright guide (a turned NIN slip) fills. Shared with the crop, so it is
  /// worked out once by the screen and handed down.
  final DocumentGuideBand? guideBand;
  final VoidCallback? onCapture;

  /// Why the shutter is disabled, read out by screen readers (the corners
  /// rule's hint). Null when there is nothing to explain.
  final String? shutterDisabledReason;

  /// Torch controls. Null [onToggleTorch] hides the button (no flash unit).
  final bool torchOn;
  final VoidCallback? onToggleTorch;

  /// Auto-capture framing state + dwell progress, driving the scan overlay.
  final DocumentFraming framing;
  final double scanProgress;

  /// Live instruction for the user, and the document's own name to put in it.
  final DocumentHint hint;
  final String hintLabel;

  /// The document being captured, and where it is from — shown in-frame,
  /// because full-screen took away the header that used to say so.
  final IdTypeConfig? idType;
  final String? country;

  /// Off once the turn-over prompt has already shown this side.
  final bool showSpecimen;

  /// Stands in for the sheet's back control, which the full-screen camera
  /// hides.
  final VoidCallback? onBack;

  /// "Upload a photo instead": the escape hatch, which must survive losing the
  /// chrome that used to host it. The bottom row's left button; null leaves
  /// that slot empty.
  final VoidCallback? onUpload;

  const DocumentViewfinder({
    super.key,
    required this.controller,
    required this.isLoading,
    required this.error,
    required this.isBack,
    required this.isProcessing,
    required this.guideAspect,
    this.guideBand,
    required this.onCapture,
    this.shutterDisabledReason,
    this.torchOn = false,
    this.onToggleTorch,
    this.nativeTextureId,
    this.nativePreviewW = 0,
    this.nativePreviewH = 0,
    this.framing = DocumentFraming.none,
    this.scanProgress = 0,
    this.hint = DocumentHint.searching,
    this.hintLabel = 'document',
    this.idType,
    this.country,
    this.showSpecimen = true,
    this.onBack,
    this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    // The feed runs under the system bars on purpose, so the controls are
    // inset by the real intrusions — read from the VIEW, not from MediaQuery.
    //
    // The flow is presented with showModalBottomSheet(useSafeArea: false),
    // which Flutter wraps in MediaQuery.removePadding(removeTop: true). That
    // zeroes `padding.top` AND reduces `viewPadding.top` by the same amount
    // (viewPadding.top - padding.top), so BOTH read zero here and the back
    // button and side badge end up underneath the status bar. Going to the
    // view gives the physical inset whatever any ancestor has done to the
    // inherited MediaQuery — which is what a full-bleed overlay actually needs.
    //
    // The screen's guide band (documentGuideBand) reads the same insets, so the
    // controls drawn here and the space the band keeps clear are one layout
    // (config/immersive_layout.dart).
    final insets = MediaQueryData.fromView(View.of(context)).viewPadding;

    // An upright guide is a turned document (config/document_turn.dart).
    final turned = guideAspect < 1;
    final tone = immersiveHintTone(
      hint: hint,
      framing: framing,
      blocked: shutterDisabledReason != null,
    );

    final stack = Stack(
      fit: StackFit.expand,
      children: [
        _buildFeed(),

        // The sample document, under the guide so the corners sit on its
        // edges. Keyed by side so turning over shows the other face.
        if (showSpecimen)
          Positioned.fill(
            child: DocumentGhost(
              key: ValueKey(isBack),
              aspect: guideAspect,
              band: guideBand,
              accent: context.myazaColors.primary,
              subject: DocumentSpecimenSubject(
                idType: idType?.key,
                title: specimenTitle(idType?.key, hintLabel),
                country: country == null || country!.isEmpty
                    ? null
                    : countryLabel(country!),
                side: isBack ? SpecimenSide.back : SpecimenSide.front,
              ),
              documentFound: framing != DocumentFraming.none &&
                  framing != DocumentFraming.wrongShape,
            ),
          ),

        // The ONLY guide. It draws the scrim, outline, corners and all the
        // auto-capture feedback from one rect (config/document_guide.dart),
        // which the post-shutter crop shares. An earlier second painter drew
        // its own geometry — two misaligned rectangles, and the user aimed
        // at the wrong one.
        Positioned.fill(
          child: DocumentScanOverlay(
            framing: framing,
            progress: scanProgress,
            aspect: guideAspect,
            band: guideBand,
          ),
        ),

        // Back, document and side on one row. Back stands in for the
        // sheet's own control, which is gone in fill mode: a camera with no
        // way out is a trap.
        Positioned(
          key: kDocumentTopBarKey,
          top: immersiveTopBarTop(insets.top),
          left: 0,
          right: 0,
          height: kImmersiveTopBarHeight,
          child: ImmersiveTopBar(
            onBack: onBack,
            country: country,
            documentLabel: shortDocumentLabel(idType, hintLabel),
            isBack: isBack,
          ),
        ),

        // The live instruction from the framing gate, under the top bar.
        if (!turned)
          Positioned(
            top: immersiveHintTop(insets.top),
            left: 0,
            right: 0,
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth:
                          constraints.maxWidth * kDocumentGuideWidthFraction),
                  child: ImmersiveHintPill(
                    key: kDocumentHintKey,
                    text: documentHintText(hint, label: hintLabel),
                    tone: tone,
                  ),
                ),
              ),
            ),
          ),

        // A turned guide (a NIN slip on a phone held upright) is framed by
        // turning the phone a quarter anticlockwise, so the hint turns with
        // the sample document and reads upright in that hold: along the
        // guide's left edge, which is then its bottom edge. The bottom row
        // stays where the thumb is.
        if (turned)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final guide = documentGuideRect(
                    constraints.biggest, guideAspect,
                    band: guideBand);
                return Stack(
                  children: [
                    Positioned(
                      left: 0,
                      width: guide.left,
                      top: guide.top,
                      height: guide.height,
                      child: Center(
                        child: RotatedBox(
                          key: kDocumentHintKey,
                          quarterTurns: kTurnedHintQuarterTurns,
                          child: ImmersiveHintPill(
                            text: documentHintText(hint, label: hintLabel),
                            tone: tone,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

        // Upload, shutter and torch in three equal slots, so the shutter
        // stays centred whether or not the side buttons are shown.
        Positioned(
          left: kImmersiveSideMargin,
          right: kImmersiveSideMargin,
          bottom: insets.bottom + kImmersiveBottomOffset,
          height: kImmersiveBottomRowHeight,
          child: ImmersiveBottomRow(
            onUpload: onUpload,
            uploadLabel:
                context.verificationText('uploadDocument.camera.uploadInstead'),
            // Visible through a capture, as the shutter is; a pick mid-capture
            // would race the still.
            uploadEnabled: !isProcessing,
            onCapture: onCapture,
            busy: isProcessing,
            progress: scanProgress,
            disabledReason: shutterDisabledReason,
            torchOn: torchOn,
            onToggleTorch: onToggleTorch,
          ),
        ),
      ],
    );

    // Fill whatever room there is — but survive being handed none.
    //
    // The camera normally owns the whole screen, so expanding is right. On the
    // frames before the immersive flag flips, though, the step is still inside
    // the sheet's scroll view, which offers INFINITE height; SizedBox.expand
    // asserts there and the whole subtree fails to lay out. A camera preview is
    // not worth crashing a screen over, so an unbounded parent gets a sensible
    // height instead of an exception.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight) return SizedBox.expand(child: stack);
        final fallback = MediaQuery.sizeOf(context).height;
        return SizedBox(
          width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
          height: fallback,
          child: stack,
        );
      },
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
      return DocumentPluginPreview(ctrl, isCapturing: isProcessing);
    }
    return ImmersiveViewfinderPlaceholder(isLoading: isLoading, error: error);
  }
}

/// Clockwise quarter turns of the hint beside a turned guide: one, as the
/// sample document is drawn (its top edge facing the right of the screen).
const int kTurnedHintQuarterTurns = 1;
