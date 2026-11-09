import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/presence/presence_background_allow_steps.dart';

void main() {
  group('backgroundAllowSteps', () {
    test('names the iOS upgrade prompt', () {
      final steps = backgroundAllowSteps(isIOS: true, foregroundGranted: true);
      expect(steps.tap, 'Change to Always Allow');
      expect(steps.lead, 'Next, your phone will ask. Tap:');
    });

    test('warns of the first iOS prompt when location is not allowed yet', () {
      final steps = backgroundAllowSteps(isIOS: true, foregroundGranted: false);
      expect(steps.lead, contains('Allow While Using App'));
      expect(steps.tap, 'Change to Always Allow');
    });

    test('sends Android 11 and later to the settings page', () {
      final steps = backgroundAllowSteps(isIOS: false, androidApi: 34, foregroundGranted: true);
      expect(steps.lead, contains('location settings'));
      expect(steps.tap, 'Allow all the time');
    });

    test('warns of the first Android prompt when location is not allowed yet', () {
      final steps = backgroundAllowSteps(isIOS: false, androidApi: 30, foregroundGranted: false);
      expect(steps.lead, contains('While using the app'));
      expect(steps.tap, 'Allow all the time');
    });

    test('keeps Android 10 in a dialog, not settings', () {
      final steps = backgroundAllowSteps(isIOS: false, androidApi: 29, foregroundGranted: true);
      expect(steps.lead, 'Next, your phone will ask. Tap:');
      expect(steps.tap, 'Allow all the time');
    });

    test('never names "all the time" before Android 10', () {
      final steps = backgroundAllowSteps(isIOS: false, androidApi: 28, foregroundGranted: false);
      expect(steps.tap, 'Allow');
    });

    test('reads an unknown Android version as a current phone', () {
      final steps = backgroundAllowSteps(isIOS: false, foregroundGranted: true);
      expect(steps.tap, 'Allow all the time');
      expect(steps.lead, contains('location settings'));
    });
  });

  test('backgroundSettingsSteps names the option each platform has', () {
    expect(backgroundSettingsSteps(isIOS: true).tap, 'Always');
    expect(backgroundSettingsSteps(isIOS: false).tap, 'Allow all the time');
  });
}
