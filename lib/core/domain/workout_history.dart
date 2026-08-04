/// WORKOUT HISTORY — the member's own training record, day by day.
///
/// Pure, I/O-free, and therefore fully unit-tested. Everything here is a
/// TRANSFORMATION of the two production sources; nothing here is a second
/// source:
///
///   • `client_workout_sessions` documents — the exact documents the member
///     app writes and TrainerHQ reads. [WorkoutDayLog] parses one with
///     `exercisesFromEntries`, the same parser the live session screen and
///     `StreakController` use, and every figure it states is computed by
///     `computeSessionStats`, the one completion authority.
///   • the served prescription (`performance.dart` / `prescription.dart`) —
///     which resolves what the COACH asked for on any past date, from the
///     version that was in force THEN.
///
/// **There is no history collection, no history mirror and no history model.**
/// A day the member trained is a session document; a day the coach prescribed
/// rest is a resolved expectation. If neither source says anything about a day,
/// this file says nothing about it either.
library;

import 'performance.dart' show MonthCell, MonthCellState;
import 'prescription.dart' show ExpectationKind;
import 'workout_session.dart';

/// One `client_workout_sessions` document, parsed.
///
/// Every field is READ from the document. There is no field here the member
/// app does not already write, which is what makes "history is the exact same
/// data TrainerHQ sees" a property of the type rather than a promise in a doc
/// comment.
class WorkoutDayLog {
  /// The document id — `ws_{clientId}_{yyyy-MM-dd}`, or a `_2` suffixed run.
  final String sessionId;

  /// The session's own `date`, at local midnight.
  final DateTime date;

  final String planName;
  final String planId;

  /// Exercise by exercise, set by set — parsed by [exercisesFromEntries], the
  /// SAME parser the live session uses, so a document can never render one way
  /// today and another way in history.
  final List<ExerciseLog> exercises;

  /// `'completed'` | `'inProgress'` | `''` (legacy). Never inferred.
  final String status;

  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// Recorded length. Null when the clock was never recorded — history then
  /// states no duration rather than a fabricated "0m".
  final int? durationSeconds;

  /// What the member chose to tell their coach at the end of this session.
  final String memberNote;

  WorkoutDayLog({
    required this.sessionId,
    required this.date,
    required this.exercises,
    this.planName = '',
    this.planId = '',
    this.status = '',
    this.startedAt,
    this.finishedAt,
    this.durationSeconds,
    this.memberNote = '',
  });

  /// The one completion authority, never a local re-derivation.
  SessionStats get stats => computeSessionStats(exercises);

  /// Local calendar day key, `yyyy-MM-dd` — the key every other surface in this
  /// app indexes days by.
  String get dayKey => _dayKey(date);

  /// The member finished this session deliberately (as opposed to walking away
  /// from it). Read from the wire, never guessed from the sets.
  bool get isFinished => status == kSessionCompleted;

  /// A session whose day has ENDED while it was still in progress. The coach's
  /// app derives exactly this and calls it abandoned; the member's app must not
  /// quietly present it as finished.
  bool wasAbandonedOn(DateTime today) {
    if (status != kSessionInProgress) return false;
    final t = DateTime(today.year, today.month, today.day);
    return DateTime(date.year, date.month, date.day).isBefore(t);
  }
}

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  // `Timestamp` without importing cloud_firestore into a pure domain file:
  // every Firestore timestamp exposes `toDate()`. A shape that does not is
  // simply unreadable, and unreadable is null — never "now", which would
  // stamp a fabricated date onto a member's history.
  try {
    final d = (v as dynamic).toDate();
    return d is DateTime ? d : null;
  } catch (_) {
    return null;
  }
}

int? _seconds(dynamic v) => v is num && v > 0 ? v.toInt() : null;

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Parses one session document. Null when it carries no readable `date` —
/// a day with no date cannot be placed on a calendar, and placing it anyway
/// (on "today", say) would invent a training day the member never had.
WorkoutDayLog? parseWorkoutDayLog(Map<String, dynamic> doc, String id) {
  final date = _date(doc['date']);
  if (date == null) return null;
  return WorkoutDayLog(
    sessionId: id,
    date: DateTime(date.year, date.month, date.day),
    planName: (doc['planName'] ?? '').toString(),
    planId: (doc['planId'] ?? '').toString(),
    exercises: exercisesFromEntries(doc['entries']),
    status: (doc['status'] ?? '').toString(),
    startedAt: _date(doc['startedAt']),
    finishedAt: _date(doc['finishedAt']),
    durationSeconds: _seconds(doc['durationSeconds']),
    memberNote: (doc['memberNote'] ?? '').toString().trim(),
  );
}

