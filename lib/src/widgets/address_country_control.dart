import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/inferred_country.dart';
import '../config/poa_country_gate.dart';
import '../i18n/text_scope.dart';
import '../providers/verification_provider.dart';
import 'country_summary_select.dart';

export '../config/poa_country_gate.dart' show poaOfferedCountries;

// ─── The Proof of Address step's country control ─────────────────────────────
//
// On every scope (the Didit PoA model: the applicant names where the document
// is from, then uploads it). The step owns the value and what a pick does
// (config/poa_country_gate.dart): on the address scope the pick is the flow's
// declared country, which also drives the search filter, the map's opening
// view and the submission's country; elsewhere it is the proof of address's
// own country, which need not be the ID's.
//
// It offers the org's accepted list (proofOfAddress.countries, the server
// refuses submissions outside it), else the whole world, in the shared
// summary row (country_summary_select.dart), as the combined ID step picks its
// country. The inferred country (server geo first, device locale second) is
// pinned in the sheet as "Your location". Mirrors the web SDK's
// steps/address/AddressCountryControl and the RN twin.

class AddressCountryControl extends ConsumerWidget {
  /// The document's country, or null while there is none.
  final String? value;

  /// The caption over the country: "Your address is in".
  final String label;

  final ValueChanged<String> onPick;

  const AddressCountryControl({
    super.key,
    required this.value,
    required this.label,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(verificationConfigProvider);
    final state = ref.watch(kYCNotifierProvider);
    final t = context.verificationText;
    return CountrySummarySelect(
      countries: poaOfferedCountries(config.proofOfAddress?.countries ?? const []),
      value: value,
      onPick: onPick,
      label: label,
      geoCountry: inferredCountry(state.serverConfig.geoCountry),
      copy: CountrySummaryCopy(
        placeholder: t('proofOfAddress.country.placeholder'),
        change: t('proofOfAddress.country.change'),
        choose: t('proofOfAddress.country.choose'),
        search: t('proofOfAddress.country.search'),
        noMatches: t('proofOfAddress.country.noMatches'),
        selected: t('proofOfAddress.country.selected'),
        yourLocation: t('proofOfAddress.country.yourLocation'),
      ),
    );
  }
}
