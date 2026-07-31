/// CONSISTENCY AS A STORY, NOT A DASHBOARD.
///
/// The numbers were already correct; what was missing was a reason to care
/// about them. This module turns the engine's output into the four things a
/// member actually responds to — where they stand, how close the next win is,
/// what they have already earned, and one honest sentence about it.
///
/// ── THE HARD RULE ──────────────────────────────────────────────────────────
/// NOTHING HERE CALCULATES A VERDICT. Every day's expectation and outcome is
/// decided by the certified engine (`performance.dart` / `prescription.dart`)
/// and arrives here already judged. This module only COUNTS what the engine
/// returned and chooses words for it. If a number here ever disagreed with the
/// coach's app it would mean the engine disagreed, not that this file invented
/// something.
///
/// ── AND THE HONESTY RULES THAT FOLLOW ──────────────────────────────────────
///  • Every figure states its WINDOW. The logs are fetched 60 days back, so
///    "longest streak" means longest in 60 days and says so. A "personal best"
///    this app cannot see is not a personal best it may claim.
///  • Absent is absent. A member with no history gets an invitation, not a
///    wall of zeroes dressed up as achievements.
///  • No copy blames. Facts may be uncomfortable; wording never accuses.
library;

import 'consistency_pair.dart';
import 'performance.dart';
import 'prescription.dart';
import 'workout_session.dart' show SessionStats;

// ═══════════════════════════════════════════════════════════════════════════
// THE HERO — where you stand, and how close the next win is
// ═══════════════════════════════════════════════════════════════════════════

/// The detail screen's opening statement.
class StreakHero {
  final int streak;
  final bool weekUnit;

  /// True once the streak is real and running — drives the lit treatment.
  final bool lit;

  /// "Current Streak"
  final String label;

  /// "2 Days" / "3 Weeks on plan"
  final String value;

  /// "Keep it going." — one short line, forward-facing.
  final String encouragement;

  /// "One more workout to reach 3 days." '' when there is no reachable
  /// milestone left inside the observable window.
  final String nextStep;

  const StreakHero({
    required this.streak,
    required this.weekUnit,
    required this.lit,
    required this.label,
    required this.value,
    required this.encouragement,
    this.nextStep = '',
  });

  String get semanticLabel => [
    label,
    value,
    encouragement,
    if (nextStep.isNotEmpty) nextStep,
  ].join('. ');
}

StreakHero buildStreakHero({
  required ConsistencyTrack track,
  required ConsistencyCardState state,
  required int streak,
  required bool weekUnit,
  required bool hasHistory,
  required bool loggedToday,
}) {
  final workout = track == ConsistencyTrack.workout;

  if (state == ConsistencyCardState.unavailable) {
    return const StreakHero(
      streak: 0,
      weekUnit: false,
      lit: false,
      label: 'Current Streak',
      value: '—',
      encouragement: "We can't reach your history right now.",
      // The reassurance IS the message here: offline must never feel like loss.
      nextStep: 'Nothing is lost — this catches up when you reconnect.',
    );
  }

  if (state == ConsistencyCardState.paused) {
    return StreakHero(
      streak: streak,
      weekUnit: weekUnit,
      lit: false,
      label: 'Current Streak',
      value: _streakValue(streak, weekUnit),
      encouragement: 'Your coaching is paused.',
      nextStep: 'Nothing counts against you, and your streak is safe.',
    );
  }

  final unit = weekUnit
      ? (streak == 1 ? 'Week' : 'Weeks')
      : (streak == 1 ? 'Day' : 'Days');
  final milestone = nextMilestone(streak, weekUnit: weekUnit);

  final String encouragement;
  if (streak > 0) {
    encouragement = loggedToday ? "Today's already done." : 'Keep it going.';
  } else if (hasHistory) {
    // A break is a comeback, never a failure.
    encouragement = 'Ready when you are.';
  } else {
    encouragement =
        workout ? 'Your first session starts it.' : 'Your first log starts it.';
  }

  final String nextStep;
  if (milestone == null) {
    nextStep = streak > 0
        ? 'You are at the longest run this app can verify.'
        : '';
  } else {
    final n = milestone.remaining;
    final thing = workout
        ? (weekUnit
            ? (n == 1 ? 'One more week on plan' : '$n more weeks on plan')
            : (n == 1 ? 'One more workout' : '$n more workouts'))
        : (n == 1 ? 'One more day logged' : '$n more days logged');
    nextStep = '$thing to reach ${milestone.target} '
        '${weekUnit ? (milestone.target == 1 ? 'week' : 'weeks') : (milestone.target == 1 ? 'day' : 'days')}.';
  }

  return StreakHero(
    streak: streak,
    weekUnit: weekUnit,
    lit: streak > 0,
    label: 'Current Streak',
    value: '$streak $unit${weekUnit ? ' on plan' : ''}',
    encouragement: encouragement,
    nextStep: nextStep,
  );
}

