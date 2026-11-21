import 'package:flutter_tts/flutter_tts.dart';

import 'liveness_speaker.dart' show DeviceVoice;

// ─── The device voice ────────────────────────────────────────────────────────
//
// The fallback for every phrase no Toden voice clip says. It takes the
// platform's Enhanced (or Premium) voice for the language when the device has
// one installed, else the platform's default voice for it.

/// The best voice [voices] (flutter_tts `getVoices`) offers for [language], as
/// `setVoice` takes it, or null to keep the default voice.
///
/// iOS reports `quality` as `premium`, `enhanced` or `default`; some voices
/// also say "(Enhanced)" in their name. Android reports `very high` down to
/// `very low`, and only a voice installed on the device that needs no
/// network counts. A region in [language] must match; a bare language
/// (`en`) takes any region.
Map<String, String>? pickEnhancedVoice(Object? voices, String language) {
  if (voices is! List) return null;
  final wanted = _localeTag(language);
  final regionless = !wanted.contains('-');
  Map<String, String>? best;
  var bestRank = 0;
  for (final raw in voices) {
    if (raw is! Map) continue;
    final voice = {
      for (final e in raw.entries)
        if (e.key is String && e.value != null) e.key as String: '${e.value}',
    };
    final name = voice['name'];
    final locale = voice['locale'];
    if (name == null || locale == null) continue;
    final tag = _localeTag(locale);
    final matches = regionless ? tag.split('-').first == wanted : tag == wanted;
    if (!matches) continue;
    final rank = _enhancedRank(voice);
    if (rank > bestRank) {
      bestRank = rank;
      best = {
        'name': name,
        'locale': locale,
        if (voice['identifier'] != null) 'identifier': voice['identifier']!,
      };
    }
  }
  return best;
}

String _localeTag(String locale) =>
    locale.trim().replaceAll('_', '-').toLowerCase();

/// 0 for an ordinary voice; higher is better.
int _enhancedRank(Map<String, String> voice) {
  if (voice['network_required'] == '1') return 0;
  if ((voice['features'] ?? '').toLowerCase().contains('notinstalled')) return 0;
  final quality = (voice['quality'] ?? '').toLowerCase();
  final name = (voice['name'] ?? '').toLowerCase();
  if (quality == 'premium' || name.contains('(premium)')) return 3;
  if (quality == 'enhanced' || name.contains('(enhanced)')) return 2;
  if (quality == 'very high') return 1;
  return 0;
}

/// [DeviceVoice] on flutter_tts. Output only: no microphone.
class FlutterTtsDeviceVoice implements DeviceVoice {
  FlutterTtsDeviceVoice(String language) {
    // An error ends the phrase as surely as its end does: the next one is not
    // held up by it.
    _tts
      ..setCompletionHandler(_finished)
      ..setCancelHandler(_finished)
      ..setErrorHandler((_) => _finished());
    // An engine that refuses the set-up still speaks with its defaults.
    _ready = _setUp(language).catchError((Object _) {});
  }

  final FlutterTts _tts = FlutterTts();
  late final Future<void> _ready;

  /// Told when the phrase being said ends.
  void Function()? _onDone;

  void _finished() {
    final onDone = _onDone;
    _onDone = null;
    onDone?.call();
  }

  Future<void> _setUp(String language) async {
    await _tts.setLanguage(language);
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    try {
      final voice = pickEnhancedVoice(await _tts.getVoices, language);
      if (voice != null) await _tts.setVoice(voice);
    } catch (_) {
      // The default voice for the language stays.
    }
  }

  @override
  Future<void> speak(String text, {required void Function() onDone}) async {
    await _ready;
    _onDone = onDone;
    await _tts.speak(text);
  }

  @override
  Future<void> stop() => _tts.stop();

  @override
  Future<void> dispose() => _tts.stop();
}
