import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/verification_config.dart';
import 'package:toden_flutter/src/liveness/voice_clips.dart';

// Who speaks, from 4.4.0 (kyc-core docs/VOICE_GUIDANCE.md): a Toden voice from
// the country of the document being verified, else a neighbouring country's,
// else the workflow's own voice, else an American one. The same rule, and the
// same seed numbers, as the web and React Native SDKs.

Map<String, Object?> _voice(String? country, String gender, {bool offered = true}) => {
      'languages': ['en'],
      'gender': gender,
      if (country != null) 'country': country,
      'offered': offered,
    };

VoiceManifest _book({Map<String, Object?> extra = const {}}) => VoiceManifest.fromJson({
      'version': 'v1',
      'voices': {
        'tolani': _voice('NG', 'female'),
        'chinedu': _voice('NG', 'male'),
        'rose': _voice('NG', 'female'),
        'obinna': _voice('NG', 'male'),
        'keith': _voice('KE', 'male'),
        'maryanne': _voice('KE', 'female'),
        'nakato': _voice('UG', 'female'),
        'lyra': _voice('GB', 'female'),
        'elise': _voice('US', 'female'),
        'danny': _voice('US', 'male'),
        'marlon': _voice(null, 'male'),
        ...extra,
      },
      'neighbours': {
        'TZ': ['KE', 'UG'],
        'RW': ['UG', 'KE'],
      },
      'fallbackCountry': 'US',
      'phrases': {
        'en': {'presence.challenge.nod': 'Nod your head'},
      },
    });

void main() {
  final book = _book();
  String? who(String choice, String? country, {String? voice, String seed = 'person-1', bool neighbours = true}) => pickVoice(
        book,
        voice: voice,
        language: 'en-US',
        applicant: VoiceApplicant(choice: choice, country: country, seed: seed, neighbours: neighbours),
      );

  group("a voice from the person's own country", () {
    test('a Kenyan hears a Kenyan voice and a Nigerian a Nigerian one, of the gender asked for', () {
      expect(who('female', 'KE'), 'maryanne');
      expect(who('male', 'KE'), 'keith');
      expect(['tolani', 'rose'], contains(who('female', 'NG')));
      expect(['chinedu', 'obinna'], contains(who('male', 'ng')));
    });

    test("one person keeps one voice, and people are spread across a country's voices", () {
      expect(who('any', 'NG', seed: 'p'), who('any', 'NG', seed: 'p'));
      expect({for (var n = 0; n < 200; n++) who('any', 'NG', seed: 'person-$n')}, {'tolani', 'chinedu', 'rose', 'obinna'});
    });

    test('the accent comes first: a country with no voice of that gender gives its other voice', () {
      expect(who('male', 'UG'), 'nakato');
    });

    test('never a voice Toden no longer offers', () {
      final withdrawn = _book(extra: {'maryanne': _voice('KE', 'female', offered: false)});
      expect(
        pickVoice(withdrawn, language: 'en', applicant: const VoiceApplicant(choice: 'female', country: 'KE', seed: 's')),
        'keith',
      );
    });
  });

  group('a neighbouring voice', () {
    test('a Tanzanian hears a Kenyan voice; the first neighbour with the gender asked for', () {
      expect(who('female', 'TZ'), 'maryanne');
      expect(who('male', 'RW'), 'keith');
      expect(who('female', 'RW'), 'nakato');
    });

    test('is skipped when switched off', () {
      expect(who('female', 'TZ', voice: 'lyra', neighbours: false), 'lyra');
    });
  });

  group('the fallbacks', () {
    test("the workflow's own voice, then an American one", () {
      expect(who('any', 'SN', voice: 'lyra'), 'lyra');
      expect(who('female', 'SN'), 'elise');
      expect(who('male', 'SN'), 'danny');
      expect(who('female', null), 'elise');
    });

    test("with matching off: the workflow's own voice, else an American one, whatever the country", () {
      expect(who('off', 'KE', voice: 'lyra'), 'lyra');
      expect(['danny', 'elise'], contains(who('off', 'KE')));
    });

    test("an older server that says nothing of countries: the workflow's voice, else the device's", () {
      final older = VoiceManifest.fromJson({
        'version': 'v1',
        'voices': {
          'lyra': {'languages': ['en']},
        },
        'phrases': {'en': {}},
      });
      const applicant = VoiceApplicant(choice: 'any', country: 'KE', seed: 's');
      expect(pickVoice(older, language: 'en', applicant: applicant), isNull);
      expect(pickVoice(older, voice: 'lyra', language: 'en', applicant: applicant), 'lyra');
    });

    test("an accent that is not one country's is never anybody's local voice", () {
      expect(who('male', 'JM', voice: 'lyra'), 'lyra');
    });
  });

  group('the settings', () {
    test("a Toden voice by default; the device's only where the admin chose it", () {
      const automatic = VoiceGuidanceConfig();
      expect(automatic.deviceVoice, isFalse);
      expect(automatic.resolvedLocalVoice, 'any');
      expect(automatic.localVoiceNeighbours, isTrue);
      const device = VoiceGuidanceConfig(voice: 'device');
      expect(device.deviceVoice, isTrue);
      expect(device.workflowVoice, isNull);
    });

    test('reads localVoice and localVoiceNeighbours from a workflow, and the app\'s over it key by key', () {
      final workflow = VoiceGuidanceConfig.fromDynamic({'voice': 'lyra', 'localVoice': 'female', 'localVoiceNeighbours': false})!;
      expect(workflow.resolvedLocalVoice, 'female');
      expect(workflow.localVoiceNeighbours, isFalse);
      final app = const VoiceGuidanceConfig(localVoice: 'male').over(workflow);
      expect(app.resolvedLocalVoice, 'male');
      expect(app.voice, 'lyra');
      expect(app.localVoiceNeighbours, isFalse);
      expect(VoiceGuidanceConfig.fromDynamic({'localVoice': 'random'})!.resolvedLocalVoice, 'any');
    });

    test("names the person by the app's user reference, and leaves the country out with matching off", () {
      final kenya = VoiceApplicant.of(choice: 'any', neighbours: true, country: 'ke', userId: 'user-9');
      expect([kenya.country, kenya.seed], ['KE', 'user-9']);
      expect(VoiceApplicant.of(choice: 'off', neighbours: true, country: 'KE').country, isNull);
      expect(VoiceApplicant.of(choice: 'any', neighbours: true).seed, kSessionVoiceSeed);
    });

    test('numbers a seed the same way every Toden SDK does (FNV-1a)', () {
      expect(voiceSeedNumber(''), 0x811c9dc5);
      expect(voiceSeedNumber('a'), 0xe40c292c);
    });
  });
}
