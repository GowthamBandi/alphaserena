/// WORKOUT EXPERIENCE — Phase 1: session integrity, the pure core.
///
/// The rules that make a workout session truthful, resumable and impossible
/// to corrupt, with no I/O so every one of them is unit-tested:
///
///  • A session EXISTS only from its first meaningful act — a completed or
///    skipped set. Opening the screen is browsing; typing is intent. Neither
///    is a workout, so neither may create one (ghost sessions were inflating
///    every coach metric).
///  • Identity is DETERMINISTIC: `ws_{clientId}_{yyyy-MM-dd}` — the same
///    day resumes the same document; a second same-day session is a
///    deliberate, suffixed act, never an accident of navigation.
///  • Skipped ≠ incomplete ≠ abandoned ≠ cancelled: a skipped set/exercise
///    is an explicit, reasoned state on the wire; abandoned is DERIVED
///    (in-progress after its day ended); cancelled never produced a doc.
library;

const String kSessionInProgress = 'inProgress';
const String kSessionCompleted = 'completed';

/// Why a member skipped — the coach's next conversation, not a judgement.
const List<String> kSkipReasons = [
  'No equipment',
  'Pain / discomfort',
  'Out of time',
  'Too fatigued',
  'Other',
];

/// Deterministic session identity. [run] > 1 marks a deliberate extra
/// session on the same day (`ws_c1_2026-07-28_2`) — never minted implicitly.
String workoutSessionIdFor(String clientId, DateTime day, {int run = 1}) {
  final key = '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
  return run <= 1 ? 'ws_${clientId}_$key' : 'ws_${clientId}_${key}_$run';
}

enum SetLogState { pending, completed, skipped }

/// One set's full story: what the coach prescribed, what the member did.
class SetLog {
  final String pReps;
  final String pWeight;
  final String pRest;
  String actualReps;
  String actualWeight;
  SetLogState state;

  /// The member corrected this set after first completing it. Surfaced to the
  /// coach: a corrected number is honest, but the coach should know it was
  /// revised rather than logged live.
  bool edited;

  SetLog({
    required this.pReps,
    required this.pWeight,
    required this.pRest,
    this.actualReps = '',
    this.actualWeight = '',
    this.state = SetLogState.pending,
    this.edited = false,
  });

  Map<String, dynamic> toJson() => {
    'pReps': pReps,
    'pWeight': pWeight,
    'pRest': pRest,
    'actualReps': actualReps,
    'actualWeight': actualWeight,
    'state': state.name,
    'edited': edited,
  };

  static SetLog fromJson(Map<String, dynamic> m) => SetLog(
    pReps: (m['pReps'] ?? '').toString(),
    pWeight: (m['pWeight'] ?? '').toString(),
    pRest: (m['pRest'] ?? '').toString(),
    actualReps: (m['actualReps'] ?? '').toString(),
    actualWeight: (m['actualWeight'] ?? '').toString(),
    state: SetLogState.values.firstWhere(
      (s) => s.name == m['state'],
      orElse: () => SetLogState.pending,
    ),
    edited: m['edited'] == true,
  );
}

class ExerciseLog {
  final String name;
  final String exerciseId;
  final List<SetLog> sets;
  bool skipped;
  String skipReason;

  ExerciseLog({
    required this.name,
    required this.exerciseId,
    required this.sets,
    this.skipped = false,
    this.skipReason = '',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'exerciseId': exerciseId,
    'sets': sets.map((s) => s.toJson()).toList(),
    'skipped': skipped,
    'skipReason': skipReason,
  };

  static ExerciseLog fromJson(Map<String, dynamic> m) => ExerciseLog(
    name: (m['name'] ?? '').toString(),
    exerciseId: (m['exerciseId'] ?? '').toString(),
    sets: ((m['sets'] as List?) ?? const [])
        .whereType<Map>()
        .map((s) => SetLog.fromJson(Map<String, dynamic>.from(s)))
        .toList(),
    skipped: m['skipped'] == true,
    skipReason: (m['skipReason'] ?? '').toString(),
  );
}

/// The locally-persisted in-progress session — everything needed to resume
/// EXACTLY where the member stopped, surviving process death, restarts and
/// navigation. The remote doc is the published truth; this is the workbench.
class WorkoutDraft {
  final String sessionId;
  final String dayKey;
  final String planName;
  final int? startedAtMillis;
  final int currentExercise;
  final List<ExerciseLog> exercises;

