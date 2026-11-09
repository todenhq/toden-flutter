import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/liveness_audio.dart';
import 'package:toden_flutter/src/config/verification_config.dart';
import 'package:toden_flutter/src/config/workflow_merge.dart';
import 'package:toden_flutter/src/i18n/translate.dart';
import 'package:toden_flutter/src/screens/consent_process_steps.dart';
import 'package:toden_flutter/src/services/api_service.dart';

void main() {
  VerificationConfig config({
    bool audio = true,
    bool liveness = true,
    bool selfie = true,
    String? scope,
    String subjectType = 'individual',
  }) =>
      VerificationConfig(
        apiKey: 'pk_test_x',
        country: 'NG',
        livenessAudio: audio,
        enableLiveness: liveness,
        enableSelfie: selfie,
        scope: scope,
        subjectType: subjectType,
      );

  group('recordsLivenessAudio', () {
    test('stays off unless the workflow asked', () {
      expect(recordsLivenessAudio(config()), isTrue);
      expect(recordsLivenessAudio(config(audio: false)), isFalse);
    });

    test('needs a liveness recording to put sound on', () {
      expect(recordsLivenessAudio(config(liveness: false)), isFalse);
      expect(recordsLivenessAudio(config(selfie: false)), isFalse);
      expect(recordsLivenessAudio(config(subjectType: 'business')), isFalse);
    });

    test('follows the scope on a scoped flow', () {
      expect(
        recordsLivenessAudio(config(scope: 'biometric-authentication')),
        isTrue,
      );
      expect(
        recordsLivenessAudio(config(scope: 'biometric-enrollment')),
        isTrue,
      );
      expect(recordsLivenessAudio(config(scope: 'address')), isFalse);
    });
  });

  test('a workflow switches it on', () {
    final merged = mergeWorkflowIntoConfig(
      config(audio: false),
      WorkflowFlowConfig.fromJson({'livenessAudio': true}),
    );
    expect(merged.livenessAudio, isTrue);
  });

  test('is not on the consent list', () {
    final labels = consentProcessSteps(
      config(scope: 'biometric-authentication'),
      isBusiness: false,
      scope: 'biometric-authentication',
      t: defaultTextFn,
    ).map((step) => step.label).join(' ');
    expect(labels.toLowerCase(), isNot(contains('sound')));
  });
}
