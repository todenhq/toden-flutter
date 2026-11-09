import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:toden_flutter/src/presence/background_presence.dart';

// iOS answers the "Always" request natively (PresenceAlwaysPermission.swift);
// this is how that answer becomes the permission enable() decides on.

void main() {
  const current = LocationPermission.whileInUse;

  test('each native answer maps to its permission', () {
    expect(alwaysAnswerToPermission('always', current), LocationPermission.always);
    expect(alwaysAnswerToPermission('whileInUse', current), LocationPermission.whileInUse);
    expect(alwaysAnswerToPermission('denied', current), LocationPermission.deniedForever);
  });

  test('no answer, or one this build does not know, keeps what was held', () {
    expect(alwaysAnswerToPermission(null, current), current);
    expect(alwaysAnswerToPermission('undetermined', current), current);
    expect(alwaysAnswerToPermission('provisional', current), current);
  });

  group('an OS that showed no prompt', () {
    test('keeps the permission iOS reported', () {
      expect(alwaysAnswerToPermission('noPrompt:whileInUse', LocationPermission.denied),
          LocationPermission.whileInUse);
      expect(alwaysAnswerToPermission('noPrompt:denied', LocationPermission.whileInUse),
          LocationPermission.deniedForever);
    });

    test('reads an instant Android answer as no prompt, and leaves iOS to report it', () {
      expect(osPromptedAfter(const Duration(milliseconds: 40), isIOS: false), isFalse);
      expect(osPromptedAfter(const Duration(seconds: 2), isIOS: false), isTrue);
      expect(osPromptedAfter(const Duration(milliseconds: 40), isIOS: true), isTrue);
    });

    test('offers Settings, never opening it, when no answer could be seen', () {
      const started = EnableBackgroundResult(true, BackgroundPresenceReason.started);
      const silent = EnableBackgroundResult(false, BackgroundPresenceReason.backgroundDenied, osPrompted: false);
      const answered = EnableBackgroundResult(false, BackgroundPresenceReason.backgroundDenied);
      expect(afterAllow(started), AllowNext.on);
      expect(afterAllow(silent), AllowNext.offer);
      expect(afterAllow(answered), AllowNext.off);
      expect(afterAllow(null), AllowNext.off);
    });

    test('sends someone to Settings only when the OS refused without asking', () {
      const silent = EnableBackgroundResult(false, BackgroundPresenceReason.backgroundDenied, osPrompted: false);
      const answered = EnableBackgroundResult(false, BackgroundPresenceReason.backgroundDenied);
      const noPin = EnableBackgroundResult(false, BackgroundPresenceReason.noPin, osPrompted: false);
      expect(needsSettings(silent), isTrue);
      expect(needsSettings(answered), isFalse);
      expect(needsSettings(noPin), isFalse);
      expect(needsSettings(null), isFalse);
    });
  });
}
