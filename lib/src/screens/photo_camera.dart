import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;

import '../config/capture_config.dart';
import '../config/immersive_layout.dart';
import '../config/photo_mode.dart';
import '../config/theme.dart';
import '../i18n/text_scope.dart';
import '../providers/camera_provider.dart';
import '../services/native_document_camera.dart';
import '../utils/permissions.dart';
import '../widgets/camera_permission_priming_view.dart';
import '../widgets/camera_permission_view.dart';
import '../widgets/flow_close.dart';
import '../widgets/immersive_controls.dart';
import '../widgets/photo_viewfinder.dart';
import '../widgets/ui_button.dart';
import '../widgets/ui_spinner.dart';

// ─── "Take a photo" inside the SDK ───────────────────────────────────────────
//
// The full-screen document camera's look, minus the scanning (config/
// photo_mode.dart). Used where the flow wants a plain photo (a supporting
// document, a business document, a proof of address, the entrance) and used
// to hand over to the system camera through image_picker.
//
// A full-screen route of its own, as the cropper is: the step under it keeps
// its state, and the camera has every pixel. The caller gets the photo back as
// the XFile image_picker gave, re-encoded as image_picker's `imageQuality: 90`
// did, so its existing size check and upload run unchanged.
//
// Back closes only the camera and returns to the step. The X closes the whole
// flow through the flow's own close (widgets/flow_close.dart), and is hidden
// when the flow cannot be closed.
//
// The camera is the scan's: on Android the SDK's own CameraX camera, started
// with its frame analysis off (photoCameraSourceFor), whose preview is upright
// on every phone; the Flutter camera plugin on iOS, and on Android only if the
// native camera cannot start.
//
// Mirrors the React Native SDK's components/PhotoCamera.tsx.

/// How the camera was left.
enum PhotoCameraExit {
  /// A photo was taken: [PhotoCameraResult.photo] holds it.
  photo,

  /// The person chose Upload: the caller opens its own picker.
  upload,

  /// Back, or the flow was closed. Nothing to do.
  cancelled,
}

/// The outcome of [openPhotoCamera].
class PhotoCameraResult {
  final PhotoCameraExit exit;

  /// The photo, a JPEG at quality 90, when [exit] is [PhotoCameraExit.photo].
  final XFile? photo;

  const PhotoCameraResult._(this.exit, [this.photo]);

  static const cancelled = PhotoCameraResult._(PhotoCameraExit.cancelled);
  static const upload = PhotoCameraResult._(PhotoCameraExit.upload);
  factory PhotoCameraResult.taken(XFile photo) =>
      PhotoCameraResult._(PhotoCameraExit.photo, photo);
}

/// What the camera's route pops with. Null is Back (the button or the system
/// gesture): the camera closes and nothing else happens.
sealed class PhotoCameraPop {
  const PhotoCameraPop();
}

class PhotoCameraClosed extends PhotoCameraPop {
  const PhotoCameraClosed();
}

class PhotoCameraUpload extends PhotoCameraPop {
  const PhotoCameraUpload();
}

class PhotoCameraTaken extends PhotoCameraPop {
  final XFile shot;
  const PhotoCameraTaken(this.shot);
}

/// Opens the in-SDK camera over the flow and waits for it.
///
/// [allowUpload] false hides Upload (a document the workflow wants
/// photographed). The X is drawn only when the flow can be closed; tapping it
/// closes the camera, then the flow, through the same handler as the header's.
Future<PhotoCameraResult> openPhotoCamera(
  BuildContext context, {
  required String title,
  String? instruction,
  double? guideAspect,
  bool allowUpload = true,
}) async {
  final flowClose = FlowClose.of(context);
  // The route sits outside the flow, so it is handed the flow's Theme (the
  // workflow's colours) and scope (its texts and providers), as the cropper is.
  final flowTheme = Theme.of(context);
  final flowScope = flowScopeOf(context);
  final popped = await Navigator.of(context).push<PhotoCameraPop>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => inFlowScope(
        flowScope,
        Theme(
          data: flowTheme,
          child: PhotoCameraScreen(
            title: title,
            instruction: instruction,
            guideAspect: guideAspect,
            allowUpload: allowUpload,
            canClose: flowClose != null,
          ),
        ),
      ),
    ),
  );
  switch (popped) {
    case null:
      return PhotoCameraResult.cancelled;
    case PhotoCameraClosed():
      // The camera's route is gone, so the flow's close finds the flow on top,
      // exactly as the header's X does.
      flowClose?.call();
      return PhotoCameraResult.cancelled;
    case PhotoCameraUpload():
      return PhotoCameraResult.upload;
    case PhotoCameraTaken(:final shot):
      return PhotoCameraResult.taken(await photoAsJpeg90(shot));
  }
}

