// ─── Document identity signals ────────────────────────────────────────────────
//
// "Is the thing in frame actually the document the user picked?" answered from
// recognized text alone.
//
// iOS answers a related question geometrically — Apple Vision finds a rectangle
// and DocumentFramingGate checks its aspect — but aspect cannot tell a passport
// from a driver's licence, and Android has no rectangle detector in ML Kit at
// all. Text signals answer it directly, and more specifically: a passport page
// says PASSPORT and carries an MRZ; a Nigerian licence says FRSC.
//
// Deliberately mirrors the server's DOCUMENT_SIGNALS / detectDocumentType
// (src/lib/ocr-parser.ts) — the server rejects a mismatched document AFTER
// upload with `document_type_mismatch`, so matching its vocabulary here means
// the camera refuses to shoot exactly what the server would later reject.
// Keep the two lists in sync when either changes.

/// Keyword signals per country → ID type. Uppercase; matched as substrings.
const Map<String, Map<String, List<String>>> kDocumentSignals = {
  'NG': {
    'passport': ['PASSPORT', 'TRAVEL DOCUMENT', 'P<NGA'],
    // LICENCE: the licence itself is spelt the UK way ("NATIONAL DRIVER'S
    // LICENCE"), so with LICENSE alone its front scored one hit and the
    // camera held at "move closer" for good.
    'drivers-license': [
      'DRIVER', 'LICENSE', 'FRSC', 'FEDERAL ROAD SAFETY', 'DRIVING LICENCE',
      'LICENCE',
    ],
    'pvc': [
      'VOTER', "VOTER'S CARD", 'PVC', 'INEC', 'INDEPENDENT NATIONAL ELECTORAL',
      'PERMANENT VOTER', 'ELECTORAL COMMISSION', 'VIN',
    ],
    // Without its own list a NIN slip could not be told from any other
    // document, so a voter's card held in its place was captured as the slip.
    'nin-slip': [
      'NATIONAL IDENTIFICATION NUMBER SLIP', 'NINS',
      'NATIONAL IDENTITY MANAGEMENT', 'NIMC', 'TRACKING ID', 'DIGITAL NIN SLIP',
    ],
  },
  'GH': {
    'passport': ['PASSPORT', 'REPUBLIC OF GHANA', 'P<GHA'],
    // ECOWAS: the card's front is headed "ECOWAS IDENTITY CARD" and names
    // neither the card nor the authority, so GHA- was its only hit.
    'ghana-card': [
      'GHANA CARD', 'NATIONAL IDENTIFICATION AUTHORITY', 'NIA', 'GHA-',
      'ECOWAS',
    ],
    'voters': ['VOTER', 'ELECTORAL COMMISSION', 'EC OF GHANA'],
    'drivers-license': [
      'DRIVER', 'LICENSE', 'DVLA', 'DRIVING AND VEHICLE', 'LICENCE',
    ],
    'ssnit': ['SSNIT', 'SOCIAL SECURITY', 'NATIONAL INSURANCE'],
  },
  'KE': {
    'passport': ['PASSPORT', 'REPUBLIC OF KENYA', 'P<KEN'],
    'national-id': [
      'REPUBLIC OF KENYA', 'NATIONAL ID', 'JAMHURI YA KENYA', 'IDENTITY CARD',
    ],
  },
  'ZA': {
    'passport': ['PASSPORT', 'P<ZAF'],
    'national-id': [
      'REPUBLIC OF SOUTH AFRICA', 'IDENTITY', 'ID NUMBER',
      'REPUBLIEK VAN SUID-AFRIKA',
    ],
  },
  'CI': {
    'cni': ['CARTE NATIONALE', 'IDENTITE', 'REPUBLIQUE DE COTE', 'CNI'],
    'residence-card': ['CARTE DE SEJOUR', 'RESIDENCE', 'TITRE DE SEJOUR'],
  },
};

/// Words that identify a passport in ANY country — an MRZ, or the word itself
/// in English or French. Global Documents means most countries have no curated
/// signal list, and a passport is the one document that identifies itself
/// everywhere.
const List<String> _universalPassportWords = ['PASSPORT', 'PASSEPORT'];

/// True when [lines] contain two or more machine-readable-zone lines. Cheap
/// structural check — no check-digit validation, which [extractMrz] does.
bool hasMrzLines(List<String> lines) {
  var count = 0;
  for (final line in lines) {
    final stripped =
        line.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9<]'), '');
    if (stripped.length >= 40 && stripped.contains('<')) count++;
  }
  return count >= 2;
}

/// What the text in frame looks like.
class DocumentTypeMatch {
  /// The ID type the text matches best, or null when nothing matched.
  final String? type;

