import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/verification_config.dart';
import 'package:toden_flutter/src/liveness/voice_playback.dart';

// The flow's early preload of the Toden voice (voice_playback.dart): started
// when the workflow resolves and when the flow opens, so the clips are in by
// the liveness step. From 4.4.0 a Toden voice is the default, so it loads
// unless guidance is off, the admin chose the device's voice, or there is no
// server.

void main() {
  test("fetches nothing with guidance off, the device's voice chosen, or no server", () {
    expect(preloadVoiceClips(const VoiceGuidanceConfig(enabled: false, voice: 'lyra'), baseUrl: 'http://localhost:3001'), isNull);
    expect(preloadVoiceClips(const VoiceGuidanceConfig(enabled: true, voice: 'device'), baseUrl: 'http://localhost:3001'), isNull);
    expect(preloadVoiceClips(const VoiceGuidanceConfig(enabled: true, voice: 'lyra'), baseUrl: null), isNull);
    expect(preloadVoiceClips(const VoiceGuidanceConfig(enabled: true, voice: 'lyra'), baseUrl: ''), isNull);
  });

  test('loads by default, with no voice named: the voice is chosen for the person', () {
    final load = preloadVoiceClips(const VoiceGuidanceConfig(enabled: true), baseUrl: 'http://127.0.0.1:9', country: 'ke', userId: 'u-1');
    expect(load, isNotNull);
    expect(load!.voice, isNull);
    expect(load.applicant?.country, 'KE');
    expect(load.applicant?.seed, 'u-1');
    expect(load.applicant?.choice, 'any');
  });

  test('a different country is a different load; with matching off it is the same one', () {
    const any = VoiceGuidanceConfig(enabled: true, language: 'en-GB');
    final kenya = preloadVoiceClips(any, baseUrl: 'http://127.0.0.1:8', country: 'KE', userId: 'u');
    expect(preloadVoiceClips(any, baseUrl: 'http://127.0.0.1:8', country: 'NG', userId: 'u'), isNot(same(kenya)));
    const off = VoiceGuidanceConfig(enabled: true, localVoice: 'off');
    final first = preloadVoiceClips(off, baseUrl: 'http://127.0.0.1:8', country: 'KE', userId: 'u');
    expect(preloadVoiceClips(off, baseUrl: 'http://127.0.0.1:8', country: 'NG', userId: 'u'), same(first));
  });

  test('starts a load for a voice, and the same server, voice and language share it while it loads', () {
    const config = VoiceGuidanceConfig(enabled: true, voice: 'lyra', language: 'en-GB');
    final first = preloadVoiceClips(config, baseUrl: 'http://127.0.0.1:9');
    expect(first, isNotNull);
    expect(first!.voice, 'lyra');
    // Asked again before its manifest has answered: the same load.
    expect(preloadVoiceClips(const VoiceGuidanceConfig(enabled: true, voice: 'lyra', language: 'en-US'), baseUrl: 'http://127.0.0.1:9'), same(first));
  });
}
