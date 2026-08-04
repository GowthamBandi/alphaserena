// ═══════════════════════════════════════════════════════════════════════════
// ALPHASERENA → SHARED ANALYTICS ADAPTERS
// ═══════════════════════════════════════════════════════════════════════════
//
// The ONLY place this app's models meet `progress_analytics.dart`. That file is
// twinned with TrainerHQ and must stay free of every app model; this file is
// AlphaSerena-only and is where the member app's `WorkoutDayLog` / `SetLog` /
// `TransformationEntry` / `RollupDay` shapes are translated.
//
// ⚠️ NOTHING HERE MAY COMPUTE A METRIC. Adapters translate; the shared core
// derives. If a number appears in this file that is not a direct field read or
// a documented parse, it belongs in the shared core instead — otherwise the two
// apps have started deriving separately again, which is the whole failure this
// module exists to prevent.

import '../domain/nutrition_history.dart';
import '../domain/workout_history.dart';
import '../domain/workout_session.dart';
import '../models/check_in_submission_model.dart';
import '../models/transformation_entry.dart';
import '../services/member_rollup_service.dart';
import '../services/nutrition_rollup_service.dart';
import 'progress_analytics.dart';

/// Numeric value of a prescription/actual string ("8-12" → 8, "40 kg" → 40).
///
/// PARITY: the identical rule as `workout_session.dart _numeric`, TrainerHQ
/// `client_workout_session_model.dart _num` and backend
/// `lib/progress.ts lowerBound` — first regex match, lower bound of a range.
/// Kept here (not in the shared core) because the raw strings are a MODEL
/// concern: the core receives numbers, so it can never disagree about parsing.
double? parseLogged(String s) {
  final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(s);
  return m == null ? null : double.tryParse(m.group(0)!);
}

// ── Training ────────────────────────────────────────────────────────────────

AnalyticsSet _set(SetLog s) => AnalyticsSet(
  prescribedReps: parseLogged(s.pReps),
  prescribedWeight: parseLogged(s.pWeight),
  actualReps: parseLogged(s.actualReps),
  actualWeight: parseLogged(s.actualWeight),
  completed: s.state == SetLogState.completed,
);

AnalyticsEntry _entry(ExerciseLog e) => AnalyticsEntry(
  exerciseId: e.exerciseId,
  exerciseName: e.name,
  sets: [for (final s in e.sets) _set(s)],
);

/// One saved session document → the neutral session shape.
AnalyticsSession analyticsSession(WorkoutDayLog log) => AnalyticsSession(
  date: log.date,
  entries: [for (final e in log.exercises) _entry(e)],
);

/// Raw `client_workout_sessions` documents → neutral sessions.
///
/// Documents that do not parse are DROPPED rather than defaulted: a session the
/// app cannot read is not a session it may guess at. `parseWorkoutDayLog`
/// already refuses a document with no usable date, which is what stops a
/// corrupt row from impersonating today and inflating a streak.
List<AnalyticsSession> analyticsSessions(
  Iterable<Map<String, dynamic>> docs, {
  String Function(Map<String, dynamic>)? idOf,
}) {
  final out = <AnalyticsSession>[];
  for (final doc in docs) {
    final id = idOf?.call(doc) ?? (doc['id'] ?? '').toString();
    final log = parseWorkoutDayLog(doc, id);
    if (log == null) continue;
    out.add(analyticsSession(log));
  }
  return out;
}

// ── Body ────────────────────────────────────────────────────────────────────

/// A published transformation checkpoint → a dated body observation.
///
/// Only COMPLETE entries with real content qualify. A private entry is
/// deliberately INCLUDED: this is the member's own screen, and hiding their own
/// data from them because they hid it from their coach would be a bug, not
/// privacy. (The coach's copy filters `!isPrivate` at its own read boundary.)
AnalyticsBodyPoint? analyticsBodyPoint(TransformationEntry e) {
  if (!e.isComplete || !e.hasContent) return null;
  return AnalyticsBodyPoint(
    date: e.recordedAt,
    weightKg: e.weightKg,
    measurements: e.measurements,
  );
}

List<AnalyticsBodyPoint> analyticsBodyPoints(
  Iterable<TransformationEntry> entries,
) => [for (final e in entries) ?analyticsBodyPoint(e)];

/// A submitted check-in packet → a dated body observation.
///
/// 🔴 THE DEFECT THIS CLOSES: a member who records their weight ONLY inside the
/// weekly check-in used to be told "Add at least two check-ins to see a trend"
/// on their own Progress screen, while their coach — whose app already
/// reconciled both sources — was looking at the trend. Check-ins carry no
/// measurements, so the map is empty by construction, not by omission.
List<AnalyticsBodyPoint> checkInBodyPoints(
  Iterable<CheckInSubmissionModel> checkIns,
) => [
  for (final c in checkIns)
    if (c.submittedAt != null && c.weightKg != null)
      AnalyticsBodyPoint(date: c.submittedAt!, weightKg: c.weightKg),
];

// ── Nutrition ───────────────────────────────────────────────────────────────