  /// 0..1 share of that type's keywords present.
  ///
  /// A RATIO, so it shrinks as a type's synonym list grows — which is why it
  /// cannot be the only bar for "is this the right document". See [matched].
  final double confidence;

  /// How many keywords actually hit.
  ///
  /// The evidence that matters when deciding the document IS the expected one:
  /// two independent hits mean the same thing whether the type lists three
  /// synonyms or eight, where [confidence] would call the same evidence 0.67 or
  /// 0.25. Kept alongside rather than replacing it — the wrong-type comparison
  /// still wants a ratio, so that two types are weighed on the same scale.
  final int matched;

  const DocumentTypeMatch(this.type, this.confidence, [this.matched = 0]);

  static const none = DocumentTypeMatch(null, 0);
}

/// True when we have signals to verify this (country, idType) at all. When
/// false the caller CANNOT check identity and must not block on it — most
/// Global Documents countries have no curated list.
bool hasDocumentSignals(String country, String idType) {
  if (kDocumentSignals[country]?[idType] != null) return true;
  // A passport identifies itself in any country.
  return idType == 'passport';
}

/// Best-matching document type for the recognized [lines] within [country].
///
/// Mirrors the server's `detectDocumentType`: score each type by the share of
/// its keywords present, then let a universal passport signal (MRZ or the word
/// itself) stand in for countries with no curated passport list.
DocumentTypeMatch detectDocumentType(List<String> lines, String country) {
  if (lines.isEmpty) return DocumentTypeMatch.none;
  final upper = foldAccents(lines.join('\n').toUpperCase());
  final signals = kDocumentSignals[country] ?? const {};

  String? bestType;
  var bestConfidence = 0.0;
  var bestMatched = 0;

  signals.forEach((type, keywords) {
    if (keywords.isEmpty) return;
    final matched = countSignalHits(upper, keywords);
    final confidence = matched / keywords.length;
    if (confidence > bestConfidence) {
      bestConfidence = confidence;
      bestMatched = matched;
      bestType = type;
    }
  });

  // Universal passport fallback — an MRZ is worth a lot on its own, since only
  // travel documents carry one.
  final mrz = hasMrzLines(lines);
  final saysPassport = _universalPassportWords.any(upper.contains);
  if (mrz || saysPassport) {
    final keywords = signals['passport'] ?? const <String>[];
    final matched = countSignalHits(upper, keywords);
    final base = keywords.isEmpty ? 0.0 : matched / keywords.length;
    final confidence = (base + (mrz ? 0.5 : 0.25)).clamp(0.0, 1.0);
    if (confidence > bestConfidence) {
      bestConfidence = confidence;
      bestMatched = matched + 1; // the MRZ / the word itself is evidence too
      bestType = 'passport';
    }
  }

  return bestType == null
      ? DocumentTypeMatch.none
      : DocumentTypeMatch(bestType, bestConfidence, bestMatched);
}

/// How many of [keywords] appear in [upper].
///
/// Short acronyms match on WORD BOUNDARIES, not as bare substrings. `VIN` sits
/// inside "driVINg", so a Nigerian driver's licence would otherwise score a
/// voter-card hit — harmless while every score is diluted by the keyword count,
/// and a false identification the moment anything counts hits directly.
int countSignalHits(String upper, List<String> keywords) {
  upper = foldAccents(upper);
  var hits = 0;
  for (final keyword in keywords) {
    if (_isShortAcronym(keyword)) {
      if (RegExp('\\b${RegExp.escape(keyword)}\\b').hasMatch(upper)) hits++;
    } else if (upper.contains(keyword)) {
      hits++;
    }
  }
  return hits;
}

bool _isShortAcronym(String keyword) =>
    keyword.length <= 4 && RegExp(r'^[A-Z]+$').hasMatch(keyword);

const Map<String, String> _accentFolds = {
  'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A',
  'Ç': 'C',
  'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
  'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I',
  'Ñ': 'N',
  'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
  'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U',
  'Ý': 'Y', 'Ÿ': 'Y',
};

/// [upper] with its accented capitals plain. The keywords are written without
/// accents, as the server's are, while a Côte d'Ivoire CNI prints "RÉPUBLIQUE
/// DE CÔTE D'IVOIRE" and "IDENTITÉ": read as printed, its front scored one hit.
String foldAccents(String upper) {
  if (!upper.runes.any((r) => r > 127)) return upper;
  final out = StringBuffer();
  for (final ch in upper.split('')) {
    out.write(_accentFolds[ch] ?? ch);
  }
  return out.toString();
}
