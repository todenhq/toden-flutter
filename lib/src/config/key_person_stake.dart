// Which key people must state their stake. Mirrors the web SDK's
// lib/key-person-stake.ts and the server's key-people/ownership.ts: keep the
// three in lockstep.
//
// Who is a beneficial owner, and so who must complete a full identity check,
// is decided from the stake. A shareholder or beneficial owner left without
// one would be filed as an ordinary shareholder, so by default each must give
// a percentage; a company's declared owners too. Directors and signatories
// are not asked. A workflow turns this off with
// `keyPeople.requireOwnership: false`.
import 'business.dart';
import 'business_application.dart';

const _needsStake = {KeyPersonRole.shareholder, KeyPersonRole.beneficialOwner};

/// Whether the workflow asks the applicant for stakes (absent = yes).
bool keyPeopleRequireOwnership(WorkflowBusinessConfig? business) {
  final kp = business?.keyPeople;
  return kp != null && kp.enabled && kp.collect && kp.requireOwnership;
}

bool _filled(String pct) => pct.trim().isNotEmpty && double.tryParse(pct.trim()) != null;

/// Whether THIS row's roles mean it owes a percentage.
bool rowNeedsStake(KeyPersonEntry row) {
  final roles = row.roles.isNotEmpty ? row.roles : [row.role];
  return roles.any(_needsStake.contains);
}

/// Whether the row is missing a stake the workflow requires: an owner role
/// with no percentage, or a company's declared owner (named) with none.
bool rowMissingStake(KeyPersonEntry row, bool stakeRequired) {
  if (!stakeRequired) return false;
  if (rowNeedsStake(row) && !_filled(row.ownershipPct)) return true;
  if (!row.isCorporate) return false;
  return row.owners.any((o) => o.name.trim().length >= 2 && !_filled(o.ownershipPct));
}
