// The "allow all the time" ask, made at the moment it is needed.
//
// The OS gives roughly one real chance to ask: iOS shows the upgrade to Always
// once, and Android 11+ sends the person to a settings page many back out of.
// So the ask is not made cold on the success screen. A short screen of its own
// comes first and gives the person their own reasons: less effort, done
// sooner, and only this one address. The success screen then reflects the
// answer, with a way to turn it on later.
//
// The rules here are pure and mirror the React Native SDK's
// presence/background-primer.ts; change both together.

/// The server's default policy (kyc-core presence/types.ts DEFAULT_POLICY).
const int kDefaultPresenceWindowDays = 10;
const int kDefaultPresenceMinNights = 3;
const int kDefaultPresenceMinDays = 5;

/// What one app-open report is worth, in tenths of a day or night (kyc-core
/// presence/types.ts SOURCE_WEIGHTS: foreground 0.6, geofence 1.0).
const int _kForegroundTenths = 6;

/// [primer] shows the explanation screen and then the OS prompt; [silent]
/// arms with no prompt (already granted); [skip] asks nothing.
enum PrimerDecision { primer, silent, skip }

PrimerDecision backgroundPrimerDecision({
  required bool wantsBackground,
  required bool registered,
  required bool alwaysGranted,
  required bool resumed,
}) {
  if (!wantsBackground || !registered || resumed) return PrimerDecision.skip;
  return alwaysGranted ? PrimerDecision.silent : PrimerDecision.primer;
}

/// A workflow's presence policy, the server's default where absent.
class PresencePolicyNumbers {
  final int windowDays;
  final int minNights;
  final int minDays;

  PresencePolicyNumbers({int? windowDays, int? minNights, int? minDays})
      : windowDays = _atLeast(windowDays, kDefaultPresenceWindowDays, 1),
        minNights = _atLeast(minNights, kDefaultPresenceMinNights, 0),
        minDays = _atLeast(minDays, kDefaultPresenceMinDays, 1);

  static int _atLeast(int? v, int fallback, int min) {
    final n = v == null || v < 0 ? fallback : v;
    return n < min ? min : n;
  }
}

/// App opens needed to reach [required] days or nights on app-open reports.
int _opensFor(int required) => ((required * 10) / _kForegroundTenths).ceil();

enum PresenceEffortUnit { evenings, days }

class PresenceEffort {
  /// App opens needed without background checks.
  final int count;

  /// Evenings at home (a person), or days at the premises (a business).
  final PresenceEffortUnit unit;
  const PresenceEffort(this.count, this.unit);

  @override
  bool operator ==(Object other) =>
      other is PresenceEffort && other.count == count && other.unit == unit;

  @override
  int get hashCode => Object.hash(count, unit);

  @override
  String toString() => 'PresenceEffort($count, $unit)';
}

/// What it takes to finish WITHOUT background checks. A person passes on
/// nights or days, whichever needs fewer opens, nights first for the same
/// count. A business premises counts days only (minNights 0).
PresenceEffort effortWithoutBackground(PresencePolicyNumbers p, {required bool isBusiness}) {
  final days = _opensFor(p.minDays);
  if (isBusiness || p.minNights <= 0) return PresenceEffort(days, PresenceEffortUnit.days);
  final nights = _opensFor(p.minNights);
  return nights <= days
      ? PresenceEffort(nights, PresenceEffortUnit.evenings)
      : PresenceEffort(days, PresenceEffortUnit.days);
}

String _unitWord(PresenceEffort e) => e.unit == PresenceEffortUnit.evenings
    ? (e.count == 1 ? 'evening' : 'evenings')
    : (e.count == 1 ? 'day' : 'days');

/// "Otherwise, open the app at home on 5 different evenings."
String effortSentence(PresenceEffort e, {required bool isBusiness}) {
  final where = isBusiness ? 'at the premises' : 'at home';
  final different = e.count == 1 ? '' : ' different';
  return 'Otherwise, open the app $where on ${e.count}$different ${_unitWord(e)}.';
}

/// "Usually confirmed within 10 days."
String withinSentence(int days) => 'Usually confirmed within $days ${days == 1 ? 'day' : 'days'}.';

/// The success card's line when background checks are off.
String finishSentence(PresenceEffort e, {required bool isBusiness}) {
  final where = isBusiness ? 'at the premises' : 'at home';
  return 'Open the app $where on ${e.count} ${_unitWord(e)} to finish, or continue with automatic checks.';
}
