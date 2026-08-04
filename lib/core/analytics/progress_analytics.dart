// ═══════════════════════════════════════════════════════════════════════════
// SHARED PROGRESS ANALYTICS — THE SINGLE SOURCE OF TRUTH
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️  THIS FILE IS TWINNED. The identical file lives at:
//        alphaserena/lib/core/analytics/progress_analytics.dart
//        trainersHQ/lib/core/analytics/progress_analytics.dart
//     A change to EITHER copy without the other is a defect, and
//     `test/progress_analytics_parity_test.dart` (present in BOTH repos, driven
//     by the SAME committed fixture `test/fixtures/progress_analytics.json`)
//     fails on that side until they agree again.
//
// ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────
//
// The coach app derived strength trends, personal bests, volume, streaks and a
// coaching verdict in `trainersHQ/lib/core/progress/progress_series.dart`; the
// member app derived none of it and its Progress screen said "Strength trends
// are next". Porting that file verbatim was impossible AND undesirable:
//
//   • IMPOSSIBLE — the two apps parse the same Firestore documents into
//     DIFFERENT model types (`ClientWorkoutSessionModel`/`SessionEntry`/
//     `SessionSet` vs `WorkoutDayLog`/`ExerciseLog`/`SetLog`). A copy would not
//     have compiled.
//   • UNDESIRABLE — copy-and-twin is the exact mechanism that has ALREADY
//     failed once on this feature: `transformation_comparison.dart` diverged
//     silently (TrainerHQ grew `transformationMeasurementKeys`, AlphaSerena
//     never received it), which is how per-side arm/calf measurements went
//     missing from a coach's view.
//
// So the math is written ONCE, against NEITHER app's models. It operates on the
// small neutral value types below; each app supplies a thin adapter. Adding a
// model field on one side can no longer change a number on the other, because
// no app model is reachable from this file.
//
// ── THE RULES THIS FILE OBEYS ──────────────────────────────────────────────
//
//  1. PURE. No Flutter, no Firestore, no GetX, no `DateTime.now()`. Every
//     windowed function takes an injected `now`, so every result is
//     deterministic under test.
//  2. NEVER FABRICATE. A series a source cannot support returns EMPTY and the
//     surface shows its empty state. A metric below `minSample` returns a value
//     the caller must not headline (see [ProgressConfidence]). Absent is
//     absent — never zero.
//  3. NULL IS NOT ZERO. "did not log" and "logged none" are different facts and
//     stay different all the way to the pixel.
//  4. THE THRESHOLDS ARE A CROSS-REPO CONTRACT. [AnalyticsPolicy] MUST equal
//     `trainershq-backend/functions/src/lib/progress_config.ts`
//     (ADHERENCE_WINDOW_DAYS / MIN_SAMPLE / ON_TRACK_PCT). Changing one is a
//     coordinated three-file edit; drift-guards pin all three sides.

import 'dart:math' as math;

// ═══════════════════════════════════════════════════════════════════════════
// NEUTRAL INPUT TYPES — what each app adapts INTO. No app model appears here.
// ═══════════════════════════════════════════════════════════════════════════

/// One logged set, reduced to the four numbers any analytic needs.
///
/// Prescribed/actual arrive as already-parsed numbers rather than the raw
/// strings both apps store ("8-12", "40kg"), because parsing a prescription
/// string is a MODEL concern that each app already solved identically
/// (`_numeric` in AlphaSerena, `_num` in TrainerHQ — both
/// `RegExp(r'-?\d+(\.\d+)?')` first-match). Re-solving it here would create a
/// third parser to keep in sync.
class AnalyticsSet {
  final double? prescribedReps;
  final double? prescribedWeight;
  final double? actualReps;
  final double? actualWeight;
  final bool completed;

  const AnalyticsSet({
    this.prescribedReps,
    this.prescribedWeight,
    this.actualReps,
    this.actualWeight,
    this.completed = false,
  });

  /// Did this set meet its prescription?
  ///
  /// PARITY: byte-for-byte the rule in TrainerHQ `SessionSet.hit`, AlphaSerena
  /// `setHitTarget`, and backend `lib/progress.ts setHit`. A dimension with no
  /// numeric target is skipped; a set with no numeric target at all counts as a
  /// hit, because there was nothing to miss.
  bool get hit {
    final repsOk =
        prescribedReps == null ||
        (actualReps != null && actualReps! >= prescribedReps!);
    final weightOk =
        prescribedWeight == null ||
        (actualWeight != null && actualWeight! >= prescribedWeight!);
    return repsOk && weightOk;
  }
}

/// One logged exercise inside a session.
class AnalyticsEntry {
  /// The library id when the entry is linked; empty for freehand/legacy logs.
  final String exerciseId;
  final String exerciseName;
  final List<AnalyticsSet> sets;

  const AnalyticsEntry({
    this.exerciseId = '',
    this.exerciseName = '',
    this.sets = const [],
  });
}

