import 'dart:io';

import 'package:camera/camera.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/immersive_layout.dart';
import 'package:toden_flutter/src/config/photo_mode.dart';
import 'package:toden_flutter/src/screens/photo_camera.dart';
import 'package:toden_flutter/src/services/document_framing_gate.dart';
import 'package:toden_flutter/src/widgets/document_ghost.dart';
import 'package:toden_flutter/src/widgets/document_scan_overlay.dart';
import 'package:toden_flutter/src/widgets/document_viewfinder.dart';
import 'package:toden_flutter/src/widgets/flow_close.dart';
import 'package:toden_flutter/src/widgets/icons/icons.dart';
import 'package:toden_flutter/src/widgets/immersive_controls.dart'
    show ImmersiveViewfinderPlaceholder, kDocumentTorchKey, kImmersiveCloseKey;
import 'package:toden_flutter/src/widgets/native_camera_preview.dart';
import 'package:toden_flutter/src/widgets/photo_viewfinder.dart';
import 'icon_finder.dart';

// Photo mode is the full-screen document camera's look without the scan: the
// same top bar and bottom row, no gate, guide or auto-capture, a shutter that
// is always live, an X that is the flow's own close, and a Back that closes
// only the camera. The scan itself must not change.

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 852);
  tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
  tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
  addTearDown(tester.view.reset);
}

PhotoViewfinder _photo({
  String? instruction,
  double? guideAspect,
  VoidCallback? onCapture,
  VoidCallback? onBack,
  VoidCallback? onClose,
  VoidCallback? onUpload,
  VoidCallback? onToggleTorch,
}) =>
    PhotoViewfinder(
      controller: null,
      isLoading: false,
      error: null,
      title: 'Utility bill',
      instruction: instruction,
      guideAspect: guideAspect,
      onCapture: onCapture ?? () {},
      onBack: onBack ?? () {},
      onClose: onClose,
      onUpload: onUpload,
      onToggleTorch: onToggleTorch,
    );

/// Semantics of the shutter: enabled or not, as screen readers are told.
bool _shutterEnabled(WidgetTester tester) => tester
    .getSemantics(find.byKey(kDocumentShutterKey))
    .flagsCollection
    .isEnabled
    .toBoolOrNull()!;

/// The primer and the spinner animate for as long as they show, so the route's
/// transitions are pumped through rather than settled.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The platform the code reads (defaultTargetPlatform), not the test host's.
final _android = TargetPlatformVariant.only(TargetPlatform.android);

