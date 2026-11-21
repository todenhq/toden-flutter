import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:toden_flutter/src/config/capture_config.dart';
import 'package:toden_flutter/src/services/document_quad_crop.dart';

// ─── A document photo sharp enough for its barcode ────────────────────────────
//
// The server reads a card's barcode from the document photo, and a barcode's
// bars are the first thing a small or twice-compressed picture loses (a
// Nigerian driver's licence stopped decoding from web captures and its number
// fell to a vision model). The camera photo keeps its detail and is compressed
// once: the crop writes the file that is uploaded.

void main() {
  group('the size a document photo keeps', () {
    test('matches the web SDK: 2600 on the longer side, quality 95', () {
      expect(CaptureConfig.documentMaxDimension, 2600);
      expect(CaptureConfig.documentImageQuality, 95);
    });

    test('a photo inside the limit keeps the size the crop gave it', () {
      expect(documentStillResize(2600, 1640), isNull);
      expect(documentStillResize(1267, 800), isNull);
    });

    test('a larger one comes inside the limit by its longer side, in shape', () {
      expect(documentStillResize(3900, 2460), (width: 2600, height: 1640));
      expect(documentStillResize(2460, 3900), (width: 1640, height: 2600));
    });
  });

  group('the one write', () {
    test('keeps every pixel of a crop inside the limit', () {
      final written =
          img.decodeJpg(encodeDocumentStill(img.Image(width: 1267, height: 800)))!;
      expect((written.width, written.height), (1267, 800));
    });

    test('brings an oversized crop inside the limit as it writes it', () {
      final written =
          img.decodeJpg(encodeDocumentStill(img.Image(width: 3900, height: 2460)))!;
      expect((written.width, written.height), (2600, 1640));
    });

    test('is the only one a camera photo gets after its crop', () {
      final screen =
          File('lib/src/screens/document_capture_screen.dart').readAsStringSync();
      // The crop's file goes on as it is; only a turned slip is turned back.
      expect(
          screen,
          contains(
              'final cropped =\n          await rotateJpegClockwise(framedRaw, _turn.captureUndoDegrees);'));
      // A photo picked from the device is still finished by the compressor.
      expect('compressDocumentImage('.allMatches(screen).length, 1);

      // Both crops write through the same function.
      final quad =
          File('lib/src/services/document_quad_crop.dart').readAsStringSync();
      expect(quad, contains('return encodeDocumentStill(cropped);'));
      final guide = File('lib/src/services/image_service.dart').readAsStringSync();
      expect(guide, contains('final once = encodeDocumentStill(cropped);'));
      expect(guide, contains('if (once.length <= p.maxBytes) return once;'));
    });

    test('the native camera hands its photo over whole, before the crop', () {
      expect(CaptureConfig.documentCaptureHandoverQuality, 100);
      final screen =
          File('lib/src/screens/document_capture_screen.dart').readAsStringSync();
      expect(screen,
          contains('quality: CaptureConfig.documentCaptureHandoverQuality,'));
    });
  });

  test('Android takes the document photo at 1440 by 2560, in the preview\'s shape',
      () {
    final camera = File(
            'android/src/main/kotlin/co/toden/flutter/DocumentCamera.kt')
        .readAsStringSync();
    expect(camera, contains('val CAPTURE_SIZE = Size(1440, 2560)'));
    expect(camera, contains('val PREVIEW_SIZE = Size(1080, 1920)'));
    // 16:9 both, or the crop maps the guide into the wrong part of the photo.
    expect(1440 / 2560, closeTo(1080 / 1920, 1e-9));
  });
}