/// One logged training session.
class AnalyticsSession {
  final DateTime date;
  final List<AnalyticsEntry> entries;

  const AnalyticsSession({required this.date, this.entries = const []});

  /// Share of COMPLETED sets that hit their target, or null when no set is
  /// completed (nothing to judge yet).
  ///
  /// PARITY: TrainerHQ `SessionAdherence.from`, backend `sessionTargetHitPct`.
  double? get targetHitPct {
    final all = [for (final e in entries) ...e.sets];
    final completed = all.where((s) => s.completed).toList();
    if (completed.isEmpty) return null;
    return completed.where((s) => s.hit).length / completed.length;
  }
}

/// One dated scalar sample on a trend chart.
class TrendPoint {
  final DateTime date;
  final double value;
  const TrendPoint(this.date, this.value);
}

/// A dated body observation. Both a transformation checkpoint and a weekly
/// check-in packet adapt into this, which is what lets [reconciledWeightSeries]
/// see a member who only ever weighs in inside a check-in.
class AnalyticsBodyPoint {
  final DateTime date;
  final double? weightKg;
  final Map<String, double> measurements;

  const AnalyticsBodyPoint({
    required this.date,
    this.weightKg,
    this.measurements = const {},
  });
}

/// A dated 0..1 adherence observation (nutrition day, lifestyle day, diet log).
/// One shape for every adherence-like source so the trend, the direction and
/// the confidence gate are computed once rather than per domain.
class AnalyticsRatio {
  final DateTime date;
  final double value;
  const AnalyticsRatio(this.date, this.value);
}

// ═══════════════════════════════════════════════════════════════════════════
// POLICY — the cross-repo threshold contract
// ═══════════════════════════════════════════════════════════════════════════

/// The ONLY place Progress thresholds and classification live.
///
/// The first three constants are the SHARED subset and MUST equal
/// `functions/src/lib/progress_config.ts`. `directionBand` and
/// `weightFlatBandKg` are client-only (the server rollup stores no direction).
class AnalyticsPolicy {
  const AnalyticsPolicy();

  /// Rolling observation window (days) — MUST match `ADHERENCE_WINDOW_DAYS`.
  static const int windowDays = 28;

  /// Minimum in-window records before a metric may be headlined — MUST match
  /// `MIN_SAMPLE`.
  static const int minSample = 3;

  /// Adherence at/above this fraction is "on track" — MUST match `ON_TRACK_PCT`.
  static const double onTrackPct = 0.8;

  /// Minimum absolute move between the recent and prior halves of a window that
  /// counts as a real change; smaller swings read as steady so day-to-day noise
  /// never flips a direction in front of a member.
  static const double directionBand = 0.05;

  /// Net weight change (kg) inside this band reads as steady — below normal
  /// scale and water-weight noise.
  static const double weightFlatBandKg = 0.3;

  /// Classifies a "higher is better" 0..1 metric from recent vs prior.
  ///
  /// Weight is deliberately NOT classified by this: whether losing or gaining
  /// is good depends on a goal weight NO collection in this platform stores, so
  /// weight movement is reported factually and never judged.
  static ProgressDirection directionFor(double recent, double prior) {
    final delta = recent - prior;
    if (delta > directionBand) return ProgressDirection.improving;
    if (delta < -directionBand) return ProgressDirection.declining;
    return ProgressDirection.steady;
  }

  /// How much to trust a metric given how many in-window records fed it.
  static ProgressConfidence confidenceFor(int sampleSize) {
    if (sampleSize <= 0) return ProgressConfidence.none;
    if (sampleSize < minSample) return ProgressConfidence.low;
    return ProgressConfidence.ok;
  }
}

/// Trend of a metric over its window. INTERNAL — the presentation layer chooses
/// the member-facing word; the enum name is never rendered verbatim.
enum ProgressDirection { improving, steady, declining, unknown }

/// Whether there is enough in-window data to trust a metric. [none] means the
/// surface says "not enough data yet" and shows NO number.
enum ProgressConfidence { none, low, ok }

// ═══════════════════════════════════════════════════════════════════════════
// INTERNAL HELPERS
// ═══════════════════════════════════════════════════════════════════════════

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

double _mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;

// ═══════════════════════════════════════════════════════════════════════════
// BODY
// ═══════════════════════════════════════════════════════════════════════════

