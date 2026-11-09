import '../config/poa_country_gate.dart';
import '../config/proof_of_address.dart';
import '../config/scope.dart';
import '../config/verification_config.dart';
import 'verification_state.dart';

// ─── The Proof of Address step's answers, read off the flow ──────────────────
//
// The document's country and the kind picked, derived the same way for the
// screen and its header (flow_step_meta.dart), so the description's window
// and name rule never describe a different kind or country than the step
// shows. Mirrors the web SDK's ProofOfAddressStep.

/// Where the document is from, or null while there is none (Continue holds).
/// On the address scope the declared country; elsewhere the country picked
/// on the step, else the ID's (config/poa_country_gate.dart).
String? poaStepCountry(VerificationConfig config, VerificationState state) =>
    poaCountryOf(
      scope: configScope(config.scope),
      selectedCountry: state.selectedCountry,
      poaCountry: state.poaCountry,
      idCountry: state.selectedCountry ?? config.country,
      offered: poaOfferedCountries(config.proofOfAddress?.countries ?? const []),
    );

/// The kind picked: the one held in state while the country offers it, else
/// the first on offer (a kind picked before the country changed may not be
/// offered there).
PoaDocumentType poaStepKind(VerificationConfig config, VerificationState state) {
  final poa = config.proofOfAddress ?? const ProofOfAddressConfig(enabled: true);
  final offered = poa.offeredTypesFor(poaStepCountry(config, state));
  final stored = state.poaDocumentType == null
      ? null
      : PoaDocumentType.tryFromKey(state.poaDocumentType!);
  return stored != null && offered.contains(stored) ? stored : offered.first;
}