String _streakValue(int streak, bool weekUnit) => weekUnit
    ? '$streak ${streak == 1 ? 'Week' : 'Weeks'} on plan'
    : '$streak ${streak == 1 ? 'Day' : 'Days'}';

// ═══════════════════════════════════════════════════════════════════════════
// ACHIEVEMENTS — what has been earned, each with its window stated
// ═══════════════════════════════════════════════════════════════════════════

enum AchievementKind { longestStreak, currentStreak, total, adherence, monthly }

class Achievement {
  final AchievementKind kind;

  /// '🏆' etc. — a single glyph, never an image asset to load.
  final String glyph;
  final String title;

  /// '14 days' / '68%' / '—' when the figure cannot be claimed.
  final String value;

  /// The window or basis, always stated. 'in 60 days', 'this month'.
  final String basis;

  /// 0..1 when the achievement has a meaningful bar; null hides it.
  final double? fraction;

  const Achievement({
    required this.kind,
    required this.glyph,
    required this.title,
    required this.value,
    required this.basis,
    this.fraction,
  });

  bool get isEmpty => value == '—';
}

/// Adherence over the resolved window: hits ÷ (hits + misses).
///
/// The denominator EXCLUDES every day the engine excluded — rest, excused,
/// paused, unscheduled, and today while it is still open. That is what makes
/// this a coaching number rather than an attendance number: a member on a
/// four-day plan who hits all four is at 100%, not 57%.
///
/// Null when nothing has resolved yet — an unearned 0% is a fabricated failure.
double? adherenceOf(List<DayVerdict> verdicts) {
  var hits = 0;
  var misses = 0;
  for (final v in verdicts) {
    if (v.isHit) hits++;
    if (v.isMiss) misses++;
  }
  final total = hits + misses;
  return total == 0 ? null : hits / total;
}

/// This month's ask and how much of it is met, from the engine's own cells.
({int done, int expected}) monthlyGoalOf(List<MonthCell> cells) {
  var done = 0;
  var expected = 0;
  for (final c in cells) {
    switch (c.state) {
      case MonthCellState.done:
        done++;
        expected++;
      case MonthCellState.missed:
        expected++;
      case MonthCellState.today:
        // Today counts in the ask only once it is required; the engine already
        // decided that by not marking it rest/excused/paused.
        expected++;
      case MonthCellState.rest:
      case MonthCellState.excused:
      case MonthCellState.paused:
      case MonthCellState.future:
      case MonthCellState.unknown:
        break;
    }
  }
  return (done: done, expected: expected);
}