/// Weight over time, RECONCILED across the two places a member records it: the
/// dedicated transformation checkpoint AND the weekly check-in packet.
///
/// De-duplicated by DAY, with [primary] winning a same-day tie — a member who
/// logged a full checkpoint and mentioned a weight in a check-in on one day has
/// recorded one weight, not two.
///
/// 🔴 THE DEFECT THIS CLOSES: the member's Progress chart read transformation
/// checkpoints ALONE, so a member who only ever weighs in inside their weekly
/// check-in was told "Add at least two check-ins to see a trend" while their
/// coach — whose app already reconciled both sources — was looking at the
/// trend. Two apps, one member, opposite answers.
List<TrendPoint> reconciledWeightSeries(
  List<AnalyticsBodyPoint> primary,
  List<AnalyticsBodyPoint> secondary,
) {
  final byDay = <DateTime, double>{};
  // Secondary first so a same-day primary sample OVERWRITES it.
  for (final s in secondary) {
    final w = s.weightKg;
    if (w != null) byDay[_day(s.date)] = w;
  }
  for (final p in primary) {
    final w = p.weightKg;
    if (w != null) byDay[_day(p.date)] = w;
  }
  final days = byDay.keys.toList()..sort();
  return [for (final d in days) TrendPoint(d, byDay[d]!)];
}

/// One measurement key (e.g. "waist") over time, ascending.
List<TrendPoint> measurementSeries(
  List<AnalyticsBodyPoint> points,
  String key,
) {
  final pts = <TrendPoint>[];
  for (final p in points) {
    final v = p.measurements[key];
    if (v != null) pts.add(TrendPoint(p.date, v));
  }
  pts.sort((a, b) => a.date.compareTo(b.date));
  return pts;
}

/// The measurement keys actually PRESENT across [points], in head-to-toe
/// reading order, with unrecognised keys kept and appended.
///
/// A surface must derive its rows from the member's own data, never from a
/// fixed list: a hard-coded list silently drops anything the member logged that
/// it does not know about — which is exactly how neck, per-side arms, thighs
/// and calves went missing from the coach's progress view — and shows empty
/// rows for keys the member never records.
List<String> presentMeasurementKeys(Iterable<AnalyticsBodyPoint> points) {
  const order = <String>[
    'neck', 'chest', 'arms', 'leftArm', 'rightArm',
    'waist', 'hips', 'thighs', 'leftThigh', 'rightThigh',
    'leftCalf', 'rightCalf',
  ];
  final present = <String>{for (final p in points) ...p.measurements.keys};
  final ordered = [for (final k in order) if (present.remove(k)) k];
  return [...ordered, ...present.toList()..sort()];
}

// ═══════════════════════════════════════════════════════════════════════════
// TRAINING
// ═══════════════════════════════════════════════════════════════════════════

/// Stable identity for one LOGGED exercise across renames: the library
/// `exerciseId` when linked, else the logged name.
///
/// Keying analytics on this instead of the raw name means renaming a library
/// exercise no longer splits its history into two series, while name-only
/// legacy data keeps working unchanged.
String exerciseIdentity(AnalyticsEntry e) =>
    e.exerciseId.isNotEmpty ? 'id:${e.exerciseId}' : 'name:${e.exerciseName}';

/// Per-session workout adherence over the window, ascending. Sessions with
/// nothing scorable are skipped — the same rule the headline metric uses, so
/// the chart and the number can never disagree.
List<TrendPoint> workoutAdherenceSeries(
  List<AnalyticsSession> sessions, {
  required DateTime now,
  int windowDays = AnalyticsPolicy.windowDays,
}) {
  final start = now.subtract(Duration(days: windowDays));
  final pts = <TrendPoint>[];
  for (final s in sessions) {
    if (s.date.isBefore(start)) continue;
    final pct = s.targetHitPct;
    if (pct != null) pts.add(TrendPoint(s.date, pct));
  }
  pts.sort((a, b) => a.date.compareTo(b.date));
  return pts;
}

/// The most-logged exercise that carries a numeric working weight — the natural
/// candidate for a strength line. Returns its stable identity [key] plus the
/// most recently logged display [name] for that key, so a renamed exercise is
/// labelled by its CURRENT name rather than a stale one. Null when no logged
/// set has a numeric weight.
({String key, String name})? topWeightedExercise(
  List<AnalyticsSession> sessions,
) {
  final counts = <String, int>{};
  final latestName = <String, String>{};
  final latestAt = <String, DateTime>{};
  for (final s in sessions) {
    for (final e in s.entries) {
      if (e.exerciseName.isEmpty && e.exerciseId.isEmpty) continue;
      final hasWeight = e.sets.any((st) => (st.actualWeight ?? 0) > 0);
      if (!hasWeight) continue;
      final key = exerciseIdentity(e);
      counts[key] = (counts[key] ?? 0) + 1;
      final at = latestAt[key];
      if (at == null || s.date.isAfter(at)) {
        latestAt[key] = s.date;
        latestName[key] = e.exerciseName;
      }
    }
  }
  if (counts.isEmpty) return null;
  // Deterministic under ties: highest count, then the identity key, so two
  // equally-logged exercises never swap places between rebuilds.
  final sorted = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  final key = sorted.first.key;
  return (key: key, name: latestName[key] ?? '');
}

