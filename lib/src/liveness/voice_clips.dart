import 'dart:math' show Random;

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

bool _isCountry(String value) => RegExp(r'^[A-Za-z]{2}$').hasMatch(value);

/// Who one voice is, as the manifest says.
class ManifestVoiceInfo {
  /// `female` or `male`; null from an older server.
  final String? gender;

  /// ISO 3166-1 alpha-2; null where the accent is not one country's.
  final String? country;

  /// False for a voice Toden no longer offers: playable where named, never chosen for anyone.
  final bool offered;

  const ManifestVoiceInfo({this.gender, this.country, this.offered = true});
}

/// Who the prompts are for, and how a voice is matched to them.
class VoiceApplicant {
  /// `female`, `male`, `any`, or `off` (their own country and its neighbours are skipped).
  final String choice;

  /// The country of the document being verified, ISO-2; null until one is picked.
  final String? country;

  /// The same for one person all session, so their voice does not change part way.
  final String seed;

  /// A neighbouring country's voice where their own has none.
  final bool neighbours;

  const VoiceApplicant({required this.choice, this.country, required this.seed, this.neighbours = true});

  /// For the settings and the person: the app's user reference names them
  /// (else one seed for this app session), and with matching off the country
  /// is left out, as it changes nothing.
  factory VoiceApplicant.of({
    required String choice,
    required bool neighbours,
    String? country,
    String? userId,
  }) {
    final code = country?.trim().toUpperCase();
    final id = userId?.trim();
    return VoiceApplicant(
      choice: choice,
      country: choice == 'off' || code == null || code.isEmpty ? null : code,
      seed: id == null || id.isEmpty ? kSessionVoiceSeed : id,
      neighbours: neighbours,
    );
  }

  /// Identifies this request among the loads of the app process.
  String get id => '$choice:${country ?? ''}:$seed:$neighbours';
}

/// A seed for this app session, for a person the app did not name (no `userId`).
final String kSessionVoiceSeed = Random().nextInt(1 << 32).toRadixString(36);

/// a times b, kept to 32 bits, without leaving the range a double holds exactly.
int _mul32(int a, int b) {
  final lo = (a & 0xffff) * b;
  final hi = ((a >> 16) * b) & 0xffff;
  return (lo + (hi << 16)) & 0xffffffff;
}

/// FNV-1a, 32 bit, over the UTF-16 code units: one person's seed to a number
/// that is the same on every run and every Toden SDK.
int voiceSeedNumber(String seed) {
  var hash = 0x811c9dc5;
  for (final unit in seed.codeUnits) {
    hash = _mul32(hash ^ unit, 0x01000193);
  }
  return hash;
}

/// The voice that speaks for this person (kyc-core docs/VOICE_GUIDANCE.md, "Who
/// speaks, from SDK 4.4.0"), or null for the device's voice: their own
/// country's, a neighbouring country's, the workflow's own [voice], then an
/// American voice. `off` skips the first two. The same rule as the web and
/// React Native SDKs' pickVoice.
String? pickVoice(VoiceManifest manifest, {String? voice, required String language, VoiceApplicant? applicant}) {
  final lang = primaryVoiceLanguage(language);
  bool speaks(String id) => manifest.voices[id]?.contains(lang) ?? false;
  final workflowVoice = voice != null && speaks(voice) ? voice : null;
  if (applicant == null) return workflowVoice;

  List<String> from(String code) => manifest.voices.keys
      .where((id) {
        final info = manifest.voiceInfo[id];
        return info != null && info.country == code.toUpperCase() && info.offered && speaks(id);
      })
      .toList()
    ..sort();
  final gender = applicant.choice == 'off' ? 'any' : applicant.choice;
  List<String> ofGender(List<String> ids) =>
      gender == 'any' ? ids : ids.where((id) => manifest.voiceInfo[id]?.gender == gender).toList();
  List<String> preferred(List<String> ids) => ofGender(ids).isNotEmpty ? ofGender(ids) : ids;
  String one(List<String> ids) => ids[voiceSeedNumber(applicant.seed) % ids.length];

  final country = applicant.country?.trim().toUpperCase();
  if (applicant.choice != 'off' && country != null && country.isNotEmpty) {
    final own = from(country);
    if (own.isNotEmpty) return one(preferred(own));
    if (applicant.neighbours) {
      final nearby = (manifest.neighbours[country] ?? const <String>[]).map(from).toList();
      final matching = nearby.map(ofGender).where((ids) => ids.isNotEmpty).firstOrNull ??
          nearby.where((ids) => ids.isNotEmpty).firstOrNull;
      if (matching != null) return one(matching);
    }
  }
  if (workflowVoice != null) return workflowVoice;
  final fallbackCountry = manifest.fallbackCountry;
  final fallback = fallbackCountry == null ? const <String>[] : from(fallbackCountry);
  return fallback.isNotEmpty ? one(preferred(fallback)) : null;
}

/// The manifest at `{server}/api/kyc/assets/voices/manifest.json`.
class VoiceManifest {
  /// Changes whenever any clip changes; part of every clip URL.
  final String version;

  /// Voice id to the languages it has clips in.
  final Map<String, Set<String>> voices;

  /// Who each voice is: gender, country and whether Toden still offers it.
  /// Empty from an older server.
  final Map<String, ManifestVoiceInfo> voiceInfo;

  /// Whose voices may speak to a country Toden has no voice from, best first.
  final Map<String, List<String>> neighbours;

  /// The country whose voices speak when nothing nearer does (US); null from an older server.
  final String? fallbackCountry;

  /// Language, then phrase key, then the exact text of that clip.
  final Map<String, Map<String, String>> phrases;

  const VoiceManifest({
    required this.version,
    required this.voices,
    required this.phrases,
    this.voiceInfo = const {},
    this.neighbours = const {},
    this.fallbackCountry,
  });

  /// Reads the server's JSON. Throws [FormatException] when it is not a
  /// manifest. Entries with an unusable id are left out.
  factory VoiceManifest.fromJson(Object? json) {
    if (json is! Map || !_isSafeSegment(json['version'])) {
      throw const FormatException('Not a voice manifest');
    }
    final voices = <String, Set<String>>{};
    final voiceInfo = <String, ManifestVoiceInfo>{};
    final rawVoices = json['voices'];
    if (rawVoices is Map) {
      rawVoices.forEach((id, entry) {
        final languages = entry is Map ? entry['languages'] : null;
        if (!_isSafeSegment(id) || languages is! List) return;
        voices[id as String] = languages.where(_isSafeSegment).cast<String>().toSet();
        final gender = (entry as Map)['gender'];
        final country = entry['country'];
        voiceInfo[id] = ManifestVoiceInfo(
          gender: gender is String ? gender : null,
          country: country is String && _isCountry(country) ? country.toUpperCase() : null,
          offered: entry['offered'] != false,
        );
      });
    }
    final neighbours = <String, List<String>>{};
    final rawNeighbours = json['neighbours'];
    if (rawNeighbours is Map) {
      rawNeighbours.forEach((country, list) {
        if (country is! String || !_isCountry(country) || list is! List) return;
        neighbours[country.toUpperCase()] =
            list.whereType<String>().where(_isCountry).map((c) => c.toUpperCase()).toList();
      });
    }
    final fallback = json['fallbackCountry'];
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
      voiceInfo: voiceInfo,
      neighbours: neighbours,
      fallbackCountry: fallback is String && _isCountry(fallback) ? fallback.toUpperCase() : null,
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
