import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'document_corners.dart';

// ─── Crop a still to the detected document, plus the bleed ────────────────────
//
// The guide crop takes the rectangle the user was ASKED to fill, so a passport
// held a little low lost its machine-readable zone to the crop even when the
// corners rule had passed. With the corners known, the still is cropped to the
// document itself with space past every corner (bleedCropRect), so the MRZ is
// never cut by us.
//
// The quad is measured in the analysis frame. The still can be a different
// shape (a 4:3 photo beside a 16:9 stream on some iOS presets); the stream is
// then the centre of the sensor the still covers, which is how camera sensors
// crop. When the two shapes match, as on Android's native camera, the mapping
// is the identity.

class _QuadCropParams {
  final Uint8List bytes;
  final List<double> quad; // 8 numbers, see DocumentQuad.fromList
  final double frameAspect;

  const _QuadCropParams(this.bytes, this.quad, this.frameAspect);
}

/// Where a stream of [frameAspect] (width / height, upright) sits inside a
/// [still] of that pixel size, normalised to the still.
Rect streamRegionInStill(Size still, double frameAspect) =>
    visibleFrameRegion(still, Size(frameAspect, 1));

/// The crop rectangle for [quad] (measured in a frame of [frameAspect]) inside
/// a [still] of that pixel size. Pure, for tests.
CropRect quadCropInStill(DocumentQuad quad, Size still, double frameAspect) =>
    bleedCropRect(quad.within(streamRegionInStill(still, frameAspect)), still);

Uint8List? _quadCropWorker(_QuadCropParams p) {
  var decoded = img.decodeImage(p.bytes);
  final quad = DocumentQuad.fromList(p.quad);
  if (decoded == null || quad == null) return null;
  decoded = img.bakeOrientation(decoded);
  final crop = quadCropInStill(
    quad,
    Size(decoded.width.toDouble(), decoded.height.toDouble()),
    p.frameAspect,
  );
  if (crop.width < 2 || crop.height < 2) return null;
  final cropped = img.copyCrop(
    decoded,
    x: crop.x,
    y: crop.y,
    width: crop.width,
    height: crop.height,
  );
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
}

/// Crops a still to [quad] plus the bleed. Null when the still cannot be read
/// or the crop would be empty; the caller then crops to the guide as before.
Future<Uint8List?> cropToDocumentQuad(
  Uint8List bytes,
  DocumentQuad quad, {
  required Size frameSize,
}) {
  if (frameSize.isEmpty) return Future.value(null);
  final flat = <double>[
    for (final c in quad.corners) ...[c.dx, c.dy],
  ];
  return compute(
    _quadCropWorker,
    _QuadCropParams(bytes, flat, frameSize.width / frameSize.height),
  );
}