/// Every exercise identity that can support a strength line, most-logged first.
/// Powers a member-facing exercise picker, so the chart is not permanently
/// stuck on whatever [topWeightedExercise] happens to return.
List<({String key, String name, int sessions})> weightedExercises(
  List<AnalyticsSession> sessions,
) {
  final counts = <String, int>{};
  final latestName = <String, String>{};
  final latestAt = <String, DateTime>{};
  for (final s in sessions) {
    for (final e in s.entries) {
      if (e.exerciseName.isEmpty && e.exerciseId.isEmpty) continue;
      if (!e.sets.any((st) => (st.actualWeight ?? 0) > 0)) continue;
      final key = exerciseIdentity(e);
      counts[key] = (counts[key] ?? 0) + 1;
      final at = latestAt[key];
      if (at == null || s.date.isAfter(at)) {
        latestAt[key] = s.date;
        latestName[key] = e.exerciseName;
      }
    }
  }
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  return [
    for (final e in entries)
      (key: e.key, name: latestName[e.key] ?? '', sessions: e.value),
  ];
}

/// Strength trend for one exercise IDENTITY: the heaviest logged working set
/// per session, ascending. Sessions logged under an OLD name of the same
/// library exercise contribute to the SAME series (id-keyed). Empty when the
/// exercise has no numeric-weight sets.
List<TrendPoint> strengthSeries(
  List<AnalyticsSession> sessions,
  String identityKey,
) {
  final pts = <TrendPoint>[];
  for (final s in sessions) {
    double best = 0;
    for (final e in s.entries) {
      if (exerciseIdentity(e) != identityKey) continue;
      for (final st in e.sets) {
        final w = st.actualWeight ?? 0;
        if (w > best) best = w;
      }
    }
    if (best > 0) pts.add(TrendPoint(s.date, best));
  }
  pts.sort((a, b) => a.date.compareTo(b.date));
  return pts;
}

/// Current training streak: consecutive calendar days, counting back from
/// today, on which a session was logged. Zero unless the most recent logged day
/// is today or yesterday — a broken streak reads as 0, never a stale count.
int workoutStreak(List<AnalyticsSession> sessions, {required DateTime now}) {
  final days = sessions.map((s) => _day(s.date)).toSet();
  if (days.isEmpty) return 0;
  final today = _day(now);
  final yesterday = today.subtract(const Duration(days: 1));
  var cursor = days.contains(today)
      ? today
      : (days.contains(yesterday) ? yesterday : null);
  if (cursor == null) return 0;
  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = cursor!.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Longest run of consecutive logged days anywhere in [sessions].
///
/// ⚠️ This is bounded by whatever window the CALLER loaded. A surface showing
/// it must state that window ("longest in 90 days"), because a personal best
/// the engine cannot see is not a personal best it may claim.
int longestWorkoutStreak(List<AnalyticsSession> sessions) {
  final days = sessions.map((s) => _day(s.date)).toList()..sort();
  if (days.isEmpty) return 0;
  var best = 1;
  var run = 1;
  for (var i = 1; i < days.length; i++) {
    if (days[i] == days[i - 1]) continue; // same day logged twice
    if (days[i].difference(days[i - 1]).inDays == 1) {
      run++;
      if (run > best) best = run;
    } else {
      run = 1;
    }
  }
  return best;
}

/// Total training volume (Σ completed-set weight × reps) in the window, kg·reps.
/// Zero when no completed set carries both a numeric weight and numeric reps.
double totalVolume(
  List<AnalyticsSession> sessions, {
  required DateTime now,
  int windowDays = AnalyticsPolicy.windowDays,
}) {
  final start = now.subtract(Duration(days: windowDays));
  var vol = 0.0;
  for (final s in sessions) {
    if (s.date.isBefore(start)) continue;
    for (final e in s.entries) {
      for (final st in e.sets) {
        if (!st.completed) continue;
        vol += (st.actualWeight ?? 0) * (st.actualReps ?? 0);
      }
    }
  }
  return vol;
}

/// Per-session training volume over the window, ascending — the chartable form
/// of [totalVolume]. Sessions with no volume are skipped rather than plotted as
/// zero (a bodyweight session is not a session that did nothing).
List<TrendPoint> volumeSeries(
  List<AnalyticsSession> sessions, {
  required DateTime now,
  int windowDays = AnalyticsPolicy.windowDays,
}) {
  final start = now.subtract(Duration(days: windowDays));
  final pts = <TrendPoint>[];
  for (final s in sessions) {
    if (s.date.isBefore(start)) continue;
    var vol = 0.0;
    for (final e in s.entries) {
      for (final st in e.sets) {
        if (!st.completed) continue;
        vol += (st.actualWeight ?? 0) * (st.actualReps ?? 0);
      }
    }
    if (vol > 0) pts.add(TrendPoint(s.date, vol));
  }
  pts.sort((a, b) => a.date.compareTo(b.date));
  return pts;
}

/// Count of distinct exercises logged in the window, identity-keyed so a
/// renamed library exercise counts once, not twice.
int distinctExercises(
  List<AnalyticsSession> sessions, {
  required DateTime now,
  int windowDays = AnalyticsPolicy.windowDays,
}) {
  final start = now.subtract(Duration(days: windowDays));
  final keys = <String>{};
  for (final s in sessions) {
    if (s.date.isBefore(start)) continue;
    for (final e in s.entries) {
      if (e.exerciseName.isNotEmpty || e.exerciseId.isNotEmpty) {
        keys.add(exerciseIdentity(e));
      }
    }
  }
  return keys.length;
}

/// Heaviest logged working set per exercise — a personal-best board, strongest
/// first. Grouped by stable identity so a rename never splits one exercise's PB
/// into two rows; labelled with the most recently logged name. Carries the date
/// the best was set, so a surface can say WHEN without a second pass.
/// Empty when no set carries a numeric weight.
List<({String exercise, double weight, DateTime at})> personalBests(
  List<AnalyticsSession> sessions, {
  int limit = 3,
}) {
  final best = <String, double>{};
  final bestAt = <String, DateTime>{};
  final latestName = <String, String>{};
  final latestAt = <String, DateTime>{};
  for (final s in sessions) {
    for (final e in s.entries) {
      if (e.exerciseName.isEmpty && e.exerciseId.isEmpty) continue;
      final key = exerciseIdentity(e);
      for (final st in e.sets) {
        final w = st.actualWeight ?? 0;
        if (w > (best[key] ?? 0)) {
          best[key] = w;
          bestAt[key] = s.date;
        }
      }
      final at = latestAt[key];
      if (at == null || s.date.isAfter(at)) {
        latestAt[key] = s.date;
        latestName[key] = e.exerciseName;
      }
    }
  }
  final entries = best.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) {
      final byWeight = b.value.compareTo(a.value);
      return byWeight != 0 ? byWeight : a.key.compareTo(b.key);
    });
  return [
    for (final e in entries.take(limit))
      (
        exercise: latestName[e.key] ?? e.key,
        weight: e.value,
        at: bestAt[e.key]!,
      ),
  ];
}