/// The still as image_picker's `imageQuality: 90` handed it back: a JPEG at
/// quality 90, full size, turned upright from its EXIF. The callers' size check
/// and upload were written for that. Falls back to the still as taken if the
/// re-encode fails, so a photo is never lost to it.
Future<XFile> photoAsJpeg90(XFile shot) async {
  final raw = await shot.readAsBytes();
  var bytes = raw;
  try {
    final out = await FlutterImageCompress.compressWithList(
      raw,
      quality: kPhotoJpegQuality,
      // Larger than any sensor: the photo is never scaled down here.
      minWidth: 1 << 15,
      minHeight: 1 << 15,
      format: CompressFormat.jpeg,
    );
    if (out.isNotEmpty) bytes = out;
  } catch (_) {
    bytes = raw;
  }
  final name = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
  try {
    final path = '${File(shot.path).parent.path}/$name';
    await File(path).writeAsBytes(bytes, flush: true);
    return XFile(path, mimeType: 'image/jpeg', name: name);
  } catch (_) {
    return XFile.fromData(bytes, mimeType: 'image/jpeg', name: name);
  }
}

enum _Phase { checking, primer, denied, camera }

/// The camera's screen: the permission states, then the viewfinder. The scan's
/// own permission handling and screens, each with the way out (back, close)
/// the camera itself has.
class PhotoCameraScreen extends ConsumerStatefulWidget {
  final String title;
  final String? instruction;
  final double? guideAspect;
  final bool allowUpload;

  /// Whether the flow can be closed, which draws the X.
  final bool canClose;

  const PhotoCameraScreen({
    super.key,
    required this.title,
    this.instruction,
    this.guideAspect,
    this.allowUpload = true,
    this.canClose = false,
  });

  @override
  ConsumerState<PhotoCameraScreen> createState() => _PhotoCameraScreenState();
}

