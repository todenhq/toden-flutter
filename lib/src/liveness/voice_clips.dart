// ─── Toden voice clips: the manifest and the matching rule ───────────────────
//
// An organisation picks a Toden voice per workflow. Toden pre-records one clip
// per voice, language and phrase and serves them from the KYC server
// (kyc-core docs/VOICE_GUIDANCE.md is the contract). This file is the pure
// part: reading the manifest, and matching the text about to be spoken to a
// clip. liveness_speaker.dart decides what plays; voice_playback.dart fetches
// and plays.

/// Where the server serves the voice assets, under its base URL.
const String kVoiceAssetsPath = '/api/kyc/assets/voices';

/// How long the manifest gets before the device voice is kept for the session.
const Duration kVoiceManifestTimeout = Duration(seconds: 3);

final RegExp _curlyApostrophes = RegExp('[‘’ʼ]');
final RegExp _whitespace = RegExp(r'\s', unicode: true);
final RegExp _notLetterDigitApostropheSpace =
    RegExp(r"[^\p{L}\p{N}' ]+", unicode: true);
final RegExp _spaceRuns = RegExp(' {2,}');

/// The one rule every Toden SDK uses to compare a text with a clip's text:
/// NFKC, lower case, curly apostrophes made straight, everything but letters,
/// digits, apostrophes and spaces removed, spaces collapsed. "Hold still…",
/// "Hold still." and "hold still" all become "hold still".
///
/// Dart has no Unicode normaliser, so NFKC is applied for the compatibility
/// characters a prompt can realistically hold (full-width forms and the Latin
/// ligatures; spaces and punctuation are handled by the steps after it).
String normaliseVoicePhrase(String text) => _compatibilityForms(text)
    .toLowerCase()
    .replaceAll(_curlyApostrophes, "'")
    .replaceAll(_whitespace, ' ')
    .replaceAll(_notLetterDigitApostropheSpace, '')
    .replaceAll(_spaceRuns, ' ')
    .trim();

const Map<int, String> _ligatures = {
  0xFB00: 'ff',
  0xFB01: 'fi',
  0xFB02: 'fl',
  0xFB03: 'ffi',
  0xFB04: 'ffl',
  0xFB05: 'st',
  0xFB06: 'st',
};

String _compatibilityForms(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      out.writeCharCode(rune - 0xFEE0); // full-width ASCII
    } else {
      out.write(_ligatures[rune] ?? String.fromCharCode(rune));
    }
  }
  return out.toString();
}

/// The primary subtag of a BCP-47 tag, lower case: `en-US` is `en`.
String primaryVoiceLanguage(String tag) =>
    tag.split(RegExp('[-_]')).first.trim().toLowerCase();

// A version, voice, language or phrase key from the server becomes part of a
// URL and of a cache file's path, so only plain segments are accepted.
final RegExp _safeSegment = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

bool _isSafeSegment(Object? value) =>
    value is String && _safeSegment.hasMatch(value) && !value.contains('..');

/// The manifest at `{server}/api/kyc/assets/voices/manifest.json`.
class VoiceManifest {
  /// Changes whenever any clip changes; part of every clip URL.
  final String version;

  /// Voice id to the languages it has clips in.
  final Map<String, Set<String>> voices;

  /// Language, then phrase key, then the exact text of that clip.
  final Map<String, Map<String, String>> phrases;

  const VoiceManifest({
    required this.version,
    required this.voices,
    required this.phrases,
  });

  /// Reads the server's JSON. Throws [FormatException] when it is not a
  /// manifest. Entries with an unusable id are left out.
  factory VoiceManifest.fromJson(Object? json) {
    if (json is! Map || !_isSafeSegment(json['version'])) {
      throw const FormatException('Not a voice manifest');
    }
    final voices = <String, Set<String>>{};
    final rawVoices = json['voices'];
    if (rawVoices is Map) {
      rawVoices.forEach((id, entry) {
        final languages = entry is Map ? entry['languages'] : null;
        if (!_isSafeSegment(id) || languages is! List) return;
        voices[id as String] = languages.where(_isSafeSegment).cast<String>().toSet();
      });
    }
    final phrases = <String, Map<String, String>>{};
    final rawPhrases = json['phrases'];
    if (rawPhrases is Map) {
      rawPhrases.forEach((lang, texts) {
        if (!_isSafeSegment(lang) || texts is! Map) return;
        phrases[lang as String] = {
          for (final entry in texts.entries)
            if (_isSafeSegment(entry.key) && entry.value is String)
              entry.key as String: entry.value as String,
        };
      });
    }
    return VoiceManifest(
      version: json['version'] as String,
      voices: voices,
      phrases: phrases,
    );
  }

  /// Normalised text to phrase key for [voice] in [language], or null when
  /// the manifest has no clips for that pair.
  Map<String, String>? phraseKeysByText(String voice, String language) {
    final lang = primaryVoiceLanguage(language);
    final texts = phrases[lang];
    if (texts == null || !(voices[voice]?.contains(lang) ?? false)) return null;
    return {
      for (final entry in texts.entries)
        normaliseVoicePhrase(entry.value): entry.key,
    };
  }
}

/// One clip: what a fetch needs to find it, and to cache it.
class VoiceClipRef {
  final String version;
  final String voice;
  final String language;
  final String phraseKey;

  const VoiceClipRef({
    required this.version,
    required this.voice,
    required this.language,
    required this.phraseKey,
  });

  /// `{version}/{voice}/{lang}/{phraseKey}.mp3`, under [kVoiceAssetsPath].
  List<String> get pathSegments => [version, voice, language, '$phraseKey.mp3'];

  /// The clip's URL on the server at [baseUrl].
  Uri url(String baseUrl) {
    final base = Uri.parse(baseUrl);
    final prefix = base.pathSegments.where((s) => s.isNotEmpty);
    return base.replace(pathSegments: [
      ...prefix,
      ...kVoiceAssetsPath.split('/').where((s) => s.isNotEmpty),
      ...pathSegments,
    ]);
  }
}