/// Session documents by day key, newest run winning a tie.
///
/// A deliberate second session on one day (`…_2`) is a real thing the session
/// screen can create. The calendar has one cell per day, so it shows the run
/// with the most completed work — never a silently-picked arbitrary one, and
/// never two cells for one date.
Map<String, WorkoutDayLog> indexWorkoutLogs(Iterable<WorkoutDayLog> logs) {
  final out = <String, WorkoutDayLog>{};
  for (final log in logs) {
    final existing = out[log.dayKey];
    if (existing == null ||
        log.stats.completedSets > existing.stats.completedSets) {
      out[log.dayKey] = log;
    }
  }
  return out;
}

/// What one day of a member's training record actually says.
///
/// The first three come from the member's OWN log; the rest come from the
/// coach's prescription. Nothing is inferred from the other direction: a day
/// with no session and no prescription is [unknown], not "rest".
enum WorkoutDayState {
  /// Every prescribed set completed.
  completed,

  /// A session exists and some sets were completed, but not all.
  partial,

  /// A session exists and NOT ONE set was completed — the member opened the
  /// workout and skipped through it. Their coach can still read it, and it is
  /// emphatically not the same as never showing up.
  skipped,

  /// The coach asked for work, the day ended, nothing was logged.
  missed,

  /// The coach prescribed no work that day. The absence of an ask, not a
  /// failure — the reason this is a first-class state and not a blank.
  rest,

  /// Coaching was suspended (medical leave, travel, a pause).
  paused,

  /// The coach cancelled this specific day after the fact.
  excused,

  /// Today, still open.
  today,

  /// Not yet.
  future,

  /// NO PRESCRIPTION EXISTS for that date and nothing was logged. The honest
  /// answer for most members on most days, and it must read as "nothing
  /// recorded", never as rest and never as a miss.
  unknown,
}

/// One day of the history calendar.
class WorkoutHistoryDay {
  final DateTime date;
  final WorkoutDayState state;

  /// The session document for that day, when one exists. This is what the day
  /// sheet renders — the log itself, not a summary of it.
  final WorkoutDayLog? log;

  /// What the coach asked for, carried through so the day sheet can say
  /// "rest day" versus "no plan" without re-resolving the verdict and risking
  /// a second, divergent answer.
  final ExpectationKind expectation;

  const WorkoutHistoryDay({
    required this.date,
    required this.state,
    this.log,
    this.expectation = ExpectationKind.unknown,
  });

  bool get hasLog => log != null;

  /// Whether the day is worth opening. A day with no session and no coach note
  /// has nothing behind it, and a cell that opens an empty sheet is worse than
  /// one that does not respond.
  bool get isOpenable => hasLog;
}

/// Composes the coach's prescription with the member's logs into one month.
///
/// [cells] MUST come from `monthCells(...)` — the production prescription
/// engine — so rest, pause, excused and missed are the coach's authored
/// answers resolved against the version in force on each date, not a weekday
/// pattern applied backwards over history.
///
/// **THE LOG WINS, and refines.** `monthCells` knows only whether a day is in
/// the logged-day SET, and that set (`sessionCountsAsTrainingDay`) deliberately
/// excludes a session containing no completed work. So a day the member opened
/// and skipped through reaches this function as `missed` — which is wrong in
/// the way that matters: they showed up. Holding the actual document here lets
/// the calendar separate "skipped" from "never opened", which is the whole
/// distinction the mission asks the four states to draw.
List<WorkoutHistoryDay> composeHistoryMonth({
  required List<MonthCell> cells,
  required Map<String, WorkoutDayLog> logsByDay,
}) {
  return [
    for (final cell in cells)
      _dayFor(cell, logsByDay[_dayKey(cell.date)]),
  ];
}

