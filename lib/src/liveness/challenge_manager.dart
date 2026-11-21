import 'dart:math';

import 'liveness_types.dart';

// ─── Challenge manager ────────────────────────────────────────────────────────
//
// Randomly selects `count` challenges from the pool at construction/reset and
// tracks which have been completed. Timing is intentionally NOT owned here —
// the liveness provider holds the dart:async Timer and calls
// currentTimeoutSeconds to know how long each challenge gets.
//
// Selection mirrors the web SDK's liveness/challenge-manager.ts: a head TURN is
// always one of the prompts (in a random position), gestures that can trigger
// each other never appear together, and no prompt appears twice.

/// Gestures within a group never appear together, because one can
/// accidentally trigger the other (head movement overlaps).
const List<Set<LivenessChallenge>> _similarityGroups = [
  {LivenessChallenge.nod, LivenessChallenge.turn},
];

bool _areSimilar(LivenessChallenge a, LivenessChallenge b) =>
    _similarityGroups.any((g) => g.contains(a) && g.contains(b));

class ChallengeManager {
  final List<ChallengeConfig> pool;
  final int count;

  late final List<ChallengeConfig> _selected;
  int _currentIndex = 0;

  // ── Factory constructor clamps count to valid range ────────────────────────

  factory ChallengeManager({
    List<ChallengeConfig>? pool,
    int count = 2,
  }) {
    final effectivePool = pool ?? kDefaultChallengePool;
    final clampedCount = count.clamp(1, effectivePool.length);
    return ChallengeManager._(pool: effectivePool, count: clampedCount);
  }

  /// No gesture challenges — flash-only liveness (`livenessMode: 'flash'`),
  /// where the screen-reflection sequence IS the check.
  ///
  /// Deliberately a separate constructor rather than `count: 0`: the factory
  /// clamps count to at least 1 so a stray `challengeCount: 0` in a consumer's
  /// config can never silently disable gesture liveness. Skipping gestures has
  /// to be asked for explicitly.
  factory ChallengeManager.none() =>
      ChallengeManager._(pool: const [], count: 0);

  /// Passive Liveness (`livenessMode: 'passive'`): the single hold prompt. No
  /// gestures and no flash; the server's liveness model does the judging.
  factory ChallengeManager.passive() =>
      ChallengeManager._(pool: const [kHoldChallenge], count: 1);

  /// Head directions (`livenessGestureSet: 'directions'`): [count] of the four
  /// (2 to 4, anything else is [kDefaultDirectionCount]), always with a head
  /// turn, in a shuffled order. A reset picks again.
  factory ChallengeManager.directions({int? count, Random? random}) {
    final n = directionCountOf(count);
    return ChallengeManager._(
      pool: kDirectionPool,
      count: n,
      pick: () => pickDirections(n, random)..shuffle(random),
    );
  }

  /// The prompts the workflow's liveness method asks for. The flash is not a
  /// prompt here: the screen runs it at the capture seam.
  factory ChallengeManager.forMode(
    String livenessMode, {
    List<ChallengeConfig>? pool,
    int count = 2,
    String? gestureSet,
    int? directionCount,
  }) =>
      switch (livenessMode) {
        'flash' => ChallengeManager.none(),
        'passive' => ChallengeManager.passive(),
        _ when gestureSet == kGestureSetDirections =>
          ChallengeManager.directions(count: directionCount),
        _ => ChallengeManager(pool: pool, count: count),
      };

  ChallengeManager._({
    required this.pool,
    required this.count,
    List<ChallengeConfig> Function()? pick,
  }) : _pick = pick {
    _selected = _pickNext();
  }

  /// How this manager picks its prompts, when not from [pool] at random.
  final List<ChallengeConfig> Function()? _pick;

  List<ChallengeConfig> _pickNext() => _pick?.call() ?? _pickRandom();

  // ── Accessors ───────────────────────────────────────────────────────────────

  /// The currently active challenge, or null when all challenges are done.
  ChallengeConfig? get current =>
      _currentIndex < _selected.length ? _selected[_currentIndex] : null;

  /// How many seconds the current challenge allows before timing out.
  /// Returns 0 when [isComplete].
  int get currentTimeoutSeconds => current?.timeoutSeconds ?? 0;

  /// The index (0-based) of the challenge being attempted.
  int get currentIndex => _currentIndex;

  /// How many challenges have been completed.
  int get completedCount => _currentIndex;

  /// How many challenges were selected for this session.
  int get totalCount => _selected.length;

  /// True once all selected challenges have been completed.
  bool get isComplete => _currentIndex >= _selected.length;

  /// Read-only snapshot of the challenges selected for this session.
  List<ChallengeConfig> get selectedChallenges =>
      List.unmodifiable(_selected);

  // ── Actions ─────────────────────────────────────────────────────────────────

  /// Advance to the next challenge. No-op when already complete.
  void advance() {
    if (!isComplete) _currentIndex++;
  }

