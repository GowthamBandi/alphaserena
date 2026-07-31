/// TODAY'S WORKOUT — the execution card.
///
/// This card is not a report and not a brochure. It exists to get a member
/// from "phone in hand" to "first set" in one tap, and — when they come back
/// mid-session — to tell them the one thing that restarts momentum: which
/// exercise, which set.
///
/// ── WHAT IT IS NOT ─────────────────────────────────────────────────────────
///  • Not an artwork banner. A photo is atmosphere; atmosphere belongs INSIDE
///    the workout experience, where the member has already committed. On Home
///    it costs 138px of the most valuable space in the app and answers no
///    question. Removed.
///  • Not a video surface. Home is for deciding; the player is for studying.
///  • Not a completion report. Once a session is done the card collapses to
///    the four facts worth stating and two ways back in.
///
/// ── PROGRESS ───────────────────────────────────────────────────────────────
/// Every percentage on this card comes from [SessionStats] and nowhere else.
/// There is no second calculation in this file, in the widget, or on Home.
/// 2 of 9 sets is 22%. One finished exercise out of three is 33%, not "done".
/// "Logged today" does not exist here — presence is the streak's question, not
/// this card's.
library;

import 'today_expectation.dart';
import 'workout_session.dart';

/// The card's one visual variant.
enum WorkoutCardMode {
  /// Sources still in flight.
  loading,

  /// Prescribed and untouched — one button: START WORKOUT.
  ready,

  /// Part-done — percentage, next exercise, next set, RESUME.
  inProgress,

  /// Every prescribed set completed — the facts, then REVIEW / EDIT LOG.
  completed,

  /// Resolved by skipping rather than finishing. Over, but not complete.
  closed,

  /// A flexible week: the member picks the days.
  flexible,

  /// Prescribed rest — a positive state, not an empty card.
  rest,

  /// The coach excused today specifically.
  excused,

  /// Coaching paused at any level.
  paused,

  /// A prescription exists but hasn't started, or has ended.
  dormant,

  /// Nothing assigned at all.
  waiting,

  /// The plan could not be loaded and none is cached.
  unavailable,
}

/// One fact chip. Chips are built from real library data only — an absent
/// chip means absent data, which is information in itself.
class WorkoutFact {
  /// 'exercises' | 'duration' | 'difficulty' | 'equipment'
  final String kind;
  final String label;

  const WorkoutFact(this.kind, this.label);
}

/// One stated figure on a finished session.
class WorkoutResult {
  final String label;
  final String value;

  const WorkoutResult(this.label, this.value);
}

class HomeWorkoutCard {
  final WorkoutCardMode mode;

  /// The plan's own name. '' when there is no plan to name.
  final String title;

  /// One line under the title. Never a label the title already implies.
  final String subtitle;

  /// The coach's words for today, VERBATIM. '' when they wrote none.
  final String coachNote;

  final List<WorkoutFact> facts;

  /// 0..100, from [SessionStats] only. Null → no bar at all; a 0% bar reads
  /// as failure before the member has done anything.
  final int? progressPercent;

  /// Where to continue. Non-null only in [WorkoutCardMode.inProgress].
  final NextUp? nextUp;

  /// The finished session's stated facts — duration, exercises, sets,
  /// adherence. Empty in every other mode.
  final List<WorkoutResult> results;

  /// Primary button label. '' → no button.
  final String cta;

  /// Secondary action ('Train anyway' on a rest day, 'Edit Workout Log' on a
  /// finished one). '' hides it.
  final String secondaryCta;

  /// The `unknown`-schedule disclosure. '' hides it.
  final String disclosure;

  const HomeWorkoutCard({
    required this.mode,
    this.title = '',
    this.subtitle = '',
    this.coachNote = '',
    this.facts = const [],
    this.progressPercent,
    this.nextUp,
    this.results = const [],
    this.cta = '',
    this.secondaryCta = '',
    this.disclosure = '',
  });

