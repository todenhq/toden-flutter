import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/scope.dart';
import 'package:toden_flutter/src/i18n/business_variants.dart';
import 'package:toden_flutter/src/i18n/translate.dart';
import 'package:toden_flutter/src/providers/step_order.dart';
import 'package:toden_flutter/src/screens/consent_process_steps.dart';
import 'package:toden_flutter/src/widgets/flow_step_meta.dart';

// ─── Scoped BUSINESS workflows ────────────────────────────────────────────────
//
// A business may carry the address, questionnaire or contact scope. The scope
// decides the steps (never the KYB application), the screens name the
// business, and a biometric scope on a business is refused. Mirrors the web
// SDK's lib/business-scope.test.ts and the RN SDK's businessScope.test.ts.

VerificationConfig _config({
  String? scope,
  String subjectType = 'business',
  bool email = false,
  bool phone = false,
  bool address = false,
  bool poa = false,
}) =>
    VerificationConfig(
      apiKey: 'pk_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      country: 'NG',
      scope: scope,
      subjectType: subjectType,
      emailVerification: email ? const EmailVerificationConfig(enabled: true) : null,
      phoneVerification: phone ? const PhoneVerificationConfig(enabled: true) : null,
      addressCollection: address ? const AddressCollectionConfig(enabled: true) : null,
      proofOfAddress: poa ? const ProofOfAddressConfig(enabled: true) : null,
    );

void main() {
  group('which flow a scoped business workflow runs', () {
    test('knows the scopes a business may carry', () {
      expect(kBusinessScopes, {'address', 'questionnaire', 'contact'});
    });

    test('never enters the KYB application once a scope is set', () {
      expect(isBusinessApplication('business', null), isTrue);
      for (final scope in kBusinessScopes) {
        expect(isBusinessApplication('business', scope), isFalse);
      }
      expect(isBusinessApplication('individual', null), isFalse);
    });

    test('refuses a business workflow with a biometric scope, and nothing else', () {
      expect(unsupportedScopeConfig('business', 'biometric-authentication'), isTrue);
      expect(unsupportedScopeConfig('business', 'biometric-enrollment'), isTrue);
      expect(unsupportedScopeConfig('individual', 'biometric-enrollment'), isFalse);
      expect(unsupportedScopeConfig('business', 'address'), isFalse);
      expect(unsupportedScopeConfig('business', null), isFalse);
      expect(isScopedBusiness('business', 'biometric-enrollment'), isFalse);
      expect(isScopedBusiness('business', 'contact'), isTrue);
    });

    test('builds the scope order, never the business application', () {
      expect(buildStepOrder(_config(scope: 'questionnaire'), const VerificationState()), [
        VerificationStep.consent,
        VerificationStep.questionnaire,
        VerificationStep.submitted,
      ]);
      expect(buildStepOrder(_config(scope: 'contact', phone: true), const VerificationState()), [
        VerificationStep.consent,
        VerificationStep.contactPhone,
        VerificationStep.submitted,
      ]);
      final address = buildStepOrder(_config(scope: 'address', poa: true), const VerificationState());
      expect(address, [
        VerificationStep.consent,
        VerificationStep.proofOfAddress,
        VerificationStep.submitted,
      ]);
      expect(address, isNot(contains(VerificationStep.businessDetails)));
      // An unscoped business workflow is still the KYB application.
      expect(
        buildStepOrder(_config(), const VerificationState()),
        contains(VerificationStep.businessDetails),
      );
    });
  });

  group('business wording on scoped screens', () {
    test('every business variant stands in for a base text, and is not itself customisable', () {
      for (final variant in kBusinessVariantTexts.keys) {
        final base = businessVariantBase(variant)!;
        expect('$base.business', variant);
        expect(kCustomisableTextKeys.contains(variant), isFalse, reason: variant);
        expect(kBusinessVariantTexts[variant]!.contains('—'), isFalse, reason: variant);
      }
      expect(businessKey('contact.email.title', true), 'contact.email.title.business');
      expect(businessKey('contact.email.title', false), 'contact.email.title');
      expect(businessKey('contact.verifyCode', true), 'contact.verifyCode');
    });

    test("lets the org's words for the base text win over the business default", () {
      final custom = createTextFn({
        'en': {'contact.email.title': 'Confirm the address'},
      }, null);
      expect(custom('contact.email.title.business'), 'Confirm the address');
      expect(defaultTextFn('contact.email.title.business'), 'Verify your business email');
      expect(defaultTextFn('questionnaire.title.business', legacy: 'Our questions'), 'Our questions');
    });

    test('lists the business steps on the consent screen', () {
      final labels = consentProcessSteps(
        _config(scope: 'address', address: true, poa: true),
        isBusiness: false,
        scope: 'address',
        t: defaultTextFn,
        scopedBusiness: true,
      ).map((s) => s.label).toList();
      expect(labels, contains('Verify your business premises'));
      expect(labels, contains("Upload a document showing your business's address"));
      expect(labels, isNot(contains('Collect your business registration details')));
    });

    test('words the step headers for the business', () {
      StepMeta meta(VerificationStep step, VerificationConfig config) => flowStepMeta(
            step,
            config: config,
            state: const VerificationState(),
            t: defaultTextFn,
            selfieComplete: false,
          );
      final contact = _config(scope: 'contact', email: true, phone: true);
      expect(meta(VerificationStep.contactEmail, contact).title, 'Verify your business email');
      expect(meta(VerificationStep.contactPhone, contact).description, contains('belongs to your business'));
      expect(meta(VerificationStep.questionnaire, _config(scope: 'questionnaire')).title,
          'A few questions about your business');
      expect(
        meta(VerificationStep.proofOfAddress, _config(scope: 'address', poa: true)).description,
        "Upload a document that shows your business's name and address, issued within the last 90 days.",
      );
      // A person keeps their own wording.
      expect(
        meta(VerificationStep.contactEmail, _config(scope: 'contact', subjectType: 'individual', email: true))
            .title,
        'Verify your email',
      );
    });
  });
}
