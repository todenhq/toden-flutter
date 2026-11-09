import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/immersive_layout.dart';
import '../config/theme.dart';
import 'document_info_pill.dart';
import 'icons/icons.dart';
import 'immersive_glass.dart';
import 'ui_spinner.dart';

// ─── The full-screen camera's controls ───────────────────────────────────────
//
// The top bar, the instruction pill and the bottom row that the document scan
// (document_viewfinder.dart) and photo mode (photo_viewfinder.dart) both draw
// over the live feed. One set of widgets, so the two cameras cannot drift apart:
// change a control here and both change together. The numbers they are laid out
// by live in config/immersive_layout.dart.
//
// Mirrors the React Native SDK's components/viewfinder/ImmersiveControls.tsx
// and ImmersiveBottomBar.tsx.

/// Keys for the controls whose overlap is a real (and once-shipped) bug: the
/// hint sat behind the shutter. Layout tests target these.
const kDocumentHintKey = ValueKey('kyc.document.hint');
const kDocumentShutterKey = ValueKey('kyc.document.shutter');
const kDocumentTorchKey = ValueKey('kyc.document.torch');
const kDocumentUploadKey = ValueKey('kyc.document.upload');
const kDocumentTopBarKey = ValueKey('kyc.document.topBar');
const kDocumentBackKey = ValueKey('kyc.document.back');
const kDocumentSideBadgeKey = ValueKey('kyc.document.sideBadge');

/// Photo mode's close button, drawn where the scan draws its side badge.
const kImmersiveCloseKey = ValueKey('kyc.camera.close');

// Short captions under the side buttons. Hard-coded beside the other fixed
// camera strings ("Capture photo", "Go back"): a catalogue key would have to be
// added to the shared customisable-texts contract, which every SDK must match.
// The React Native SDK's ImmersiveBottomBar uses the same words.
const String kUploadCaption = 'Upload';
const String kTorchCaptionOff = 'Light';
const String kTorchCaptionOn = 'Light on';

/// The scan's upload hint, read out by screen readers.
const String kDocumentUploadHint =
    'Choose a photo of your document instead of using the camera.';

/// Side of the spinner on the dark frame while the camera starts, the React
/// Native SDK's small spinner. UiSpinner fills the box it is given, and a bare
/// one under a full-screen Center grew to the width of the phone.
const double kViewfinderSpinnerSize = 20;

/// Grows the 52 side buttons to a 60 target.
const double _kSideHitSlop = 4;

/// Calls [builder] with whether the pointer is down on it: the controls change
/// colour or opacity while pressed, never their layout.
class _Pressable extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget Function(bool pressed) builder;

  const _Pressable({required this.onTap, required this.builder});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      child: widget.builder(enabled && _pressed),
    );
  }
}

/// The glass every top-bar item sits on.
BoxDecoration _glass({Color color = ImmersiveGlass.fill}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(UiRadius.full),
      border: Border.all(color: ImmersiveGlass.border),
    );

enum _TopBarSlot { back, pill, right }

/// Back, document and side on one row. The document pill is centred on the
/// screen and is the item that gives way on a narrow phone: it may use the
/// width left between the two sides (the wider of them, mirrored, so it stays
/// centred), and truncates its label past that. The React Native SDK's TopBar.
///
/// In photo mode there is no side to name: [isBack] is null, and [onClose]
/// puts the close button where the side badge goes. With neither, the right
/// of the row is empty.
class ImmersiveTopBar extends StatelessWidget {
  final VoidCallback? onBack;
  final String? country;
  final String documentLabel;

  /// The scan's side badge: front (false) or back (true). Null leaves it out.
  final bool? isBack;

  /// Photo mode: close the whole flow. Drawn in place of the side badge.
  final VoidCallback? onClose;