/// The five milestones worth celebrating, in the order they matter.
///
/// [logWindowDays] is stated on every window-bounded figure, because a
/// "longest streak" this app can only see 60 days of is not an all-time record
/// and must never be presented as one.
List<Achievement> buildAchievements({
  required ConsistencyTrack track,
  required bool logsAvailable,
  required int currentStreak,
  required int? longestStreak,
  required int totalLogged,
  required List<DayVerdict> verdicts,
  required List<MonthCell> monthCells,
  required bool weekUnit,
  int logWindowDays = kLogWindowDays,
}) {
  final workout = track == ConsistencyTrack.workout;
  final window = 'in $logWindowDays days';

  if (!logsAvailable) {
    // Every tile honestly blank rather than five confident zeroes.
    return [
      for (final k in AchievementKind.values)
        Achievement(
          kind: k,
          glyph: _glyph(k),
          title: _title(k, workout),
          value: '—',
          basis: 'unavailable',
        ),
    ];
  }

  final adherence = adherenceOf(verdicts);
  final month = monthlyGoalOf(monthCells);

  return [
    Achievement(
      kind: AchievementKind.longestStreak,
      glyph: '🏆',
      title: 'Longest Streak',
      value: longestStreak == null || longestStreak == 0
          ? '—'
          : '$longestStreak ${longestStreak == 1 ? 'day' : 'days'}',
      basis: window,
    ),
    Achievement(
      kind: AchievementKind.currentStreak,
      glyph: '🔥',
      title: 'Current Streak',
      value: currentStreak == 0
          ? '—'
          : weekUnit
              ? '$currentStreak ${currentStreak == 1 ? 'week' : 'weeks'}'
              : '$currentStreak ${currentStreak == 1 ? 'day' : 'days'}',
      basis: weekUnit ? 'weeks on plan' : 'running now',
    ),
    Achievement(
      kind: AchievementKind.total,
      glyph: workout ? '💪' : '🥗',
      title: workout ? 'Total Workouts' : 'Days Logged',
      value: totalLogged == 0 ? '—' : '$totalLogged',
      basis: window,
    ),
    Achievement(
      kind: AchievementKind.adherence,
      glyph: '📈',
      title: 'Adherence',
      value: adherence == null ? '—' : '${(adherence * 100).round()}%',
      basis: 'of days your coach asked for',
      fraction: adherence,
    ),
    Achievement(
      kind: AchievementKind.monthly,
      glyph: '🎯',
      title: 'Monthly Goal',
      value: month.expected == 0 ? '—' : '${month.done}/${month.expected}',
      basis: 'this month',
      fraction: month.expected == 0
          ? null
          : (month.done / month.expected).clamp(0.0, 1.0),
    ),
  ];
}

String _glyph(AchievementKind k) => switch (k) {
  AchievementKind.longestStreak => '🏆',
  AchievementKind.currentStreak => '🔥',
  AchievementKind.total => '💪',
  AchievementKind.adherence => '📈',
  AchievementKind.monthly => '🎯',
};

String _title(AchievementKind k, bool workout) => switch (k) {
  AchievementKind.longestStreak => 'Longest Streak',
  AchievementKind.currentStreak => 'Current Streak',
  AchievementKind.total => workout ? 'Total Workouts' : 'Days Logged',
  AchievementKind.adherence => 'Adherence',
  AchievementKind.monthly => 'Monthly Goal',
};

// ═══════════════════════════════════════════════════════════════════════════
// THE CLOSING LINE — one sentence, earned by the data
// ═══════════════════════════════════════════════════════════════════════════

/// The page's last word. Chosen from real evidence, never a random fortune
/// cookie: each branch below is unlocked by something the member actually did.
///
/// It is ordered so the most SPECIFIC true thing wins — "you have already
/// beaten last week" beats a generic "keep going", because a member can tell
/// the difference and only one of them reads as being noticed.
String motivationMessage({
  required ConsistencyTrack track,
  required ConsistencyCardState state,
  required int streak,
  required bool hasHistory,
  required TrackWeek thisWeek,
  required int lastWeekDone,
  required double? adherence,
}) {
  final workout = track == ConsistencyTrack.workout;

  switch (state) {
    case ConsistencyCardState.loading:
      return '';
    case ConsistencyCardState.unavailable:
      return 'Your history is safe — it will be here when you reconnect.';
    case ConsistencyCardState.paused:
      return 'Coaching is paused. Nothing is counting, and nothing is lost.';
    case ConsistencyCardState.unscheduled:
    case ConsistencyCardState.active:
      break;
  }

  if (!hasHistory) {
    return workout
        ? 'Everything starts with one session. Today is as good as any.'
        : 'Everything starts with one logged day. Today is as good as any.';
  }

  // A finished week is worth naming before anything else.
  if (thisWeek.expected > 0 && thisWeek.done >= thisWeek.expected) {
    return 'You have done everything your coach asked this week.';
  }

  // Beating last week is the most motivating comparison available, because it
  // is a race against a version of the member that actually existed.
  if (lastWeekDone > 0 && thisWeek.done > lastWeekDone) {
    return "You're ahead of where you were last week.";
  }
  if (lastWeekDone > 0 && thisWeek.done == lastWeekDone - 1) {
    return workout
        ? 'One more session and you match last week.'
        : 'One more logged day and you match last week.';
  }

  if (streak >= 7) return 'A week straight. This is what a habit looks like.';
  if (streak > 0) return 'Small wins become lifelong habits.';

  if (adherence != null && adherence >= 0.8) {
    return "Your record is strong — one day off doesn't change that.";
  }
  return "You're building momentum. Showing up is most of it.";
}