  const WorkoutDraft({
    required this.sessionId,
    required this.dayKey,
    required this.planName,
    required this.exercises,
    this.startedAtMillis,
    this.currentExercise = 0,
  });

  Map<String, dynamic> toJson() => {
    'v': 1,
    'sessionId': sessionId,
    'dayKey': dayKey,
    'planName': planName,
    if (startedAtMillis != null) 'startedAtMillis': startedAtMillis,
    'currentExercise': currentExercise,
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };

  /// Null on junk — a corrupt draft must never corrupt a session.
  static WorkoutDraft? fromJson(dynamic m) {
    if (m is! Map) return null;
    final sessionId = (m['sessionId'] ?? '').toString();
    final dayKey = (m['dayKey'] ?? '').toString();
    if (sessionId.isEmpty || dayKey.isEmpty) return null;
    return WorkoutDraft(
      sessionId: sessionId,
      dayKey: dayKey,
      planName: (m['planName'] ?? '').toString(),
      startedAtMillis: m['startedAtMillis'] is num
          ? (m['startedAtMillis'] as num).toInt()
          : null,
      currentExercise: m['currentExercise'] is num
          ? (m['currentExercise'] as num).toInt()
          : 0,
      exercises: ((m['exercises'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => ExerciseLog.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// THE creation gate: a session is real only once something HAPPENED.
bool hasMeaningfulActivity(List<ExerciseLog> exercises) => exercises.any(
  (e) =>
      e.skipped ||
      e.sets.any((s) => s.state != SetLogState.pending),
);

/// Whether any work was actually DONE (drives streaks — a session that is
/// only skips marks presence for the coach but never a training day).
bool hasCompletedWork(List<ExerciseLog> exercises) =>
    exercises.any((e) => e.sets.any((s) => s.state == SetLogState.completed));

/// Whether a RAW `client_workout_sessions` document counts as a TRAINING DAY
/// for streaks, the week rail and the calendar.
///
/// THE ONE RULE, applied in both directions. The live path already used
/// [hasCompletedWork] — `StreakController.markWorkoutToday` is called only
/// when a set was genuinely completed. The REPOSITORY re-read did not: it
/// counted any document that carried a `date`, and a session is written the
/// moment ANY set is touched, including a skip. So a member who opened a
/// workout and skipped through it saw no streak change — until they restarted
/// the app, at which point the same day joined the streak, moved the week
/// rail and filled a calendar cell. One fact, two answers, decided by whether
/// the process had been killed.
///
/// LEGACY SAFETY: a document whose `entries` this parser cannot read keeps
/// counting. This predicate may only ever REMOVE a day it can positively prove
/// contains zero completed sets — silently erasing a member's history on a
/// shape we failed to parse would be a far worse bug than the one it fixes.
bool sessionCountsAsTrainingDay(Map<String, dynamic>? doc) {
  if (doc == null) return false;
  final logs = exercisesFromEntries(doc['entries']);
  if (logs.isEmpty) return true; // unreadable / legacy — presence stands
  return hasCompletedWork(logs);
}

/// The wire entries for `client_workout_sessions` — additive over the legacy
/// shape (old coach builds ignore the new keys; new builds render them).
List<Map<String, dynamic>> buildSessionEntries(List<ExerciseLog> exercises) {
  return exercises
      .map(
        (ex) => <String, dynamic>{
          'exerciseName': ex.name,
          if (ex.exerciseId.isNotEmpty) 'exerciseId': ex.exerciseId,
          if (ex.skipped) 'skipped': true,
          if (ex.skipped && ex.skipReason.isNotEmpty)
            'skipReason': ex.skipReason,
          'sets': List.generate(ex.sets.length, (i) {
            final s = ex.sets[i];
            return {
              'setNumber': i + 1,
              'prescribedReps': s.pReps,
              'prescribedWeight': s.pWeight,
              'prescribedRest': s.pRest,
              'actualReps': s.actualReps.trim(),
              'actualWeight': s.actualWeight.trim(),
              'completed': s.state == SetLogState.completed,
              if (s.state == SetLogState.skipped) 'skipped': true,
              if (s.edited) 'edited': true,
            };
          }),
        },
      )
      .toList();
}

/// Builds fresh logs from the SERVED plan items (`getMyTraining`). One
/// implementation, shared by the briefing and the session, so the two can
/// never disagree about what today's workout contains.
///
/// Legacy/flat plans (no `setRows`) synthesize N identical sets from the
/// summary — the shape the builder dual-writes for older documents.
List<ExerciseLog> exercisesFromServedItems(List<Map<String, dynamic>> items) {
  return items.map((ex) {
    final rows = (ex['setRows'] as List?) ?? const [];
    final sets = <SetLog>[];
    if (rows.isNotEmpty) {
      for (final r in rows.whereType<Map>()) {
        final m = Map<String, dynamic>.from(r);
        sets.add(SetLog(
          pReps: (m['reps'] ?? '').toString(),
          pWeight: (m['weight'] ?? '').toString(),
          pRest: (m['rest'] ?? '').toString(),
        ));
      }
    } else {
      final count = (ex['sets'] is num)
          ? (ex['sets'] as num).toInt()
          : int.tryParse('${ex['sets']}') ?? 0;
      final reps = (ex['reps'] ?? '').toString();
      final weight = (ex['weight'] ?? '').toString();
      final n = count > 0 ? count : (reps.isNotEmpty ? 1 : 0);
      for (var i = 0; i < n; i++) {
        sets.add(SetLog(pReps: reps, pWeight: weight, pRest: ''));
      }
    }
    return ExerciseLog(
      name: ex['name']?.toString() ?? 'Exercise',
      exerciseId: (ex['exerciseId'] ?? '').toString(),
      sets: sets,
    );
  }).toList();
}

/// Rebuilds resumable logs from a previously-saved REMOTE doc (crash without
/// a draft, or a same-day return). Prescription fields come back from the
/// wire so the session renders exactly as it did.
List<ExerciseLog> exercisesFromEntries(dynamic entries) {
  if (entries is! List) return const [];
  return entries.whereType<Map>().map((raw) {
    final m = Map<String, dynamic>.from(raw);
    final sets = ((m['sets'] as List?) ?? const []).whereType<Map>().map((s) {
      final sm = Map<String, dynamic>.from(s);
      return SetLog(
        pReps: (sm['prescribedReps'] ?? '').toString(),
        pWeight: (sm['prescribedWeight'] ?? '').toString(),
        pRest: (sm['prescribedRest'] ?? '').toString(),
        actualReps: (sm['actualReps'] ?? '').toString(),
        actualWeight: (sm['actualWeight'] ?? '').toString(),
        state: sm['skipped'] == true
            ? SetLogState.skipped
            : sm['completed'] == true
                ? SetLogState.completed
                : SetLogState.pending,
        edited: sm['edited'] == true,
      );
    }).toList();
    return ExerciseLog(
      name: (m['exerciseName'] ?? 'Exercise').toString(),
      exerciseId: (m['exerciseId'] ?? '').toString(),
      sets: sets,
      skipped: m['skipped'] == true,
      skipReason: (m['skipReason'] ?? '').toString(),
    );
  }).toList();
}

/// Whole seconds from start to finish; null when either end is missing.
/// Clamped at zero — clock skew must never produce a negative workout.
int? sessionDurationSeconds(int? startedAtMillis, int? finishedAtMillis) {
  if (startedAtMillis == null || finishedAtMillis == null) return null;
  final s = ((finishedAtMillis - startedAtMillis) / 1000).round();
  return s < 0 ? 0 : s;
}

// ═══════════════════════════════════════════════════════════════════════════
// SESSION STATS — the summary's numbers, computed exactly as the COACH's app
// computes them, so the two can never show different figures for one session.
// ═══════════════════════════════════════════════════════════════════════════

double? _numeric(String s) {
  final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(s);
  return m == null ? null : double.tryParse(m.group(0)!);
}

/// PARITY: byte-for-byte the rule in TrainerHQ's `SessionSet.hit` — a
/// dimension with no numeric target is skipped; a set with no numeric targets
/// at all counts as a hit (there was nothing to miss).
bool setHitTarget(SetLog s) {
  final repsTarget = _numeric(s.pReps);
  final weightTarget = _numeric(s.pWeight);
  final aReps = _numeric(s.actualReps);
  final aWeight = _numeric(s.actualWeight);
  final repsOk = repsTarget == null || (aReps != null && aReps >= repsTarget);
  final weightOk =
      weightTarget == null || (aWeight != null && aWeight >= weightTarget);
  return repsOk && weightOk;
}

/// Everything the completion screen states — each figure derived from logged
/// facts only, never estimated.
class SessionStats {
  final int completedSets;
  final int skippedSets;
  final int totalSets;
  final int skippedExercises;

  /// Exercises where EVERY prescribed set was completed. An exercise carrying
  /// even one skipped or pending set is not finished, so it is not counted —
  /// the completion screen's "3 of 5 exercises" must mean the same thing the
  /// member would mean by it.
  ///
  /// Lives here rather than in a caller because this class is the single
  /// completion authority; a second place computing "exercises done" is
  /// exactly how two surfaces start disagreeing.
  final int completedExercises;

  /// Σ (reps × weight) over completed sets where BOTH are numeric — the same
  /// definition as the coach app's `totalVolume`. Zero for bodyweight-only
  /// work, which is honest: volume is a load metric, not an effort score.
  final double volumeKg;

  /// Share of COMPLETED sets that met their target, or null when nothing was
  /// completed (nothing to judge).
  final double? targetHitPct;

  const SessionStats({
    required this.completedSets,
    required this.skippedSets,
    required this.totalSets,
    required this.skippedExercises,
    required this.volumeKg,
    required this.targetHitPct,
    this.completedExercises = 0,
  });

  bool get hasVolume => volumeKg > 0;

  // ── TRUTHFUL COMPLETION — the engine decides, not the UI ────────────────
  //
  // "One completed set → Logged today ✓" was the previous member-facing story:
  // presence-based, binary, and generous. Presence is the right question for
  // STREAKS (did the member show up), but it is the wrong answer for "is
  // today's workout done" — a member who finished 1 of 18 sets read exactly
  // like one who finished 18 of 18. These getters are the single completion
  // authority; every surface renders them rather than inventing its own rule.

  /// Progress through the prescribed session, 0..1 — completed ÷ prescribed.
  /// SKIPPED SETS COUNT AGAINST: a skip is honest and first-class, but it is
  /// not done work, and a 100% that includes skips would be a lie.
  double get progressFraction =>
      totalSets == 0 ? 0 : completedSets / totalSets;

  /// [progressFraction] as a whole percent, floored — 17/18 sets reads 94,
  /// never a rounded-up 100: "100%" is reserved for actually finishing.
  int get progressPercent => (progressFraction * 100).floor();

  /// Every set resolved — done or explicitly skipped, nothing pending. This is
  /// "the session is over", distinct from "everything was done".
  bool get isFullyResolved =>
      totalSets > 0 && completedSets + skippedSets == totalSets;

  /// TRUE completion: every prescribed set completed. No skips, no pendings.
  bool get isComplete => totalSets > 0 && completedSets == totalSets;
}

SessionStats computeSessionStats(List<ExerciseLog> exercises) {
  var completed = 0;
  var skipped = 0;
  var total = 0;
  var hits = 0;
  var volume = 0.0;
  var completedExercises = 0;
  for (final ex in exercises) {
    if (!ex.skipped &&
        ex.sets.isNotEmpty &&
        ex.sets.every((s) => s.state == SetLogState.completed)) {
      completedExercises++;
    }
    for (final s in ex.sets) {
      total++;
      if (s.state == SetLogState.skipped) skipped++;
      if (s.state != SetLogState.completed) continue;
      completed++;
      if (setHitTarget(s)) hits++;
      final r = _numeric(s.actualReps);
      final w = _numeric(s.actualWeight);
      if (r != null && w != null) volume += r * w;
    }
  }
  return SessionStats(
    completedSets: completed,
    skippedSets: skipped,
    totalSets: total,
    skippedExercises: exercises.where((e) => e.skipped).length,
    completedExercises: completedExercises,
    volumeKg: volume,
    targetHitPct: completed == 0 ? null : hits / completed,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// NEXT UP — "where do I continue?", the one thing a returning member needs
// ═══════════════════════════════════════════════════════════════════════════

/// The exact point a half-finished session resumes at.
///
/// [SessionStats] answers HOW MUCH is done; this answers WHERE. Home shows
/// both, because "42% done" tells a member they are behind and nothing about
/// what to do about it — the single most useful sentence the app can offer
/// someone who put the phone down mid-workout is "Bench Press, set 2 of 4".
class NextUp {
  final String exerciseName;

  /// Position in the session's exercise list — lets a caller jump straight
  /// there without re-deriving it.
  final int exerciseIndex;

  /// 1-based, counting EVERY prescribed set (a skipped set still occupies its
  /// number — the member should see "set 3 of 4", not a renumbered "set 2").
  final int setNumber;
  final int totalSets;

  /// The coach's own words, verbatim — '8-12', 'bodyweight', '60s'. Never
  /// parsed, never normalised into a number nobody wrote.
  final String prescribedReps;
  final String prescribedWeight;

  const NextUp({
    required this.exerciseName,
    required this.exerciseIndex,
    required this.setNumber,
    required this.totalSets,
    this.prescribedReps = '',
    this.prescribedWeight = '',
  });

  /// "12 reps × 60 kg" — the same vocabulary the session screen uses, so the
  /// member reads one phrasing across both surfaces. A dimension the coach
  /// left blank is simply absent; nothing is invented to fill the line, and a
  /// weight that already carries its unit is not suffixed twice.
  String get targetLine {
    final w = prescribedWeight.trim();
    final hasUnit = w.isEmpty ||
        RegExp(r'[a-zA-Z]').hasMatch(w); // 'bodyweight', '60 kg', '135 lbs'
    return [
      if (prescribedReps.trim().isNotEmpty) '${prescribedReps.trim()} reps',
      if (w.isNotEmpty) hasUnit ? w : '$w kg',
    ].join(' × ');
  }
}

/// The first unresolved set in the session, or null when nothing is left.
///
/// Resolved means completed OR skipped: a skip is a first-class, deliberate
/// answer, so re-offering it would ignore what the member already said. A
/// skipped EXERCISE is stepped over whole for the same reason.
NextUp? nextUpFrom(List<ExerciseLog> exercises) {
  for (var i = 0; i < exercises.length; i++) {
    final ex = exercises[i];
    if (ex.skipped) continue;
    for (var j = 0; j < ex.sets.length; j++) {
      if (ex.sets[j].state != SetLogState.pending) continue;
      return NextUp(
        exerciseName: ex.name,
        exerciseIndex: i,
        setNumber: j + 1,
        totalSets: ex.sets.length,
        prescribedReps: ex.sets[j].pReps,
        prescribedWeight: ex.sets[j].pWeight,
      );
    }
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════════
// BRIEFING — the estimate, and the honesty rules around it
// ═══════════════════════════════════════════════════════════════════════════

/// Seconds assumed for performing one set. A modelling constant, NOT a
/// coach's word and NOT member data — which is exactly why every surface
/// that shows the result must label it with "≈".
const int kAssumedWorkSecondsPerSet = 45;

int _restSecondsOf(String rest) {
  final m = RegExp(r'\d+').firstMatch(rest);
  return m == null ? 0 : int.parse(m.group(0)!);
}

/// A transparent duration estimate: prescribed rests + an assumed work time
/// per set, rounded to the nearest 5 minutes. Null when there is nothing to
/// estimate from. Never presented without the "≈" that makes it a guess.
int? estimatedMinutes(List<ExerciseLog> exercises) {
  var seconds = 0;
  var sets = 0;
  for (final ex in exercises) {
    if (ex.skipped) continue;
    for (final s in ex.sets) {
      sets++;
      seconds += kAssumedWorkSecondsPerSet + _restSecondsOf(s.pRest);
    }
  }
  if (sets == 0) return null;
  final mins = (seconds / 60).round();
  if (mins <= 5) return 5;
  return (mins / 5).round() * 5;
}

/// Distinct, order-preserving values (muscle groups, equipment) with blanks
/// dropped — the briefing shows what the library actually knows, nothing more.
List<String> distinctLabels(Iterable<String> values) {
  final seen = <String>{};
  final out = <String>[];
  for (final v in values) {
    final t = v.trim();
    if (t.isEmpty) continue;
    final key = t.toLowerCase();
    if (seen.add(key)) out.add(t);
  }
  return out;
}
