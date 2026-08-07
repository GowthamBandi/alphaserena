/// CONSISTENCY — TWO CARDS, TWO TRACKS, ONE ENGINE.
///
/// Workout and nutrition are different behaviours with different rhythms, and
/// a member reads them as separate identities: *I trained* and *I ate well*.
/// A single combined card averages those two facts into one number that
/// describes neither — and worse, it lets a strong week in one track quietly
/// paper over a collapse in the other.
///
/// So: two cards, side by side, each with its OWN state machine, each fed by
/// the Prescription Engine for its own track. One can be a prescribed rest day
/// while the other is mid-progress; one can be unreadable while the other is
/// live. Nothing here is shared except the rules.
///
/// ── THE FOUR THINGS EACH CARD SAYS ─────────────────────────────────────────
///  1. STREAK       — the number you can lose. Named, large, first.
///  2. THIS WEEK    — the coach's ask, and how much of it is done.
///  3. TODAY        — today's own progress, in that track's unit.
///  4. NEXT         — the milestone within reach, so there is always a target
///                    slightly ahead of where you stand.
///
/// ── HONESTY RULES ──────────────────────────────────────────────────────────
///  • Unreadable logs render [ConsistencyCardState.unavailable], never a 0.
///  • A milestone the engine CANNOT OBSERVE is never offered. Logs are fetched
///    in a 60-day window, so "100-day streak" is not a goal this app can ever
///    confirm — offering it would be a promise the data cannot keep.
///  • Rest, excused and paused are positive states outside every denominator.
///  • No copy blames.
library;

import 'performance.dart';
// TodayMark and markFor now live in `performance.dart`, beside the month
// calendar that must agree with them. Re-exported so the dozen call sites
// that import this library keep working: one declaration, two names.
export 'performance.dart' show TodayMark, markFor;
import 'prescription.dart';
import '../utils/day_key_guard.dart' show addCalendarDays;

/// Which card. They never share state — only rules.
enum ConsistencyTrack { workout, nutrition }

enum ConsistencyCardState {
  /// Sources still in flight — skeleton, never a zero.
  loading,

  /// Logs could not be read (offline / rules). Never shown as 0.
  unavailable,

  /// Coaching paused for this track. The streak is safe.
  paused,

  /// No prescription for this track: presence only, and said so.
  unscheduled,

  /// A prescription exists and the week can be measured.
  active,
}

/// One day's resolved state, for the week rail.
///
/// These are the engine's own verdicts, renamed for rendering — nothing here
/// re-judges a day. Home draws them at low fidelity (a glance); the detail
/// screen draws all of them distinctly (the truth).
///
/// NOTE ON "SKIPPED": there is deliberately no member-skipped-a-day state. The
/// data model has skipped SETS, not skipped DAYS — a day the member opened and
/// abandoned produces no qualifying log and is therefore [missed], exactly like
/// a day they never opened. Inventing a third appearance would be fabricating a
/// distinction the repository cannot make.

// ═══════════════════════════════════════════════════════════════════════════
// MILESTONES — always a target slightly ahead, never one out of reach
// ═══════════════════════════════════════════════════════════════════════════

/// Day-streak milestones. Bounded by [kLogWindowDays]: a streak longer than
/// the fetch window cannot be verified, so it is not offered as a goal.
const List<int> kDayMilestones = [3, 7, 14, 21, 30, 45, 60];

/// Weeks-on-plan milestones. The same 60-day window is ~8.5 weeks, which is
/// why this list stops at 8 rather than running to a satisfying 52.
const List<int> kWeekMilestones = [2, 4, 6, 8];

/// The window `ActivityHistoryService` fetches (mirrors `StreakController.cap`).
const int kLogWindowDays = 60;

/// The next target above [streak], or null once the observable window is
/// exhausted — at which point the card celebrates the window instead of
/// dangling a goal the engine can never confirm.
class StreakMilestone {
  final int target;
  final int current;
  final bool weekUnit;

  const StreakMilestone({
    required this.target,
    required this.current,
    required this.weekUnit,
  });

  int get remaining => (target - current).clamp(0, target);

  double get fraction =>
      target <= 0 ? 0 : (current / target).clamp(0.0, 1.0);

  /// "2 days to 7" · "1 week to 4". Short, because it lives in a 172px card.
  String get label {
    final unit = weekUnit
        ? (remaining == 1 ? 'week' : 'weeks')
        : (remaining == 1 ? 'day' : 'days');
    return '$remaining $unit to $target';
  }
}

StreakMilestone? nextMilestone(int streak, {required bool weekUnit}) {
  final ladder = weekUnit ? kWeekMilestones : kDayMilestones;
  for (final m in ladder) {
    if (streak < m) {
      return StreakMilestone(target: m, current: streak, weekUnit: weekUnit);
    }
  }
  return null; // beyond what this window can verify
}

// ═══════════════════════════════════════════════════════════════════════════
// MEALS — the nutrition card's "today" unit
// ═══════════════════════════════════════════════════════════════════════════