WorkoutHistoryDay _dayFor(MonthCell cell, WorkoutDayLog? log) {
  if (log != null) {
    final stats = log.stats;
    final state = stats.isComplete
        ? WorkoutDayState.completed
        : stats.completedSets > 0
            ? WorkoutDayState.partial
            : WorkoutDayState.skipped;
    return WorkoutHistoryDay(
      date: cell.date,
      state: state,
      log: log,
      expectation: cell.expectation,
    );
  }
  return WorkoutHistoryDay(
    date: cell.date,
    state: switch (cell.state) {
      MonthCellState.done => WorkoutDayState.completed,
      MonthCellState.missed => WorkoutDayState.missed,
      MonthCellState.rest => WorkoutDayState.rest,
      MonthCellState.paused => WorkoutDayState.paused,
      MonthCellState.excused => WorkoutDayState.excused,
      MonthCellState.today => WorkoutDayState.today,
      MonthCellState.future => WorkoutDayState.future,
      MonthCellState.unknown => WorkoutDayState.unknown,
    },
    expectation: cell.expectation,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// CALORIES — a MODEL, and labelled as one everywhere it is shown
// ═══════════════════════════════════════════════════════════════════════════

/// Metabolic equivalent for resistance training at a moderate effort — the
/// Compendium of Physical Activities' value for "resistance training, multiple
/// exercises, 8-15 reps".
///
/// A MODELLING CONSTANT, exactly like [kAssumedWorkSecondsPerSet], and it
/// carries the same obligation: nothing derived from it may ever be presented
/// as a measurement. Nobody counted these calories — not the member, not the
/// coach, and not a sensor. Every surface that renders the result labels it.
const double kResistanceTrainingMet = 5.0;

/// The longest session length the calorie MODEL will accept as an input.
///
/// ── WHY A CLAMP IS NECESSARY ──────────────────────────────────────────────
///
/// `durationSeconds` is wall clock — `finishedAt - startedAt`, with no pause
/// concept anywhere in the session screens. A member who starts at 09:00, is
/// interrupted, and finishes the same session at 18:00 has a session document
/// honestly recording nine elapsed hours. That is a true statement about the
/// clock and a false one about training, and [estimatedWorkoutCalories] is
/// LINEAR in it: forty minutes of real work reported as nine hours turned
/// 245 kcal into 3308 kcal, a figure the member can personally disprove.
///
/// ── WHY THE CLAMP LIVES HERE AND NOWHERE ELSE ─────────────────────────────
///
/// The recorded duration is a FACT and is left alone — Duration still states
/// the elapsed time, here and in TrainerHQ, because that is what was measured.
/// What is clamped is a MODEL INPUT, and bounding a model input to the range
/// the model is valid over is not falsifying data: the MET formula describes
/// continuous resistance training, and no such bout runs for nine hours. Above
/// this bound the model has nothing to say, so it says the most it honestly
/// can rather than extrapolating.
///
/// Three hours is deliberately generous — long enough that no real session is
/// ever clamped, short enough that an abandoned clock cannot inflate the
/// figure by an order of magnitude.
const int kMaxModelledSessionSeconds = 3 * 60 * 60;

/// Energy expenditure over a recorded session, or **null**.
///
/// Null when either input is missing, and that is the point: this app does not
/// own a body-weight guess and must never invent one. A member who has never
/// entered their weight sees no calorie figure at all, which is the truth —
/// far better than a number computed from an assumed 70 kg stranger.
///
/// The standard MET formula: kcal/min = MET × 3.5 × kg ÷ 200, over a duration
/// bounded by [kMaxModelledSessionSeconds].
double? estimatedWorkoutCalories({
  required int? durationSeconds,
  required double? bodyWeightKg,
}) {
  if (durationSeconds == null || durationSeconds <= 0) return null;
  if (bodyWeightKg == null || bodyWeightKg <= 0) return null;
  final bounded = durationSeconds > kMaxModelledSessionSeconds
      ? kMaxModelledSessionSeconds
      : durationSeconds;
  final minutes = bounded / 60.0;
  return kResistanceTrainingMet * 3.5 * bodyWeightKg / 200.0 * minutes;
}
