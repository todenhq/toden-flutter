import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/verification_config.dart';
import 'package:toden_flutter/src/liveness/voice_playback.dart';

// The flow's early preload of the Toden voice (voice_playback.dart): started
// when the workflow resolves and when the flow opens, so the clips are in by
// the liveness step. It fetches nothing unless there is a voice to load.

void main() {
  test('fetches nothing with guidance off, no voice or no server', () {
    expect(preloadVoiceClips(const VoiceGuidanceConfig(enabled: false, voice: 'lyra'), baseUrl: 'http://localhost:3001'), isNull);
    expect(preloadVoiceClips(const VoiceGuidanceConfig(enabled: true), baseUrl: 'http://localhost:3001'), isNull);
    expect(preloadVoiceClips(const VoiceGuidanceConfig(enabled: true, voice: 'lyra'), baseUrl: null), isNull);
    expect(preloadVoiceClips(const VoiceGuidanceConfig(enabled: true, voice: 'lyra'), baseUrl: ''), isNull);
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
