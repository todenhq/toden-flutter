import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/liveness/blur_budget.dart';

// The full-screen liveness camera gives its blur up on a phone that cannot
// draw it in time (liveness/blur_budget.dart).

const _fast = Duration(milliseconds: 8);
const _slow = Duration(milliseconds: 30);

void _feed(BlurBudget budget, Duration frame, int count) {
  for (var i = 0; i < count; i++) {
    budget.add(frame);
  }
}

void main() {
  test('a phone that keeps up keeps the blur', () {
    final budget = BlurBudget();
    _feed(budget, _fast, 600);
    expect(budget.affordable, isTrue);
  });

  test('the first frames after the camera opens are not judged', () {
    final budget = BlurBudget();
    _feed(budget, _slow, kBlurWarmupFrames);
    _feed(budget, _fast, kBlurWindowFrames * 3);
    expect(budget.affordable, isTrue);
  });

  test('slow windows in a row end the blur, once', () {
    final budget = BlurBudget();
    _feed(budget, _fast, kBlurWarmupFrames);
    var ended = 0;
    for (var i = 0; i < kBlurWindowFrames * kBlurSlowWindows; i++) {
      if (budget.add(_slow)) ended++;
    }
    expect(budget.affordable, isFalse);
    expect(ended, 1);
  });

  test('a few slow frames in a window are tolerated', () {
    final budget = BlurBudget();
    _feed(budget, _fast, kBlurWarmupFrames);
    for (var i = 0; i < kBlurWindowFrames * 4; i++) {
      // One in four is slow: under the share that ends the blur.
      budget.add(i % 4 == 0 ? _slow : _fast);
    }
    expect(budget.affordable, isTrue);
  });

  test('the blur never comes back', () {
    final budget = BlurBudget();
    _feed(budget, _fast, kBlurWarmupFrames);
    _feed(budget, _slow, kBlurWindowFrames * kBlurSlowWindows);
    _feed(budget, _fast, kBlurWindowFrames * 10);
    expect(budget.affordable, isFalse);
  });

  test('one burst of slow frames keeps the blur, as on an iPhone as its camera started', () {
    // Measured 2026-11-18: 27 slow frames in a row, then a phone keeping up.
    final budget = BlurBudget();
    _feed(budget, _fast, kBlurWarmupFrames);
    _feed(budget, _slow, kBlurWindowFrames);
    _feed(budget, _fast, kBlurWindowFrames * 20);
    expect(budget.affordable, isTrue);
  });

  test('the warm-up covers a camera starting on a 120 Hz screen', () {
    expect(kBlurWarmupFrames, greaterThanOrEqualTo(180));
  });

  test('frames drawn while the photo is taken are not judged', () {
    // Measured 2026-11-18: the blur went at 9.5 s and 16.8 s, as the selfie was taken.
    final budget = BlurBudget();
    _feed(budget, _fast, kBlurWarmupFrames);
    _feed(budget, _slow, kBlurWindowFrames - 1);
    budget.pause();
    _feed(budget, _slow, kBlurWindowFrames - 1);
    budget.pause();
    _feed(budget, _fast, kBlurWindowFrames * 5);
    expect(budget.affordable, isTrue);
  });
}
