import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/verification_config.dart';
import 'package:toden_flutter/src/config/workflow_merge.dart';
import 'package:toden_flutter/src/i18n/translate.dart';
import 'package:toden_flutter/src/liveness/device_voice.dart';
import 'package:toden_flutter/src/liveness/liveness_types.dart';
import 'package:toden_flutter/src/services/api_service.dart';

// voiceGuidance: a bare boolean or { enabled, language, voice }; the SDK's own
// value sits over the workflow's key by key; and the device voice prefers an
// Enhanced voice.

void main() {
  group('VoiceGuidanceConfig.fromDynamic', () {
    test('a bare boolean sets enabled alone', () {
      final on = VoiceGuidanceConfig.fromDynamic(true)!;
      expect(on.enabled, isTrue);
      expect(on.voice, isNull);
      expect(on.resolvedLanguage, 'en-US');
      expect(VoiceGuidanceConfig.fromDynamic(false)!.enabled, isFalse);
    });

    test('an object carries enabled, language and voice', () {
      final c = VoiceGuidanceConfig.fromDynamic(
        {'enabled': true, 'language': 'en-GB', 'voice': 'lyra', 'later': 1},
      )!;
      expect(c.enabled, isTrue);
      expect(c.language, 'en-GB');
      expect(c.voice, 'lyra');
    });

    test('an object without enabled is on', () {
      expect(VoiceGuidanceConfig.fromDynamic({'voice': 'rory'})!.enabled, isTrue);
    });

    test('ignores values of the wrong type', () {
      final c = VoiceGuidanceConfig.fromDynamic({'enabled': 'no', 'voice': 3, 'language': ''})!;
      expect(c.enabled, isTrue);
      expect(c.voice, isNull);
      expect(c.language, isNull);
      expect(VoiceGuidanceConfig.fromDynamic('lyra'), isNull);
      expect(VoiceGuidanceConfig.fromDynamic(null), isNull);
    });
  });

  group('the prop over the workflow', () {
    VerificationConfig merged(VoiceGuidanceConfig prop, Object? workflow) =>
        mergeWorkflowIntoConfig(
          VerificationConfig(apiKey: 'pk_test_x', voiceGuidance: prop),
          WorkflowFlowConfig.fromJson({
            if (workflow != null) 'voiceGuidance': workflow,
          }),
        );

    test('a prop voice keeps the workflow enabled and language', () {
      final v = merged(
        const VoiceGuidanceConfig(voice: 'rory'),
        {'enabled': true, 'language': 'en-GB', 'voice': 'lyra'},
      ).voiceGuidance;
      expect(v.voice, 'rory');
      expect(v.language, 'en-GB');
      expect(v.enabled, isTrue);
    });

    test('a bare boolean prop overrides enabled only', () {
      final v = merged(VoiceGuidanceConfig.off, {'language': 'en-GB', 'voice': 'lyra'})
          .voiceGuidance;
      expect(v.enabled, isFalse);
      expect(v.voice, 'lyra');
      expect(v.language, 'en-GB');
    });

    test('no prop takes the workflow whole', () {
      final v = merged(const VoiceGuidanceConfig(), {'voice': 'lyra'}).voiceGuidance;
      expect(v.voice, 'lyra');
      expect(v.enabled, isTrue);
      expect(merged(const VoiceGuidanceConfig(), false).voiceGuidance.enabled, isFalse);
    });

    test('a workflow that says nothing keeps the prop', () {
      final v = merged(const VoiceGuidanceConfig(voice: 'rory'), null).voiceGuidance;
      expect(v.voice, 'rory');
      expect(v.enabled, isTrue);
    });
  });

  test('the default liveness wording is the Toden clip wording', () {
    expect(defaultTextFn('presence.challenge.nod'), 'Nod your head');
    expect(defaultTextFn('presence.challenge.turn'), 'Turn your head');
    expect(defaultTextFn('presence.challenge.blink'), 'Blink your eyes');
    expect(defaultTextFn('presence.challenge.smile'), 'Smile');
    expect(defaultTextFn('presence.position.holdStill'), 'Hold still');
    // Each default instruction maps to a key whose default is that same text.
    kPresenceInstructionKeys.forEach((text, key) {
      expect(defaultTextFn(key), text, reason: key);
    });
  });

  group('pickEnhancedVoice', () {
    const ios = [
      {'name': 'Samantha', 'locale': 'en-US', 'quality': 'default', 'identifier': 'a'},
      {'name': 'Ava (Enhanced)', 'locale': 'en-US', 'quality': 'enhanced', 'identifier': 'b'},
      {'name': 'Daniel (Enhanced)', 'locale': 'en-GB', 'quality': 'enhanced', 'identifier': 'c'},
    ];

    test('takes the Enhanced voice for the language and region', () {
      expect(pickEnhancedVoice(ios, 'en-US'),
          {'name': 'Ava (Enhanced)', 'locale': 'en-US', 'identifier': 'b'});
      expect(pickEnhancedVoice(ios, 'en-GB')?['identifier'], 'c');
    });

    test('a Premium voice beats an Enhanced one', () {
      final voices = [
        ...ios,
        {'name': 'Zoe (Premium)', 'locale': 'en-US', 'quality': 'premium', 'identifier': 'd'},
      ];
      expect(pickEnhancedVoice(voices, 'en-US')?['identifier'], 'd');
    });

    test('a bare language takes any region', () {
      expect(pickEnhancedVoice(ios, 'en'), isNotNull);
    });

    test('keeps the default when there is no Enhanced voice', () {
      expect(pickEnhancedVoice(ios, 'fr-FR'), isNull);
      expect(pickEnhancedVoice([ios.first], 'en-US'), isNull);
      expect(pickEnhancedVoice(null, 'en-US'), isNull);
    });

    test('on Android, only an installed very high voice that needs no network', () {
      const android = [
        {'name': 'en-us-x-net', 'locale': 'en-US', 'quality': 'very high', 'network_required': '1', 'features': ''},
        {'name': 'en-us-x-gone', 'locale': 'en-US', 'quality': 'very high', 'network_required': '0', 'features': 'notInstalled'},
        {'name': 'en-us-x-local', 'locale': 'en-US', 'quality': 'very high', 'network_required': '0', 'features': 'embeddedTts'},
        {'name': 'en-us-x-normal', 'locale': 'en-US', 'quality': 'normal', 'network_required': '0', 'features': ''},
      ];
      expect(pickEnhancedVoice(android, 'en_US'), {'name': 'en-us-x-local', 'locale': 'en-US'});
    });
  });
}