  const ImmersiveTopBar({
    super.key,
    required this.onBack,
    required this.country,
    required this.documentLabel,
    this.isBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final Widget? right = onClose != null
        ? _CloseButton(onTap: onClose!)
        : (isBack == null ? null : _SideBadge(isBack: isBack!));
    return CustomMultiChildLayout(
      delegate: _TopBarLayout(),
      children: [
        if (onBack != null)
          LayoutId(id: _TopBarSlot.back, child: _BackButton(onTap: onBack!)),
        if (documentLabel.isNotEmpty)
          LayoutId(
            id: _TopBarSlot.pill,
            child: DocumentInfoPill(label: documentLabel, country: country),
          ),
        if (right != null) LayoutId(id: _TopBarSlot.right, child: right),
      ],
    );
  }
}

class _TopBarLayout extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final loose = BoxConstraints.loose(size);
    var rightWidth = 0.0;
    if (hasChild(_TopBarSlot.right)) {
      rightWidth = layoutChild(_TopBarSlot.right, loose).width;
      positionChild(_TopBarSlot.right,
          Offset(size.width - kImmersiveSideMargin - rightWidth, 0));
    }
    if (hasChild(_TopBarSlot.back)) {
      layoutChild(_TopBarSlot.back, loose);
      positionChild(_TopBarSlot.back, const Offset(kImmersiveSideMargin, 0));
    }
    if (hasChild(_TopBarSlot.pill)) {
      final sideWidth = math.max(kImmersiveTopBarHeight, rightWidth);
      final pillMax = math.max(
        kImmersiveTopBarHeight,
        size.width -
            2 * (kImmersiveSideMargin + sideWidth + kImmersiveTopBarGap),
      );
      final pill = layoutChild(
        _TopBarSlot.pill,
        BoxConstraints(maxWidth: pillMax, maxHeight: size.height),
      );
      positionChild(_TopBarSlot.pill, Offset((size.width - pill.width) / 2, 0));
    }
  }

  @override
  bool shouldRelayout(_TopBarLayout oldDelegate) => false;
}

/// A round glass button on the top bar.
class _TopBarButton extends StatelessWidget {
  final Key surfaceKey;
  final String label;
  final UiIconData icon;
  final VoidCallback onTap;

  const _TopBarButton({
    required this.surfaceKey,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: _Pressable(
        onTap: onTap,
        builder: (pressed) => Container(
          key: surfaceKey,
          width: kImmersiveTopBarHeight,
          height: kImmersiveTopBarHeight,
          alignment: Alignment.center,
          decoration: _glass(
              color: pressed ? ImmersiveGlass.pressed : ImmersiveGlass.fill),
          child: UiIcon(icon, size: 20, color: ImmersiveGlass.text),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) => _TopBarButton(
        surfaceKey: kDocumentBackKey,
        label: 'Go back',
        icon: UiIcons.arrowLeft,
        onTap: onTap,
      );
}

/// Leaves the whole flow, as the sheet header's X does.
class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) => _TopBarButton(
        surfaceKey: kImmersiveCloseKey,
        label: 'Close',
        icon: UiIcons.x,
        onTap: onTap,
      );
}

/// "FRONT" / "BACK": which face of the document is expected right now.
class _SideBadge extends StatelessWidget {
  final bool isBack;

