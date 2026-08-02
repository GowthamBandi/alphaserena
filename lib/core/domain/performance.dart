/// PRESCRIPTION ENGINE — Phase 4: the Member Performance domain.
///
/// Pure Dart. Everything here is computed from four REAL inputs — the coach's
/// prescription versions (served by the backend), the coach's per-day excuses,
/// the client-level pause, and the member's own logged day-keys — using the
/// certified Step-1 engine (`verdictFor` / `weekVerdict`). Both apps carry the
/// byte-identical engine, so a number computed here can never disagree with
/// the coach's side: same inputs, same rule set, one answer.
///
/// THE ONE RULE, still: no day is ever judged against an expectation nobody
/// wrote. No prescription → `unknown` → excluded and disclosed. A missed day
/// exists only where a coach said "this day is required" and it ended
/// unlogged, unexcused.
library;

import 'prescription.dart';
import 'today_expectation.dart' show localDayKey;

// ═══════════════════════════════════════════════════════════════════════════
// SERVED HISTORY — parsing the raw material getMyTraining now carries
// ═══════════════════════════════════════════════════════════════════════════

/// One track's prescription material: versions in force across the window,
/// the coach's per-day excuses, and the client-level pause.
class TrackHistory {
  final List<Prescription> versions;
  final Set<String> excusedDays;
  final PrescriptionException? coachingPause;

  const TrackHistory({
    this.versions = const [],
    this.excusedDays = const {},
    this.coachingPause,
  });

  bool get hasPrescription => versions.isNotEmpty;

  /// Null-safe parse of `prescriptionData.<track>`; junk entries are dropped,
  /// never defaulted.
  static TrackHistory fromServed(
    dynamic served, {
    PrescriptionException? coachingPause,
  }) {
    if (served is! Map) return TrackHistory(coachingPause: coachingPause);
    final versions = <Prescription>[];
    final raw = served['versions'];
    if (raw is List) {
      for (final v in raw) {
        if (v is Map) {
          final p = Prescription.fromMap(Map<String, dynamic>.from(v));
          if (p != null) versions.add(p);
        }
      }
    }
    final excused = <String>{};
    final rawExcused = served['excusedDays'];
    if (rawExcused is Map) {
      excused.addAll(rawExcused.keys.map((k) => k.toString()));
    }
    return TrackHistory(
      versions: versions,
      excusedDays: excused,
      coachingPause: coachingPause,
    );
  }

