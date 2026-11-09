import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, SystemUiOverlayStyle;
import 'package:image/image.dart' as img;

import '../config/document_crop_geometry.dart';
import '../config/document_turn.dart';
import '../config/immersive_layout.dart';
import '../config/theme.dart';
import '../services/image_service.dart' show rotateJpegClockwise;
import 'icons/icons.dart';
import 'immersive_glass.dart';
import '../i18n/text_scope.dart';
import 'ui_spinner.dart';

// ─── Gallery-photo cropper ────────────────────────────────────────────────────
//
// Shown after "Upload a photo instead": an interactive ID-card crop box over the
// picked image, so a gallery photo arrives at the same framing the camera's
// guide would have produced. It looks like the full-screen scan screen it opens
// from: a black editor stage, the same dark glass controls, the same 8pt rhythm
// (config/immersive_layout.dart).
//
// A NIN slip's box stands upright on a stage taller than wide, as its guide
// does (config/document_turn.dart), and the crop is turned back to landscape
// before it is returned, as an upright capture is. Rotate turns the photo a
// quarter clockwise at a time, so a sideways photo can be stood up to fit the
// box, and the box is fitted afresh to the turned photo.
// Geometry: config/document_crop_geometry.dart.
//
// Mirrors the React Native SDK's components/DocumentCropper.tsx: change both
// together.

const double _kHandleRadius = 28; // touch radius for the corner handles (a 56 target)
const double _kEdgeTarget = 22; // half of the 44 target around each mid-edge bar
const double _kArm = 22; // corner-bracket arm length
const double _kHandleThickness = 4;
const double _kEdgeBar = 20; // mid-edge bar length
const Duration _kGridFade = Duration(milliseconds: 150);
const Duration _kTurn = Duration(milliseconds: 280); // Rotate's quarter turn on screen
const Duration _kFrameOut = Duration(milliseconds: 120); // the crop frame leaving as a turn starts
const Duration _kFrameIn = Duration(milliseconds: 150); // and returning, refitted, as it ends

const Color _kDim = Color.fromRGBO(0, 0, 0, 0.6);
const Color _kGrid = Color.fromRGBO(255, 255, 255, 0.35);
const Color _kHelp = Color.fromRGBO(255, 255, 255, 0.7);

// Fixed strings beside the existing hard-coded "Cancel", as the scan screen's
// captions are: a catalogue key would have to join the shared customisable-texts
// contract that every SDK must match.
const String _kHelpText = 'Drag the corners to the edges of your ID';
const String _kRotateHint = 'Turns the photo a quarter turn clockwise.';

/// The title: the document by name when it is known.
String cropperTitle(String? documentLabel) {
  final label = documentLabel?.trim() ?? '';
  return label.isNotEmpty
      ? 'Fit your $label in the frame'
      : 'Fit your ID in the frame';
}

class _CropParams {
  final Uint8List bytes;
  final int srcX;
  final int srcY;
  final int srcW;
  final int srcH;

  const _CropParams({
    required this.bytes,
    required this.srcX,
    required this.srcY,
    required this.srcW,
    required this.srcH,
  });
}

// Top-level so compute() can run it in a separate isolate.
Uint8List _doCropImage(_CropParams p) {
  final decoded = img.decodeImage(p.bytes);
  if (decoded == null) throw Exception('Could not decode image');
  final baked = img.bakeOrientation(decoded);
  final sw = p.srcW.clamp(1, baked.width - p.srcX);
  final sh = p.srcH.clamp(1, baked.height - p.srcY);
  final cropped = img.copyCrop(baked, x: p.srcX, y: p.srcY, width: sw, height: sh);
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
}

// ─── Crop handle ──────────────────────────────────────────────────────────────

enum _CropHandle { none, move, tl, tr, bl, br, t, r, b, l }

/// The photo as shown when Rotate was pressed, turning over the stage.
class _Turning {
  final Uint8List bytes;
  final Rect rect;
  final double scale;
  final bool ready;

  const _Turning({
    required this.bytes,
    required this.rect,
    required this.scale,
    this.ready = false,
  });

  _Turning get asReady =>
      _Turning(bytes: bytes, rect: rect, scale: scale, ready: true);
}

// ─── Document cropper screen ──────────────────────────────────────────────────

class DocumentCropperScreen extends StatefulWidget {
  final Uint8List imageBytes;

