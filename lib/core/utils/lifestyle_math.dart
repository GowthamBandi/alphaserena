// Pure, Firebase-free math for the daily lifestyle tracker. Water is stored in
// millilitres and shown as glasses; targets fall back to platform defaults when
// the coach hasn't set one. Kept dependency-light so it unit-tests in isolation.

/// Platform default daily targets (used when a coach target is absent).
class LifestyleDefaults {
  static const double waterMl = 2500;
  static const int steps = 8000;
  static const double sleepHours = 8;
  static const double glassSizeMl = 250;
}

/// 'yyyy-MM-dd' from a local DateTime (day key + doc-id suffix).
String dayKey(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// Nearest whole glasses for [ml] at [glassSizeMl] each (guards bad size).
int glassesFor(double ml, double glassSizeMl) {
  if (glassSizeMl <= 0) return 0;
  final g = (ml / glassSizeMl).round();
  return g < 0 ? 0 : g;
}

/// Millilitres for [glasses] at [glassSizeMl] each.
double mlForGlasses(int glasses, double glassSizeMl) => glasses * glassSizeMl;

/// The coach target when set (> 0), otherwise the platform [fallback].
double effectiveTarget(double? coachTarget, double fallback) {
  if (coachTarget != null && coachTarget > 0) return coachTarget;
  return fallback;
}

/// Adherence over a window. [perDayValues] entries are null for days not logged;
/// average is over logged days only, hit = value >= target (target must be > 0).
class Adherence {
  final int loggedDays;
  final int hitDays;
  final double average;
  final double hitRate;

  const Adherence({
    this.loggedDays = 0,
    this.hitDays = 0,
    this.average = 0,
    this.hitRate = 0,
  });
}

Adherence adherenceFor(List<double?> perDayValues, double target) {
  final logged = perDayValues.whereType<double>().toList();
  if (logged.isEmpty) return const Adherence();
  final hits = (target > 0) ? logged.where((v) => v >= target).length : 0;
  final avg = logged.reduce((a, b) => a + b) / logged.length;
  return Adherence(
    loggedDays: logged.length,
    hitDays: hits,
    average: avg,
    hitRate: hits / logged.length,
  );
}

/// Supplement adherence as taken / prescribed (0 when nothing prescribed).
double supplementRate(int taken, int prescribed) {
  if (prescribed <= 0) return 0;
  return taken / prescribed;
}

// ── Validation ─────────────────────────────────────────────────────────────
//
// Nothing validated a lifestyle target or a logged value. `int.tryParse('-5')`
// is -5, so a coach could save a NEGATIVE steps goal or a 99-hour sleep goal,
// and a member could submit either. The bounds below are the single definition
// of "a possible human day" and are mirrored byte-for-byte in trainersHQ's
// copy of this file (pinned by a parity test on each side).

/// Physiological / practical bounds for every lifestyle quantity.
class LifestyleLimits {
  /// A glass has to be a drinkable size for the glasses↔ml conversion to mean
  /// anything — a 0 ml glass makes every water figure infinite.
  static const double minGlassMl = 50;
  static const double maxGlassMl = 2000;

  /// 20 L/day is already past the point where water is dangerous; anything
  /// above it is a typo, not a goal.
  static const double maxWaterMl = 20000;
  static const int maxWaterGlasses = 60;

  static const int maxSteps = 100000;

  /// A day is 24 hours. A sleep goal cannot exceed one.
  static const double maxSleepHours = 24;
}

/// Validates one coach-set or member-entered quantity.
///
/// Returns null when [raw] is acceptable, otherwise a coach/member-facing
/// message. A BLANK value is valid and means "no goal" — clearing a target is a
/// deliberate action, not an error.
String? validateOptionalNumber(
  String? raw, {
  required String label,
  required double max,
  double min = 0,
  bool integer = false,
  bool allowZero = false,
}) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null) return '$label must be a number.';
  if (value.isNaN || value.isInfinite) return '$label must be a number.';
  if (integer && value != value.roundToDouble()) {
    return '$label must be a whole number.';
  }
  if (!allowZero && value == 0) return '$label must be more than 0.';
  if (value < min) return '$label cannot be negative.';
  if (value > max) {
    final ceiling =
        max == max.roundToDouble() ? max.toStringAsFixed(0) : max.toString();
    return '$label looks too high (max $ceiling).';
  }
  return null;
}

/// Validates a member's own daily entry. Same bounds as the coach's targets —
/// a value a coach cannot set is a value a member cannot log.
String? validateStepsEntry(String? raw) => validateOptionalNumber(raw,
    label: 'Steps',
    max: LifestyleLimits.maxSteps.toDouble(),
    integer: true,
    allowZero: true);

String? validateSleepEntry(String? raw) => validateOptionalNumber(raw,
    label: 'Sleep', max: LifestyleLimits.maxSleepHours, allowZero: true);

// ── HABIT HISTORY STATISTICS ────────────────────────────────────────────────
//
// TWINS of the same functions in trainersHQ's `lifestyle_math.dart`. The two
// apps compute a member's streaks and trend from the SAME server-derived
// rollup days, so if these ever diverged a member and their coach would read
// different streaks off identical data. Pinned by
// `test/lifestyle_cross_app_contract_test.dart`, which exists because these
// two files have silently drifted before.

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Current + best consecutive-day GOAL-HIT streaks for one habit. [hitDays] is
/// the set of local days on which the logged value met the target. The current
/// streak counts back from today/yesterday only (a lapsed streak reads 0, not
/// a stale count); the best streak scans all history.
({int current, int best}) habitStreaks(Set<DateTime> hitDays, DateTime now) {
  if (hitDays.isEmpty) return (current: 0, best: 0);
  final days = hitDays.map(_day).toSet();
  final sorted = days.toList()..sort();
  var best = 1;
  var run = 1;
  for (var i = 1; i < sorted.length; i++) {
    run = sorted[i].difference(sorted[i - 1]).inDays == 1 ? run + 1 : 1;
    if (run > best) best = run;
  }
  final today = _day(now);
  final yesterday = today.subtract(const Duration(days: 1));
  final anchor = days.contains(today)
      ? today
      : (days.contains(yesterday) ? yesterday : null);
  var current = 0;
  if (anchor != null) {
    var cursor = anchor;
    while (days.contains(cursor)) {
      current++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
  }
  return (current: current, best: best);
}

/// Trend of a habit: recent-window average vs prior-window average.
/// Returns 1 (up), -1 (down) or 0 (flat / not enough data). [band] is the
/// relative change (fraction of the prior average) that counts as movement.
int trendDirection(double? recentAvg, double? priorAvg, {double band = 0.05}) {
  if (recentAvg == null || priorAvg == null || priorAvg <= 0) return 0;
  final delta = (recentAvg - priorAvg) / priorAvg;
  if (delta > band) return 1;
  if (delta < -band) return -1;
  return 0;
}

/// The highest (or lowest) logged day, or null when nothing is logged.
///
/// Over days the member actually LOGGED — an unlogged day is an absence, not a
/// bad day. Ties resolve to the MOST RECENT day: when a member matches their
/// best again, the useful thing to say is that they did it again.
MapEntry<DateTime, double>? extremeDayFor(
  Map<DateTime, double> dayValues, {
  required bool best,
}) {
  MapEntry<DateTime, double>? found;
  for (final e in dayValues.entries) {
    if (found == null) {
      found = e;
      continue;
    }
    final better = best ? e.value > found.value : e.value < found.value;
    final tieButNewer = e.value == found.value && e.key.isAfter(found.key);
    if (better || tieButNewer) found = e;
  }
  return found;
}
