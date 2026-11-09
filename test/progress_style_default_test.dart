import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/verification_config.dart';

// The progress bar is the default indicator (2026-09-29). Steps and none stay
// available, and a value this build does not know takes the default.

void main() {
  test('a config that says nothing draws the bar', () {
    const config = VerificationConfig(apiKey: 'pk_test_x');
    expect(config.progressStyle, VerificationProgressStyle.bar);
  });

  test('a workflow value maps to its style, and an unknown one to the bar', () {
    expect(VerificationProgressStyle.fromJson('steps'), VerificationProgressStyle.steps);
    expect(VerificationProgressStyle.fromJson('none'), VerificationProgressStyle.none);
    expect(VerificationProgressStyle.fromJson('bar'), VerificationProgressStyle.bar);
    expect(VerificationProgressStyle.fromJson('dots'), VerificationProgressStyle.bar);
  });
}