/// Distinct calendar days with a logged session in the window.
int activeDays(
  List<AnalyticsSession> sessions, {
  required DateTime now,
  int windowDays = AnalyticsPolicy.windowDays,
}) {
  final start = now.subtract(Duration(days: windowDays));
  return sessions
      .where((s) => !s.date.isBefore(start))
      .map((s) => _day(s.date))
      .toSet()
      .length;
}

/// Sessions per week over the window, from observed activity.
///
/// This is FREQUENCY OBSERVED, never frequency-vs-target: no collection in this
/// platform stores a prescribed weekly session count, so a "3 of 4 planned"
/// figure would be invented. It reports what happened and says over what span.
double sessionsPerWeek(
  List<AnalyticsSession> sessions, {
  required DateTime now,
  int windowDays = AnalyticsPolicy.windowDays,
}) {
  if (windowDays <= 0) return 0;
  final start = now.subtract(Duration(days: windowDays));
  final n = sessions.where((s) => !s.date.isBefore(start)).length;
  return n / (windowDays / 7.0);
}

// ═══════════════════════════════════════════════════════════════════════════
// ADHERENCE (nutrition · lifestyle · anything 0..1 and dated)
// ═══════════════════════════════════════════════════════════════════════════

/// Per-day adherence over the window, ascending, de-duplicated by DAY.
/// A day is a day: two documents describing one date must not both be plotted.
List<TrendPoint> adherenceSeries(
  List<AnalyticsRatio> ratios, {
  required DateTime now,
  int windowDays = AnalyticsPolicy.windowDays,
}) {
  final start = now.subtract(Duration(days: windowDays));
  final byDay = <DateTime, double>{};
  for (final r in ratios) {
    if (r.date.isBefore(start)) continue;
    byDay[_day(r.date)] = r.value.clamp(0.0, 1.0).toDouble();
  }
  final days = byDay.keys.toList()..sort();
  return [for (final d in days) TrendPoint(d, byDay[d]!)];
}

/// A headline adherence figure over the window, with its own trust gate.
///
/// Returns null when NOTHING in the window is scorable — an unearned 0% is a
/// fabricated failure, and this platform does not show one.
({double value, ProgressDirection direction, int sample, ProgressConfidence confidence})?
    adherenceSummary(
  List<AnalyticsRatio> ratios, {
  required DateTime now,
  int windowDays = AnalyticsPolicy.windowDays,
}) {
  final series = adherenceSeries(ratios, now: now, windowDays: windowDays);
  if (series.isEmpty) return null;
  final half = now.subtract(Duration(days: windowDays ~/ 2));
  final recent = [
    for (final p in series)
      if (!p.date.isBefore(half)) p.value,
  ];
  final prior = [
    for (final p in series)
      if (p.date.isBefore(half)) p.value,
  ];
  final direction = (recent.isNotEmpty && prior.isNotEmpty)
      ? AnalyticsPolicy.directionFor(_mean(recent), _mean(prior))
      : ProgressDirection.unknown;
  final values = [for (final p in series) p.value];
  return (
    value: _mean(values),
    direction: direction,
    sample: series.length,
    confidence: AnalyticsPolicy.confidenceFor(series.length),
  );
}

