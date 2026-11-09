import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:toden_flutter/src/config/document_guide.dart';
import 'package:toden_flutter/src/config/document_turn.dart';
import 'package:toden_flutter/src/services/image_service.dart';

// After the shutter a slip framed upright is cropped to the upright guide (the
// one drawn) and then turned back to landscape before it is stored.

Uint8List _jpeg(img.Image image) =>
    Uint8List.fromList(img.encodeJpg(image, quality: 100));

void main() {
  test('crops a turned slip to the upright guide that was drawn', () async {
    // A still exactly the viewfinder's size, so guide points are pixels.
    const view = Size(393, 852);
    final band = documentGuideBand(topInset: 59, bottomInset: 34);
    final aspect = screenGuideAspect(kNinSlipGuideAspect, true);
    final guide = documentGuideRect(view, aspect, band: band);
    final still = img.Image(width: 393, height: 852);

    final cropped = img.decodeJpg(await cropCardRegionBytes(
      _jpeg(still),
      viewW: view.width,
      viewH: view.height,
      aspect: aspect,
      band: band,
      maxBytes: 1 << 24,
    ))!;
    expect(cropped.width, closeTo(guide.width, 1.5));
    expect(cropped.height, closeTo(guide.height, 1.5));
  });

  test('turns the default capture back with a quarter counter-clockwise', () async {
    // Upright crop: 40 wide, 80 tall, with the slip's TOP along the right edge
    // (the direction the guide shows). A dark block marks that edge.
    final upright = img.Image(width: 40, height: 80)
      ..clear(img.ColorRgb8(255, 255, 255));
    img.fillRect(upright,
        x1: 30, y1: 0, x2: 39, y2: 79, color: img.ColorRgb8(0, 0, 0));

    final turned = img.decodeJpg(
        await rotateJpegClockwise(_jpeg(upright), undoDegrees(null)))!;
    expect(turned.width, 80);
    expect(turned.height, 40);
    // Landscape again, with the marked edge along the top.
    expect(turned.getPixel(40, 3).r, lessThan(60));
    expect(turned.getPixel(40, 36).r, greaterThan(200));
  });

  test('no turn leaves the bytes untouched', () async {
    final bytes = _jpeg(img.Image(width: 4, height: 4));
    expect(identical(await rotateJpegClockwise(bytes, 0), bytes), isTrue);
  });
}