  /// The full day resolution for [date] — expectation AND outcome, via the
  /// certified engine.
  DayVerdict verdictOn(
    DateTime date, {
    required Set<String> logged,
    required DateTime today,
  }) {
    return verdictFor(
      versions,
      date,
      logged: logged.contains(localDayKey(date)),
      today: today,
      excused: excusedDays.contains(localDayKey(date)),
      coachingPause: coachingPause,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TIMELINE — the coaching story, newest first
// ═══════════════════════════════════════════════════════════════════════════

/// Last [days] days resolved, newest first — the tappable coaching timeline.
List<DayVerdict> timeline(
  TrackHistory h, {
  required Set<String> logged,
  required DateTime today,
  int days = 30,
}) {
  final t = DateTime(today.year, today.month, today.day);
  return [
    for (var i = 0; i < days; i++)
      h.verdictOn(t.subtract(Duration(days: i)), logged: logged, today: t),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════
// MONTH VIEW — every day an honest state, no fabricated colours
// ═══════════════════════════════════════════════════════════════════════════

enum MonthCellState {
  done,
  missed,
  rest,
  excused,
  paused,
  today,
  future,

  /// No prescription covered this day (or it was outside validity): excluded
  /// from every score, rendered faint — never as a miss, never invisible.
  unknown,
}

class MonthCell {
  final DateTime date;
  final MonthCellState state;

  /// What the coach asked for that day. Carried so a COUNT over these cells
  /// (the monthly goal) can tell an asked-for day from a bonus one without
  /// re-resolving the verdict and risking a second, divergent answer.
  final ExpectationKind expectation;

  const MonthCell(
    this.date,
    this.state, {
    this.expectation = ExpectationKind.unknown,
  });
}

/// Every day of [month] (1st → last), each with an honest state.
List<MonthCell> monthCells(
  TrackHistory h, {
  required Set<String> logged,
  required DateTime month,
  required DateTime today,
}) {
  final t = DateTime(today.year, today.month, today.day);
  final first = DateTime(month.year, month.month, 1);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  return [
    for (var i = 0; i < daysInMonth; i++)
      _cellFor(h, first.add(Duration(days: i)), logged, t),
  ];
}

MonthCell _cellFor(
  TrackHistory h,
  DateTime date,
  Set<String> logged,
  DateTime today,
) {
  if (date.isAfter(today)) return MonthCell(date, MonthCellState.future);
  final v = h.verdictOn(date, logged: logged, today: today);
  final e = v.expectation;
  // DONE always wins — a bonus session on a rest day is still a session, and
  // (since the two-axis fix) so is a session under no prescription at all.
  if (v.outcome == OutcomeKind.done) {
    return MonthCell(date, MonthCellState.done, expectation: e);
  }
  if (v.outcome == OutcomeKind.excusedByCoach) {
    return MonthCell(date, MonthCellState.excused, expectation: e);
  }
  if (v.outcome == OutcomeKind.open) {
    return MonthCell(date, MonthCellState.today, expectation: e);
  }
  if (v.outcome == OutcomeKind.missed) {
    return MonthCell(date, MonthCellState.missed, expectation: e);
  }
  // Excluded: say WHY, honestly.
  switch (e) {
    case ExpectationKind.rest:
    case ExpectationKind.optional:
      return MonthCell(date, MonthCellState.rest, expectation: e);
    case ExpectationKind.paused:
      return MonthCell(date, MonthCellState.paused, expectation: e);
    default:
      return MonthCell(date, MonthCellState.unknown, expectation: e);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// THIS WEEK — Completed / Expected, in the unit the prescription uses
// ═══════════════════════════════════════════════════════════════════════════

/// One track's current week, framed in ITS unit: sessions-per-week for a
/// frequency prescription, required-days for everything else.
class TrackWeek {
  /// Days (or sessions) completed so far this week — bonus days count.
  final int done;

  /// The week's ask: frequency target, or required days in the FULL week
  /// (excused and paused days are not asked, so they are not counted).
  final int expected;

  final bool isFrequency;

  /// Frequency only — sessions still open ("2 more this week, you pick").
  final int remaining;

  /// Coach-approved days this week (excused + exception rest inside an
  /// otherwise-active week) — surfaced, never hidden.
  final int coachApproved;

  /// The whole week is paused / has no prescription.
  final bool paused;
  final bool unknown;

  const TrackWeek({
    this.done = 0,
    this.expected = 0,
    this.isFrequency = false,
    this.remaining = 0,
    this.coachApproved = 0,
    this.paused = false,
    this.unknown = false,
  });
}

/// Resolves the CURRENT week (Monday-based) for one track.
TrackWeek weekSummary(
  TrackHistory h, {
  required Set<String> logged,
  required DateTime today,
}) {
  final t = DateTime(today.year, today.month, today.day);
  final monday = t.subtract(Duration(days: t.weekday - 1));

  if (!h.hasPrescription && h.coachingPause == null) {
    return const TrackWeek(unknown: true);
  }

  var done = 0;
  var required = 0;
  var excused = 0;
  var pausedDays = 0;
  var unknownDays = 0;
  var frequencyDays = 0;
  var frequencyTarget = 0;

  for (var i = 0; i < 7; i++) {
    final day = monday.add(Duration(days: i));
    final e = expectationFor(
      h.versions,
      day,
      coachingPause: h.coachingPause,
    );
    final isExcused = h.excusedDays.contains(localDayKey(day));
    final loggedDay = logged.contains(localDayKey(day));
    if (loggedDay && !day.isAfter(t)) done++;

    if (isExcused) {
      excused++;
      continue;
    }
    switch (e.kind) {
      case ExpectationKind.required:
        required++;
      case ExpectationKind.optional:
        if (e.reason == 'frequency') {
          frequencyDays++;
          final v = versionEffectiveOn(h.versions, day);
          if (v != null && v.rhythm.type == RhythmType.frequency) {
            frequencyTarget = v.rhythm.count;
          } else {
            final r = _activeReplacementRhythm(v, day);
            if (r != null && r.type == RhythmType.frequency) {
              frequencyTarget = r.count;
            }
          }
        }
      case ExpectationKind.rest:
        if (e.reason != 'rhythm') excused++; // an exception the coach granted
      case ExpectationKind.paused:
        pausedDays++;
      case ExpectationKind.notYetStarted:
      case ExpectationKind.ended:
      case ExpectationKind.unknown:
        unknownDays++;
    }
  }

  if (pausedDays == 7) return const TrackWeek(paused: true);
  if (unknownDays == 7) return const TrackWeek(unknown: true);

  if (frequencyDays > 0 && frequencyTarget > 0) {
    return TrackWeek(
      done: done,
      expected: frequencyTarget,
      isFrequency: true,
      remaining: (frequencyTarget - done).clamp(0, 7),
      coachApproved: excused,
    );
  }
  return TrackWeek(
    done: done,
    expected: required,
    coachApproved: excused,
  );
}

Rhythm? _activeReplacementRhythm(Prescription? p, DateTime day) {
  if (p == null) return null;
  Rhythm? active;
  for (final e in p.exceptions) {
    if (e.covers(day) && e.replacementRhythm != null) {
      active = e.replacementRhythm;
    }
  }
  return active;
}

// ═══════════════════════════════════════════════════════════════════════════
// STREAKS — only the ones the freeze kept (▲4)
// ═══════════════════════════════════════════════════════════════════════════
//
// The freeze judged every candidate streak and kept TWO:
//   • the DIET daily streak — genuinely daily, genuinely binary;
//   • the WORKOUT WEEKLY-adherence streak — "5 weeks on plan" is the correct
//     unit for weekdays and frequency alike; the day-streak it replaces
//     punished every member training fewer than 7 days (a 4×/week member
//     could never exceed 2 — the original defect).
// Excluded days (rest, paused, excused, unknown) are TRANSPARENT: they never
// break either streak, because a member on medical leave returning to "0"
// learns that the app punishes illness.

/// Consecutive weeks (newest first, current week transparent until it ends or
/// is already satisfied) in which the member did everything the coach asked.
///
/// A week is a HIT when: frequency target met, or every required day is done
/// or excused. A week with NOTHING asked (all rest/paused/unknown) is
/// transparent — skipped, never a break.
int weeklyAdherenceStreak(
  TrackHistory h, {
  required Set<String> logged,
  required DateTime today,
  int maxWeeks = 26,
}) {
  if (!h.hasPrescription) return 0;
  final t = DateTime(today.year, today.month, today.day);
  final currentMonday = t.subtract(Duration(days: t.weekday - 1));
  var streak = 0;
  for (var w = 0; w < maxWeeks; w++) {
    final monday = currentMonday.subtract(Duration(days: 7 * w));
    switch (_weekOutcome(h, monday, logged: logged, today: t)) {
      case _WeekResult.hit:
        streak++;
      case _WeekResult.transparent:
        continue;
      case _WeekResult.missed:
        return streak;
    }
  }
  return streak;
}

/// The LONGEST run of satisfied weeks inside the window — the weekly twin of
/// [weeklyAdherenceStreak], evaluated by the identical [_weekOutcome].
///
/// "Longest streak" used to be raw calendar-consecutive-day math while
/// "current streak" was this. A Mon/Wed/Fri member six weeks into a perfect run
/// therefore read *Current 6 weeks · Longest 1 day* — two engines, two units,
/// one screen. Both figures now come from here, so a best can never be shorter
/// than the run happening right now.
int bestWeeklyAdherenceStreak(
  TrackHistory h, {
  required Set<String> logged,
  required DateTime today,
  int maxWeeks = 26,
}) {
  if (!h.hasPrescription) return 0;
  final t = DateTime(today.year, today.month, today.day);
  final currentMonday = t.subtract(Duration(days: t.weekday - 1));
  var best = 0;
  var run = 0;
  // Oldest → newest, so a run is counted forwards exactly as it was lived.
  for (var w = maxWeeks - 1; w >= 0; w--) {
    final monday = currentMonday.subtract(Duration(days: 7 * w));
    switch (_weekOutcome(h, monday, logged: logged, today: t)) {
      case _WeekResult.hit:
        run++;
        if (run > best) best = run;
      case _WeekResult.transparent:
        continue; // never breaks, never extends
      case _WeekResult.missed:
        run = 0;
    }
  }
  return best;
}

/// The LONGEST prescription-aware daily run inside [cap] days — the daily twin
/// of [dailyStreak], using the identical verdicts.
///
/// Prescribed rest, pauses, excuses and unscheduled days stay TRANSPARENT here
/// exactly as they do in the live streak, which is what stops a compliant
/// four-days-a-week member's personal best from being pinned at 1.
int bestDailyStreak(
  TrackHistory h, {
  required Set<String> logged,
  required DateTime today,
  int cap = 365,
}) {
  final t = DateTime(today.year, today.month, today.day);
  var best = 0;
  var run = 0;
  for (var i = cap - 1; i >= 0; i--) {
    final v = h.verdictOn(t.subtract(Duration(days: i)), logged: logged, today: t);
    if (v.outcome == OutcomeKind.done) {
      run++;
      if (run > best) best = run;
    } else if (v.isExcluded || v.outcome == OutcomeKind.open) {
      continue;
    } else {
      run = 0;
    }
  }
  return best;
}

enum _WeekResult { hit, missed, transparent }

_WeekResult _weekOutcome(
  TrackHistory h,
  DateTime monday, {
  required Set<String> logged,
  required DateTime today,
}) {
  final isCurrent = !monday
      .add(const Duration(days: 6))
      .isBefore(DateTime(today.year, today.month, today.day));

  var asked = 0;
  var satisfied = 0;
  var frequencyTarget = 0;
  var done = 0;
  var missed = 0;

  for (var i = 0; i < 7; i++) {
    final day = monday.add(Duration(days: i));
    final v = h.verdictOn(day, logged: logged, today: today);
    if (v.outcome == OutcomeKind.done) done++;
    if (v.expectation == ExpectationKind.optional && v.reason == 'frequency') {
      final ver = versionEffectiveOn(h.versions, day);
      final r = ver == null
          ? null
          : (ver.rhythm.type == RhythmType.frequency
                ? ver.rhythm
                : _activeReplacementRhythm(ver, day));
      if (r != null && r.type == RhythmType.frequency) {
        frequencyTarget = r.count;
      }
    }
    if (v.expectation == ExpectationKind.required) {
      asked++;
      if (v.outcome == OutcomeKind.done ||
          v.outcome == OutcomeKind.excusedByCoach) {
        satisfied++;
      } else if (v.outcome == OutcomeKind.missed) {
        missed++;
      }
    }
  }

  if (frequencyTarget > 0) {
    if (done >= frequencyTarget) return _WeekResult.hit;
    // A short current week is OPEN — transparent until it actually ends.
    return isCurrent ? _WeekResult.transparent : _WeekResult.missed;
  }
  if (asked == 0) return _WeekResult.transparent; // nothing asked, no verdict
  if (missed > 0) return _WeekResult.missed;
  if (satisfied == asked) return _WeekResult.hit;
  return isCurrent ? _WeekResult.transparent : _WeekResult.missed;
}

/// The diet-style DAILY streak, prescription-aware: consecutive DONE days over
/// days that were actually asked; excluded days (rest, paused, excused,
/// unknown) are transparent. Today never breaks it while still open.
int dailyStreak(
  TrackHistory h, {
  required Set<String> logged,
  required DateTime today,
  int cap = 365,
}) {
  final t = DateTime(today.year, today.month, today.day);
  var streak = 0;
  for (var i = 0; i < cap; i++) {
    final v = h.verdictOn(
      t.subtract(Duration(days: i)),
      logged: logged,
      today: t,
    );
    if (v.outcome == OutcomeKind.done) {
      streak++;
    } else if (v.isExcluded) {
      continue; // transparent — never breaks, never extends
    } else if (v.outcome == OutcomeKind.open) {
      continue; // today, still in progress
    } else {
      return streak; // a genuine miss
    }
  }
  return streak;
}

// ═══════════════════════════════════════════════════════════════════════════
// INSIGHTS — computed from real verdicts, evidence-gated, guilt-free
// ═══════════════════════════════════════════════════════════════════════════

enum InsightKind { pattern, improvement, recovery, cleanWeek }

class Insight {
  final InsightKind kind;
  final String text;
  const Insight(this.kind, this.text);
}

/// Coaching insights, at most three, each requiring real evidence. Framing
/// rule: facts may be uncomfortable ("Wednesdays are your toughest day") but
/// wording is never an accusation — the member should end the sentence
/// knowing what to do, not how to feel.
List<Insight> insightsFor(
  TrackHistory h, {
  required Set<String> logged,
  required DateTime today,
  required String trackLabel, // 'workouts' | 'meals'
  int windowDays = 60,
}) {
  final verdicts = timeline(
    h,
    logged: logged,
    today: today,
    days: windowDays,
  );
  final out = <Insight>[];

  // 1. Clean current stretch — the most motivating true sentence available.
  final last7 = verdicts.take(7);
  final misses7 = last7.where((v) => v.isMiss).length;
  final done7 = last7.where((v) => v.isHit).length;
  if (misses7 == 0 && done7 >= 2) {
    out.add(Insight(
      InsightKind.cleanWeek,
      'A clean week — every $trackLabel day handled.',
    ));
  }

  // 2. Weekday pattern — needs ≥2 misses on one weekday, and strictly more
  // than every other weekday (mirrors the consistency module's rule).
  final missesByWeekday = List<int>.filled(8, 0);
  for (final v in verdicts) {
    if (v.isMiss) missesByWeekday[v.date.weekday]++;
  }
  var worst = 0;
  for (var d = 1; d <= 7; d++) {
    if (missesByWeekday[d] >= 2 &&
        (worst == 0 || missesByWeekday[d] > missesByWeekday[worst])) {
      if (worst != 0 && missesByWeekday[d] == missesByWeekday[worst]) continue;
      worst = d;
    }
  }
  if (worst != 0) {
    const names = [
      '', 'Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays',
      'Saturdays', 'Sundays',
    ];
    out.add(Insight(
      InsightKind.pattern,
      '${names[worst]} are your toughest day — planning them lighter or '
      'earlier usually helps.',
    ));
  }

  // 3. Weekend vs weekday — both sides need ≥4 required days of evidence and
  // a ≥25-point gap. Only the POSITIVE side is stated.
  var wdAsked = 0, wdDone = 0, weAsked = 0, weDone = 0;
  for (final v in verdicts) {
    if (v.expectation != ExpectationKind.required) continue;
    if (v.outcome != OutcomeKind.done && v.outcome != OutcomeKind.missed) {
      continue;
    }
    final weekend = v.date.weekday >= 6;
    if (weekend) {
      weAsked++;
      if (v.isHit) weDone++;
    } else {
      wdAsked++;
      if (v.isHit) wdDone++;
    }
  }
  if (wdAsked >= 4 && weAsked >= 4) {
    final wdRate = wdDone / wdAsked;
    final weRate = weDone / weAsked;
    if (weRate - wdRate >= 0.25) {
      out.add(Insight(
        InsightKind.pattern,
        'You complete $trackLabel better on weekends.',
      ));
    } else if (wdRate - weRate >= 0.25) {
      out.add(Insight(
        InsightKind.pattern,
        'Weekdays are your strong ground — weekends drift.',
      ));
    }
  }

  // 4. Week-over-week improvement — only ever stated when true and positive.
  final thisWeek = weekSummary(h, logged: logged, today: today);
  final lastWeek = weekSummary(
    h,
    logged: logged,
    today: DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 7)),
  );
  if (!thisWeek.unknown && !lastWeek.unknown && thisWeek.done > lastWeek.done) {
    out.add(Insight(
      InsightKind.improvement,
      'Your consistency is up on last week — '
      '${thisWeek.done} vs ${lastWeek.done} days.',
    ));
  }

  // 5. Recovery respected — ≥3 prescribed rest days, at most one trained.
  final restDays = verdicts
      .where((v) => v.expectation == ExpectationKind.rest)
      .toList();
  if (restDays.length >= 3) {
    final trained = restDays.where((v) => v.isHit).length;
    if (trained <= 1) {
      out.add(const Insight(
        InsightKind.recovery,
        'Recovery days are being respected — that is part of the program.',
      ));
    }
  }

  return out.take(3).toList();
}