// `mealProgress` REMOVED (AlphaSerena Lifestyle completion).
//
// It counted a meal as complete when every prescribed food in it was marked
// `eaten` or `partial` — the adherence model that Phase 3B retired when coach
// recommendations became read-only. Nothing wrote those marks any more and
// nothing called this function; it was a legacy calculation sitting in the
// domain layer looking authoritative. Nutrition progress is now measured from
// the FOOD LOG, which is a different question with a different answer.

// ═══════════════════════════════════════════════════════════════════════════
// THE CARD
// ═══════════════════════════════════════════════════════════════════════════

class ConsistencyCard {
  final ConsistencyTrack track;
  final ConsistencyCardState state;

  final int streak;

  /// Weeks-on-plan rather than days. A member training 4×/week could never
  /// push a day streak past 2, so a day count punished the very compliance it
  /// claimed to measure.
  final bool weekUnit;

  /// Monday..Sunday marks for the week rail. Seven entries, or empty.
  final List<TodayMark> week;

  final int weekDone;
  final int weekExpected;

  /// "Any 4 per week" — counted in sessions, and the copy says so.
  final bool isFrequency;

  final TodayMark today;

  /// The ONE line of copy on the Home card, under the streak. Forward-facing
  /// always: it is the only sentence a member reads before deciding whether
  /// this section is about them or about statistics.
  final String motivation;

  /// Which rail slot is today (0 = Monday). Carried on the MODEL rather than
  /// read from the clock inside the widget: a widget that calls
  /// `DateTime.now()` is untestable and can disagree with the rail it is
  /// drawing when a build straddles midnight.
  final int todayIndex;

  const ConsistencyCard({
    required this.track,
    required this.state,
    this.streak = 0,
    this.weekUnit = false,
    this.week = const [],
    this.weekDone = 0,
    this.weekExpected = 0,
    this.isFrequency = false,
    this.today = TodayMark.unknown,
    this.motivation = '',
    this.todayIndex = 0,
  });

  String get title =>
      track == ConsistencyTrack.workout ? 'WORKOUT' : 'NUTRITION';

  bool get isReal =>
      state == ConsistencyCardState.active ||
      state == ConsistencyCardState.unscheduled;

  /// The headline number, or an honest em dash.
  String get streakValue => streakValueFor(streakCount);

  /// The headline number as something that can be COUNTED to, or null when
  /// there is no real streak to count — an em dash is not a quantity, and a
  /// card in a blocked or unknown state must never animate its way to one.
  double? get streakCount => isReal ? streak.toDouble() : null;

  /// [streakValue] at an intermediate figure.
  String streakValueFor(double? shown) =>
      shown == null ? '—' : '${shown.round()}';

  String get streakUnit {
    if (!isReal) return weekUnit ? 'weeks on plan' : 'day streak';
    if (weekUnit) return streak == 1 ? 'week on plan' : 'weeks on plan';
    return 'day streak';
  }

  bool get showWeekRail => week.length == 7 &&
      state != ConsistencyCardState.loading &&
      state != ConsistencyCardState.unavailable;

  /// '3 of 5 this week' · '2 of 4 sessions' · '' when nothing is asked.
  String get weekLine {
    if (state == ConsistencyCardState.loading) return '';
    if (state == ConsistencyCardState.unavailable) return 'History unavailable';
    if (state == ConsistencyCardState.paused) return 'Coaching paused';
    if (state == ConsistencyCardState.unscheduled) return 'No schedule set';
    if (weekExpected <= 0) return 'Nothing asked this week';
    return isFrequency
        ? '$weekDone of $weekExpected sessions'
        : '$weekDone of $weekExpected this week';
  }

  /// The status chip for a day the coach did not ask for training/logging.
  String get todayChip => switch (today) {
    TodayMark.rest => 'Rest day',
    TodayMark.excused => 'Excused',
    TodayMark.paused => 'Paused',
    _ => '',
  };

  String get semanticLabel {
    final name = track == ConsistencyTrack.workout ? 'Workout' : 'Nutrition';
    switch (state) {
      case ConsistencyCardState.loading:
        return '$name consistency, loading';
      case ConsistencyCardState.unavailable:
        return '$name consistency unavailable — your history could not be '
            'loaded. Your streak is safe.';
      case ConsistencyCardState.paused:
        return '$name coaching is paused. Nothing counts against you and your '
            'streak is safe.';
      case ConsistencyCardState.unscheduled:
        return '$name consistency: $streak $streakUnit. No schedule set, '
            'counting the days you showed up.';
      case ConsistencyCardState.active:
        // Spoken form of what is on screen: the streak, the one line of copy,
        // and the week the seven circles encode. A screen reader gets no
        // benefit from circles, so the week is voiced as its summary.
        return [
          '$name consistency: $streak $streakUnit',
          if (motivation.isNotEmpty) motivation,
          weekLine,
          if (todayChip.isNotEmpty) 'Today: $todayChip',
        ].join('. ');
    }
  }
}


TodayMark _markFrom(DayVerdict v, DateTime today) => markFor(v, today);

