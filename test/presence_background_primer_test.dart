import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/presence/presence_background_primer.dart';

// Mirrors the React Native SDK's __tests__/backgroundPrimer.test.ts.

void main() {
  group('when the background ask is made', () {
    PrimerDecision decide({
      bool wants = true,
      bool registered = true,
      bool granted = false,
      bool resumed = false,
    }) =>
        backgroundPrimerDecision(
          wantsBackground: wants,
          registered: registered,
          alwaysGranted: granted,
          resumed: resumed,
        );

    test('shows the explanation first when the person has not granted it', () {
      expect(decide(), PrimerDecision.primer);
    });

    test('arms with no prompt when it is already granted', () {
      expect(decide(granted: true), PrimerDecision.silent);
    });

    test('asks nothing when background is off, unregistered, or the screen is shown again', () {
      expect(decide(wants: false), PrimerDecision.skip);
      expect(decide(registered: false), PrimerDecision.skip);
      expect(decide(resumed: true), PrimerDecision.skip);
    });
  });

  group('the effort without background checks', () {
    test('counts app opens at 0.6 each, as the server scores them', () {
      expect(effortWithoutBackground(PresencePolicyNumbers(), isBusiness: false),
          const PresenceEffort(5, PresenceEffortUnit.evenings));
    });

    test('counts days only for a business premises', () {
      expect(effortWithoutBackground(PresencePolicyNumbers(), isBusiness: true),
          const PresenceEffort(9, PresenceEffortUnit.days));
      expect(effortWithoutBackground(PresencePolicyNumbers(minNights: 0, minDays: 3), isBusiness: false),
          const PresenceEffort(5, PresenceEffortUnit.days));
    });

    test('follows the workflow policy', () {
      expect(effortWithoutBackground(PresencePolicyNumbers(minNights: 6, minDays: 2), isBusiness: false),
          const PresenceEffort(4, PresenceEffortUnit.days));
      expect(PresencePolicyNumbers(windowDays: 14).windowDays, 14);
      expect(PresencePolicyNumbers().windowDays, 10);
    });

    test('words the lines for a person and a business', () {
      expect(effortSentence(const PresenceEffort(5, PresenceEffortUnit.evenings), isBusiness: false),
          'Otherwise, open the app at home on 5 different evenings.');
      expect(effortSentence(const PresenceEffort(1, PresenceEffortUnit.days), isBusiness: true),
          'Otherwise, open the app at the premises on 1 day.');
      expect(withinSentence(10), 'Usually confirmed within 10 days.');
      expect(finishSentence(const PresenceEffort(9, PresenceEffortUnit.days), isBusiness: true),
          'Open the app at the premises on 9 days to finish, or continue with automatic checks.');
    });
  });
}