/// One day of the server-computed nutrition rollup → a 0..1 adherence ratio.
///
/// The value is the mean of the per-macro `computed.targetAdherence` the
/// BACKEND already calculated (`functions/src/lib/nutrition.ts
/// computeTargetAdherence`). Nothing is re-derived here — the trigger owns that
/// arithmetic and this reads its output, which is what keeps one number in one
/// place across a member's app, a coach's app and a Cloud Function.
///
/// A day with NO targets yields null and is skipped: an unset target must never
/// be scored as a miss. That is the same "do not penalize metrics without
/// targets" rule the lifestyle and check-in surfaces already apply.
AnalyticsRatio? nutritionRatio(NutritionRollupDay day) {
  final values = day.targetAdherence.values
      .map((v) => v.clamp(0.0, 1.0).toDouble())
      .toList();
  if (values.isEmpty) return null;
  return AnalyticsRatio(
    day.date,
    values.reduce((a, b) => a + b) / values.length,
  );
}

List<AnalyticsRatio> nutritionRatios(Iterable<NutritionRollupDay> days) => [
  for (final d in days) ?nutritionRatio(d),
];

/// Live food-log days (the same documents the rollup is derived from) → ratios.
///
/// Used ONLY for the current, still-settling month, whose rollup cell may not
/// have been written yet — the trigger runs on write, so today's day is
/// available locally before it is available as a rollup. Older months always
/// come from the rollup so the member and the coach read one number.
List<AnalyticsRatio> nutritionRatiosFromLogs(Iterable<NutritionDayLog> logs) {
  final out = <AnalyticsRatio>[];
  for (final l in logs) {
    final adherence = l.day.computed?.targetAdherence;
    if (adherence == null || adherence.isEmpty) continue;
    final values = adherence.values
        .map((v) => v.clamp(0.0, 1.0).toDouble())
        .toList();
    out.add(
      AnalyticsRatio(l.date, values.reduce((a, b) => a + b) / values.length),
    );
  }
  return out;
}

// ── Lifestyle ───────────────────────────────────────────────────────────────

/// The coach's lifestyle goals, read off the live `clients` document.
///
/// EVERY field is nullable and there are NO platform fallbacks here on purpose.
/// The Today screen may show a "suggested" default ring; an ADHERENCE SCORE may
/// not — scoring a member against a goal nobody set is exactly the fabricated
/// metric this platform keeps removing.
class LifestyleGoals {
  final double? waterMl;
  final double? steps;
  final double? sleepHours;
  final int? supplementCount;

  const LifestyleGoals({
    this.waterMl,
    this.steps,
    this.sleepHours,
    this.supplementCount,
  });

  bool get any =>
      waterMl != null ||
      steps != null ||
      sleepHours != null ||
      (supplementCount ?? 0) > 0;

  /// Parses `clients.lifestyleTargets` + `clients.supplementPlan`.
  factory LifestyleGoals.fromClient(Map<String, dynamic>? client) {
    double? n(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final raw = client?['lifestyleTargets'];
    final t = raw is Map ? Map<String, dynamic>.from(raw) : null;
    final stack = client?['supplementPlan'];
    return LifestyleGoals(
      waterMl: n(t?['waterTargetMl']),
      steps: n(t?['stepsTarget']),
      sleepHours: n(t?['sleepHoursTarget']),
      // The PRESCRIBED STACK SIZE, because the rollup value is a count of items
      // taken. A denominator of 1 would score "took any one supplement" as a
      // perfect day. The rollup carries only what was taken — the prescribed
      // snapshot is not in the read model — so the CURRENT stack is the
      // denominator, the same approximation TrainerHQ's `_prescribedFor` makes.
      supplementCount: stack is List && stack.isNotEmpty ? stack.length : null,
    );
  }
}

/// One rollup day → a 0..1 lifestyle adherence ratio.
///
/// The day's score is the share of GOALS THE COACH SET that the member met.
/// A habit with no goal is not in the denominator; a habit with a goal the
/// member did not log that day is a miss — which is the difference between this
/// and the per-habit `goalHitRate` on the History screen, whose denominator is
/// logged days because it answers "when you logged, did you hit it?".
///
/// Here the question is "how much of what your coach asked for did you do
/// today?", so a silent day is a day the ask was not met. Returns null when the
/// coach set NO goals — never 0%, which would read as total failure against
/// nothing.
AnalyticsRatio? lifestyleRatio(RollupDay day, LifestyleGoals goals) {
  var asked = 0;
  var met = 0;

  void score(double? target, double? value) {
    if (target == null || target <= 0) return;
    asked++;
    if (value != null && value >= target) met++;
  }

  score(goals.waterMl, day.waterMl);
  score(goals.steps, day.steps);
  score(goals.sleepHours, day.sleepHours);
  score(
    goals.supplementCount?.toDouble(),
    day.supplementItems?.toDouble(),
  );

  if (asked == 0) return null;
  return AnalyticsRatio(day.date, met / asked);
}

List<AnalyticsRatio> lifestyleRatios(
  Iterable<RollupDay> days,
  LifestyleGoals goals,
) => [for (final d in days) ?lifestyleRatio(d, goals)];
