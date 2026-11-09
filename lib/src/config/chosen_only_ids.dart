import '../services/api_service.dart' show SdkConfigIdType;
import 'retired_id_types.dart';
import 'verification_config.dart';

// ─── ID types a workflow offers only when it lists them by name ──────────────
//
// MIRRORS kyc-core's src/lib/workflows/chosen-only-ids.ts and the web SDK's
// lib/chosen-only-ids.ts: change them together.
//
// A workflow country with no ID list offers every ID the organisation holds
// EXCEPT these: they were added after most workflows were built, and verify
// less than the IDs beside them, so an org chooses them. The server already
// leaves them out of the list it serves a published workflow session; the SDK
// applies the same rule whenever a workflow is mounted, so a list served
// without it (an older server, the full grant list) cannot offer them. A
// mount configured in code lists its own IDs and is not filtered.

const Set<String> _kChosenOnlyIdTypes = {
  'NG/phone-number',
  'NG/nin-phone',
  'NG/nin-slip',
  'NG/tax-id',
  'NG/vnin',
};

/// The IDs [config] lists for [country] (null when it lists none).
List<String>? _listedIdTypesFor(VerificationConfig config, String country) {
  final upper = country.toUpperCase();
  for (final entry in config.countries ?? const <WorkflowCountryOption>[]) {
    if (entry.country.toUpperCase() != upper) continue;
    final ids = entry.idTypes;
    return ids != null && ids.isNotEmpty ? ids : null;
  }
  final top = config.idTypes;
  if (config.country?.toUpperCase() == upper && top != null && top.isNotEmpty) {
    return top;
  }
  return null;
}

/// The served rows without the chosen-only IDs [config] does not list for
/// their country.
List<SdkConfigIdType> withoutUnchosenIdTypes(
  List<SdkConfigIdType> rows,
  VerificationConfig config,
) =>
    [
      for (final row in rows)
        if (!_kChosenOnlyIdTypes.contains('${row.country.toUpperCase()}/${row.idType}') ||
            (_listedIdTypesFor(config, row.country)?.contains(row.idType) ?? false))
          row,
    ];

/// What the ID picker may offer from a served list: never a retired type, and
/// on a workflow mount never a chosen-only type the workflow does not list.
/// Applied wherever the server's ID list lands (the /config fetch and the
/// workflow gate), so every reader sees the same list. Mirrors the web SDK's
/// `servedConfig` in VerificationConfigContext.
List<SdkConfigIdType> servedIdTypes(
  List<SdkConfigIdType> rows,
  VerificationConfig config,
) {
  final offered = [
    for (final row in rows)
      if (!isRetiredIdType(row.country, row.idType)) row,
  ];
  return config.workflowId != null
      ? withoutUnchosenIdTypes(offered, config)
      : offered;
}