  /// Whether the card is an EXECUTION surface (plan facts + an action) rather
  /// than a state panel.
  bool get showsContent =>
      mode == WorkoutCardMode.ready ||
      mode == WorkoutCardMode.inProgress ||
      mode == WorkoutCardMode.flexible ||
      mode == WorkoutCardMode.completed ||
      mode == WorkoutCardMode.closed;

  bool get isFinished =>
      mode == WorkoutCardMode.completed || mode == WorkoutCardMode.closed;

  bool get hasProgress => (progressPercent ?? 0) > 0;

  double get progressFraction => ((progressPercent ?? 0) / 100).clamp(0.0, 1.0);

  String get semanticLabel => [
    if (title.isNotEmpty) title,
    if (subtitle.isNotEmpty) subtitle,
    if (hasProgress) '$progressPercent percent complete',
    if (nextUp != null)
      'Next exercise ${nextUp!.exerciseName}, set ${nextUp!.setNumber} of '
          '${nextUp!.totalSets}'
          '${nextUp!.targetLine.isEmpty ? '' : ', ${nextUp!.targetLine}'}',
    for (final r in results) '${r.label} ${r.value}',
    for (final f in facts) f.label,
    if (coachNote.isNotEmpty) 'Note from your coach: $coachNote',
    if (disclosure.isNotEmpty) disclosure,
  ].join('. ');
}

/// Fact chips, built only from data that exists.
List<WorkoutFact> workoutFacts({
  required int exerciseCount,
  required int? estimatedMinutes,
  required List<String> difficulty,
  required List<String> equipment,
}) => [
  if (exerciseCount > 0)
    WorkoutFact(
      'exercises',
      exerciseCount == 1 ? '1 exercise' : '$exerciseCount exercises',
    ),
  // The estimate always wears its "≈" — it is prescribed rests plus a
  // modelling constant, not a measurement.
  if (estimatedMinutes != null)
    WorkoutFact('duration', '≈$estimatedMinutes min'),
  if (difficulty.isNotEmpty) WorkoutFact('difficulty', difficulty.join(' · ')),
  if (equipment.isNotEmpty)
    WorkoutFact(
      'equipment',
      equipment.length <= 2
          ? equipment.join(' · ')
          : '${equipment.take(2).join(' · ')} +${equipment.length - 2}',
    ),
];

/// A finished session's stated figures. Each appears only if it is real:
/// a session with no recorded clock states no duration rather than "0:00",
/// and adherence is absent when nothing was completed (nothing to judge).
List<WorkoutResult> workoutResults({
  required SessionStats stats,
  required int? durationSeconds,
}) {
  final out = <WorkoutResult>[];
  if (durationSeconds != null && durationSeconds > 0) {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    out.add(WorkoutResult(
      'Duration',
      m >= 60
          ? '${m ~/ 60}h ${m % 60}m'
          : (m > 0 ? '${m}m' : '${s}s'),
    ));
  }
  out.add(WorkoutResult('Exercises', '${stats.completedExercises}'));
  out.add(WorkoutResult('Sets', '${stats.completedSets}/${stats.totalSets}'));
  final hit = stats.targetHitPct;
  if (hit != null) {
    out.add(WorkoutResult('Adherence', '${(hit * 100).round()}%'));
  }
  return out;
}

