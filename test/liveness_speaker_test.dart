import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/liveness/liveness_speaker.dart';
import 'package:toden_flutter/src/liveness/voice_clips.dart';

// Which voice says each liveness phrase: a loaded Toden clip whose text is the
// phrase, else the device voice, and never an error that reaches the flow.
// Phrases take turns: none is cut off, and only the newest waiting is said.

class _Device implements DeviceVoice {
  final List<String> said = [];
  int stops = 0;
  bool disposed = false;
  bool failSpeak = false;
  void Function()? _onDone;

  /// The engine's end event (completion, cancel or error) for the phrase.
  void end() => _onDone?.call();

  @override
  Future<void> speak(String text, {required void Function() onDone}) async {
    if (failSpeak) throw Exception('engine');
    said.add(text);
    _onDone = onDone;
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async => disposed = true;
}

class _Player implements ClipPlayer {
  final List<String> played = [];
  bool prepared = false;
  bool failPlay = false;
  int stops = 0;
  bool disposed = false;
  void Function()? _onDone;

  /// The clip has played to the end.
  void end() => _onDone?.call();

  @override
  Future<void> prepare() async => prepared = true;
  @override
  Future<void> play(String clip, {required void Function() onDone}) async {
    if (failPlay) throw Exception('decoder');
    played.add(clip);
    _onDone = onDone;
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async => disposed = true;
}

class _Assets implements VoiceAssets {
  _Assets({this.manifestFuture, this.missing = const {}});

  /// Null answers the manifest below at once.
  final Future<VoiceManifest> Function()? manifestFuture;
  final Set<String> missing;
  int manifestCalls = 0;
  final List<VoiceClipRef> fetched = [];
  final Map<String, Completer<String>> pending = {};
  bool holdClips = false;

  @override
  Future<VoiceManifest> manifest() {
    manifestCalls++;
    return manifestFuture?.call() ?? Future.value(_manifest);
  }

