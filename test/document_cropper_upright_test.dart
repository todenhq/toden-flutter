import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:toden_flutter/src/config/document_guide.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/widgets/document_cropper.dart';

// ─── A NIN slip's crop box stands upright on a phone ─────────────────────────
//
// The camera frames a NIN slip upright on a phone held upright
// (config/document_turn.dart), so a picked photo of it is upright too. The crop
// box used to stay landscape, too short to hold the slip. It now takes the
// guide's shape, and the crop is turned back to landscape like a capture.

// A tall photo, as a phone takes one of an upright slip.
final _photo = img.encodePng(img.Image(width: 300, height: 600));

Rect _cropRect(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.descendant(
    of: find.byType(DocumentCropperScreen),
    matching: find.byWidgetPredicate((w) =>
        w is CustomPaint &&
        w.painter.runtimeType.toString() == '_CropOverlayPainter'),
  ));
  return (paint.painter as dynamic).cropRect as Rect;
}

// Lets the photo decode and the crop run: both are real async work. Each step
// also moves the test clock on, so Rotate's turn plays out.
Future<void> _settle(WidgetTester tester, {bool Function()? until}) async {
  for (var i = 0; i < 40 && !(until?.call() ?? i >= 5); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// The two buttons, by what they announce: Rotate's caption is not the button.
Finder _rotate() => find.bySemanticsLabel('Rotate');
Finder _usePhoto() => find.bySemanticsLabel('Use photo');

/// Opens the cropper on a phone-sized screen; [onPop] gets what it returns.
Future<void> _open(WidgetTester tester, double aspect,
    {void Function(Object?)? onPop, Uint8List? photo}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(extensions: const [UiColorScheme.light]),
    home: const SizedBox.shrink(),
  ));
  final nav = tester.state<NavigatorState>(find.byType(Navigator));
  nav
      .push<Object?>(MaterialPageRoute(
        builder: (_) =>
            DocumentCropperScreen(imageBytes: photo ?? _photo, aspect: aspect),
      ))
      .then((v) => onPop?.call(v));
  await _settle(tester);
}

void main() {
  testWidgets('a NIN slip on a phone gets a portrait crop box', (tester) async {
    await _open(tester, kNinSlipGuideAspect);
    final crop = _cropRect(tester);
    expect(crop.height, greaterThan(crop.width));
    expect(crop.width / crop.height, closeTo(1 / kNinSlipGuideAspect, 1e-6));
  });

  testWidgets('the photo sits 16 inside the stage', (tester) async {
    await _open(tester, kCardGuideAspect);
    final paint = tester.widget<CustomPaint>(find.descendant(
      of: find.byType(DocumentCropperScreen),
      matching: find.byWidgetPredicate((w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_CropOverlayPainter'),
    ));
    final photo = (paint.painter as dynamic).imgRect as Rect;
    final stage = tester.getSize(find.byWidget(paint));
    // A tall photo on a tall stage: its height is the limiting side.
    expect(photo.top, closeTo(16, 1e-6));
    expect(stage.height - photo.bottom, closeTo(16, 1e-6));
    expect(photo.left, greaterThanOrEqualTo(16));
  });

  testWidgets('names the document in the title, with a plain fallback',
      (tester) async {
    await _open(tester, kCardGuideAspect);
    expect(find.text('Fit your ID in the frame'), findsOneWidget);
    expect(find.text('Drag the corners to the edges of your ID'),
        findsOneWidget);
    expect(cropperTitle('NIN slip'), 'Fit your NIN slip in the frame');
    expect(cropperTitle('  '), 'Fit your ID in the frame');
  });

  testWidgets('an ID card keeps its landscape box on a phone', (tester) async {
    await _open(tester, kCardGuideAspect);
    final crop = _cropRect(tester);
    expect(crop.width / crop.height, closeTo(kCardGuideAspect, 1e-6));
  });

  testWidgets('the upright crop is returned turned back to landscape',
      (tester) async {
    Object? popped;
    await _open(tester, kNinSlipGuideAspect, onPop: (v) => popped = v);
    await tester.tap(_usePhoto());
    await _settle(tester, until: () => popped != null);
    final out = img.decodeImage(popped! as Uint8List)!;
    expect(out.width, greaterThan(out.height));
  });

  group('Rotate', () {
    // A slip scanned sideways: a landscape photo, its left half red.
    Uint8List sideways() {
      final image = img.Image(width: 600, height: 300);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(image,
          x1: 0, y1: 0, x2: 299, y2: 299, color: img.ColorRgb8(255, 0, 0));
      return img.encodePng(image);
    }

    testWidgets(
        'refits the upright box, at the same aspect, to the turned photo',
        (tester) async {
      await _open(tester, kNinSlipGuideAspect, photo: sideways());
      final before = _cropRect(tester);
      await tester.tap(_rotate());
      await _settle(tester);
      await _settle(tester);
      final after = _cropRect(tester);
      expect(
          after.width / after.height, closeTo(1 / kNinSlipGuideAspect, 1e-6));
      // Stood up, the photo is tall, so the box can be much bigger.
      expect(after.height, greaterThan(before.height * 1.5));
    });

    testWidgets('the crop of a turned photo comes back the way the photo was',
        (tester) async {
      Object? popped;
      await _open(tester, kNinSlipGuideAspect,
          photo: sideways(), onPop: (v) => popped = v);
      await tester.tap(_rotate());
      await _settle(tester);
      await _settle(tester);
      await tester.tap(_usePhoto());
      await _settle(tester, until: () => popped != null);
      // Rotate turned it a quarter clockwise; the upright box's turn back undoes
      // that, so the slip is landscape again, its red half still on the left.
      final out = img.decodeImage(popped! as Uint8List)!;
      expect(out.width, greaterThan(out.height));
      final left = out.getPixel(out.width ~/ 8, out.height ~/ 2);
      final right = out.getPixel(out.width * 7 ~/ 8, out.height ~/ 2);
      expect(left.g, lessThan(80));
      expect(right.g, greaterThan(180));
    });

    testWidgets('has the label from the catalogue, its hint and a caption',
        (tester) async {
      await _open(tester, kCardGuideAspect);
      expect(_rotate(), findsOneWidget);
      expect(
        tester.getSemantics(_rotate()),
        matchesSemantics(
          label: 'Rotate',
          hint: 'Turns the photo a quarter turn clockwise.',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(find.text('Rotate'), findsOneWidget);
    });

    testWidgets('a press during a turn is ignored, and the turn finishes',
        (tester) async {
      await _open(tester, kNinSlipGuideAspect, photo: sideways());
      final before = _cropRect(tester);
      await tester.tap(_rotate());
      await tester.pump();
      // Mid-turn: a second press must not start a second turn.
      await tester.tap(_rotate(), warnIfMissed: false);
      await _settle(tester);
      await _settle(tester);
      final after = _cropRect(tester);
      // One quarter turn: the sideways slip stands up, the box grows.
      expect(after.height, greaterThan(before.height * 1.5));
    });

    testWidgets('under reduced motion, swaps the turned photo in',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _open(tester, kNinSlipGuideAspect, photo: sideways());
      final before = _cropRect(tester);
      await tester.tap(_rotate());
      await _settle(tester);
      await _settle(tester);
      expect(_cropRect(tester).height, greaterThan(before.height * 1.5));
    });
  });
}
