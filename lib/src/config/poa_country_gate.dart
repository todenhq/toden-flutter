import 'country_names.g.dart' show kCountryNames;

// ─── The Proof of Address step's country: where the document is from ─────────
//
// Every scope asks for it (user decision 2026-11-07). Before, only the address
// scope did and every other flow read the document against the ID's country,
// but people live outside the country that issued their ID. Outside the
// address scope the ID's country is offered as the starting answer, since it
// is usually right, and the applicant can change it. On the address scope the
// declared country (`selectedCountry`) is the answer, and the scope seeds none.
// An org that accepts exactly ONE country has the control show it as a
// settled fact. Continue holds until there is a country (2026-09-08).
//
// A THREE-WAY MIRROR of the web SDK's lib/poa-country-gate.ts and the RN
// SDK's lib/poa-country-gate.ts; change the rule in one and change all three.

/// The proof of address's country, or null while there is none to read the
/// document against (Continue holds on null).
///
/// [selectedCountry] is the address scope's declared country; elsewhere the
/// ID's. [poaCountry] is the country picked on the PoA step (outside the
/// address scope). [idCountry] is the flow's own country, the ID's, offered
/// as the starting answer.
String? poaCountryOf({
  required String? scope,
  required String? selectedCountry,
  required String? poaCountry,
  required String? idCountry,
  required List<String> offered,
}) {
  if (offered.length == 1) return offered.single;
  String? clean(String? code) {
    final c = code?.trim().toUpperCase();
    return c == null || c.isEmpty ? null : c;
  }

  if (scope == 'address') return clean(selectedCountry);
  final picked = clean(poaCountry);
  if (picked != null) return picked;
  final id = clean(idCountry);
  return id != null && offered.contains(id) ? id : null;
}

/// What the country row offers: the org's accepted list
/// (`proofOfAddress.countries`, unknown codes dropped; the server refuses
/// submissions outside it), else every named country.
List<String> poaOfferedCountries(List<String> configured) {
  final list = configured
      .map((c) => c.toUpperCase())
      .where(kCountryNames.containsKey)
      .toList(growable: false);
  return list.isNotEmpty ? list : kCountryNames.keys.toList(growable: false);
}