/// Workout adherence over the window with the same shape and gate as
/// [adherenceSummary]. Measures the QUALITY of logged sessions (share of
/// completed sets hitting prescription), NOT sessions-vs-frequency — there is
/// no stored prescribed frequency to measure against.
({double value, ProgressDirection direction, int sample, ProgressConfidence confidence})?
    workoutAdherenceSummary(
  List<AnalyticsSession> sessions, {
  required DateTime now,
  int windowDays = AnalyticsPolicy.windowDays,
}) {
  final start = now.subtract(Duration(days: windowDays));
  final half = now.subtract(Duration(days: windowDays ~/ 2));
  final scored = <({DateTime date, double pct})>[];
  for (final s in sessions) {
    if (s.date.isBefore(start)) continue;
    final pct = s.targetHitPct;
    if (pct != null) scored.add((date: s.date, pct: pct));
  }
  if (scored.isEmpty) return null;
  final recent = [
    for (final s in scored)
      if (!s.date.isBefore(half)) s.pct,
  ];
  final prior = [
    for (final s in scored)
      if (s.date.isBefore(half)) s.pct,
  ];
  final direction = (recent.isNotEmpty && prior.isNotEmpty)
      ? AnalyticsPolicy.directionFor(_mean(recent), _mean(prior))
      : ProgressDirection.unknown;
  return (
    value: _mean([for (final s in scored) s.pct]),
    direction: direction,
    sample: scored.length,
    confidence: AnalyticsPolicy.confidenceFor(scored.length),
  );
}

