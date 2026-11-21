import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'voice_clips.dart';

// ─── The liveness speaker ────────────────────────────────────────────────────
//
// Says each liveness prompt: with the workflow's Toden voice when a clip for
// that exact text is loaded, else with the device's speech engine, as before.
// Nothing here throws or makes the flow wait: a manifest that does not come,
// a clip that does not load and a clip that will not play all leave that
// phrase to the device voice. The platform parts sit behind the three
// interfaces below (voice_playback.dart), so tests need no platform channels.
//
// Turn-taking (the same in all three SDKs). A phrase is never cut off
// mid-word: one that arrives while another is being said waits for it to
// finish, then a short pause, and only the NEWEST waiting phrase is said
// (guidance that changed twice meanwhile skips the stale one in between).
// Cutting the last phrase off for every new one made the prompts run into
// each other ("Hold sti- Turn your head"), which a person following them can
// mistake for one garbled instruction.

/// The pause between the end of one phrase and the start of the next. A
/// breath, as between two things a person says to you: at a quarter of a
/// second the prompts came back to back ("Hold still" "Turn your head"
/// "Good.") and read as rushed, barked commands, though each clip alone is
/// calm (user, 2026-11-17). The web SDK's PAUSE_BETWEEN_PHRASES_MS.
const kPauseBetweenPhrases = Duration(milliseconds: 700);

/// PURE. Far longer than any prompt takes to say, at the device voice's
/// slowest: a phrase whose end event never comes is taken as said after it,
/// so the phrases after it are not held up for ever.
Duration longestPhrase(String text) =>
    Duration(milliseconds: 2000 + text.length * 120);

/// How long a phrase whose Toden clip is still on its way waits for it before
/// the device voice says it. The clips start loading when the flow opens
/// (voice_playback.dart preloadVoiceClips), so by the liveness step they are
/// usually in; this covers a slow network on the first run, where the device
/// voice used to say the first prompt or two and then the Toden voice took
/// over (user, 2026-11-20). Never waited when there is no voice, the manifest
/// failed, or the phrase has no clip.
const kFirstClipGrace = Duration(milliseconds: 2000);

/// The device's speech engine.
abstract interface class DeviceVoice {
  /// Starts saying [text], and calls [onDone] once it has been said, stopped
  /// or has failed.
  Future<void> speak(String text, {required void Function() onDone});
  Future<void> stop();
  Future<void> dispose();
}

/// Plays a clip that [VoiceAssets.clip] made ready.
abstract interface class ClipPlayer {
  /// Sets the platform up for playing beside the camera and microphone.
  Future<void> prepare();

  /// Starts [clip], and calls [onDone] once it has played to the end or has
  /// failed. Throws when it cannot be played.
  Future<void> play(String clip, {required void Function() onDone});
  Future<void> stop();
  Future<void> dispose();
}

/// The server's voice assets.
abstract interface class VoiceAssets {
  /// The manifest. Throws when there is none (the switch is off: 404).
  Future<VoiceManifest> manifest();

  /// Makes one clip ready to play and answers its handle for
  /// [ClipPlayer.play]. Throws when it cannot.
  Future<String> clip(VoiceClipRef ref);
}

/// One voice's clips in one language, loading from [VoiceAssets] in the
/// background from the moment it is made: the manifest, then every clip of
/// the voice at once. Shared by the flow's early preload and the liveness
/// speaker ([VoicePreloads]), so nothing is fetched twice. Never throws.
class VoiceClipLoad {
  VoiceClipLoad(
    this._assets, {
    required this.voice,
    required this.language,
    Duration manifestTimeout = kVoiceManifestTimeout,
  }) {
    settled = _run(manifestTimeout);
  }

  final VoiceAssets _assets;
  final String voice;
  final String language;

  final Completer<Map<String, String>?> _keys = Completer();
  final Map<String, Future<String?>> _clips = {};
  bool _failed = false;

  /// Resolves when the manifest and every clip have answered, however.
  late final Future<void> settled;

  /// Normalised text to phrase key; null when there is no manifest (off,
  /// failed or too slow) or it has no clips for this voice and language.
  Future<Map<String, String>?> get keys => _keys.future;

  /// Whether the manifest never gave clips: a later load may try again.
  bool get failed => _failed;

  /// One phrase's clip, ready to play; null when it did not load. Only
  /// meaningful once [keys] has answered.
  Future<String?> clip(String phraseKey) => _clips[phraseKey] ?? Future<String?>.value();

