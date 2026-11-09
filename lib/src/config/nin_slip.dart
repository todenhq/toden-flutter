// ─── NIN and its slip ─────────────────────────────────────────────────────────
//
// The NIN slip is NIN read from paper (kyc-core and the builder merged them,
// 2026-11-07): a workflow offers one or the other, as the builder's NIN Slip
// switch says. A workflow built before the merge may list both; then only the
// slip is offered, as the builder now reads that workflow, so the picker never
// shows "NIN" beside "NIN (Slip)". Mirrors the web SDK's lib/nin-slip.ts.

/// [types] without NG `nin` when NG `nin-slip` is among them. [keyOf] reads
/// an entry's ID key.
List<T> withoutNinBesideSlip<T>(
  String country,
  List<T> types,
  String Function(T type) keyOf,
) {
  if (country.toUpperCase() != 'NG' || !types.any((t) => keyOf(t) == 'nin-slip')) {
    return types;
  }
  return [for (final t in types) if (keyOf(t) != 'nin') t];
}