  /// The document's own width over height (landscape). Defaults to an ID card;
  /// a NIN slip is longer, and its box stands upright on a tall stage.
  final double aspect;

  /// The selected ID type's name, for the title ("Fit your NIN slip in the
  /// frame").
  final String? documentLabel;

  const DocumentCropperScreen({
    super.key,
    required this.imageBytes,
    this.aspect = 85.6 / 53.98,
    this.documentLabel,
  });

  /// A camera editor's stage: the photo reads against pure black.
  static const Color stage = Color(0xFF000000);

  @override
  State<DocumentCropperScreen> createState() => _DocumentCropperScreenState();
}

class _DocumentCropperScreenState extends State<DocumentCropperScreen>
    with TickerProviderStateMixin {
  // The box's shape, decided once from the first stage this screen measured,
  // so turning the phone mid-crop does not reshape a box already placed.
  ({double aspect, bool turned})? _guide;
  double get _idAR => _guide?.aspect ?? widget.aspect;

  // The picked photo's own size, before any Rotate.
  Size? _original;
  Size? _stage;

  // Clockwise quarter turns from Rotate, and the photo as turned. Turned from
  // the original each time, so going round never re-encodes a re-encode.
  int _turns = 0;
  late Uint8List _shownBytes = widget.imageBytes;
  bool _isRotating = false;
  bool _isProcessing = false;

  /// Null until placed, and again after a Rotate until it is refitted.
  Rect? _crop;

  Size? get _natural =>
      _original == null ? null : turnedSize(_original!, _turns);

  /// Letterboxed inside the stage with a 16 margin, so no handle meets the
  /// screen edge.
  Rect? get _imgRect {
    final natural = _natural;
    final stage = _stage;
    if (natural == null || stage == null || natural.isEmpty || stage.isEmpty) {
      return null;
    }
    return insetContainRect(natural, stage);
  }

  // The rule-of-thirds grid shows only while a handle or the box is held.
  late final AnimationController _grid;
  _CropHandle _handle = _CropHandle.none;
  Offset _panStart = Offset.zero;
  Rect _cropAtPanStart = Rect.zero;

  // ── Rotate, animated ──────────────────────────────────────────────────────
  // The photo as shown turns a quarter on screen while the real turn is made
  // from the original in the background. The turning copy sits over the stage
  // and holds its final pose until the turned photo has loaded underneath,
  // then gives way to it: no snap, no blank frame. The crop frame fades out as
  // the turn starts and back in, refitted, as it ends. One turn at a time:
  // presses during a turn are ignored.
  _Turning? _turning;
  late final AnimationController _turn;
  late final AnimationController _frame;
  bool _turnBusy = false;
  bool _swapPending = false;
  VoidCallback? _spinStart;
  final List<Timer> _timers = [];

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _grid = AnimationController(vsync: this);
    _turn = AnimationController(vsync: this);
    _frame = AnimationController(vsync: this, value: 1);
    _loadOriginalSize();
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _grid.dispose();
    _turn.dispose();
    _frame.dispose();
    super.dispose();
  }

  Future<void> _loadOriginalSize() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      codec.dispose();
      if (mounted) setState(() => _original = size);
    } catch (_) {
      // Fall through: confirm is gated on the photo's size.
    }
  }

  void _later(VoidCallback fn, Duration after) {
    _timers.add(Timer(after, fn));
  }

  // Starts the on-screen turn, once the turning copy has drawn (or after a
  // short wait).
  void _startSpin() {
    final go = _spinStart;
    _spinStart = null;
    go?.call();
  }

  void _endTurn() {
    if (!_turnBusy || !mounted) return;
    _swapPending = false;
    _spinStart = null;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    setState(() {
      _turning = null;
      _isRotating = false;
    });
    _turnBusy = false;
    // Back to rest, and the frame returns.
    _turn.value = 0;
    if (_reduceMotion) {
      _frame.value = 1;
    } else {
      _frame.animateTo(1, duration: _kFrameIn, curve: Curves.easeInOut);
    }
  }

  Future<void> _onRotate() async {
    final original = _original;
    final stage = _stage;
    final from = _imgRect;
    if (_turnBusy ||
        _isRotating ||
        _isProcessing ||
        original == null ||
        stage == null ||
        from == null) {
      return;
    }
    _turnBusy = true;
    HapticFeedback.lightImpact();
    final reduceMotion = _reduceMotion;
    final next = (_turns + 1) % 4;
    final to = insetContainRect(turnedSize(original, next), stage);
    setState(() {
      _isRotating = true;
      _turning = _Turning(
        bytes: _shownBytes,
        rect: from,
        scale: quarterTurnScale(from, to),
      );
    });
    if (reduceMotion) {
      _frame.value = 0;
    } else {
      _frame.animateTo(0, duration: _kFrameOut, curve: Curves.easeInOut);
    }

    final spun = Completer<void>();
    void done() {
      if (!spun.isCompleted) spun.complete();
    }

    _spinStart = () {
      if (!mounted) return done();
      setState(() => _turning = _turning?.asReady);
      // Reduced motion: no turn on screen, the photo is swapped once ready.
      if (reduceMotion) return done();
      _turn
          .animateTo(1, duration: _kTurn, curve: Curves.easeOutCubic)
          .whenCompleteOrCancel(done);
    };
    _later(_startSpin, const Duration(milliseconds: 250));

    // From the original each time, so going round never re-encodes a re-encode.
    Uint8List? turned;
    try {
      turned = next == 0
          ? widget.imageBytes
          : await rotateJpegClockwise(widget.imageBytes, next * 90);
    } catch (_) {
      turned = null;
    }
    await spun.future;
    if (!mounted) return;
    if (turned == null) {
      // The photo stays as it was; the person can still crop it.
      if (reduceMotion) return _endTurn();
      _turn
          .animateBack(0,
              duration: _kFrameOut * 1.5, curve: Curves.easeOutCubic)
          .whenCompleteOrCancel(_endTurn);
      return;
    }
    _swapPending = true;
    setState(() {
      _shownBytes = turned!;
      _turns = next;
      _crop = null;
    });
    // The turned photo's first frame ends the turn; this only guards a load
    // that never reports.
    _later(_endTurn, const Duration(milliseconds: 1500));
  }

  // ── Gesture handling ─────────────────────────────────────────────────────

  _CropHandle _hitTest(Offset p, Rect c) {
    bool near(Offset at) =>
        (p.dx - at.dx).abs() < _kEdgeTarget &&
        (p.dy - at.dy).abs() < _kEdgeTarget;
    if ((p - c.topLeft).distance < _kHandleRadius) return _CropHandle.tl;
    if ((p - c.topRight).distance < _kHandleRadius) return _CropHandle.tr;
    if ((p - c.bottomLeft).distance < _kHandleRadius) return _CropHandle.bl;
    if ((p - c.bottomRight).distance < _kHandleRadius) return _CropHandle.br;
    if (near(c.topCenter)) return _CropHandle.t;
    if (near(c.centerRight)) return _CropHandle.r;
    if (near(c.bottomCenter)) return _CropHandle.b;
    if (near(c.centerLeft)) return _CropHandle.l;
    if (c.inflate(8).contains(p)) return _CropHandle.move;
    return _CropHandle.none;
  }

  void _setDragging(bool dragging) {
    final to = dragging ? 1.0 : 0.0;
    if (_reduceMotion) {
      _grid.value = to;
    } else {
      _grid.animateTo(to, duration: _kGridFade, curve: Curves.easeInOut);
    }
  }

  void _onPanDown(DragDownDetails d) {
    final c = _crop;
    // No dragging a frame that is hidden for a turn.
    if (c == null || _turnBusy) {
      _handle = _CropHandle.none;
      return;
    }
    _handle = _hitTest(d.localPosition, c);
    _panStart = d.localPosition;
    _cropAtPanStart = c;
    if (_handle != _CropHandle.none) {
      _setDragging(true);
      HapticFeedback.lightImpact();
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final bounds = _imgRect;
    if (_handle == _CropHandle.none || bounds == null) return;
    final dx = d.localPosition.dx - _panStart.dx;
    final dy = d.localPosition.dy - _panStart.dy;
    final s = _cropAtPanStart;
    final ar = _idAR;
    final bottom = s.bottom;

    final Rect next;
    switch (_handle) {
      case _CropHandle.none:
        return;
      case _CropHandle.move:
        next = s.translate(dx, dy);
      case _CropHandle.br:
        final w = s.width + dx;
        next = Rect.fromLTWH(s.left, s.top, w, w / ar);
      case _CropHandle.bl:
        final w = s.width - dx;
        next = Rect.fromLTWH(s.left + dx, s.top, w, w / ar);
      case _CropHandle.tr:
        final w = s.width + dx;
        final h = w / ar;
        next = Rect.fromLTWH(s.left, bottom - h, w, h);
      case _CropHandle.tl:
        final w = s.width - dx;
        final h = w / ar;
        next = Rect.fromLTWH(s.left + dx, bottom - h, w, h);
      // A mid-edge bar moves its own edge; the box keeps its shape, so it
      // grows or shrinks about the middle of the opposite edge.
      case _CropHandle.r:
        final w = s.width + dx;
        final h = w / ar;
        next = Rect.fromLTWH(s.left, s.top + (s.height - h) / 2, w, h);
      case _CropHandle.l:
        final w = s.width - dx;
        final h = w / ar;
        next = Rect.fromLTWH(s.left + dx, s.top + (s.height - h) / 2, w, h);
      case _CropHandle.b:
        final h = s.height + dy;
        final w = h * ar;
        next = Rect.fromLTWH(s.left + (s.width - w) / 2, s.top, w, h);
      case _CropHandle.t:
        final h = s.height - dy;
        final w = h * ar;
        next = Rect.fromLTWH(s.left + (s.width - w) / 2, bottom - h, w, h);
    }

    setState(() => _crop = clampCropRect(next, bounds, ar));
  }

  void _onPanEnd() {
    if (_handle == _CropHandle.none) return;
    _handle = _CropHandle.none;
    _setDragging(false);
  }

  // ── Confirm: crop image in isolate, pop with result ──────────────────────

  Future<void> _onConfirm() async {
    final natural = _natural;
    final imgRect = _imgRect;
    final crop = _crop;
    if (natural == null || imgRect == null || crop == null || _isProcessing) {
      return;
    }
    setState(() => _isProcessing = true);

    final scaleX = natural.width / imgRect.width;
    final scaleY = natural.height / imgRect.height;

    final sx = ((crop.left - imgRect.left) * scaleX)
        .round()
        .clamp(0, natural.width.toInt() - 1);
    final sy = ((crop.top - imgRect.top) * scaleY)
        .round()
        .clamp(0, natural.height.toInt() - 1);
    final sw = (crop.width * scaleX).round();
    final sh = (crop.height * scaleY).round();

    try {
      // Rotate crops the turned photo, not the original.
      final cropped = await compute(
        _doCropImage,
        _CropParams(bytes: _shownBytes, srcX: sx, srcY: sy, srcW: sw, srcH: sh),
      );
      // An upright box is turned back to landscape, as an upright capture is.
      final result = _guide?.turned == true
          ? await rotateJpegClockwise(cropped, undoDegrees(null))
          : cropped;
      if (mounted) Navigator.of(context).pop<Uint8List>(result);
    } catch (_) {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    final insets = MediaQuery.paddingOf(context);
    final rotateLabel = context.verificationText('uploadDocument.crop.rotate');
    final confirmLabel = context.verificationText('uploadDocument.crop.confirm');
    final rotateDisabled = _crop == null || _isProcessing || _isRotating;
    final confirmDisabled = _crop == null || _isRotating || _isProcessing;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: DocumentCropperScreen.stage,
        body: Column(
          children: [
            // ── Top bar: close, the title, and an empty slot that keeps the
            // title centred.
            Padding(
              padding: EdgeInsets.fromLTRB(kImmersiveSideMargin,
                  insets.top + kImmersiveTopBarOffset, kImmersiveSideMargin, 0),
              child: SizedBox(
                height: kImmersiveTopBarHeight,
                child: Row(
                  children: [
                    _Pressable(
                      label: 'Cancel',
                      onTap: () =>
                          Navigator.of(context).pop<Uint8List?>(null),
                      builder: (pressed) => _GlassRound(
                        size: kImmersiveTopBarHeight,
                        pressed: pressed,
                        child: const UiIcon(UiIcons.x,
                            size: 20, color: ImmersiveGlass.text),
                      ),
                    ),
                    const SizedBox(width: kImmersiveTopBarGap),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          cropperTitle(widget.documentLabel),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: text.bodyMedium.copyWith(
                            fontSize: 16,
                            height: 22 / 16,
                            fontWeight: FontWeight.w600,
                            color: ImmersiveGlass.text,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: kImmersiveTopBarGap),
                    const SizedBox.square(dimension: kImmersiveTopBarHeight),
                  ],
                ),
              ),
            ),

            // ── Image + crop overlay ─────────────────────────────────────────
            Expanded(
              child: LayoutBuilder(builder: (ctx, cons) => _buildStage(cons)),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(kImmersiveSideMargin, 0,
                  kImmersiveSideMargin, kImmersiveGuideGapAboveControls),
              child: Text(
                _kHelpText,
                textAlign: TextAlign.center,
                style: text.bodySmall.copyWith(
                  fontSize: 14,
                  height: 20 / 14,
                  color: _kHelp,
                ),
              ),
            ),

            // ── Bottom bar: Rotate as a round glass button, then the primary
            // action. The caption hangs below the round button; the row
            // reserves its space.
            Padding(
              padding: EdgeInsets.fromLTRB(
                kImmersiveSideMargin,
                0,
                kImmersiveSideMargin,
                kImmersiveCaptionGap +
                    kImmersiveCaptionLineHeight +
                    insets.bottom +
                    kImmersiveBottomOffset,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox.square(
                    dimension: kImmersiveSideButtonSize,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: _Pressable(
                            label: rotateLabel,
                            hint: _kRotateHint,
                            onTap: rotateDisabled ? null : _onRotate,
                            builder: (pressed) => Opacity(
                              opacity: rotateDisabled && !_isRotating ? 0.5 : 1,
                              // The photo turning is the feedback; no spinner
                              // over the icon.
                              child: _GlassRound(
                                size: kImmersiveSideButtonSize,
                                pressed: pressed,
                                child: const UiIcon(UiIcons.refreshCw,
                                    size: 22, color: ImmersiveGlass.text),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: kImmersiveSideButtonSize + kImmersiveCaptionGap,
                          left: -kImmersiveSideButtonSize,
                          right: -kImmersiveSideButtonSize,
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: Text(
                                rotateLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: text.bodySmall.copyWith(
                                  fontSize: 12,
                                  height: kImmersiveCaptionLineHeight / 12,
                                  fontWeight: FontWeight.w500,
                                  color: ImmersiveGlass.caption,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Pressable(
                      label: confirmLabel,
                      onTap: confirmDisabled ? null : _onConfirm,
                      builder: (pressed) => Opacity(
                        opacity: confirmDisabled && !_isProcessing
                            ? 0.5
                            : pressed
                                ? 0.85
                                : 1,
                        child: Container(
                          height: kImmersiveSideButtonSize,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: ShapeDecoration(
                            color: colors.primary,
                            shape: const StadiumBorder(),
                          ),
                          child: _isProcessing
                              ? SizedBox.square(
                                  dimension: 20,
                                  child: UiSpinner(color: colors.onPrimary),
                                )
                              : Text(
                                  confirmLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.label.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onPrimary,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStage(BoxConstraints cons) {
    final size = cons.biggest;
    if (size != _stage) _stage = size;
    if (size.width > 0 && size.height > 0) {
      _guide ??= documentCropGuide(widget.aspect, size.width / size.height);
    }
    final imgRect = _imgRect;
    if (_original == null || imgRect == null) {
      // UiSpinner fills whatever box it is given, so it is sized here; a bare
      // one in a Center drew as wide as the screen.
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: UiSpinner(color: Colors.white),
        ),
      );
    }
    // Place the box once the photo's rect and its shape are known (again after
    // a Rotate). The controls outside this builder read it, so they rebuild.
    if (_crop == null) {
      _crop = initialCropRect(imgRect, _idAR);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    final crop = _crop!;
    final turning = _turning;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: _onPanDown,
      onPanUpdate: _onPanUpdate,
      onPanEnd: (_) => _onPanEnd(),
      onPanCancel: _onPanEnd,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fromRect(
            rect: imgRect,
            child: Image.memory(
              _shownBytes,
              fit: BoxFit.contain,
              // Hidden under the turning copy until the turned photo has
              // drawn here.
              frameBuilder: (context, child, frame, _) {
                if (frame != null && _swapPending) {
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _endTurn());
                }
                return Opacity(
                  opacity: turning?.ready == true ? 0 : 1,
                  child: child,
                );
              },
            ),
          ),
          if (turning != null)
            Positioned.fromRect(
              rect: turning.rect,
              child: AnimatedBuilder(
                animation: _turn,
                builder: (context, child) {
                  final v = _turn.value;
                  return Transform.rotate(
                    angle: v * math.pi / 2,
                    child: Transform.scale(
                      scale: 1 + (turning.scale - 1) * v,
                      child: child,
                    ),
                  );
                },
                child: Image.memory(
                  turning.bytes,
                  fit: BoxFit.contain,
                  frameBuilder: (context, child, frame, _) {
                    if (frame != null && _spinStart != null) {
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _startSpin());
                    }
                    return child;
                  },
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: _frame,
                child: CustomPaint(
                  painter: _CropOverlayPainter(
                    imgRect: imgRect,
                    cropRect: crop,
                    grid: _grid,
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

// ─── Controls ─────────────────────────────────────────────────────────────────

/// A button that redraws while held: a background change only, never a layout
/// shift.
class _Pressable extends StatefulWidget {
  final String label;
  final String? hint;
  final VoidCallback? onTap;
  final Widget Function(bool pressed) builder;

  const _Pressable({
    required this.label,
    this.hint,
    required this.onTap,
    required this.builder,
  });

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: widget.label,
      hint: widget.hint,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        child: widget.builder(enabled && _pressed),
      ),
    );
  }
}

/// A round control on the scan screen's dark glass.
class _GlassRound extends StatelessWidget {
  final double size;
  final bool pressed;
  final Widget child;

  const _GlassRound({
    required this.size,
    required this.pressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: pressed ? ImmersiveGlass.pressed : ImmersiveGlass.fill,
        border: Border.all(color: ImmersiveGlass.border),
      ),
      child: child,
    );
  }
}

// ─── Crop overlay painter ─────────────────────────────────────────────────────

class _CropOverlayPainter extends CustomPainter {
  final Rect imgRect;
  final Rect cropRect;

  /// The thirds grid's opacity: shown only while dragging.
  final Animation<double> grid;

  _CropOverlayPainter({
    required this.imgRect,
    required this.cropRect,
    required this.grid,
  }) : super(repaint: grid);

  @override
  void paint(Canvas canvas, Size size) {
    final c = cropRect;

    // ── 4 dim rects around the crop window ──────────────────────────────────
    final dim = Paint()..color = _kDim;
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, c.top), dim);
    canvas.drawRect(Rect.fromLTRB(0, c.bottom, size.width, size.height), dim);
    canvas.drawRect(Rect.fromLTRB(0, c.top, c.left, c.bottom), dim);
    canvas.drawRect(Rect.fromLTRB(c.right, c.top, size.width, c.bottom), dim);

    // ── Rule-of-thirds grid, only while dragging (hairline) ─────────────────
    final g = grid.value;
    if (g > 0) {
      final line = Paint()
        ..color = _kGrid.withValues(alpha: _kGrid.a * g)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0;
      for (final f in const [1 / 3, 2 / 3]) {
        final x = c.left + c.width * f;
        final y = c.top + c.height * f;
        canvas.drawLine(Offset(x, c.top), Offset(x, c.bottom), line);
        canvas.drawLine(Offset(c.left, y), Offset(c.right, y), line);
      }
    }

    // ── White border ────────────────────────────────────────────────────────
    canvas.drawRect(
      c,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── L-shaped corner handles, on the corners ─────────────────────────────
    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kHandleThickness
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    for (final (at, sx, sy) in [
      (c.topLeft, 1.0, 1.0),
      (c.topRight, -1.0, 1.0),
      (c.bottomLeft, 1.0, -1.0),
      (c.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(at.dx, at.dy + sy * _kArm)
          ..lineTo(at.dx, at.dy)
          ..lineTo(at.dx + sx * _kArm, at.dy),
        corner,
      );
    }

    // ── Mid-edge bars: 20 × 4, lying along the edge they sit on ─────────────
    final bar = Paint()..color = Colors.white;
    const radius = Radius.circular(_kHandleThickness / 2);
    for (final r in [
      Rect.fromCenter(
          center: c.topCenter, width: _kEdgeBar, height: _kHandleThickness),
      Rect.fromCenter(
          center: c.bottomCenter, width: _kEdgeBar, height: _kHandleThickness),
      Rect.fromCenter(
          center: c.centerLeft, width: _kHandleThickness, height: _kEdgeBar),
      Rect.fromCenter(
          center: c.centerRight, width: _kHandleThickness, height: _kEdgeBar),
    ]) {
      canvas.drawRRect(RRect.fromRectAndRadius(r, radius), bar);
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) =>
      oldDelegate.cropRect != cropRect ||
      oldDelegate.imgRect != imgRect ||
      oldDelegate.grid != grid;
}
