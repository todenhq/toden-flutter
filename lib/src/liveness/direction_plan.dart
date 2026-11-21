import 'liveness_types.dart';

// ─── The gestures Core picked for one liveness attempt ───────────────────────
//
// kyc-core docbio/direction-plan.ts: the head directions, since 2026-11-18
// the classic gestures too, and since 2026-11-19 the flash colours. PURE. A
// port of the web SDK's liveness/direction-plan.ts.
//
// The SDK used to pick the order itself; a modified client could then choose
// its own. Now each attempt asks Core for a plan (POST /liveness/directions),
// asks for exactly those gestures in that order, and names the plan in its
// liveness claim (`directionPlanId`), which Core checks at the verification.
// Without a plan (an older Core, or no answer in time) the SDK picks as before
// and names none, which Core records.
//
// The flash colours follow the same path: a check that runs a flash asks Core
// for them too (a flash-only check asks for colours and no gestures), shows
// exactly those in that order, and its own pick only when no usable plan came.

/// The gesture vocabulary a plan is for: head directions, classic, or none (a
/// flash-only check). Each value's `name` is its wire name.
enum PlanSet { directions, classic, none }

/// The flash colour names every SDK and Core share.
const List<String> kFlashColourNames = [
  'red',
  'green',
  'blue',
  'magenta',
  'cyan',
];

/// The classic gestures Core may plan, in the pool's order.
const List<LivenessChallenge> kClassicChallenges = [
  LivenessChallenge.nod,
  LivenessChallenge.turn,
  LivenessChallenge.blink,
  LivenessChallenge.smile,
];

/// What one attempt asks Core for.
class PlanRequest {
  /// [count] head directions, 2 to 4.
  const PlanRequest.directions(this.count, {this.flash})
      : set = PlanSet.directions,
        pool = const [];

  /// [count] classic gestures, 2 or 3, from [pool] when the integration
  /// narrowed it (empty: all four).
  const PlanRequest.classic(this.count, {this.pool = const [], this.flash})
      : set = PlanSet.classic;

  /// A flash-only check: [flash] colours and no gestures.
  const PlanRequest.flashOnly(int this.flash)
      : set = PlanSet.none,
        count = 0,
        pool = const [];

  final PlanSet set;
  final int count;

  /// Classic only: the gestures the integration allows, when it narrowed them.
  final List<LivenessChallenge> pool;

  /// How many flash colours to show (2 to 5), when the check runs a flash:
  /// Core picks them. Null when it runs none.
  final int? flash;

  /// The request body. No count for a flash-only check; the pool only with a
  /// classic request, and only when it narrows anything; the flash only when
  /// the check runs one. As the web SDK sends it.
  Map<String, Object> toJson() => {
        if (set != PlanSet.none) 'count': count,
        'set': set.name,
        if (set == PlanSet.classic && pool.isNotEmpty)
          'pool': [for (final g in pool) g.name],
        if (flash != null) 'flash': flash!,
      };
}

/// The classic request for an integration's own challenge pool, or null when
/// that pool holds no classic gesture: Core can only plan nod, turn, blink and
/// smile, and a plan from all four would ask what the integration left out.
/// No pool asks for any of the four. [flash] asks for the flash colours too.
PlanRequest? classicPlanRequest(
  int count,
  List<ChallengeConfig>? pool, {
  int? flash,
}) {
  if (pool == null) return PlanRequest.classic(count, flash: flash);
  final allowed = [
    for (final g in kClassicChallenges)
      if (pool.any((c) => c.type == g)) g,
  ];
  return allowed.isEmpty
      ? null
      : PlanRequest.classic(count, pool: allowed, flash: flash);
}

class DirectionPlan {
  const DirectionPlan({
    required this.planId,
    required this.prompts,
    this.flash = const [],
  });

  final String planId;

  /// The gestures to ask, in order: head directions or classic; empty for a
  /// flash-only check.
  final List<LivenessChallenge> prompts;

  /// The flash colours to show, in order; empty when none was asked (or an
  /// older Core answered).
  final List<String> flash;
}

/// How long the first instruction waits for the plan before the SDK picks its
/// own.
const Duration kDirectionPlanWait = Duration(milliseconds: 2500);

final RegExp _planId = RegExp(r'^[a-z0-9]{8,40}$', caseSensitive: false);

LivenessChallenge? _classicFromName(Object? name) {
  for (final g in kClassicChallenges) {
    if (g.name == name) return g;
  }
  return null;
}

/// The flash colours of an answer: 2 to 5 distinct known names, or none.
List<String> _flashOf(Object? raw) {
  if (raw is! List ||
      raw.length < 2 ||
      raw.length > kFlashColourNames.length) {
    return const [];
  }
  if (!raw.every(kFlashColourNames.contains) ||
      raw.toSet().length != raw.length) {
    return const [];
  }
  return List<String>.unmodifiable(raw.cast<String>());
}

/// A plan from Core the SDK can use for what it asked, or null. Head
/// directions: 2 to 4 distinct, a turn among them. Classic: 1 to 3 distinct
/// classic gestures, all from the pool when one was given. Reads `prompts`,
/// else `directions` (a Core from before classic plans). When the flash was
/// asked for, exactly that many usable colours must come back, or there is no
/// plan and the SDK picks its own.
DirectionPlan? parseDirectionPlan(
  Object? raw, [
  PlanRequest request = const PlanRequest.directions(3),
]) {
  if (raw is! Map) return null;
  final planId = raw['planId'];
  final names = raw['prompts'] is List ? raw['prompts'] : raw['directions'];
  if (planId is! String || !_planId.hasMatch(planId)) return null;
  final flash = request.flash != null ? _flashOf(raw['flash']) : const <String>[];
  // A flash asked for and not given back usable: the SDK picks its own.
  if (request.flash != null && flash.length != request.flash) return null;
  if (request.set == PlanSet.none) {
    return DirectionPlan(planId: planId, prompts: const [], flash: flash);
  }
  if (names is! List || names.toSet().length != names.length) return null;
  if (request.set == PlanSet.classic) {
    final allowed =
        request.pool.isNotEmpty ? request.pool : kClassicChallenges;
    if (names.isEmpty || names.length > 3) return null;
    final prompts = <LivenessChallenge>[];
    for (final name in names) {
      final gesture = _classicFromName(name);
      if (gesture == null || !allowed.contains(gesture)) return null;
      prompts.add(gesture);
    }
    return DirectionPlan(planId: planId, prompts: prompts, flash: flash);
  }
  if (names.length < 2 || names.length > kDirectionChallenges.length) {
    return null;
  }
  final directions = <LivenessChallenge>[];
  for (final name in names) {
    final direction = directionFromName(name);
    if (direction == null) return null;
    directions.add(direction);
  }
  if (!directions.any((d) =>
      d == LivenessChallenge.turnLeft || d == LivenessChallenge.turnRight)) {
    return null;
  }
  return DirectionPlan(planId: planId, prompts: directions, flash: flash);
}

/// Where the current attempt's plan request stands.
enum DirectionPlanStatus { none, pending, ready, failed }

/// What the first instruction does about the plan: wait for it, or go on
/// without it. [askedAt] and [now] are on the same clock, in milliseconds.
bool planGateWaits(DirectionPlanStatus status, int askedAt, int now) =>
    status == DirectionPlanStatus.pending &&
    now - askedAt < kDirectionPlanWait.inMilliseconds;
