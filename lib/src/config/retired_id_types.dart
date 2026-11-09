// ─── ID types that are no longer offered ──────────────────────────────────────
//
// MIRRORS kyc-core's RETIRED_DOCUMENTS (src/lib/documents/catalog.ts) and the
// web SDK's lib/retired-id-types.ts: change them together.
//
// NG `bvn-premium` was a second ID type for one BVN lookup with one extra
// flag; it is now the `premium` option on BVN. Old grants still carry the
// row, and a server from before it was retired still serves it, so the
// picker drops it here as well: it must never sit beside BVN again. Its
// curated definition stays (config/id_types.dart), so a run already holding
// it still resolves.

const Set<String> _kRetiredIdTypes = {'NG/bvn-premium'};

/// Whether ([country], [idType]) is retired and must never be offered.
bool isRetiredIdType(String country, String idType) =>
    _kRetiredIdTypes.contains('${country.toUpperCase()}/$idType');