void main() {
  group('photo mode viewfinder', () {
    testWidgets('has no gate, guide, sample or side badge', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_host(_photo()));
      expect(tester.takeException(), isNull);
      expect(find.byType(DocumentScanOverlay), findsNothing);
      expect(find.byType(DocumentGhost), findsNothing);
      expect(find.byKey(kPhotoGuideKey), findsNothing);
      expect(find.byKey(kDocumentSideBadgeKey), findsNothing);
      // No instruction asked for, no pill.
      expect(find.byKey(kDocumentHintKey), findsNothing);
    });

    testWidgets('the shutter is always enabled and shows the camera glyph',
        (tester) async {
      _phone(tester);
      final handle = tester.ensureSemantics();
      var taps = 0;
      // No controller at all: the camera is still starting. The shutter is
      // drawn live anyway; the camera ignores a tap it cannot act on.
      await tester.pumpWidget(_host(_photo(onCapture: () => taps++)));
      expect(_shutterEnabled(tester), isTrue);
      expect(
          find.descendant(
              of: find.byKey(kDocumentShutterKey),
              matching: findUiIcon(UiIcons.camera)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(kDocumentShutterKey),
              matching: findUiIcon(UiIcons.scanLine)),
          findsNothing);
      await tester.tap(find.byKey(kDocumentShutterKey));
      await tester.tap(find.byKey(kDocumentShutterKey));
      expect(taps, 2);
      handle.dispose();
    });

    testWidgets('PhotoShutter never holds the shutter', (tester) async {
      expect(PhotoShutter.busy, isFalse);
      expect(PhotoShutter.progress, 0);
      expect(PhotoShutter.disabledReason, isNull);
    });

    testWidgets('an instruction is a neutral pill under the top bar',
        (tester) async {
      _phone(tester);
      await tester
          .pumpWidget(_host(_photo(instruction: PhotoCopy.fitDocument)));
      expect(find.text(PhotoCopy.fitDocument), findsOneWidget);
      final hint = tester.getRect(find.byKey(kDocumentHintKey));
      expect(hint.top, immersiveHintTop(59));
      expect(
          find.descendant(
              of: find.byKey(kDocumentHintKey),
              matching: findUiIcon(UiIcons.scanLine)),
          findsOneWidget);
    });

    testWidgets('a blank instruction draws no pill', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_host(_photo(instruction: '   ')));
      expect(find.byKey(kDocumentHintKey), findsNothing);
    });

    testWidgets('a guide is drawn only when the caller asks for one',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(_host(_photo(guideAspect: 1.4)));
      expect(find.byKey(kPhotoGuideKey), findsOneWidget);
    });

    testWidgets('the close X sits where the side badge goes, and calls close',
        (tester) async {
      _phone(tester);
      var closed = 0;
      await tester.pumpWidget(_host(_photo(onClose: () => closed++)));
      final bar = tester.getRect(find.byKey(kDocumentTopBarKey));
      final x = tester.getRect(find.byKey(kImmersiveCloseKey));
      expect(x.right, bar.right - kImmersiveSideMargin);
      expect(x.top, bar.top);
      expect(x.height, kImmersiveTopBarHeight);
      await tester.tap(find.byKey(kImmersiveCloseKey));
      expect(closed, 1);
    });

    testWidgets('no close handler, no X', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_host(_photo()));
      expect(find.byKey(kImmersiveCloseKey), findsNothing);
      expect(find.byKey(kDocumentBackKey), findsOneWidget);
    });

    testWidgets('Upload shows only with an upload handler', (tester) async {
      _phone(tester);
      var uploads = 0;
      await tester.pumpWidget(_host(_photo()));
      expect(find.byKey(kDocumentUploadKey), findsNothing);
      await tester.pumpWidget(_host(_photo(onUpload: () => uploads++)));
      await tester.tap(find.byKey(kDocumentUploadKey));
      expect(uploads, 1);
    });
  });

  group('the camera route', () {
    // Camera access not yet granted, as permission_handler reports it
    // (PermissionStatus.denied is 0): the camera opens on the scan's primer.
    const permissions =
        MethodChannel('flutter.baseflow.com/permissions/methods');
    setUp(() => TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger
            .setMockMethodCallHandler(permissions, (call) async {
          if (call.method == 'checkPermissionStatus') return 0;
          return null;
        }));
    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, null));

    /// A step inside a flow: the flow's close, and a button that opens the
    /// camera and keeps what it came back with.
    Future<List<PhotoCameraResult>> pumpStep(
      WidgetTester tester, {
      VoidCallback? flowClose,
    }) async {
      _phone(tester);
      final results = <PhotoCameraResult>[];
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: FlowClose(
            onClose: flowClose,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async => results.add(await openPhotoCamera(
                    context,
                    title: 'Proof of address',
                    instruction: PhotoCopy.fitDocument,
                  )),
                  child: const Text('Take a photo'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Take a photo'));
      await _settle(tester);
      expect(find.byType(PhotoCameraScreen), findsOneWidget);
      return results;
    }

    testWidgets('Back closes only the camera', (tester) async {
      var flowClosed = 0;
      final results = await pumpStep(tester, flowClose: () => flowClosed++);
      await tester.tap(find.byKey(kDocumentBackKey));
      await _settle(tester);
      expect(find.byType(PhotoCameraScreen), findsNothing);
      expect(find.text('Take a photo'), findsOneWidget);
      expect(flowClosed, 0);
      expect(results.single.exit, PhotoCameraExit.cancelled);
    });

    testWidgets('the system back closes only the camera', (tester) async {
      var flowClosed = 0;
      final results = await pumpStep(tester, flowClose: () => flowClosed++);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.maybePop();
      await _settle(tester);
      expect(find.byType(PhotoCameraScreen), findsNothing);
      expect(flowClosed, 0);
      expect(results.single.exit, PhotoCameraExit.cancelled);
    });

    testWidgets('the X closes the camera, then calls the flow\'s close',
        (tester) async {
      var flowClosed = 0;
      final results = await pumpStep(tester, flowClose: () => flowClosed++);
      await tester.tap(find.byKey(kImmersiveCloseKey));
      await _settle(tester);
      expect(find.byType(PhotoCameraScreen), findsNothing);
      expect(flowClosed, 1);
      expect(results.single.exit, PhotoCameraExit.cancelled);
    });

    testWidgets('no X when the flow cannot be closed', (tester) async {
      await pumpStep(tester);
      expect(find.byKey(kImmersiveCloseKey), findsNothing);
      expect(find.byKey(kDocumentBackKey), findsOneWidget);
    });

    testWidgets('without camera access yet, the primer shows under the bar',
        (tester) async {
      await pumpStep(tester, flowClose: () {});
      expect(find.text('Allow camera access'), findsOneWidget);
      expect(find.text('Proof of address'), findsOneWidget);
    });
  });

  test('the photo comes back as a JPEG file the callers can read and preview',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = await Directory.systemTemp.createTemp('photo_mode');
    addTearDown(() => dir.delete(recursive: true));
    final still = File('${dir.path}/CAP_0001.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    // No image plugin on the test host: the re-encode falls back to the still
    // as taken, which must still arrive whole.
    final photo = await photoAsJpeg90(XFile(still.path));
    expect(photo.mimeType, 'image/jpeg');
    expect(photo.name, endsWith('.jpg'));
    expect(File(photo.path).existsSync(), isTrue);
    expect(await photo.readAsBytes(), [0xFF, 0xD8, 0xFF, 0xD9]);
    expect(kPhotoJpegQuality, 90);
  });

  test('Android takes the native camera, iOS keeps the plugin', () {
    expect(photoCameraSourceFor(TargetPlatform.android),
        PhotoCameraSource.native);
    expect(photoCameraSourceFor(TargetPlatform.iOS), PhotoCameraSource.plugin);
  });

  testWidgets('the viewfinder draws a native texture when it has one',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_host(PhotoViewfinder(
      controller: null,
      nativeTextureId: 7,
      nativePreviewW: 1920,
      nativePreviewH: 1080,
      isLoading: false,
      error: null,
      title: 'Utility bill',
      onCapture: () {},
      onBack: () {},
    )));
    final preview =
        tester.widget<NativeCameraPreview>(find.byType(NativeCameraPreview));
    expect(preview.textureId, 7);
    expect(find.byType(ImmersiveViewfinderPlaceholder), findsNothing);
  });

  group('the camera on each platform', () {
    // Camera access already granted (PermissionStatus.granted is 1).
    const permissions =
        MethodChannel('flutter.baseflow.com/permissions/methods');
    const native = MethodChannel('kyc_sdk_flutter/document_camera');
    const plugin = MethodChannel('plugins.flutter.io/camera_android_camerax');
    late List<MethodCall> nativeCalls;
    late List<MethodCall> pluginCalls;

    setUp(() {
      nativeCalls = [];
      pluginCalls = [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(permissions, (call) async {
        if (call.method == 'checkPermissionStatus') return 1;
        return null;
      });
      messenger.setMockMethodCallHandler(native, (call) async {
        nativeCalls.add(call);
        switch (call.method) {
          case 'start':
            return {
              'textureId': 7,
              'rotation': 90,
              'previewWidth': 1920,
              'previewHeight': 1080,
            };
          case 'hasTorch':
            return true;
          case 'captureStill':
            return Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
        }
        return null;
      });
      messenger.setMockMethodCallHandler(plugin, (call) async {
        pluginCalls.add(call);
        return null;
      });
    });

    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(permissions, null);
      messenger.setMockMethodCallHandler(native, null);
      messenger.setMockMethodCallHandler(plugin, null);
    });

    Future<List<PhotoCameraResult>> open(WidgetTester tester) async {
      _phone(tester);
      final results = <PhotoCameraResult>[];
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => results.add(
                    await openPhotoCamera(context, title: 'Proof of address')),
                child: const Text('Take a photo'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Take a photo'));
      await _settle(tester);
      return results;
    }

    testWidgets(
        'Android shows the native preview, with its analysis off, '
        'and takes the native still', variant: _android, (tester) async {
      final results = await open(tester);

      final start = nativeCalls.firstWhere((c) => c.method == 'start');
      expect(start.arguments, {'analyze': false});
      final preview =
          tester.widget<NativeCameraPreview>(find.byType(NativeCameraPreview));
      expect(preview.textureId, 7);
      expect(preview.bufferWidth, 1920);
      expect(preview.bufferHeight, 1080);
      // The plugin never opened a camera.
      expect(pluginCalls.where((c) => c.method == 'create'), isEmpty);

      // The torch is the native camera's.
      await tester.tap(find.byKey(kDocumentTorchKey));
      await tester.pump();
      expect(
          nativeCalls.where((c) => c.method == 'setTorch').single.arguments,
          {'enabled': true});

      // The shutter takes the native still and hands it back as a JPEG file.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(kDocumentShutterKey));
        for (var i = 0; i < 20 && results.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await _settle(tester);
      expect(
          nativeCalls.where((c) => c.method == 'captureStill').single.arguments,
          {'quality': 100});
      expect(results.single.exit, PhotoCameraExit.photo);
      final photo = results.single.photo!;
      expect(photo.mimeType, 'image/jpeg');
      expect(await tester.runAsync(photo.readAsBytes),
          [0xFF, 0xD8, 0xFF, 0xD9]);
      // Leaving the camera closes it.
      expect(nativeCalls.last.method, 'dispose');
    });

    testWidgets('iOS keeps the plugin and never starts the native camera',
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
        (tester) async {
      await open(tester);
      expect(find.byType(PhotoCameraScreen), findsOneWidget);
      expect(nativeCalls, isEmpty);
      expect(find.byType(NativeCameraPreview), findsNothing);
    });
  });

  group('the scan is unchanged', () {
    testWidgets('side badge, no X, the scan-line shutter held by its gate',
        (tester) async {
      _phone(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(DocumentViewfinder(
        controller: null,
        isLoading: false,
        error: null,
        isBack: false,
        isProcessing: false,
        guideAspect: 1.586,
        framing: DocumentFraming.none,
        onCapture: null,
        shutterDisabledReason: 'Show all four corners',
        hintLabel: 'Passport',
        onBack: () {},
      )));
      expect(find.byKey(kDocumentSideBadgeKey), findsOneWidget);
      expect(find.byKey(kImmersiveCloseKey), findsNothing);
      expect(find.byType(DocumentScanOverlay), findsOneWidget);
      expect(find.byKey(kDocumentHintKey), findsOneWidget);
      expect(_shutterEnabled(tester), isFalse);
      expect(
          find.descendant(
              of: find.byKey(kDocumentShutterKey),
              matching: findUiIcon(UiIcons.scanLine)),
          findsOneWidget);
      handle.dispose();
    });
  });
}