  @override
  Future<String> clip(VoiceClipRef ref) async {
    fetched.add(ref);
    if (missing.contains(ref.phraseKey)) throw Exception('404');
    if (holdClips) {
      return (pending[ref.phraseKey] = Completer<String>()).future;
    }
    return 'clip:${ref.phraseKey}';
  }
}

final _manifest = VoiceManifest.fromJson(const {
  'version': 'v1',
  'voices': {
    'lyra': {'languages': ['en']},
  },
  'phrases': {
    'en': {
      'presence.position.holdStill': 'Hold still',
      'presence.challenge.nod': 'Nod your head',
      'presence.challenge.passed': 'Good.',
    },
  },
});

const _pause = kPauseBetweenPhrases;

void main() {
  late _Device device;
  late _Player player;

  setUp(() {
    device = _Device();
    player = _Player();
  });

  LivenessSpeaker speaker(_Assets assets, {bool enabled = true, Duration? timeout}) =>
      LivenessSpeaker(
        enabled: enabled,
        device: device,
        player: player,
        assets: assets,
        manifestTimeout: timeout ?? kVoiceManifestTimeout,
      );

  /// A speaker with Lyra's clips loaded, in fake time.
  LivenessSpeaker withClips(FakeAsync async, {_Assets? assets}) {
    final s = speaker(assets ?? _Assets())..start(voice: 'lyra', language: 'en');
    async.flushMicrotasks();
    return s;
  }

  /// Says [text] and lets it start.
  void say(FakeAsync async, LivenessSpeaker s, String text) {
    s.speak(text);
    async.flushMicrotasks();
  }

  group('which voice says it', () {
    test('plays the loaded clip whose text is the phrase, after normalising', () {
      fakeAsync((async) {
        final assets = _Assets();
        final s = speaker(assets)..start(voice: 'lyra', language: 'en-US');
        async.flushMicrotasks();

        say(async, s, 'Hold still…');
        expect(player.prepared, isTrue);
        expect(player.played, ['clip:presence.position.holdStill']);
        expect(device.said, isEmpty);
        expect(assets.fetched.map((r) => r.language).toSet(), {'en'});
        expect(assets.fetched.map((r) => r.phraseKey).toSet(), {
          'presence.position.holdStill',
          'presence.challenge.nod',
          'presence.challenge.passed',
        });
      });
    });

    test('a reworded phrase goes to the device voice', () {
      fakeAsync((async) {
        final s = withClips(async);
        say(async, s, 'Please nod your head slowly');
        expect(player.played, isEmpty);
        expect(device.said, ['Please nod your head slowly']);
      });
    });

    test('a clip that did not load goes to the device voice', () {
      fakeAsync((async) {
        final s = withClips(async, assets: _Assets(missing: {'presence.challenge.nod'}));
        say(async, s, 'Nod your head');
        device.end();
        async.elapse(_pause);
        say(async, s, 'Good.');
        expect(device.said, ['Nod your head']);
        expect(player.played, ['clip:presence.challenge.passed']);
      });
    });

    test('a clip still loading is waited for, briefly, then played', () {
      fakeAsync((async) {
        final assets = _Assets()..holdClips = true;
        final s = withClips(async, assets: assets);
        say(async, s, 'Nod your head');
        async.elapse(const Duration(milliseconds: 800));
        expect(device.said, isEmpty, reason: 'the Toden clip is on its way');
        assets.pending['presence.challenge.nod']!.complete('clip:nod');
        async.flushMicrotasks();
        expect(player.played, ['clip:nod']);
        expect(device.said, isEmpty);
      });
    });

    test('a clip still loading after the grace goes to the device voice', () {
      fakeAsync((async) {
        final assets = _Assets()..holdClips = true;
        final s = withClips(async, assets: assets);
        say(async, s, 'Nod your head');
        async.elapse(kFirstClipGrace);
        expect(device.said, ['Nod your head']);
        expect(player.played, isEmpty);
        device.end();
        async.elapse(_pause);

        assets.pending['presence.position.holdStill']!.complete('clip:hold');
        async.flushMicrotasks();
        say(async, s, 'Hold still');
        expect(player.played, ['clip:hold']);
      });
    });

    test('a manifest still on its way is waited for too, within the grace', () {
      fakeAsync((async) {
        final later = Completer<VoiceManifest>();
        final s = speaker(_Assets(manifestFuture: () => later.future))..start(voice: 'lyra', language: 'en');
        say(async, s, 'Good.');
        async.elapse(const Duration(milliseconds: 500));
        expect(device.said, isEmpty);
        later.complete(_manifest);
        async.flushMicrotasks();
        expect(player.played, ['clip:presence.challenge.passed']);
      });
    });

    test('never waits for a phrase with no clip, or once loading has failed', () {
      fakeAsync((async) {
        final assets = _Assets()..holdClips = true;
        final s = withClips(async, assets: assets);
        say(async, s, 'Please nod your head slowly');
        expect(device.said, ['Please nod your head slowly'], reason: 'no clip has this text');

        final failed = speaker(_Assets(manifestFuture: () => Future.error(Exception('404'))))
          ..start(voice: 'lyra', language: 'en');
        async.flushMicrotasks();
        device.said.clear();
        say(async, failed, 'Hold still');
        expect(device.said, ['Hold still']);
      });
    });

    test('never waits without a voice', () {
      fakeAsync((async) {
        final s = speaker(_Assets())..start(language: 'en');
        say(async, s, 'Hold still');
        expect(device.said, ['Hold still']);
      });
    });

    test('a clip that will not play goes to the device voice', () {
      fakeAsync((async) {
        final s = withClips(async);
        player.failPlay = true;
        say(async, s, 'Good.');
        expect(device.said, ['Good.']);
      });
    });

    test('no manifest (404) leaves everything to the device voice', () {
      fakeAsync((async) {
        final assets = _Assets(manifestFuture: () => Future.error(Exception('404')));
        final s = withClips(async, assets: assets);
        say(async, s, 'Hold still');
        expect(device.said, ['Hold still']);
        expect(player.played, isEmpty);
        expect(player.prepared, isFalse);
        expect(assets.fetched, isEmpty);
      });
    });

    test('a manifest that takes too long is given up on', () {
      fakeAsync((async) {
        final never = Completer<VoiceManifest>();
        final assets = _Assets(manifestFuture: () => never.future);
        final s = speaker(assets, timeout: const Duration(milliseconds: 10))
          ..start(voice: 'lyra', language: 'en');
        async.elapse(const Duration(milliseconds: 10));
        say(async, s, 'Hold still');
        expect(device.said, ['Hold still']);
        expect(assets.fetched, isEmpty);
      });
    });

    test('a voice or language the manifest lacks fetches no clips', () {
      fakeAsync((async) {
        final assets = _Assets();
        final s = speaker(assets)..start(voice: 'danny', language: 'en');
        async.flushMicrotasks();
        expect(assets.fetched, isEmpty);
        say(async, s, 'Hold still');
        expect(device.said, ['Hold still']);
      });
    });

    test('no voice fetches no manifest', () {
      fakeAsync((async) {
        final assets = _Assets();
        final s = speaker(assets)..start(language: 'en-US');
        async.flushMicrotasks();
        say(async, s, 'Hold still');
        expect(assets.manifestCalls, 0);
        expect(device.said, ['Hold still']);
      });
    });

    test('the manifest is fetched once a session', () async {
      final assets = _Assets();
      final s = speaker(assets)
        ..start(voice: 'lyra', language: 'en')
        ..start(voice: 'lyra', language: 'en');
      await s.clipsLoaded;
      expect(assets.manifestCalls, 1);
    });

    test('guidance off says nothing and fetches nothing', () {
      fakeAsync((async) {
        final assets = _Assets();
        final s = speaker(assets, enabled: false)..start(voice: 'lyra', language: 'en');
        async.flushMicrotasks();
        say(async, s, 'Hold still');
        expect(assets.manifestCalls, 0);
        expect(device.said, isEmpty);
        expect(player.played, isEmpty);
      });
    });
  });

  group('turn-taking', () {
    test('a phrase waits for the one being said, then a pause', () {
      fakeAsync((async) {
        final s = withClips(async);
        say(async, s, 'Hold still');
        say(async, s, 'Move closer');
        expect(player.played, ['clip:presence.position.holdStill']);
        expect(device.said, isEmpty);
        expect(player.stops + device.stops, 2, reason: 'nothing was cut off');

        player.end();
        async.elapse(_pause - const Duration(milliseconds: 1));
        expect(device.said, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(device.said, ['Move closer']);
      });
    });

    test('a device phrase is waited for too', () {
      fakeAsync((async) {
        final s = withClips(async);
        say(async, s, 'Move closer');
        say(async, s, 'Nod your head');
        expect(player.played, isEmpty);

        device.end();
        async.elapse(_pause);
        expect(player.played, ['clip:presence.challenge.nod']);
      });
    });

    test('only the newest waiting phrase is said', () {
      fakeAsync((async) {
        final s = speaker(_Assets());
        say(async, s, 'Hold still');
        say(async, s, 'Move closer');
        say(async, s, 'Centre your face');
        device.end();
        async.elapse(_pause);
        device.end();
        async.elapse(_pause);
        expect(device.said, ['Hold still', 'Centre your face']);
      });
    });

    test('a waiting phrase equal to the one being said is dropped', () {
      fakeAsync((async) {
        final s = speaker(_Assets());
        say(async, s, 'Hold still');
        say(async, s, 'Move closer');
        say(async, s, 'Hold still.');
        device.end();
        async.elapse(_pause * 4);
        expect(device.said, ['Hold still']);
      });
    });

    test('the same phrase twice in a row is said once, until a stop', () {
      fakeAsync((async) {
        final s = speaker(_Assets());
        say(async, s, 'Move closer');
        device.end();
        async.elapse(_pause);
        say(async, s, 'Move closer.');
        expect(device.said, ['Move closer']);
        s.stop();
        async.flushMicrotasks();
        say(async, s, 'Move closer');
        expect(device.said, ['Move closer', 'Move closer']);
      });
    });

    test('a device voice that fails has finished', () {
      fakeAsync((async) {
        final s = speaker(_Assets());
        device.failSpeak = true;
        say(async, s, 'Hold still');
        device.failSpeak = false;
        say(async, s, 'Move closer');
        async.elapse(_pause);
        expect(device.said, ['Move closer']);
      });
    });

    test('the watchdog ends a phrase whose end never comes', () {
      fakeAsync((async) {
        final s = speaker(_Assets());
        say(async, s, 'Hold still');
        say(async, s, 'Move closer');
        async.elapse(longestPhrase('Hold still'));
        expect(device.said, ['Hold still']);
        async.elapse(_pause);
        expect(device.said, ['Hold still', 'Move closer']);
      });
    });

    test('a late end event from an earlier phrase is ignored', () {
      fakeAsync((async) {
        final s = speaker(_Assets());
        say(async, s, 'Hold still');
        final endHold = device._onDone!;
        device.end();
        async.elapse(_pause);
        say(async, s, 'Move closer');
        say(async, s, 'Centre your face');
        endHold();
        async.elapse(_pause);
        expect(device.said, ['Hold still', 'Move closer']);
      });
    });

    test('skipping the waiting phrase lets the one being said finish', () {
      fakeAsync((async) {
        final s = speaker(_Assets());
        say(async, s, 'Hold still. The screen will flash briefly');
        say(async, s, 'Move closer');
        final stops = device.stops;
        s.skipWaiting();
        expect(device.stops, stops, reason: 'nothing was cut off');

        device.end();
        async.elapse(_pause);
        expect(device.said, ['Hold still. The screen will flash briefly']);
        say(async, s, 'Move closer');
        expect(device.said.last, 'Move closer');
      });
    });

    test('stop cuts off the phrase and forgets the waiting one', () {
      fakeAsync((async) {
        final s = withClips(async);
        say(async, s, 'Hold still');
        say(async, s, 'Move closer');
        final stops = player.stops;
        s.stop();
        async.flushMicrotasks();
        expect(player.stops, stops + 1);
        async.elapse(longestPhrase('Hold still') + _pause);
        expect(device.said, isEmpty);

        say(async, s, 'Nod your head');
        expect(player.played.last, 'clip:presence.challenge.nod');
      });
    });

    test('dispose stops everything and says nothing after', () {
      fakeAsync((async) {
        final s = withClips(async);
        say(async, s, 'Move closer');
        say(async, s, 'Hold still');
        s.dispose();
        async.flushMicrotasks();
        say(async, s, 'Nod your head');
        async.elapse(longestPhrase('Move closer') + _pause);
        expect(device.disposed, isTrue);
        expect(player.disposed, isTrue);
        expect(device.said, ['Move closer']);
        expect(player.played, isEmpty);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('the clips load once, before the step', () {
    test('a preload made when the flow opens is played from, and fetches nothing more', () {
      fakeAsync((async) {
        final assets = _Assets();
        final preloads = VoicePreloads();
        final load = preloads.obtain('srv|lyra|en', () => VoiceClipLoad(assets, voice: 'lyra', language: 'en'));
        async.flushMicrotasks();
        expect(assets.manifestCalls, 1);
        expect(assets.fetched, hasLength(3));

        // The liveness step asks again: the same load, nothing fetched twice.
        expect(preloads.obtain('srv|lyra|en', () => VoiceClipLoad(_Assets(), voice: 'lyra', language: 'en')), same(load));
        final s = LivenessSpeaker(enabled: true, device: device, player: player, clips: load)
          ..start(voice: 'lyra', language: 'en');
        async.flushMicrotasks();
        say(async, s, 'Hold still');
        expect(player.played, ['clip:presence.position.holdStill']);
        expect(assets.manifestCalls, 1);
        expect(assets.fetched, hasLength(3));
      });
    });

    test('a preload whose manifest failed is tried again by the next asker', () {
      fakeAsync((async) {
        final preloads = VoicePreloads();
        final failed = preloads.obtain('srv|lyra|en',
            () => VoiceClipLoad(_Assets(manifestFuture: () => Future.error(Exception('offline'))), voice: 'lyra', language: 'en'));
        async.flushMicrotasks();
        expect(failed.failed, isTrue);
        final again = preloads.obtain('srv|lyra|en', () => VoiceClipLoad(_Assets(), voice: 'lyra', language: 'en'));
        expect(again, isNot(same(failed)));
      });
    });
  });
}