/// The Monday-based rail. `done` is the only filled state; a miss is shown as
/// an empty slot rather than an alarm, because the rail's job is momentum, not
/// indictment — the full miss history lives one tap away on the detail screen.
List<TodayMark> buildWeekRail(
  TrackHistory history, {
  required Set<String> logged,
  required DateTime today,
}) {
  final t = DateTime(today.year, today.month, today.day);
  final monday = addCalendarDays(t, -(t.weekday - 1));
  return [
    for (var i = 0; i < 7; i++)
      () {
        final day = addCalendarDays(monday, i);
        if (day.isAfter(t)) return TodayMark.future;
        return _markFrom(
          history.verdictOn(day, logged: logged, today: t),
          t,
        );
      }(),
  ];
}

/// Builds ONE track's card. Called twice, independently — the workout card
/// never consults nutrition data and vice versa.
ConsistencyCard buildConsistencyCard({
  required ConsistencyTrack track,
  required bool loading,
  required bool logsAvailable,
  required TrackHistory history,
  required Set<String> logged,
  required TrackWeek week,
  required int streak,
  required bool weekUnit,
  required DateTime today,
}) {
  if (loading) {
    return ConsistencyCard(track: track, state: ConsistencyCardState.loading);
  }
  if (!logsAvailable) {
    return ConsistencyCard(
      track: track,
      state: ConsistencyCardState.unavailable,
      motivation: 'Offline — your streak is safe.',
    );
  }

  final rail = buildWeekRail(history, logged: logged, today: today);
  final todayMark = rail[today.weekday - 1];

  if (week.paused) {
    return ConsistencyCard(
      track: track,
      state: ConsistencyCardState.paused,
      streak: streak,
      weekUnit: weekUnit,
      week: rail,
      today: TodayMark.paused,
      motivation: 'Paused — your streak is safe.',
      todayIndex: today.weekday - 1,
    );
  }

  if (week.unknown) {
    return ConsistencyCard(
      track: track,
      state: ConsistencyCardState.unscheduled,
      streak: streak,
      // Weeks-on-plan needs a plan.
      weekUnit: false,
      week: rail,
      today: todayMark,
      motivation: homeMotivation(
        state: ConsistencyCardState.unscheduled,
        track: track,
        streak: streak,
        today: todayMark,
        hasHistory: logged.isNotEmpty,
        weekDone: 0,
        weekExpected: 0,
      ),
      todayIndex: today.weekday - 1,
    );
  }

  return ConsistencyCard(
    track: track,
    state: ConsistencyCardState.active,
    streak: streak,
    weekUnit: weekUnit,
    week: rail,
    weekDone: week.done,
    weekExpected: week.expected,
    isFrequency: week.isFrequency,
    today: todayMark,
    motivation: homeMotivation(
      state: ConsistencyCardState.active,
      track: track,
      streak: streak,
      today: todayMark,
      hasHistory: logged.isNotEmpty,
      weekDone: week.done,
      weekExpected: week.expected,
    ),
    todayIndex: today.weekday - 1,
  );
}


// ═══════════════════════════════════════════════════════════════════════════
// THE HOME CARD'S ONE LINE
// ═══════════════════════════════════════════════════════════════════════════

/// The single sentence under the streak number.
///
/// It is the whole reason the Home card reads as coaching rather than as a
/// statistic, so it is ordered by KINDNESS-THAT-IS-TRUE: a coach-approved day
/// is celebrated before any progress is mentioned, because a member following
/// the plan exactly must never read as behind.
///
/// Deliberately short — this line sits in a ~150px column and competes with
/// nothing. No branch blames.
String homeMotivation({
  required ConsistencyCardState state,
  required ConsistencyTrack track,
  required int streak,
  required TodayMark today,
  required bool hasHistory,
  required int weekDone,
  required int weekExpected,
}) {
  final workout = track == ConsistencyTrack.workout;

  switch (state) {
    case ConsistencyCardState.loading:
      return '';
    case ConsistencyCardState.unavailable:
      return 'Offline — your streak is safe.';
    case ConsistencyCardState.paused:
      return 'Paused — your streak is safe.';
    case ConsistencyCardState.unscheduled:
    case ConsistencyCardState.active:
      break;
  }

  // 1. The coach protected today. Say it first, and warmly.
  if (today == TodayMark.excused) return 'Excused today. Costs you nothing.';
  if (today == TodayMark.rest) return 'Rest day. Recovery counts.';

  // 2. Today is already handled.
  if (today == TodayMark.done) {
    if (weekExpected > 0 && weekDone >= weekExpected) return 'Perfect week.';
    return 'Done today. Nice.';
  }

  // 3. The week is already satisfied even though today is open.
  if (weekExpected > 0 && weekDone >= weekExpected) {
    return "Week complete. You're ahead.";
  }

  // 4. A live streak is the strongest honest motivator there is.
  if (streak > 0) return 'Keep it going.';

  // 5. Zero, but with history: a comeback, never a failure.
  if (hasHistory) return 'Ready when you are.';

  // 6. Brand new.
  return workout ? 'Start your first session.' : 'Log your first day.';
}
