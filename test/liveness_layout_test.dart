import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/liveness/liveness_layout.dart';

// ─── The selfie circle fits the SHORT phone too ─────────────────────────────
//
// Two real devices are the vectors. On the iPhone the fixed size stands; on
// the Samsung the height rule takes over. The
// same devices are pinned in React Native's livenessLayout.test.ts (its cap is
// its own 300; the rule is what is shared).

void main() {
  test('keeps the full circle on a tall phone (iPhone 16 Pro Max)', () {
    final layout = livenessLayout(const Size(440, 956));
    expect(layout.circle, kLivenessCircleMax);
  });

  test('shrinks the circle on a short phone (Samsung S24, 360×780)', () {
    final layout = livenessLayout(const Size(360, 780));
    expect(layout.circle, 240);
  });

  test('never drops below the floor on a very short screen (iPhone SE class)', () {
    final layout = livenessLayout(const Size(375, 667));
    expect(layout.circle, kLivenessCircleMin);
  });

  test('is bounded by the width on a narrow tall screen', () {
    final layout = livenessLayout(const Size(300, 956));
    expect(layout.circle, 300 - kLivenessCircleSideGutter);
  });

  test('never exceeds the cap and grows with the window', () {
    expect(livenessLayout(const Size(1024, 2000)).circle, kLivenessCircleMax);
    final short = livenessLayout(const Size(400, 760)).circle;
    final tall = livenessLayout(const Size(400, 900)).circle;
    expect(tall, greaterThan(short));
  });
}