  Future<void> _run(Duration manifestTimeout) async {
    try {
      final manifest = await _assets.manifest().timeout(manifestTimeout);
      final keys = manifest.phraseKeysByText(voice, language);
      if (keys == null) {
        _failed = true;
        _keys.complete(null);
        return;
      }
      final lang = primaryVoiceLanguage(language);
      for (final key in keys.values.toSet()) {
        _clips[key] = _assets
            .clip(VoiceClipRef(version: manifest.version, voice: voice, language: lang, phraseKey: key))
            .then<String?>((path) => path, onError: (Object _) => null);
      }
      _keys.complete(keys);
      await Future.wait(_clips.values);
    } catch (_) {
      // No manifest: the device voice speaks.
      _failed = true;
      if (!_keys.isCompleted) _keys.complete(null);
    }
  }
}

/// The voice loads of this app process, one per server, voice and language,
/// so the flow's early preload and the liveness step share one. A load whose
/// manifest failed is replaced the next time it is asked for.
class VoicePreloads {
  final Map<String, VoiceClipLoad> _loads = {};

  /// The load for [id], made with [create] unless a usable one exists.
  VoiceClipLoad obtain(String id, VoiceClipLoad Function() create) {
    final existing = _loads[id];
    if (existing != null && !existing.failed) return existing;
    return _loads[id] = create();
  }

  @visibleForTesting
  void clear() => _loads.clear();
}

class LivenessSpeaker {
  LivenessSpeaker({
    required bool enabled,
    required DeviceVoice device,
    ClipPlayer? player,
    VoiceAssets? assets,
    VoiceClipLoad? clips,
    Duration manifestTimeout = kVoiceManifestTimeout,
    Duration clipGrace = kFirstClipGrace,
  })  : _enabled = enabled,
        _device = device,
        _player = player,
        _assets = assets,
        _preloaded = clips,
        _manifestTimeout = manifestTimeout,
        _clipGrace = clipGrace;

  final bool _enabled;
  final DeviceVoice _device;
  final ClipPlayer? _player;
  final VoiceAssets? _assets;
  final VoiceClipLoad? _preloaded;
  final Duration _manifestTimeout;
  final Duration _clipGrace;

  /// The clips this speaker plays from, once [start] has been asked for a voice.
  VoiceClipLoad? _load;

  /// Set once the load has settled: from then on nothing is waited for.
  bool _loadSettled = false;

  /// The player made ready, once (memoised so a waiting phrase and the load share it).
  Future<bool>? _playerReady;

  /// Normalised text to phrase key, once the manifest has answered.
  Map<String, String> _keysByText = const {};

  /// Phrase key to a clip ready to play.
  final Map<String, String> _readyClips = {};

  /// The last phrase asked for, normalised: the same phrase twice in a row is
  /// said once (a guidance line set again on every frame, say).
  String? _lastSpoken;

  /// The phrase being said, normalised, until the pause after it is over.
  String? _speaking;

  /// The newest phrase waiting for its turn.
  String? _waiting;

  /// Bumped by every phrase and every stop, so a late end event from an
  /// earlier phrase, or a phrase still starting after a stop, is ignored.
  int _turn = 0;

  /// The pause after a phrase, or the watchdog that ends a phrase whose end
  /// never came.
  Timer? _turnTimer;
  bool _disposed = false;
  Future<void>? _clipsLoaded;

  /// Resolves when the clip preload has finished, whatever its outcome.
  @visibleForTesting
  Future<void> get clipsLoaded => _clipsLoaded ?? Future<void>.value();

  /// Starts loading [voice]'s clips in [language], in the background. No
  /// voice, guidance off or no player leaves every phrase to the device voice
  /// and fetches nothing.
  void start({String? voice, required String language}) {
    final player = _player;
    if (!_enabled || voice == null || player == null) return;
    if (_clipsLoaded != null) return;
    final load = _preloaded ??
        (_assets == null
            ? null
            : VoiceClipLoad(_assets, voice: voice, language: language, manifestTimeout: _manifestTimeout));
    if (load == null) return;
    _load = load;
    _clipsLoaded = _loadClips(load);
  }

  Future<bool> _preparedPlayer() => _playerReady ??= _player!
      .prepare()
      .then((_) => true, onError: (Object _) => false);