/// Participation TREND: distinct active days in the recent half of the window
/// versus the prior half, as rates.
///
/// Deliberately separate from an absolute "has this member gone quiet?" —
/// momentum answers the directional "trending up or down?". Null when nothing
/// is logged in either half.
({double recentRate, double priorRate, int recentDays, int halfWindow, ProgressDirection direction})?
    momentum(
  List<DateTime> activityDates, {
  required DateTime now,
  int windowDays = AnalyticsPolicy.windowDays,
}) {
  final half = windowDays ~/ 2;
  if (half <= 0) return null;
  final windowStart = now.subtract(Duration(days: windowDays));
  final recentStart = now.subtract(Duration(days: half));

  final recentDays = activityDates
      .where((d) => !d.isBefore(recentStart) && !d.isAfter(now))
      .map(_day)
      .toSet()
      .length;
  final priorDays = activityDates
      .where((d) => !d.isBefore(windowStart) && d.isBefore(recentStart))
      .map(_day)
      .toSet()
      .length;
  if (recentDays + priorDays == 0) return null;

  final recentRate = (recentDays / half).clamp(0.0, 1.0).toDouble();
  final priorRate = (priorDays / half).clamp(0.0, 1.0).toDouble();
  return (
    recentRate: recentRate,
    priorRate: priorRate,
    recentDays: recentDays,
    halfWindow: half,
    direction: AnalyticsPolicy.directionFor(recentRate, priorRate),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// SMOOTHING + SHAPE
// ═══════════════════════════════════════════════════════════════════════════

/// Trailing simple moving average over [window] samples. Returns a list the
/// same length as [values]; early positions average what is available so the
/// smoothed line spans the whole series. [window] < 2 returns the input.
List<double> movingAverage(List<double> values, int window) {
  if (window < 2 || values.length < 2) return List<double>.from(values);
  final out = <double>[];
  for (var i = 0; i < values.length; i++) {
    final from = math.max(0, i - window + 1);
    var sum = 0.0;
    for (var j = from; j <= i; j++) {
      sum += values[j];
    }
    out.add(sum / (i - from + 1));
  }
  return out;
}

/// Net change across a series (last − first), or null with fewer than two
/// points. The honest answer to "how much did this move?" — never a slope
/// fitted through two points and presented as a rate.
double? netChange(List<TrendPoint> series) {
  if (series.length < 2) return null;
  return series.last.value - series.first.value;
}

/// Direction of a "higher is better" series from its own two halves. Returns
/// [ProgressDirection.unknown] with fewer than two points, or when either half
/// is empty — never a direction inferred from a single observation.
ProgressDirection seriesDirection(List<TrendPoint> series) {
  if (series.length < 2) return ProgressDirection.unknown;
  final mid = series.length ~/ 2;
  final prior = series.take(mid).map((p) => p.value).toList();
  final recent = series.skip(mid).map((p) => p.value).toList();
  if (prior.isEmpty || recent.isEmpty) return ProgressDirection.unknown;
  return AnalyticsPolicy.directionFor(_mean(recent), _mean(prior));
}

/// Direction of a WEIGHT series — factual, never judged.
///
/// [ProgressDirection.improving] here means "went up", [declining] means "went
/// down". Whether either is good depends on a goal weight this platform does
/// not store, so no caller may colour it good or bad. Movement inside
/// [AnalyticsPolicy.weightFlatBandKg] is steady.
ProgressDirection weightMovement(List<TrendPoint> series) {
  final net = netChange(series);
  if (net == null) return ProgressDirection.unknown;
  if (net > AnalyticsPolicy.weightFlatBandKg) return ProgressDirection.improving;
  if (net < -AnalyticsPolicy.weightFlatBandKg) {
    return ProgressDirection.declining;
  }
  return ProgressDirection.steady;
}

// ═══════════════════════════════════════════════════════════════════════════
// OVERALL VERDICT
// ═══════════════════════════════════════════════════════════════════════════

/// One scored dimension feeding the overall verdict.
class ScoredDimension {
  final String id;
  final String label;
  final double value;
  final ProgressDirection direction;
  final int sample;
  final ProgressConfidence confidence;

  const ScoredDimension({
    required this.id,
    required this.label,
    required this.value,
    required this.direction,
    required this.sample,
    required this.confidence,
  });
}

/// The headline score (0..1): the mean of the dimensions that are trustworthy
/// enough to state.
///
/// Only dimensions with at least [ProgressConfidence.low] count; null when none
/// qualifies, which the surface renders as "still building" rather than 0%.
double? overallScore(List<ScoredDimension> dimensions) {
  final vals = [
    for (final d in dimensions)
      if (d.confidence != ProgressConfidence.none) d.value,
  ];
  if (vals.isEmpty) return null;
  return _mean(vals);
}

/// The combined direction: any improving with no declining → improving; any
/// declining with no improving → declining; otherwise steady. Unknown when no
/// dimension expresses a direction.
ProgressDirection overallDirection(List<ScoredDimension> dimensions) {
  var improving = 0;
  var declining = 0;
  var known = 0;
  for (final d in dimensions) {
    switch (d.direction) {
      case ProgressDirection.improving:
        improving++;
        known++;
      case ProgressDirection.declining:
        declining++;
        known++;
      case ProgressDirection.steady:
        known++;
      case ProgressDirection.unknown:
        break;
    }
  }
  if (known == 0) return ProgressDirection.unknown;
  if (improving > 0 && declining == 0) return ProgressDirection.improving;
  if (declining > 0 && improving == 0) return ProgressDirection.declining;
  return ProgressDirection.steady;
}

/// The single decision-oriented state for the Progress hero.
///
/// Grounded ONLY in real signals: the score, its overall direction, and how
/// recently the member was active. A review being due is deliberately NOT an
/// input — that is an action cue, not a judgement of how the member is doing.
enum ProgressVerdict {
  building,
  slipping,
  behind,
  steady,
  improving,
  excellent,
}

ProgressVerdict progressVerdict({
  required double? score,
  required ProgressDirection overall,
  int? daysSinceActive,
}) {
  if (score == null) return ProgressVerdict.building;
  final quiet = daysSinceActive != null && daysSinceActive > 10;
  if (quiet || overall == ProgressDirection.declining) {
    return ProgressVerdict.slipping;
  }
  if (score < AnalyticsPolicy.onTrackPct) return ProgressVerdict.behind;
  final active = daysSinceActive == null || daysSinceActive <= 3;
  if (score >= 0.9 && active) return ProgressVerdict.excellent;
  if (overall == ProgressDirection.improving) return ProgressVerdict.improving;
  return ProgressVerdict.steady;
}

// ═══════════════════════════════════════════════════════════════════════════
// INSIGHTS — deterministic, evidence-backed, never generated
// ═══════════════════════════════════════════════════════════════════════════

/// What an insight is ABOUT. Drives the icon and accent only; the sentence is
/// built from the numbers, never from a template bank.
enum InsightKind { training, nutrition, lifestyle, body, streak, record }

/// How an insight reads. `neutral` exists because most true statements about a
/// member's month are neither a win nor a warning, and dressing them as either
/// is how a product starts lying.
enum InsightTone { positive, neutral, caution }

/// One deterministic observation.
///
/// EVERY field is derived from a number the engine already computed. There is
/// no language model, no template roulette, no "you're crushing it!". Given the
/// same inputs this returns the same sentences, forever — which is the only way
/// an insight can be trusted enough to act on.
class ProgressInsight {
  final InsightKind kind;
  final InsightTone tone;

  /// The claim, stated plainly. Contains the number it is about.
  final String headline;

  /// WHERE the claim comes from — the window, the sample, the source. An
  /// insight that cannot show its work is an opinion.
  final String basis;

  const ProgressInsight({
    required this.kind,
    required this.tone,
    required this.headline,
    required this.basis,
  });
}

String _pct(double v) => '${(v * 100).round()}%';

String _plural(int n, String one, [String? many]) =>
    n == 1 ? one : (many ?? '${one}s');

/// Builds the insight list from already-computed evidence.
///
/// Ordered by how much a member can act on it: a declining dimension first, an
/// improving one next, then records and streaks. Returns EMPTY when there is
/// nothing true to say — a screen with no insights is honest; a screen with
/// invented ones is not.
List<ProgressInsight> buildInsights({
  required List<ScoredDimension> dimensions,
  required int windowDays,
  required int currentStreak,
  required int longestStreak,
  required int streakWindowDays,
  List<({String exercise, double weight, DateTime at})> bests = const [],
  List<TrendPoint> weight = const [],
  ({String key, String name})? strengthExercise,
  List<TrendPoint> strength = const [],
}) {
  final out = <ProgressInsight>[];

  // 1 — DECLINING dimensions first. The thing worth doing something about.
  for (final d in dimensions) {
    if (d.direction != ProgressDirection.declining) continue;
    if (d.confidence == ProgressConfidence.none) continue;
    out.add(
      ProgressInsight(
        kind: _kindOf(d.id),
        tone: InsightTone.caution,
        headline: '${d.label} is trending down — ${_pct(d.value)} this period.',
        basis:
            'Compared with the previous $windowDays days · '
            '${d.sample} ${_plural(d.sample, "day")} recorded',
      ),
    );
  }

  // 2 — IMPROVING dimensions.
  for (final d in dimensions) {
    if (d.direction != ProgressDirection.improving) continue;
    if (d.confidence == ProgressConfidence.none) continue;
    out.add(
      ProgressInsight(
        kind: _kindOf(d.id),
        tone: InsightTone.positive,
        headline: '${d.label} is improving — ${_pct(d.value)} this period.',
        basis:
            'Compared with the previous $windowDays days · '
            '${d.sample} ${_plural(d.sample, "day")} recorded',
      ),
    );
  }

  // 3 — STRENGTH movement on the tracked lift.
  final strengthNet = netChange(strength);
  if (strengthExercise != null &&
      strengthNet != null &&
      strengthNet.abs() >= 0.5) {
    final up = strengthNet > 0;
    out.add(
      ProgressInsight(
        kind: InsightKind.record,
        tone: up ? InsightTone.positive : InsightTone.neutral,
        headline:
            '${strengthExercise.name} top set is '
            '${up ? "up" : "down"} ${strengthNet.abs().toStringAsFixed(1)} kg.',
        basis:
            'Heaviest working set per session · '
            '${strength.length} ${_plural(strength.length, "session")}',
      ),
    );
  }

  // 4 — A PERSONAL BEST, with the date it was set.
  if (bests.isNotEmpty) {
    final b = bests.first;
    out.add(
      ProgressInsight(
        kind: InsightKind.record,
        tone: InsightTone.positive,
        headline:
            'Heaviest logged set: ${b.weight.toStringAsFixed(1)} kg '
            'on ${b.exercise}.',
        basis: 'Set on ${_shortDate(b.at)} · within the loaded history',
      ),
    );
  }

  // 5 — STREAK. Current first, then the record if it is genuinely bettered.
  if (currentStreak >= 2) {
    out.add(
      ProgressInsight(
        kind: InsightKind.streak,
        tone: InsightTone.positive,
        headline:
            '$currentStreak-day training streak, and it is still running.',
        basis: 'Consecutive days with a logged session',
      ),
    );
  }
  if (longestStreak >= 2 && longestStreak > currentStreak) {
    out.add(
      ProgressInsight(
        kind: InsightKind.streak,
        tone: InsightTone.neutral,
        headline: 'Your best run so far is $longestStreak days.',
        // The window is stated because a streak this app cannot SEE is not a
        // streak it may claim you never had.
        basis: 'Longest in the last $streakWindowDays days',
      ),
    );
  }

  // 6 — WEIGHT movement, stated factually and never judged: this platform
  // stores no goal weight, so "good" is not ours to decide.
  final weightNet = netChange(weight);
  if (weightNet != null && weightNet.abs() >= AnalyticsPolicy.weightFlatBandKg) {
    out.add(
      ProgressInsight(
        kind: InsightKind.body,
        tone: InsightTone.neutral,
        headline:
            'Weight has moved ${weightNet > 0 ? "up" : "down"} '
            '${weightNet.abs().toStringAsFixed(1)} kg.',
        basis:
            '${_shortDate(weight.first.date)} → ${_shortDate(weight.last.date)} · '
            '${weight.length} check-${_plural(weight.length, "in")}',
      ),
    );
  }

  return out;
}

InsightKind _kindOf(String dimensionId) => switch (dimensionId) {
  'workout' => InsightKind.training,
  'nutrition' => InsightKind.nutrition,
  'lifestyle' => InsightKind.lifestyle,
  _ => InsightKind.training,
};

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `d MMM` without pulling `intl` into a file that must stay dependency-free
/// so both apps and a plain `dart test` can consume it identically.
String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';
