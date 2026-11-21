import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/liveness/voice_clips.dart';
import 'package:toden_flutter/src/liveness/voice_playback.dart';

// The manifest, the matching rule and the clip URLs of the Toden voices
// (kyc-core docs/VOICE_GUIDANCE.md).

const _manifestJson = {
  'version': '3f9a1c2b',
  'voices': {
    'lyra': {'languages': ['en']},
    'rory': {'languages': ['en']},
  },
  'phrases': {
    'en': {
      'presence.position.holdStill': 'Hold still',
      'presence.failed.timeout': "Time's up. Please try again.",
      'presence.challenge.passed': 'Good.',
    },
  },
};

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  final List<Uri> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

void main() {
  group('normaliseVoicePhrase', () {
    test('"Hold still…", "Hold still." and "hold still" are one phrase', () {
      for (final text in ['Hold still…', 'Hold still.', 'hold still', '  Hold   still! ']) {
        expect(normaliseVoicePhrase(text), 'hold still', reason: text);
      }
    });

    test('curly and straight apostrophes match', () {
      expect(
        normaliseVoicePhrase('Time’s up. Please try again.'),
        normaliseVoicePhrase("Time's up. Please try again."),
      );
      expect(normaliseVoicePhrase("Time's up. Please try again."), "time's up please try again");
    });

    test('odd spaces and full-width letters become plain ones', () {
      expect(normaliseVoicePhrase('Hold still'), 'hold still');
      expect(normaliseVoicePhrase('Ｈold still'), 'hold still');
    });

    test('a reworded phrase stays different', () {
      expect(normaliseVoicePhrase('Kindly hold still'), isNot('hold still'));
    });

    test('letters outside English are kept', () {
      expect(normaliseVoicePhrase('Tournez la tête.'), 'tournez la tête');
    });
  });

  test('primaryVoiceLanguage reads the primary subtag, lower case', () {
    expect(primaryVoiceLanguage('en-US'), 'en');
    expect(primaryVoiceLanguage('EN_gb'), 'en');
    expect(primaryVoiceLanguage('fr'), 'fr');
  });

  group('VoiceManifest', () {
    test('maps normalised text to key for a voice and language it has', () {
      final keys = VoiceManifest.fromJson(_manifestJson).phraseKeysByText('lyra', 'en-US');
      expect(keys, {
        'hold still': 'presence.position.holdStill',
        "time's up please try again": 'presence.failed.timeout',
        'good': 'presence.challenge.passed',
      });
    });

    test('has nothing for a voice or language without clips', () {
      final manifest = VoiceManifest.fromJson(_manifestJson);
      expect(manifest.phraseKeysByText('danny', 'en'), isNull);
      expect(manifest.phraseKeysByText('lyra', 'fr-FR'), isNull);
    });

    test('refuses what is not a manifest', () {
      expect(() => VoiceManifest.fromJson('nope'), throwsFormatException);
      expect(() => VoiceManifest.fromJson({'voices': {}}), throwsFormatException);
      expect(() => VoiceManifest.fromJson({'version': '../x'}), throwsFormatException);
    });

    test('leaves out ids that could not be a path segment', () {
      final manifest = VoiceManifest.fromJson({
        'version': 'v1',
        'voices': {
          '../evil': {'languages': ['en']},
          'lyra': {'languages': ['en', '../x']},
        },
        'phrases': {
          'en': {'presence.position.holdStill': 'Hold still', '../../etc': 'x', 'k': 3},
        },
      });
      expect(manifest.voices.keys, ['lyra']);
      expect(manifest.voices['lyra'], {'en'});
      expect(manifest.phrases['en'], {'presence.position.holdStill': 'Hold still'});
    });
  });

  group('VoiceClipRef.url', () {
    const ref = VoiceClipRef(
      version: '3f9a1c2b',
      voice: 'lyra',
      language: 'en',
      phraseKey: 'presence.position.holdStill',
    );
    const url =
        'https://api.toden.co/api/kyc/assets/voices/3f9a1c2b/lyra/en/presence.position.holdStill.mp3';

    test('sits under the server the SDK talks to', () {
      expect(ref.url('https://api.toden.co').toString(), url);
      expect(ref.url('https://api.toden.co/').toString(), url);
      expect(
        ref.url('http://10.0.2.2:3001').toString(),
        'http://10.0.2.2:3001/api/kyc/assets/voices/3f9a1c2b/lyra/en/presence.position.holdStill.mp3',
      );
    });
  });

  group('HttpVoiceAssets', () {
    late Directory cache;
    setUp(() => cache = Directory.systemTemp.createTempSync('toden_voice_test'));
    tearDown(() => cache.deleteSync(recursive: true));

    HttpVoiceAssets assets(_Adapter adapter) => HttpVoiceAssets(
          'https://api.toden.co',
          dio: Dio()..httpClientAdapter = adapter,
          cacheRoot: () async => cache,
        );

    test('reads the manifest from the server, without a key', () async {
      final adapter = _Adapter((_) => _json(_manifestJson));
      final manifest = await assets(adapter).manifest();
      expect(manifest.version, '3f9a1c2b');
      expect(adapter.requested.single.toString(),
          'https://api.toden.co/api/kyc/assets/voices/manifest.json');
    });

    test('a 404 (the switch is off) throws, so the device voice stays', () async {
      final adapter = _Adapter((_) => _json({'error': 'not_found'}, 404));
      await expectLater(assets(adapter).manifest(), throwsA(isA<DioException>()));
    });

    test('caches a clip once per version and reads it from disk after', () async {
      final adapter = _Adapter((_) => ResponseBody.fromBytes([1, 2, 3], 200));
      const ref = VoiceClipRef(
        version: 'v1',
        voice: 'lyra',
        language: 'en',
        phraseKey: 'presence.position.holdStill',
      );
      final source = assets(adapter);
      final path = await source.clip(ref);
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
      expect(path, endsWith('toden_voices/v1/lyra/en/presence.position.holdStill.mp3'));
      expect(await source.clip(ref), path);
      expect(adapter.requested, hasLength(1));
    });

    test('a missing clip throws and leaves nothing behind', () async {
      final adapter = _Adapter((_) => _json({'error': 'not_found'}, 404));
      const ref = VoiceClipRef(version: 'v1', voice: 'lyra', language: 'en', phraseKey: 'x.y');
      await expectLater(assets(adapter).clip(ref), throwsA(isA<DioException>()));
      expect(File('${cache.path}/toden_voices/v1/lyra/en/x.y.mp3').existsSync(), isFalse);
    });
  });
}
