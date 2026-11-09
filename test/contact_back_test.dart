import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/contact_recovery.dart';
import 'package:toden_flutter/src/providers/step_order.dart';

// Back on the email and phone checks. Mirrors the web SDK's
// lib/contact-back.test.ts: phone backs into email when the flow has one,
// else consent; email backs into consent; none while recovering from a
// refused submission; none on a consent-less flow's opening step.

VerificationConfig _config({bool email = false, bool phone = false, bool consent = true}) =>
    VerificationConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      consentStep: consent,
      emailVerification: email ? const EmailVerificationConfig(enabled: true) : null,
      phoneVerification: phone ? const PhoneVerificationConfig(enabled: true) : null,
    );

/// Where Back lands from [step]: the step before it in the order.
VerificationStep? _before(VerificationConfig config, VerificationStep step) {
  final order = buildStepOrder(config, const VerificationState());
  final i = order.indexOf(step);
  return i > 0 ? order[i - 1] : null;
}

void main() {
  test('phone backs into email when the flow has an email step, else consent', () {
    expect(_before(_config(email: true, phone: true), VerificationStep.contactPhone),
        VerificationStep.contactEmail);
    expect(_before(_config(phone: true), VerificationStep.contactPhone), VerificationStep.consent);
  });

  test('email backs into consent', () {
    expect(_before(_config(email: true, phone: true), VerificationStep.contactEmail),
        VerificationStep.consent);
  });

  test('a consent-less flow opens on its contact step, which has no Back', () {
    final config = _config(email: true, consent: false);
    expect(openingStep(config), VerificationStep.contactEmail);
  });

  test('no Back while recovering from a refused submission', () {
    expect(contactBackShown(VerificationStep.contactEmail, const []), isTrue);
    expect(contactBackShown(VerificationStep.contactPhone, const []), isTrue);
    expect(contactBackShown(VerificationStep.contactEmail, const ['email']), isFalse);
    expect(contactBackShown(VerificationStep.contactPhone, const ['phone']), isFalse);
    expect(contactBackShown(VerificationStep.contactPhone, const ['email']), isTrue);
    expect(contactBackShown(VerificationStep.idType, const ['email']), isTrue);
  });
}