  /// Re-shuffle the pool and restart from challenge 0.
  void reset() {
    _currentIndex = 0;
    _selected
      ..clear()
      ..addAll(_pickNext());
  }

  /// Asks exactly [challenges], in that order, from the first: Core's plan for
  /// this attempt (direction_plan.dart). Only before the first instruction has
  /// been given, which the caller makes sure of.
  void replaceWith(List<ChallengeConfig> challenges) {
    _currentIndex = 0;
    _selected
      ..clear()
      ..addAll(challenges);
  }

  // ── Internal ─────────────────────────────────────────────────────────────────

  List<ChallengeConfig> _pickRandom() {
    if (count <= 0) return <ChallengeConfig>[];
    final random = Random();
    final shuffled = List<ChallengeConfig>.from(pool)..shuffle(random);
    final picked = <ChallengeConfig>[];
    bool taken(ChallengeConfig c) => picked.any((p) => p.type == c.type);

    // A head TURN is always one of the prompts, because the server's
    // shape-from-movement test needs one: a turn swings the nose across the
    // face, which a flat picture cannot do. The rest stay random.
    for (final c in shuffled) {
      if (c.type == LivenessChallenge.turn) {
        picked.add(c);
        break;
      }
    }

    // Greedily add challenges that aren't similar to those already picked.
    for (final c in shuffled) {
      if (picked.length >= count) break;
      if (taken(c) || picked.any((p) => _areSimilar(p.type, c.type))) continue;
      picked.add(c);
    }

    // The similarity rule was too strict for this pool: fill the rest.
    for (final c in shuffled) {
      if (picked.length >= count) break;
      if (!taken(c)) picked.add(c);
    }

    // The turn went first to guarantee it; shuffle so its position is random.
    return picked..shuffle(random);
  }
}

/// A run asks for this many head directions unless the workflow says otherwise.
const int kDefaultDirectionCount = 3;

/// The workflow's `livenessDirectionCount` as a count to use: 2 to 4, anything
/// else (unset included) 3.
int directionCountOf(Object? count) =>
    count is int && count >= 2 && count <= kDirectionPool.length
        ? count
        : kDefaultDirectionCount;

/// PURE given [random]. The directions of a run, [count] of the four (2 to 4,
/// anything else is 3), always with at least one head turn, left or right. A
/// turn is what tells a head from a flat picture: Core only calls a capture
/// flat when a turn was asked for, and a photo can be tilted up and down but
/// not turned. The rest are picked at random from the other three, so which
/// directions and their order are what a recording made earlier cannot know.
/// Returned in the pool's order; the caller shuffles. The web SDK's
/// pickDirections.
List<ChallengeConfig> pickDirections([int count = kDefaultDirectionCount, Random? random]) {
  final rng = random ?? Random();
  final n = directionCountOf(count);
  final turns = kDirectionPool
      .where((c) =>
          c.type == LivenessChallenge.turnLeft ||
          c.type == LivenessChallenge.turnRight)
      .toList();
  final turn = turns[rng.nextInt(turns.length)];
  final rest = kDirectionPool.where((c) => c != turn).toList();
  // A partial Fisher-Yates with the same random source: n - 1 of the other three.
  for (var i = 0; i < n - 1; i++) {
    final j = i + rng.nextInt(rest.length - i);
    final held = rest[i];
    rest[i] = rest[j];
    rest[j] = held;
  }
  final chosen = {turn, ...rest.take(n - 1)};
  return kDirectionPool.where(chosen.contains).toList();
}

/// The prompts for a plan Core picked (direction_plan.dart): its gestures,
/// head directions or classic, in its order. A classic gesture takes the
/// integration's own [pool] entry when it has one, so its wording and timeout
/// stand, else this SDK's. The flash is not a prompt here (it runs at the
/// capture seam), so Dual Check needs nothing added. Unknown names are left
/// out.
List<ChallengeConfig> planChallenges(
  List<LivenessChallenge> prompts, {
  List<ChallengeConfig>? pool,
}) {
  final known = [...kDirectionPool, ...?pool, ...kDefaultChallengePool];
  return [
    for (final type in prompts)
      for (final c in known.where((c) => c.type == type).take(1)) c,
  ];
}

/// The prompts a run used, in order, as wire names for the liveness claim
/// (`integrity.liveness.challenges`): 'nod', 'turn', 'blink', 'smile',
/// 'flash', 'hold'.
///
/// [gestures] are the prompts the manager ran. The flash runs at the capture
/// seam, so it is placed here: after the gestures in 'both', alone in 'flash',
/// and FIRST when a flash-only check fell back to gestures.
List<String> livenessClaimChallenges({
  required String mode,
  required List<LivenessChallenge> gestures,
  bool fellBackToGestures = false,
}) {
  final names = [for (final g in gestures) g.name];
  if (fellBackToGestures) return ['flash', ...names];
  return switch (mode) {
    'flash' => const ['flash'],
    'both' => [...names, 'flash'],
    _ => names,
  };
}