  Future<void> _loadClips(VoiceClipLoad load) async {
    try {
      final keys = await load.keys;
      if (keys == null || _disposed) return;
      if (!await _preparedPlayer() || _disposed) return;
      _keysByText = keys;
      await Future.wait(keys.values.toSet().map((key) async {
        final clip = await load.clip(key);
        if (clip != null && !_disposed) _readyClips[key] = clip;
      }));
    } catch (_) {
      // No manifest, no voice or no audio set-up: the device voice speaks.
    } finally {
      _loadSettled = true;
    }
  }

  /// [phrase]'s clip, ready to play: at once when it is in; while the clips
  /// are still loading, waited for up to [_clipGrace]; else null, for the
  /// device voice. Nothing is waited for with no voice, once loading has
  /// settled, when the manifest failed, or for a phrase with no clip.
  Future<String?> _clipFor(String phrase) async {
    final known = _keysByText[phrase];
    if (known != null && _readyClips[known] != null) return _readyClips[known];
    final load = _load;
    if (load == null || _loadSettled) return null;
    try {
      return await _awaitClip(load, phrase).timeout(_clipGrace);
    } on TimeoutException {
      return null;
    }
  }

  Future<String?> _awaitClip(VoiceClipLoad load, String phrase) async {
    final keys = await load.keys;
    final key = keys?[phrase];
    if (key == null) return null;
    final clip = await load.clip(key);
    if (clip == null || !await _preparedPlayer()) return null;
    return clip;
  }

  /// Says [text] once the phrase being said has finished. A loaded clip whose
  /// text matches plays; anything else goes to the device voice.
  void speak(String text) {
    if (!_enabled || _disposed) return;
    final phrase = normaliseVoicePhrase(text);
    if (phrase.isEmpty || phrase == _lastSpoken) return;
    _lastSpoken = phrase;
    if (_speaking != null) {
      _waiting = phrase == _speaking ? null : text;
      return;
    }
    _startPhrase(text);
  }

  void _startPhrase(String text) {
    final phrase = normaliseVoicePhrase(text);
    _speaking = phrase;
    final turn = ++_turn;
    void finished() => _finishPhrase(turn);
    // The watchdog allows for the wait on a loading clip; it starts over once
    // the phrase actually starts (_say).
    _setTurnTimer(longestPhrase(text) + _clipGrace, finished);
    unawaited(_say(text, phrase, turn, finished));
  }

  Future<void> _say(
    String text,
    String phrase,
    int turn,
    void Function() finished,
  ) async {
    // Nothing should be playing; this only clears a phrase the watchdog ended.
    await _silence();
    if (turn != _turn) return;
    final clip = await _clipFor(phrase);
    if (turn != _turn || _disposed) return;
    _setTurnTimer(longestPhrase(text), finished);
    if (clip != null && await _played(clip, finished)) return;
    if (turn != _turn) return;
    try {
      await _device.speak(text, onDone: finished);
    } catch (_) {
      finished(); // a device voice that fails has finished
    }
  }

  Future<bool> _played(String clip, void Function() finished) async {
    try {
      await _player!.play(clip, onDone: finished);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The phrase of [turn] has been said: pause, then say the one waiting.
  void _finishPhrase(int turn) {
    if (turn != _turn || _speaking == null) return;
    _setTurnTimer(kPauseBetweenPhrases, () {
      _speaking = null;
      final next = _waiting;
      _waiting = null;
      if (next != null && !_disposed) _startPhrase(next);
    });
  }

  void _setTurnTimer(Duration after, void Function() run) {
    _turnTimer?.cancel();
    _turnTimer = Timer(after, () {
      _turnTimer = null;
      run();
    });
  }

  /// Forgets the phrase waiting for its turn and lets the one being said
  /// finish (the flash starts: what was asked before it is out of date).
  void skipWaiting() {
    _waiting = null;
    _lastSpoken = _speaking;
  }

  /// Stops whatever is being said, forgets the phrase waiting and the last
  /// phrase, so the next one is said at once even when it repeats it (a retry
  /// starts over).
  Future<void> stop() async {
    _endTurns();
    _lastSpoken = null;
    await _silence();
  }

  void _endTurns() {
    _turn++;
    _turnTimer?.cancel();
    _turnTimer = null;
    _speaking = null;
    _waiting = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    _endTurns();
    _readyClips.clear();
    await _silence();
    await _quietly(_device.dispose);
    final player = _player;
    if (player != null) await _quietly(player.dispose);
  }

  Future<void> _silence() async {
    final player = _player;
    await Future.wait([
      if (player != null) _quietly(player.stop),
      _quietly(_device.stop),
    ]);
  }

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Speech is best-effort: a failure never reaches the flow.
    }
  }
}