  const _SideBadge({required this.isBack});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: isBack ? 'Back of the document' : 'Front of the document',
      excludeSemantics: true,
      child: Container(
        key: kDocumentSideBadgeKey,
        height: kImmersiveTopBarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: _glass(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryOnDark(context.myazaColors.primary),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isBack ? 'BACK' : 'FRONT',
              style: const TextStyle(
                color: ImmersiveGlass.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An instruction on the glass. The icon's colour carries the state, so the
/// words stay white and legible over any scene.
class ImmersiveHintPill extends StatelessWidget {
  final String text;
  final ImmersiveHintTone tone;

  const ImmersiveHintPill({
    super.key,
    required this.text,
    required this.tone,
  });

  static const Map<ImmersiveHintTone, UiIconData> _icons = {
    ImmersiveHintTone.neutral: UiIcons.scanLine,
    ImmersiveHintTone.action: UiIcons.info,
    ImmersiveHintTone.ready: UiIcons.circleCheck,
    ImmersiveHintTone.warning: UiIcons.circleAlert,
  };

  @override
  Widget build(BuildContext context) {
    final toneColour = switch (tone) {
      ImmersiveHintTone.ready => UiColors.success,
      ImmersiveHintTone.warning => UiColors.warning,
      ImmersiveHintTone.action => primaryOnDark(context.myazaColors.primary),
      ImmersiveHintTone.neutral => const Color.fromRGBO(255, 255, 255, 0.7),
    };
    // A polite live region: a new instruction is read out as it arrives.
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: kImmersiveHintPaddingV),
        decoration: _glass(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            UiIcon(_icons[tone]!, size: 16, color: toneColour),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                maxLines: kImmersiveHintMaxLines,
                overflow: TextOverflow.ellipsis,
                strutStyle: const StrutStyle(
                  fontSize: 15,
                  height: kImmersiveHintLineHeight / 15,
                  forceStrutHeight: true,
                ),
                style: const TextStyle(
                  color: ImmersiveGlass.text,
                  fontSize: 15,
                  height: kImmersiveHintLineHeight / 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Upload, shutter and torch in three equal slots, so the shutter stays
/// centred whether or not the side buttons are shown. Positioned by the
/// caller, at the full-screen camera's bottom row.
class ImmersiveBottomRow extends StatelessWidget {
  /// The left button. Null leaves that slot empty.
  final VoidCallback? onUpload;

  /// Read out with the upload button: what choosing a photo instead means.
  final String uploadHint;

  /// The upload button's spoken label.
  final String uploadLabel;

  /// Visible through a capture, as the shutter is, but not tappable: a pick
  /// mid-capture would race the still.
  final bool uploadEnabled;

  final VoidCallback? onCapture;
  final bool busy;
  final double progress;
  final String? disabledReason;

  /// The shutter's glyph: the scan line for a scan, a camera for a photo.
  final UiIconData shutterIcon;

  /// Torch controls. Null [onToggleTorch] hides the button (no flash unit).
  final bool torchOn;
  final VoidCallback? onToggleTorch;

  const ImmersiveBottomRow({
    super.key,
    required this.onUpload,
    required this.uploadLabel,
    this.uploadHint = kDocumentUploadHint,
    this.uploadEnabled = true,
    required this.onCapture,
    this.busy = false,
    this.progress = 0,
    this.disabledReason,
    this.shutterIcon = UiIcons.scanLine,
    this.torchOn = false,
    this.onToggleTorch,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _slot(onUpload == null
            ? null
            : _SideButton(
                key: kDocumentUploadKey,
                icon: UiIcons.image,
                caption: kUploadCaption,
                label: uploadLabel,
                hint: uploadHint,
                onTap: uploadEnabled ? onUpload : null,
              )),
        _slot(_ShutterButton(
          key: kDocumentShutterKey,
          onCapture: onCapture,
          busy: busy,
          progress: progress,
          disabledReason: disabledReason,
          icon: shutterIcon,
        )),
        _slot(onToggleTorch == null
            ? null
            : _SideButton(
                key: kDocumentTorchKey,
                icon: torchOn ? UiIcons.zap : UiIcons.zapOff,
                caption: torchOn ? kTorchCaptionOn : kTorchCaptionOff,
                label: torchOn ? 'Turn off the torch' : 'Turn on the torch',
                lit: torchOn,
                onTap: onToggleTorch,
              )),
      ],
    );
  }

  /// One of the bottom row's three equal slots, as tall as the shutter.
  static Widget _slot(Widget? child) => Expanded(
        child: SizedBox(
          height: kImmersiveShutterSize,
          child: child == null ? null : Center(child: child),
        ),
      );
}

/// A round glass button beside the shutter, with its caption hanging below.
/// Laid out at its 60 target, the 52 button centred in it, so the caption
/// starts 6 under the button's edge.
class _SideButton extends StatelessWidget {
  final UiIconData icon;
  final String caption;
  final String label;
  final String? hint;

  /// Solid white when on, so "on" never depends on the scene behind it. Null
  /// for a button that is not a toggle.
  final bool? lit;
  final VoidCallback? onTap;

  const _SideButton({
    super.key,
    required this.icon,
    required this.caption,
    required this.label,
    this.hint,
    this.lit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const target = kImmersiveSideButtonSize + 2 * _kSideHitSlop;
    final on = lit ?? false;
    return SizedBox.square(
      dimension: target,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Semantics(
              button: true,
              label: label,
              hint: hint,
              selected: lit,
              enabled: onTap != null,
              excludeSemantics: true,
              onTap: onTap,
              child: _Pressable(
                onTap: onTap,
                builder: (pressed) => Center(
                  child: Container(
                    width: kImmersiveSideButtonSize,
                    height: kImmersiveSideButtonSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: on ? Colors.white : ImmersiveGlass.border),
                      color: on
                          ? (pressed
                              ? const Color.fromRGBO(255, 255, 255, 0.82)
                              : Colors.white)
                          : (pressed
                              ? ImmersiveGlass.pressed
                              : ImmersiveGlass.fill),
                    ),
                    child: UiIcon(
                      icon,
                      size: 22,
                      color: on
                          ? context.myazaColors.primary
                          : ImmersiveGlass.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top:
                _kSideHitSlop + kImmersiveSideButtonSize + kImmersiveCaptionGap,
            left: -kImmersiveSideButtonSize,
            right: -kImmersiveSideButtonSize,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  strutStyle: const StrutStyle(
                    fontSize: 12,
                    height: kImmersiveCaptionLineHeight / 12,
                    forceStrutHeight: true,
                  ),
                  style: const TextStyle(
                    color: ImmersiveGlass.caption,
                    fontSize: 12,
                    height: kImmersiveCaptionLineHeight / 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shutter: a white ring around the brand disc, the dwell drawn around it.
class _ShutterButton extends StatelessWidget {
  final VoidCallback? onCapture;
  final bool busy;
  final double progress;
  final String? disabledReason;
  final UiIconData icon;

  const _ShutterButton({
    super.key,
    required this.onCapture,
    required this.busy,
    required this.progress,
    required this.icon,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final enabled = onCapture != null && !busy;
    // Grey while the camera, or the corner gate, is holding it; the brand
    // colour while busy too, under the spinner, as the React Native SDK.
    final ready = onCapture != null || busy;
    final reason = enabled ? null : disabledReason;
    const ring = kImmersiveShutterSize + 8;
    return Semantics(
      button: true,
      enabled: enabled,
      label: reason == null ? 'Capture photo' : 'Capture photo. $reason',
      excludeSemantics: true,
      onTap: enabled ? onCapture : null,
      child: SizedBox.square(
        dimension: kImmersiveShutterSize,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // The dwell, drawn around the shutter: someone holding steady can
            // see it working instead of wondering whether to press.
            if (progress > 0 && progress < 1)
              Positioned(
                top: -4,
                left: -4,
                width: ring,
                height: ring,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _DwellRingPainter(
                        progress: progress, color: colors.primary),
                  ),
                ),
              ),
            _Pressable(
              onTap: enabled ? onCapture : null,
              builder: (pressed) => Opacity(
                opacity: busy ? 0.6 : (pressed ? 0.85 : 1),
                child: Container(
                  width: kImmersiveShutterSize,
                  height: kImmersiveShutterSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Container(
                    width: 62,
                    height: 62,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ready ? colors.primary : colors.gray400,
                    ),
                    child: busy
                        ? const SizedBox.square(
                            dimension: kViewfinderSpinnerSize,
                            child:
                                UiSpinner(color: Colors.white, strokeWidth: 2),
                          )
                        : UiIcon(icon, size: 26, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dwell arc: radius 40, 3 wide, from 12 o'clock clockwise.
class _DwellRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _DwellRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: size.center(Offset.zero), radius: 40),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_DwellRingPainter old) =>
      old.progress != progress || old.color != color;
}

/// The dark frame before the feed arrives: a small spinner while the camera
/// starts, or "Camera unavailable" once it has failed.
class ImmersiveViewfinderPlaceholder extends StatelessWidget {
  final bool isLoading;
  final String? error;

  const ImmersiveViewfinderPlaceholder(
      {super.key, required this.isLoading, this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111111),
      child: Center(
        child: error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const UiIcon(UiIcons.videoOff,
                      color: Colors.white54, size: 36),
                  const SizedBox(height: UiSpacing.sm),
                  Text('Camera unavailable',
                      style: context.myazaText.bodySmall
                          .copyWith(color: Colors.white70)),
                ],
              )
            : SizedBox.square(
                dimension: kViewfinderSpinnerSize,
                child: UiSpinner(
                    color: context.myazaColors.primary, strokeWidth: 2),
              ),
      ),
    );
  }
}