/// THE decision point for Home's workout card.
///
/// [presentation] is the already-tested mapping of the SERVED expectation, so
/// this never re-decides what today IS — only how it looks once the member's
/// own session is taken into account.
HomeWorkoutCard buildHomeWorkoutCard({
  required bool loading,
  required bool loadFailed,
  required bool hasCachedPlan,
  required TodayWorkoutPresentation presentation,
  required String planName,
  required String coachLabel,
  required String coachNote,
  required List<WorkoutFact> facts,
  required SessionStats? todayStats,
  required NextUp? nextUp,
  int? durationSeconds,
}) {
  if (loading) return const HomeWorkoutCard(mode: WorkoutCardMode.loading);

  // A load FAILURE with nothing cached must never read as "no plan assigned":
  // the coach did not remove anything, the network did.
  if (loadFailed && !hasCachedPlan) {
    return const HomeWorkoutCard(
      mode: WorkoutCardMode.unavailable,
      title: "Couldn't load today's session",
      subtitle: 'Your plan is safe — this will load when you reconnect.',
      cta: 'Retry',
    );
  }

  final p = presentation;
  final stats = todayStats;

  switch (p.mode) {
    case TodayWorkoutMode.waiting:
      return HomeWorkoutCard(
        mode: WorkoutCardMode.waiting,
        title: 'No session yet',
        subtitle: '$coachLabel is preparing your training.',
      );

    case TodayWorkoutMode.notYetStarted:
    case TodayWorkoutMode.ended:
      return HomeWorkoutCard(
        mode: WorkoutCardMode.dormant,
        title: p.title,
        subtitle: p.body,
      );

    case TodayWorkoutMode.paused:
      return HomeWorkoutCard(
        mode: WorkoutCardMode.paused,
        title: p.title,
        subtitle: p.body,
      );

    case TodayWorkoutMode.excused:
      return HomeWorkoutCard(
        mode: WorkoutCardMode.excused,
        title: p.title,
        subtitle: p.body,
        // An offer on an excused day, never an expectation.
        secondaryCta: p.trainAnyway ? 'Train anyway' : '',
      );

    case TodayWorkoutMode.rest:
      return HomeWorkoutCard(
        mode: WorkoutCardMode.rest,
        title: p.title,
        subtitle: p.body,
        secondaryCta: p.trainAnyway ? 'Train anyway' : '',
      );

    case TodayWorkoutMode.flexible:
    case TodayWorkoutMode.training:
    case TodayWorkoutMode.unknownDisclosed:
      final flexible = p.mode == TodayWorkoutMode.flexible;

      // ── FINISHED: every prescribed set completed ──────────────────────
      if (stats != null && stats.isComplete) {
        return HomeWorkoutCard(
          mode: WorkoutCardMode.completed,
          title: planName,
          subtitle: 'Completed',
          progressPercent: 100,
          results: workoutResults(
            stats: stats,
            durationSeconds: durationSeconds,
          ),
          cta: 'Review Workout',
          secondaryCta: 'Edit Workout Log',
          disclosure: p.disclosure,
        );
      }

      // ── CLOSED: resolved by skipping. Over, but not complete. ─────────
      if (stats != null && stats.isFullyResolved) {
        return HomeWorkoutCard(
          mode: WorkoutCardMode.closed,
          title: planName,
          subtitle: stats.skippedSets == 1
              ? '1 set skipped'
              : '${stats.skippedSets} sets skipped',
          progressPercent: stats.progressPercent,
          results: workoutResults(
            stats: stats,
            durationSeconds: durationSeconds,
          ),
          cta: 'Review Workout',
          secondaryCta: 'Edit Workout Log',
          disclosure: p.disclosure,
        );
      }

      // ── IN PROGRESS: the resume point is the whole point ──────────────
      if (stats != null && stats.totalSets > 0 && stats.completedSets > 0) {
        return HomeWorkoutCard(
          mode: WorkoutCardMode.inProgress,
          title: planName,
          subtitle: '',
          progressPercent: stats.progressPercent,
          nextUp: nextUp,
          // NO fact chips mid-session. "6 exercises · 45 min · Barbell" is
          // DECISION information — it helps someone choose whether now is a
          // good time. That choice was already made; repeating it here is
          // noise between the member and the set they came back for.
          cta: 'Resume Workout',
          disclosure: p.disclosure,
        );
      }

      // ── NOT STARTED ───────────────────────────────────────────────────
      return HomeWorkoutCard(
        mode: flexible ? WorkoutCardMode.flexible : WorkoutCardMode.ready,
        title: planName,
        subtitle: flexible ? p.body : 'Prepared by $coachLabel',
        coachNote: coachNote,
        facts: facts,
        cta: flexible ? 'Start a Session' : 'Start Workout',
        disclosure: p.disclosure,
      );
  }
}