class _PhotoCameraScreenState extends ConsumerState<PhotoCameraScreen>
    with WidgetsBindingObserver {
  _Phase _phase = _Phase.checking;
  bool _initializing = false;
  bool _hasTorch = false;
  bool _torchOn = false;

  /// True while a still is being taken. The shutter is never disabled; this
  /// drops a second tap so two captures never contend for the camera.
  bool _capturing = false;

  /// Set once the route has been popped, so nothing pops it twice.
  bool _leaving = false;

  // Android's native camera, the scan's, with no frame analysis. Null on iOS
  // and on the Android fallback, where the camera plugin drives the feed.
  NativeDocumentCamera? _native;
  int? _nativeTextureId;
  int _nativePreviewW = 0;
  int _nativePreviewH = 0;

  // Set when the native camera failed to start, so the plugin fallback sticks
  // for the rest of the screen.
  bool _nativeFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // The controller is released by the camera provider when this route, its
    // only listener, goes. The native camera is ours to close.
    final native = _native;
    _native = null;
    if (native != null) unawaited(native.dispose());
    super.dispose();
  }

  /// The camera, straight away when access is already granted; otherwise the
  /// "Allow camera access" primer first, as the scan does.
  Future<void> _check() async {
    bool granted;
    try {
      granted = await hasCameraPermission();
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    if (granted) {
      _start();
    } else {
      setState(() => _phase = _Phase.primer);
    }
  }

  Future<void> _start() async {
    if (_initializing || !mounted) return;
    _initializing = true;
    setState(() => _phase = _Phase.camera);
    try {
      // Android: an explicit permission gate before the camera opens. iOS is
      // left to the camera controller's own denial signal, as on the scan.
      if (Platform.isAndroid) {
        bool granted;
        try {
          granted = await requestCameraPermission();
        } catch (_) {
          granted = false;
        }
        if (!mounted) return;
        if (!granted) {
          setState(() => _phase = _Phase.denied);
          return;
        }
      }
      // Android's normal path; the plugin below is the fallback.
      if (photoCameraSourceFor(defaultTargetPlatform) ==
              PhotoCameraSource.native &&
          !_nativeFailed &&
          await _startNative()) {
        return;
      }
      if (!mounted) return;
      final notifier = ref.read(cameraNotifierProvider.notifier);
      // A photo only: no sound, no clip, no frame stream.
      await notifier.initialize(
        direction: CameraLensDirection.back,
        resolution: CaptureConfig.documentResolution,
      );
      if (!mounted) return;
      final state = ref.read(cameraNotifierProvider);
      setState(() {
        if (state.isPermissionDenied) _phase = _Phase.denied;
        _hasTorch = notifier.hasTorch;
        _torchOn = false;
      });
    } finally {
      _initializing = false;
    }
  }

  /// Starts the native camera with no frame analysis: preview, torch and
  /// still only. Returns false when it could not start, which latches
  /// [_nativeFailed] so the caller falls back to the plugin.
  Future<bool> _startNative() async {
    final camera = NativeDocumentCamera();
    try {
      final textureId = await camera.start(analyze: false);
      if (!mounted) {
        unawaited(camera.dispose());
        return true; // the screen is gone; nothing to fall back to
      }
      if (textureId < 0) {
        unawaited(camera.dispose());
        _nativeFailed = true;
        return false;
      }
      final hasTorch = await camera.hasTorch();
      if (!mounted) {
        unawaited(camera.dispose());
        return true;
      }
      setState(() {
        _native = camera;
        _nativeTextureId = textureId;
        _nativePreviewW = camera.previewWidth;
        _nativePreviewH = camera.previewHeight;
        _hasTorch = hasTorch;
        _torchOn = false;
      });
      return true;
    } catch (_) {
      unawaited(camera.dispose());
      _nativeFailed = true;
      return false;
    }
  }

  // The camera is released when the app is backgrounded (Settings, the OS
  // prompt). On iOS the controller is dead on return, so it is reopened, only
  // while the camera is showing. On Android both the native camera and the
  // plugin reopen by themselves.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || state != AppLifecycleState.resumed) return;
    if (!Platform.isIOS) return;
    if (_phase != _Phase.camera || _initializing) return;
    _start();
  }

  Future<void> _toggleTorch() async {
    final next = !_torchOn;
    setState(() => _torchOn = next);
    final native = _native;
    if (native != null) {
      await native.setTorch(next);
    } else {
      await ref.read(cameraNotifierProvider.notifier).setTorch(next);
    }
  }

  Future<void> _capture() async {
    if (_capturing || _leaving) return;
    final native = _native;
    if (native != null) return _captureNative(native);
    final controller = ref.read(cameraNotifierProvider.notifier).controller;
    if (controller == null || !controller.value.isInitialized) return;
    _capturing = true;
    try {
      final shot = await controller.takePicture();
      if (!mounted) return;
      _leave(PhotoCameraTaken(shot));
    } catch (_) {
      // A failed shutter is a no-op: the person can tap again.
    } finally {
      _capturing = false;
    }
  }

  /// The native still: upright JPEG bytes (the rotation is baked in
  /// natively), kept as a file so the caller gets the same XFile the plugin
  /// gives. Quality 100 here: [photoAsJpeg90] makes the one lossy pass.
  Future<void> _captureNative(NativeDocumentCamera native) async {
    _capturing = true;
    try {
      final bytes = await native.captureStill(quality: 100);
      if (!mounted || bytes == null || bytes.isEmpty) return;
      final shot = await _stillFile(bytes);
      if (!mounted) return;
      _leave(PhotoCameraTaken(shot));
    } catch (_) {
      // A failed shutter is a no-op: the person can tap again.
    } finally {
      _capturing = false;
    }
  }

  static Future<XFile> _stillFile(List<int> bytes) async {
    Directory dir;
    try {
      dir = await getTemporaryDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }
    final name = 'CAP_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final path = '${dir.path}/$name';
    await File(path).writeAsBytes(bytes, flush: true);
    return XFile(path, mimeType: 'image/jpeg', name: name);
  }

  void _leave([PhotoCameraPop? result]) {
    if (_leaving || !mounted) return;
    _leaving = true;
    Navigator.of(context).pop(result);
  }

  VoidCallback? get _onClose =>
      widget.canClose ? () => _leave(const PhotoCameraClosed()) : null;

  VoidCallback? get _onUpload =>
      widget.allowUpload ? () => _leave(const PhotoCameraUpload()) : null;

  @override
  Widget build(BuildContext context) {
    final cameraState = ref.watch(cameraNotifierProvider);
    if (_phase == _Phase.camera) {
      final controller = ref.read(cameraNotifierProvider.notifier).controller;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        // Light icons: the camera feed behind the status bar is dark.
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: PhotoViewfinder(
            controller: cameraState.isReady ? controller : null,
            nativeTextureId: _nativeTextureId,
            nativePreviewW: _nativePreviewW,
            nativePreviewH: _nativePreviewH,
            // A live native texture owns the feed; the plugin's state is
            // irrelevant then.
            isLoading: _nativeTextureId == null &&
                (cameraState.isLoading || _initializing),
            error: _nativeTextureId == null &&
                    cameraState.status == CameraStatus.error
                ? cameraState.error
                : null,
            title: widget.title,
            instruction: widget.instruction,
            guideAspect: widget.guideAspect,
            onCapture: () => unawaited(_capture()),
            onBack: _leave,
            onClose: _onClose,
            onUpload: _onUpload,
            torchOn: _torchOn,
            onToggleTorch: _hasTorch ? () => unawaited(_toggleTorch()) : null,
          ),
        ),
      );
    }
    return _buildPreCamera(context);
  }

  /// Before the camera runs: the same screens the scan shows, under the
  /// camera's own top bar.
  Widget _buildPreCamera(BuildContext context) {
    final colors = context.myazaColors;
    final insets = MediaQueryData.fromView(View.of(context)).viewPadding;
    final t = context.verificationText;
    final Widget content = switch (_phase) {
      _Phase.primer => CameraPermissionPrimingView(
          message: t('primer.camera.body'),
          onGrant: () => unawaited(_start()),
        ),
      _Phase.denied => CameraPermissionView(
          message: widget.allowUpload
              ? PhotoCopy.permissionDenied
              : PhotoCopy.permissionDeniedNoUpload,
          onOpenSettings: openDeviceAppSettings,
          // iOS: only Settings can grant, and that relaunches the app.
          onRetry: Platform.isIOS ? null : () => unawaited(_start()),
          secondaryAction: _onUpload == null
              ? null
              : UiButton.ghost(
                  label: t('uploadDocument.camera.uploadInstead'),
                  onPressed: _onUpload,
                ),
        ),
      _ => Center(
          child: SizedBox.square(
            dimension: kViewfinderSpinnerSize,
            child: UiSpinner(color: colors.primary, strokeWidth: 2),
          ),
        ),
    };
    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: UiSpacing.lg,
              right: UiSpacing.lg,
              top: immersiveTopBarTop(insets.top) + kImmersiveTopBarHeight,
              bottom: insets.bottom,
            ),
            child: content,
          ),
          Positioned(
            key: kDocumentTopBarKey,
            top: immersiveTopBarTop(insets.top),
            left: 0,
            right: 0,
            height: kImmersiveTopBarHeight,
            child: ImmersiveTopBar(
              onBack: _leave,
              country: null,
              documentLabel: widget.title,
              onClose: _onClose,
            ),
          ),
        ],
      ),
    );
  }
}
