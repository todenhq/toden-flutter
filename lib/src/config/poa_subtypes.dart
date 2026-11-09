import '../i18n/translate.dart' show TextFn;
import 'proof_of_address.dart';

// ─── The documents inside each proof-of-address kind ─────────────────────────
//
// As business documents sit inside their groups. The applicant picks the
// KIND; the server's reader recognises which document within it was uploaded
// (a water bill, a lease), so the SDK never asks for the subtype.
//
// MIRRORS kyc-core's POA_DOCUMENT_SUBTYPES (src/lib/proof-of-address/types.ts)
// and the web SDK's lib/poa-subtypes.ts. The keys are an add-only contract.

/// Each kind's subtypes, in the order they are listed.
const Map<PoaDocumentType, List<String>> kPoaSubtypesByKind = {
  PoaDocumentType.utilityBill: [
    'electricity_bill',
    'water_bill',
    'gas_bill',
    'internet_bill',
    'phone_bill',
    'waste_bill',
  ],
  PoaDocumentType.bankStatement: [
    'bank_statement',
    'credit_card_statement',
    'mortgage_statement',
    'loan_statement',
  ],
  PoaDocumentType.tenancyAgreement: [
    'tenancy_agreement',
    'lease_agreement',
    'property_title',
  ],
  PoaDocumentType.governmentDocument: [
    'tax_document',
    'property_rates_bill',
    'voter_registration',
    'voter_id',
    'benefits_letter',
    'government_letter',
  ],
  PoaDocumentType.other: [
    'insurance_document',
    'employer_letter',
    'education_letter',
    'other_document',
  ],
};

final Set<String> _kAllSubtypes = {
  for (final list in kPoaSubtypesByKind.values) ...list,
};

/// Whether [subtype] is one this build knows.
bool isPoaSubtype(String subtype) => _kAllSubtypes.contains(subtype);

String _camel(String subtype) => subtype.replaceAllMapped(
    RegExp(r'_([a-z])'), (m) => m.group(1)!.toUpperCase());

/// A subtype's text key: `proofOfAddress.subtype.electricityBill`.
String poaSubtypeKey(String subtype) => 'proofOfAddress.subtype.${_camel(subtype)}';

/// A subtype's short text key, the word that reads inside a sentence:
/// `proofOfAddress.subtypeShort.electricityBill` ("electricity").
String poaSubtypeShortKey(String subtype) =>
    'proofOfAddress.subtypeShort.${_camel(subtype)}';

/// The subtypes accepted inside one kind. The workflow's `documentSubtypes`
/// narrows a kind only where it names at least one of that kind's subtypes;
/// a kind it says nothing about keeps all of them.
List<String> acceptedPoaSubtypes(PoaDocumentType kind, List<String> configured) {
  final own = kPoaSubtypesByKind[kind]!;
  final picked = configured.where(_kAllSubtypes.contains).toSet();
  final narrowed = own.where(picked.contains).toList(growable: false);
  return narrowed.isNotEmpty ? narrowed : List.of(own, growable: false);
}

/// Joins [words] with "or" the language's way, as the web SDK's
/// `Intl.ListFormat(language, { type: 'disjunction' })` does for the
/// languages the SDK ships copy in; anything else is comma-joined, the web
/// SDK's own fallback.
String _disjunction(List<String> words, String? language) {
  if (words.isEmpty) return '';
  if (words.length == 1) return words.single;
  final lang = (language == null || language.isEmpty) ? 'en' : language;
  final base = lang.split(RegExp('[-_]')).first.toLowerCase();
  final or = switch (base) {
    'en' => 'or',
    'fr' || 'pt' => 'ou',
    'es' => 'o',
    'de' => 'oder',
    _ => null,
  };
  if (or == null) return words.join(', ');
  final head = words.sublist(0, words.length - 1).join(', ');
  // Plain `en` is US English to Intl, which keeps the serial comma.
  final serial = words.length > 2 && (lang == 'en' || lang == 'en-US');
  return '$head${serial ? ',' : ''} $or ${words.last}';
}

/// A kind's documents in one short phrase: "Electricity, water, gas, or
/// internet". The short names are lower case so they read inside a sentence;
/// the phrase gets its capital here.
String poaKindSummary(
  PoaDocumentType kind,
  List<String> configured,
  TextFn t, {
  String? language,
}) {
  final words = [
    for (final s in acceptedPoaSubtypes(kind, configured)) t(poaSubtypeShortKey(s)),
  ];
  final phrase = _disjunction(words, language);
  return phrase.isEmpty ? phrase : phrase[0].toUpperCase() + phrase.substring(1);
}

/// The window a kind's document must fall within, in days (0 = any date): the
/// kind's own window, else `maxAgeDays`, else 90. A recognised subtype's own
/// window (`documentSubtypeValidity`) is the server's to apply.
int poaKindDays(ProofOfAddressConfig? poa, PoaDocumentType kind) =>
    poa?.documentValidity[kind.key] ?? poa?.maxAgeDays ?? 90;

/// "3 months", "1 year", "Any date".
String poaPeriodLabel(int days, TextFn t) {
  if (days <= 0) return t('proofOfAddress.validity.any');
  if (days % 365 == 0) {
    final years = days ~/ 365;
    return years == 1
        ? t('proofOfAddress.validity.year')
        : t('proofOfAddress.validity.years', vars: {'count': years});
  }
  final months = (days / 30).round().clamp(1, 1 << 30);
  return months == 1
      ? t('proofOfAddress.validity.month')
      : t('proofOfAddress.validity.months', vars: {'count': months});
}
