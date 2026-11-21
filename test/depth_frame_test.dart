import 'dart:async';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/liveness/depth_frame.dart';

/// Reads a PNG as kyc-core's docbio/depth-sensor.ts does: the header's fields
/// and the readings, big-endian, filter 0 rows only (what the SDK writes).
({int width, int height, int depth, int colour, int interlace, List<int> mm}) readPng(Uint8List png) {
  final data = ByteData.sublistView(png);
  expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  var off = 8;
  late int width, height, depth, colour, interlace;
  final idat = BytesBuilder();
  while (off + 8 <= png.length) {
    final len = data.getUint32(off);
    final type = String.fromCharCodes(png.sublist(off + 4, off + 8));
    final body = png.sublist(off + 8, off + 8 + len);
    if (type == 'IHDR') {
      final h = ByteData.sublistView(body);
      width = h.getUint32(0);
      height = h.getUint32(4);
      depth = body[8];
      colour = body[9];
      interlace = body[12];
    } else if (type == 'IDAT') {
      idat.add(body);
    } else if (type == 'IEND') {
      break;
    }
    off += 12 + len;
  }
  final raw = ZLibDecoder().convert(idat.takeBytes());
  final stride = width * 2;
  final mm = <int>[];
  for (var y = 0; y < height; y++) {
    expect(raw[y * (stride + 1)], 0, reason: 'row filter');
    for (var x = 0; x < width; x++) {
      final i = y * (stride + 1) + 1 + x * 2;
      mm.add((raw[i] << 8) | raw[i + 1]);
    }
  }
  return (width: width, height: height, depth: depth, colour: colour, interlace: interlace, mm: mm);
}

class FakeDepthCamera implements DepthCamera {
  FakeDepthCamera(this.answer);
  final Future<DepthFrame?> Function() answer;
  int calls = 0;

  @override
  Future<DepthFrame?> capture(Duration timeout) {
    calls++;
    return answer();
  }
}

void main() {
  // Values across the whole 16-bit range, so a byte-order slip shows.
  final frame = DepthFrame(
    width: 3,
    height: 2,
    mm: Uint16List.fromList([0, 1, 412, 435, 1499, 65535]),
  );

  test('the PNG is what Core reads: 16-bit greyscale, not interlaced, millimetres', () {
    final png = readPng(encodeDepthPng(frame));
    expect(png.width, 3);
    expect(png.height, 2);
    expect(png.depth, 16);
    expect(png.colour, 0);
    expect(png.interlace, 0);
    expect(png.mm, [0, 1, 412, 435, 1499, 65535]);
  });

  test('the native reply is read as little-endian millimetres', () {
    final bytes = ByteData(6)
      ..setUint16(0, 412, Endian.little)
      ..setUint16(2, 0, Endian.little)
      ..setUint16(4, 1200, Endian.little);
    final read = depthFrameFromReply({'width': 3, 'height': 1, 'mm': bytes.buffer.asUint8List()});
    expect(read?.width, 3);
    expect(read?.mm, [412, 0, 1200]);
  });

  test('a malformed reply is no frame', () {
    expect(depthFrameFromReply(null), isNull);
    expect(depthFrameFromReply({'width': 2, 'height': 2, 'mm': Uint8List(6)}), isNull);
    expect(depthFrameFromReply({'width': 0, 'height': 1, 'mm': Uint8List(0)}), isNull);
  });

  test('off the iPhone nothing is asked of the camera', () async {
    final camera = FakeDepthCamera(() async => frame);
    expect(await captureDepthPng(camera: camera, supported: false), isNull);
    expect(camera.calls, 0);
  });

  test('a frame comes back as the PNG', () async {
    final png = await captureDepthPng(camera: FakeDepthCamera(() async => frame), supported: true);
    expect(readPng(png!).mm, frame.mm);
  });

  test('a failure or no frame is no frame, never an error', () async {
    expect(await captureDepthPng(camera: FakeDepthCamera(() async => null), supported: true), isNull);
    expect(
      await captureDepthPng(camera: FakeDepthCamera(() => Future.error(StateError('busy'))), supported: true),
      isNull,
    );
  });

  test('a reply that never comes is cut off', () async {
    final png = await captureDepthPng(
      camera: FakeDepthCamera(() => Completer<DepthFrame?>().future),
      supported: true,
      timeout: const Duration(milliseconds: 10),
    );
    expect(png, isNull);
  });

  test('a camera opening meanwhile waits for the depth camera to close', () async {
    final reply = Completer<DepthFrame?>();
    final capture = captureDepthPng(camera: FakeDepthCamera(() => reply.future), supported: true);
    var free = false;
    final waiting = depthCameraFree().then((_) => free = true);
    await Future<void>.delayed(Duration.zero);
    expect(free, isFalse);
    reply.complete(null);
    await waiting;
    expect(free, isTrue);
    expect(await capture, isNull);
    // Nothing running: free at once.
    await depthCameraFree();
  });
}
