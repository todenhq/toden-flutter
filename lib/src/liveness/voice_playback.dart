import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;

import '../config/verification_config.dart' show VoiceGuidanceConfig;
import '../services/api_service.dart' show kSdkVersion;
import 'device_voice.dart';
import 'liveness_speaker.dart';
import 'voice_clips.dart';

// ─── Toden voices on the device ──────────────────────────────────────────────
//
// The platform half of liveness_speaker.dart: the clips come from the KYC
// server into the app's temporary directory (one folder per manifest version,
// so a clip is fetched once per device until Toden changes it) and play
// through just_audio.

/// This app process's voice loads, shared by the flow's preload and the
/// liveness step.
final VoicePreloads _preloads = VoicePreloads();

/// Starts loading the workflow's Toden voice clips from the server at
/// [baseUrl], in the background, as soon as the flow knows its voice (the
/// workflow resolving, or the flow opening), so they are in by the liveness
/// step's first prompt (user, 2026-11-20: the device voice said the first
/// prompts before the Toden voice took over). Asking again for the same
/// server, voice and language reuses the load. Null, and nothing fetched, with
/// guidance off, no voice or no server. Never throws or waits.
VoiceClipLoad? preloadVoiceClips(VoiceGuidanceConfig config, {required String? baseUrl}) {
  final voice = config.voice;
  if (!config.enabled || voice == null || baseUrl == null || baseUrl.isEmpty) return null;
  final language = config.resolvedLanguage;
  final id = '$baseUrl|$voice|${primaryVoiceLanguage(language)}';
  try {
    return _preloads.obtain(id, () => VoiceClipLoad(HttpVoiceAssets(baseUrl), voice: voice, language: language));
  } catch (_) {
    return null; // never the flow's problem: the device voice speaks
  }
}

/// The speaker for one liveness step: guidance off says nothing, no voice (or
/// no server) uses the device voice alone, and a voice plays its clips from
/// the flow's preload (or starts it now, when the flow did not).
LivenessSpeaker createLivenessSpeaker(
  VoiceGuidanceConfig config, {
  required String? baseUrl,
}) {
  final language = config.resolvedLanguage;
  final clips = preloadVoiceClips(config, baseUrl: baseUrl);
  final speaker = LivenessSpeaker(
    enabled: config.enabled,
    device: config.enabled ? FlutterTtsDeviceVoice(language) : const _Silent(),
    player: clips != null ? JustAudioClipPlayer() : null,
    clips: clips,
  );
  speaker.start(voice: config.voice, language: language);
  return speaker;
}

class _Silent implements DeviceVoice {
  const _Silent();
  @override
  Future<void> speak(String text, {required void Function() onDone}) async =>
      onDone();
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

/// [ClipPlayer] on just_audio.
///
/// iOS: the session is play-and-record, default-to-speaker and
/// mix-with-others, so a clip plays while the camera runs and while the
/// microphone records the liveness clip, and never stops or ducks either. The
/// camera plugin only ever adds options to the session's, so it keeps these.
/// Android: the player never asks for audio focus, so it takes nothing from
/// the recording or from other apps.
class JustAudioClipPlayer implements ClipPlayer {
  AudioPlayer? _player;

  /// Told when the clip playing ends.
  void Function()? _onDone;

  void _finished() {
    final onDone = _onDone;
    _onDone = null;
    onDone?.call();
  }

  @override
  Future<void> prepare() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker |
          AVAudioSessionCategoryOptions.mixWithOthers |
          AVAudioSessionCategoryOptions.allowBluetoothA2dp |
          AVAudioSessionCategoryOptions.allowAirPlay,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
      androidWillPauseWhenDucked: false,
    ));
    if (_player != null) return;
    final player = _player = AudioPlayer(
      handleInterruptions: false,
      handleAudioSessionActivation: false,
    );
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _finished();
    });
  }

  @override
  Future<void> play(String clip, {required void Function() onDone}) async {
    final player = _player;
    if (player == null) throw StateError('Clip player not prepared');
    _onDone = null;
    await player.setFilePath(clip);
    _onDone = onDone;
    // The clip's end comes as the completed state, above; a clip that fails
    // while playing has finished too.
    unawaited(player.play().catchError((Object _) => _finished()));
  }

  @override
  Future<void> stop() async {
    _onDone = null;
    await _player?.stop();
  }

  @override
  Future<void> dispose() async {
    _onDone = null;
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}

/// [VoiceAssets] from the KYC server: public, no key.
class HttpVoiceAssets implements VoiceAssets {
  HttpVoiceAssets(this.baseUrl, {Dio? dio, Future<Directory> Function()? cacheRoot})
      : _dio = dio ??
            Dio(BaseOptions(
              headers: {'X-SDK-Version': kSdkVersion},
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            )),
        _cacheRoot = cacheRoot ?? getTemporaryDirectory;

  final String baseUrl;
  final Dio _dio;
  final Future<Directory> Function() _cacheRoot;

  Uri get _manifestUrl {
    final base = Uri.parse(baseUrl);
    return base.replace(pathSegments: [
      ...base.pathSegments.where((s) => s.isNotEmpty),
      ...kVoiceAssetsPath.split('/').where((s) => s.isNotEmpty),
      'manifest.json',
    ]);
  }

  @override
  Future<VoiceManifest> manifest() async {
    final res = await _dio.getUri<Object?>(
      _manifestUrl,
      options: Options(responseType: ResponseType.json),
    );
    return VoiceManifest.fromJson(res.data);
  }

  @override
  Future<String> clip(VoiceClipRef ref) async {
    final root = await _cacheRoot();
    final file = File([root.path, 'toden_voices', ...ref.pathSegments].join('/'));
    if (await file.exists() && await file.length() > 0) return file.path;

    final res = await _dio.getUri<List<int>>(
      ref.url(baseUrl),
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = res.data;
    if (bytes == null || bytes.isEmpty) throw const FormatException('Empty clip');
    await file.parent.create(recursive: true);
    // Written aside and moved into place, so a half-written clip is never read.
    final part = File('${file.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(file.path);
    return file.path;
  }
}
