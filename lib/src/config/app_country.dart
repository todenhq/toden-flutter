import 'verification_config.dart';

// MIRRORS the web SDK's lib/app-country.ts. Keep the two in lockstep.
//
// The country an app passes (`country`), on a flow that verifies IDs from
// several.
//
// A workflow's own countries win over the app's config, so on a multi-country
// workflow `country` used to be ignored: the picker opened on the workflow's
// own country, else on the visitor's location. An app that already knows its
// user's country had no way to say so. Now, when the flow offers the country
// the app passed, the picker opens on it; with `lockCountry` there is no picker
// and the flow runs as if it offered that country alone (user decision
// 2026-11-21: one `country`, not a second one beside it).
//
// The app's country only ever chooses among the countries the flow offers. One
// the flow does not offer changes nothing (the picker shows as usual), since
// the server would refuse an ID from it anyway. A single-country flow has
// nothing to choose: there `country` stays what it always was, the flow's own.

/// The flow's config with the app's own `country` applied: made the country
/// the picker opens on, or, when locked, the only country the flow offers.
/// [appCountry] is the app's value as passed, before any workflow replaced it.
/// A flow with one country, or a country it does not offer, comes back
/// unchanged. Pure.
VerificationConfig applyAppCountry(VerificationConfig config, String? appCountry) {
  final offered = config.countries;
  if (offered == null || offered.length <= 1) return config;
  final wanted = appCountry?.trim().toUpperCase();
  if (wanted == null || wanted.isEmpty) return config;
  final matches = offered.where((c) => c.country.toUpperCase() == wanted);
  if (matches.isEmpty) return config;
  final match = matches.first;
  return config.copyWith(
    country: match.country,
    appCountry: match.country,
    countries: config.lockCountry ? [match] : null,
  );
}
