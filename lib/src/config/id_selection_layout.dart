// ─── Where a multi-country flow picks the ID's country ───────────────────────
//
// On a flow that offers more than one country (user decision 2026-11-07, a
// builder Advanced setting):
//
//  - `combined` (the default): a country row at the top of the ID-type step,
//    the IDs for that country beneath it. One step.
//  - `separate`: a country step of its own, then the ID types. Two steps, the
//    layout before this setting existed.
//
// MIRRORS kyc-core's `idSelectionLayout` in the workflow config schema and the
// web SDK's lib/id-selection-layout.ts.

enum IdSelectionLayout {
  combined,
  separate;

  /// The wire value (`combined` / `separate`), or null for anything else.
  static IdSelectionLayout? tryParse(Object? raw) => switch (raw) {
        'combined' => IdSelectionLayout.combined,
        'separate' => IdSelectionLayout.separate,
        _ => null,
      };
}

/// Whether the country is picked on the ID-type step rather than a step of
/// its own: true unless the flow keeps the separate layout.
bool countryOnIdStep(IdSelectionLayout? layout) =>
    layout != IdSelectionLayout.separate;