// ═══════════════════════════════════════════════════════════════════════════
// DAY SUMMARY — what one tapped day actually was
// ═══════════════════════════════════════════════════════════════════════════

/// One row in the tapped-day sheet.
class DayFact {
  final String label;
  final String value;
  const DayFact(this.label, this.value);
}

/// A tapped day, fully described.
///
/// [stats] is the real session for that day when one could be read — the SAME
/// `computeSessionStats` every other surface uses, over the SAME document. It
/// is null when the day has no session, when the fetch failed, or on the
/// nutrition track, and the sheet then simply states less rather than
/// estimating anything.
class DaySummary {
  final DateTime date;
  final String outcomeLabel;
  final String expectationLabel;
  final String reason;
  final String coachNote;
  final List<DayFact> facts;

  /// Whether a session lookup is still running — the sheet shows a quiet
  /// placeholder rather than claiming "no data" before it knows.
  final bool loadingSession;

  const DaySummary({
    required this.date,
    required this.outcomeLabel,
    required this.expectationLabel,
    this.reason = '',
    this.coachNote = '',
    this.facts = const [],
    this.loadingSession = false,
  });
}

String expectationLabelFor(ExpectationKind k) => switch (k) {
  ExpectationKind.required => 'Session expected',
  ExpectationKind.optional => "Optional — your choice",
  ExpectationKind.rest => 'Rest prescribed',
  ExpectationKind.paused => 'Coaching paused',
  ExpectationKind.notYetStarted => 'Plan had not started',
  ExpectationKind.ended => 'Plan had ended',
  ExpectationKind.unknown => 'No schedule set',
};

String outcomeLabelFor(DayVerdict v) {
  if (v.isHit) return 'Completed';
  if (v.isMiss) return 'Missed';
  return switch (v.outcome) {
    OutcomeKind.excusedByCoach => 'Excused by your coach',
    OutcomeKind.open => 'Still open',
    _ => switch (v.expectation) {
      ExpectationKind.rest => 'Rest day',
      ExpectationKind.paused => 'Paused',
      _ => 'Not counted',
    },
  };
}

String reasonLabelFor(String reason) => switch (reason) {
  'travel' => 'Travel',
  'deload' => 'Deload',
  'medical' => 'Medical leave',
  'closure' => 'Gym closed',
  'custom' => 'Coach exception',
  'pause' => 'Paused by coach',
  'rhythm' => '',
  'frequency' => '',
  _ => '',
};

/// The session facts for a completed day, from the ONE completion engine.
/// Each appears only when it is real — a session with no recorded clock states
/// no duration rather than "0m".
List<DayFact> dayFactsFrom({
  required SessionStats? stats,
  required int? durationSeconds,
}) {
  if (stats == null) return const [];
  final out = <DayFact>[];
  if (durationSeconds != null && durationSeconds > 0) {
    final m = durationSeconds ~/ 60;
    out.add(DayFact(
      'Duration',
      m >= 60 ? '${m ~/ 60}h ${m % 60}m' : (m > 0 ? '${m}m' : '<1m'),
    ));
  }
  out.add(DayFact('Exercises', '${stats.completedExercises}'));
  out.add(DayFact(
      'Sets', '${stats.completedSets}/${stats.totalSets}'));
  final hit = stats.targetHitPct;
  if (hit != null) {
    out.add(DayFact('Adherence', '${(hit * 100).round()}%'));
  }
  return out;
}
