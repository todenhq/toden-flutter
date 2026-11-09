import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/services/document_detection.dart';

// ─── The frame the detector measured in ───────────────────────────────────────
//
// The corner gate judges the detector's quad against the part of the frame the
// preview shows, so it needs the frame's UPRIGHT size. The Flutter camera
// plugin on iOS delivers frames already turned portrait; swapping their sides
// as if they were landscape sensor frames put every corner of an upright NIN
// slip outside the visible part, and the slip was never captured.

void main() {
  test('a portrait frame is upright already', () {
    expect(uprightFrameSize(1080, 1920), const Size(1080, 1920));
  });

  test('a landscape sensor frame is turned upright', () {
    expect(uprightFrameSize(1920, 1080), const Size(1080, 1920));
  });

  test('the size the native side reports wins', () {
    expect(
      uprightFrameSize(1920, 1080, reportedWidth: 1080, reportedHeight: 1920),
      const Size(1080, 1920),
    );
    expect(
      uprightFrameSize(1080, 1920, reportedWidth: 1080, reportedHeight: 1920),
      const Size(1080, 1920),
    );
  });

  test('a missing or empty reported size falls back to the rule', () {
    expect(uprightFrameSize(1080, 1920, reportedWidth: 0, reportedHeight: 0),
        const Size(1080, 1920));
    expect(uprightFrameSize(1920, 1080, reportedWidth: 1080),
        const Size(1080, 1920));
  });
}
