import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/i18n/translate.dart';
import 'package:toden_flutter/src/providers/verification_state.dart' show VerificationStep;
import 'package:toden_flutter/src/utils/click_log.dart';
import 'package:toden_flutter/src/utils/step_log.dart';

void main() {
  final t = createTextFn(null, null, const {});

  group('controlFor', () {
    test('names a button by the catalogue key of its label', () {
      final hit = controlFor(['  Continue '], t);
      expect(hit.control, 'common.continue');
      expect(hit.label, 'Continue');
    });

    test('matches the workflow’s own words and reports the English default', () {
      final custom = createTextFn({'en': {'common.continue': 'Carry on'}}, 'en', const {});
      final hit = controlFor(['Carry on'], custom);
      expect(hit.control, 'common.continue');
      expect(hit.label, 'Continue');
    });

    test('never records text that is not SDK copy, such as an address', () {
      final hit = controlFor(['12 Admiralty Way, Lekki'], t);
      expect(hit.control, kUnnamedControl);
      expect(hit.label, '');
    });
  });

  group('StepLog.recordClick', () {
    setUp(StepLog.reset);

    test('stamps the step the applicant is on and rides the snapshot', () {
      StepLog.record(VerificationStep.consent);
      logPress(['Continue'], t);
      final clicks = StepLog.snapshot()!['clicks'] as List;
      expect(clicks, hasLength(1));
      expect(clicks.first['control'], 'common.continue');
      expect(clicks.first['step'], 'consent');
    });

    test('collapses a double tap, keeps a later press, and caps at 60', () {
      StepLog.record(VerificationStep.consent);
      final t0 = DateTime.utc(2026, 11, 19, 10);
      StepLog.recordClick('common.continue', 'Continue', now: t0);
      StepLog.recordClick('common.continue', 'Continue', now: t0.add(const Duration(milliseconds: 200)));
      StepLog.recordClick('common.continue', 'Continue', now: t0.add(const Duration(seconds: 2)));
      expect(StepLog.snapshot()!['clicks'] as List, hasLength(2));
      for (var i = 0; i < 80; i++) {
        StepLog.recordClick('k$i', 'K', now: t0.add(Duration(minutes: 1, seconds: i)));
      }
      expect(StepLog.snapshot()!['clicks'] as List, hasLength(60));
    });

    test('leaves clicks off when there were none', () {
      StepLog.record(VerificationStep.consent);
      expect(StepLog.snapshot()!.containsKey('clicks'), isFalse);
    });
  });

  group('named controls and choices', () {
    setUp(StepLog.reset);

    test('records the shutter, a catalogue key, and the kind of a choice, never the value', () {
      StepLog.record(VerificationStep.idType);
      logChoice('idType');
      logControl('capture.shutter', 'Take photo');
      logKey('common.retake');
      final clicks = (StepLog.snapshot()!['clicks'] as List).cast<Map>();
      expect(clicks.map((c) => c['control']), ['choice.idType', 'capture.shutter', 'common.retake']);
      expect(clicks.first['label'], 'an ID type');
      expect(clicks.last['label'], isNotEmpty);
    });
  });
}
