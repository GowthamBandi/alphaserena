import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/core/domain/consistency_pair.dart';
import 'package:alphaserena/core/domain/consistency_story.dart';
import 'package:alphaserena/core/domain/performance.dart';
import 'package:alphaserena/core/domain/prescription.dart';
import 'package:alphaserena/core/domain/workout_session.dart';

/// WORKOUT CONSISTENCY — THE SOURCE-OF-TRUTH SUITE.
///
/// Every test here pins an invariant that the platform was violating, and each
/// one names the surface it broke. The theme is a single rule:
///
///   **A day the member trained is a day the member trained.**
///
/// Nothing about a coach's paperwork — a prescription that does not exist, a
/// plan that has not started, a pause — may erase a session that actually
/// happened. Expectation and outcome are two separate axes, and the engine had
/// been collapsing them for every member who has no prescription, which is
/// most of the platform.
void main() {
  _bug1();
  // Wednesday 2026-07-29. Every date below is relative to it.
  final today = DateTime(2026, 7, 29);
  String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  DateTime ago(int n) => today.subtract(Duration(days: n));
  Set<String> logged(List<int> daysAgo) => {for (final n in daysAgo) key(ago(n))};

  Prescription presc({
    required Rhythm rhythm,
    DateTime? start,
    DateTime? end,
    int version = 1,
    DateTime? effectiveFrom,
  }) => Prescription(
    version: version,
    effectiveFrom: effectiveFrom ?? DateTime(2026, 1, 1),
    startDate: start ?? DateTime(2026, 1, 1),
    endDate: end,
    rhythm: rhythm,
  );

  // ═════════════════════════════════════════════════════════════════════════
  // 1. THE ROOT CAUSE — a session under no prescription must still be a hit
  // ═════════════════════════════════════════════════════════════════════════
  //
  // `prescription.dart` itself documents `unknown` as "today's state for every
  // member on the platform". Under it, `verdictFor` returned `excluded`
  // WITHOUT EVER CONSULTING `logged` — so a member who trained five days last
  // week saw an empty week strip, an empty 30-day calendar, "—" adherence and
  // "—" monthly goal, beside a streak number that said 5. That contradiction
  // IS the incorrect experience.
  group('a logged day is DONE whatever was asked of it', () {
    test('no prescription at all — a session is still a hit, never excluded', () {
      final v = verdictFor([], ago(1), logged: true, today: today);
      expect(v.expectation, ExpectationKind.unknown);
      expect(v.isHit, isTrue,
          reason: 'the member trained; no paperwork can undo that');
      expect(v.isMiss, isFalse);
    });

    test('an unlogged unknown day is still excluded, never a miss', () {
      final v = verdictFor([], ago(1), logged: false, today: today);
      expect(v.outcome, OutcomeKind.excluded);
      expect(v.isMiss, isFalse);
    });

    test('training before the plan started counts', () {
      final p = [presc(rhythm: const Rhythm.daily(), start: ago(2))];
      final v = verdictFor(p, ago(5), logged: true, today: today);
      expect(v.expectation, ExpectationKind.notYetStarted);
      expect(v.isHit, isTrue);
    });

    test('training after the plan ended counts', () {
      final p = [presc(rhythm: const Rhythm.daily(), end: ago(5))];
      final v = verdictFor(p, ago(2), logged: true, today: today);
      expect(v.expectation, ExpectationKind.ended);
      expect(v.isHit, isTrue);
    });

    test('training through a coaching pause counts', () {
      final pause = PrescriptionException(
        from: ago(10),
        type: ExceptionType.medical,
      );
      final v = verdictFor(
        [presc(rhythm: const Rhythm.daily())],
        ago(3),
        logged: true,
        today: today,
        coachingPause: pause,
      );
      expect(v.expectation, ExpectationKind.paused);
      expect(v.isHit, isTrue,
          reason: 'a session during medical leave is a session');
    });

    test('a paused day with no session stays excluded — streaks freeze', () {
      final pause = PrescriptionException(from: ago(10), type: ExceptionType.pause);
      final v = verdictFor(
        [presc(rhythm: const Rhythm.daily())],
        ago(3),
        logged: false,
        today: today,
        coachingPause: pause,
      );
      expect(v.isExcluded, isTrue);
      expect(v.isMiss, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 2. THE SURFACES — week strip and 30-day calendar for an unscheduled member
  // ═════════════════════════════════════════════════════════════════════════
  group('the unscheduled member sees their own history', () {
    const none = TrackHistory();

    test('the week rail fills the days they trained', () {
      // Mon + Tue of the current week (today is Wednesday).
      final rail = buildWeekRail(none, logged: logged([2, 1]), today: today);
      expect(rail[0], TodayMark.done, reason: 'Monday was trained');
      expect(rail[1], TodayMark.done, reason: 'Tuesday was trained');
      // TODAY IS MARKED AS TODAY, even with nothing asked of the member.
      //
      // This assertion used to expect `unknown`, reasoning that `open` "would
      // imply something is expected of them today, and nothing is", and noting
      // that Home still draws a today-dot from `todayIndex`.
      //
      // The reasoning was sound and the outcome was not, which a real device
      // settled: on the DETAIL screen the only today affordance for an
      // unscheduled day was the faint `isToday` ring, and a member's Thursday
      // rendered indistinguishably from their Wednesday and Friday — while the
      // nutrition track beside it, which had a schedule, marked today clearly.
      // Same member, same week, same screen.
      //
      // `open` is defined as "today, still running — never a miss", and all
      // three clauses are true of an unscheduled day. It does not claim a day
      // was ASKED for: that lives on the expectation axis, which is untouched,
      // and `adherenceOf` / the monthly goal still ignore this day entirely.
      expect(rail[2], TodayMark.open);
      expect(rail[2], isNot(TodayMark.missed));
      expect(rail[3], TodayMark.future);
    });

    test('training today fills today, prescription or not', () {
      final rail = buildWeekRail(none, logged: logged([0]), today: today);
      expect(rail[2], TodayMark.done);
    });

    test('the 30-day timeline marks trained days as hits', () {
      final v = timeline(none, logged: logged([1, 2, 3]), today: today, days: 10);
      expect(v.where((e) => e.isHit).length, 3);
      expect(v.where((e) => e.isMiss).length, 0,
          reason: 'nothing was asked, so nothing can be missed');
    });

    test('the month grid shows trained days as done, not faint unknowns', () {
      final cells = monthCells(
        none,
        logged: logged([1, 2]),
        month: today,
        today: today,
      );
      final done = cells.where((c) => c.state == MonthCellState.done).length;
      expect(done, 2);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 3. SCORING STAYS HONEST — the fix must not fabricate a goal or a rate
  // ═════════════════════════════════════════════════════════════════════════
  //
  // Making an unscheduled session a hit is only safe if every RATIO still
  // measures what its label claims. "Adherence — of days your coach asked
  // for" may not count a day the coach never asked for, in either half.
  group('ratios measure exactly what they claim', () {
    test('adherence ignores days the coach never asked for', () {
      const none = TrackHistory();
      final v = timeline(none, logged: logged([1, 2, 3]), today: today, days: 10);
      expect(adherenceOf(v), isNull,
          reason: 'no required day resolved — 100% would be invented');
    });

    test('adherence over a real prescription counts required days only', () {
      final h = TrackHistory(versions: [
        presc(rhythm: Rhythm.weekdays({DateTime.monday, DateTime.tuesday})),
      ]);
      // Monday trained, Tuesday missed, plus a bonus session on Sunday.
      final v = timeline(
        h,
        logged: logged([2, 3]), // Mon 27th + Sun 26th
        today: today,
        days: 7,
      );
      expect(adherenceOf(v), closeTo(0.5, 0.001),
          reason: '1 of 2 required days; the Sunday bonus is outside the ask');
    });

    test('a monthly goal is never invented for a member with no schedule', () {
      const none = TrackHistory();
      final cells = monthCells(
        none,
        logged: logged([1, 2, 3]),
        month: today,
        today: today,
      );
      expect(monthlyGoalOf(cells).expected, 0,
          reason: 'the coach set no monthly ask');
    });

    test('a bonus rest-day session does not inflate the monthly goal', () {
      final h = TrackHistory(versions: [
        presc(rhythm: Rhythm.weekdays({DateTime.monday})),
      ]);
      final cells = monthCells(
        h,
        logged: logged([2, 3]), // Mon (required) + Sun (rest)
        month: today,
        today: today,
      );
      final g = monthlyGoalOf(cells);
      expect(g.done, lessThanOrEqualTo(g.expected));
      expect(g.expected, greaterThan(0));
      // Every Monday of July that has passed is an ask; the Sunday is not.
      expect(g.done, 1);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 4. ONE ENGINE FOR CURRENT *AND* LONGEST STREAK
  // ═════════════════════════════════════════════════════════════════════════
  //
  // "Longest Streak" was raw calendar-consecutive-day math while "Current
  // Streak" was weeks-on-plan from the engine. A Mon/Wed/Fri member six weeks
  // into a perfect run read: Current 6 weeks · Longest 1 day.
  group('longest streak speaks the same language as current streak', () {
    final mwf = TrackHistory(versions: [
      presc(rhythm: Rhythm.weekdays({
        DateTime.monday,
        DateTime.wednesday,
        DateTime.friday,
      })),
    ]);

    /// Every Mon/Wed/Fri for the last [weeks] weeks, up to and including today.
    Set<String> perfectMwf(int weeks) {
      final out = <String>{};
      for (var i = 0; i <= weeks * 7; i++) {
        final d = ago(i);
        if (d.weekday == DateTime.monday ||
            d.weekday == DateTime.wednesday ||
            d.weekday == DateTime.friday) {
          out.add(key(d));
        }
      }
      return out;
    }

    test('a perfect 4x-week member has a longest streak in WEEKS', () {
      final log = perfectMwf(4);
      final current = weeklyAdherenceStreak(mwf, logged: log, today: today);
      final best = bestWeeklyAdherenceStreak(mwf, logged: log, today: today);
      expect(current, greaterThan(0));
      expect(best, greaterThanOrEqualTo(current),
          reason: 'a best can never be shorter than the run happening now');
    });

    test('the daily best is prescription-aware, not calendar-consecutive', () {
      // Mon/Wed/Fri trained perfectly: calendar-consecutive math says 1.
      final log = perfectMwf(3);
      expect(bestDailyStreak(mwf, logged: log, today: today),
          greaterThan(2),
          reason: 'prescribed rest days are transparent, not breaks');
    });

    test('a real miss caps the best at the longest clean run', () {
      final h = TrackHistory(versions: [presc(rhythm: const Rhythm.daily())]);
      // 5 clean days, a gap, then 2 clean days.
      final log = logged([1, 2, 4, 5, 6, 7, 8]);
      expect(bestDailyStreak(h, logged: log, today: today), 5);
    });

    test('the achievement tile pluralises in the streak unit', () {
      final a = buildAchievements(
        track: ConsistencyTrack.workout,
        logsAvailable: true,
        currentStreak: 3,
        longestStreak: 6,
        totalLogged: 20,
        verdicts: const [],
        monthCells: const [],
        weekUnit: true,
      ).first;
      expect(a.kind, AchievementKind.longestStreak);
      expect(a.value, '6 weeks',
          reason: 'a weeks-on-plan best must not be labelled in days');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 5. WHAT COUNTS AS A TRAINING DAY — ONE definition, live and on re-read
  // ═════════════════════════════════════════════════════════════════════════
  //
  // `hasCompletedWork`'s own doc comment is the contract: "a session that is
  // only skips marks presence for the coach but never a training day". The
  // live optimistic update honoured it; the repository re-read did not, so a
  // skip-only day joined the streak the moment the app was restarted.
  group('a training day means work was actually completed', () {
    Map<String, dynamic> doc(List<Map<String, dynamic>> sets) => {
      'entries': [
        {'exerciseName': 'Bench Press', 'sets': sets},
      ],
    };

    test('a completed set makes it a training day', () {
      expect(
        sessionCountsAsTrainingDay(doc([
          {'setNumber': 1, 'completed': true},
        ])),
        isTrue,
      );
    });

    test('a skip-only session is presence for the coach, not a training day', () {
      expect(
        sessionCountsAsTrainingDay(doc([
          {'setNumber': 1, 'completed': false, 'skipped': true},
          {'setNumber': 2, 'completed': false, 'skipped': true},
        ])),
        isFalse,
      );
    });

    test('an opened-but-untouched session is not a training day', () {
      expect(
        sessionCountsAsTrainingDay(doc([
          {'setNumber': 1, 'completed': false},
        ])),
        isFalse,
      );
    });

    test('the rule matches the in-session rule exactly', () {
      final sets = [
        {'setNumber': 1, 'completed': false, 'skipped': true},
        {'setNumber': 2, 'completed': true},
      ];
      final live = hasCompletedWork(exercisesFromEntries(doc(sets)['entries']));
      expect(sessionCountsAsTrainingDay(doc(sets)), live);
    });

    test('an unreadable/legacy document keeps counting — never a silent erase', () {
      // A shape this parser cannot read must not delete a member's history.
      expect(sessionCountsAsTrainingDay({'entries': null}), isTrue);
      expect(sessionCountsAsTrainingDay({}), isTrue);
      expect(sessionCountsAsTrainingDay(null), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 5b. THE REAL WIRE — the predicate over what the app actually writes
  // ═════════════════════════════════════════════════════════════════════════
  //
  // The tests above hand-write documents. These build them with the PRODUCTION
  // writer, so the predicate is pinned against the bytes that really land in
  // `client_workout_sessions` rather than against a fixture that happens to
  // agree with it.
  group('the predicate holds over documents the app really writes', () {
    ExerciseLog exercise(List<SetLogState> states) => ExerciseLog(
      name: 'Squat',
      exerciseId: 'ex_squat',
      sets: [
        for (final s in states)
          SetLog(pReps: '8', pWeight: '60', pRest: '90', state: s),
      ],
    );

    Map<String, dynamic> wire(List<ExerciseLog> logs) => {
      'entries': buildSessionEntries(logs),
    };

    test('a real completed session round-trips as a training day', () {
      final logs = [
        exercise([SetLogState.completed, SetLogState.completed]),
      ];
      expect(sessionCountsAsTrainingDay(wire(logs)), isTrue);
      expect(hasCompletedWork(logs), isTrue);
    });

    test('a real skip-only session round-trips as NOT a training day', () {
      final logs = [
        exercise([SetLogState.skipped, SetLogState.skipped]),
      ];
      expect(sessionCountsAsTrainingDay(wire(logs)), isFalse);
      expect(hasCompletedWork(logs), isFalse);
    });

    test('one completed set among skips is enough', () {
      final logs = [
        exercise([SetLogState.skipped]),
        exercise([SetLogState.skipped, SetLogState.completed]),
      ];
      expect(sessionCountsAsTrainingDay(wire(logs)), isTrue);
    });

    test('the wire predicate and the live predicate never disagree', () {
      const states = SetLogState.values;
      for (final a in states) {
        for (final b in states) {
          final logs = [exercise([a, b])];
          expect(
            sessionCountsAsTrainingDay(wire(logs)),
            hasCompletedWork(logs),
            reason: 'wire=$a,$b',
          );
        }
      }
    });

    test('two sessions on one day are ONE training day', () {
      // Both runs stamp the same calendar date, so the day-key SET collapses
      // them — a double session cannot inflate a streak.
      final morning = wire([exercise([SetLogState.completed])]);
      final evening = wire([exercise([SetLogState.completed])]);
      final days = <String>{};
      for (final doc in [morning, evening]) {
        if (sessionCountsAsTrainingDay(doc)) days.add(key(today));
      }
      expect(days.length, 1);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 6. HOME AND THE CONSISTENCY SCREEN CANNOT DIVERGE
  // ═════════════════════════════════════════════════════════════════════════
  //
  // Both surfaces build from the same three calls. These pin that the shared
  // inputs produce identical answers, so a future edit to one screen cannot
  // quietly fork the numbers.
  group('Home and the detail screen resolve identically', () {
    final h = TrackHistory(versions: [
      presc(rhythm: Rhythm.weekdays({
        DateTime.monday,
        DateTime.tuesday,
        DateTime.thursday,
      })),
    ]);
    final log = logged([1, 2]);

    test('the week rail is byte-identical on both surfaces', () {
      final home = buildConsistencyCard(
        track: ConsistencyTrack.workout,
        loading: false,
        logsAvailable: true,
        history: h,
        logged: log,
        week: weekSummary(h, logged: log, today: today),
        streak: weeklyAdherenceStreak(h, logged: log, today: today),
        weekUnit: true,
        today: today,
      ).week;
      final detail = buildWeekRail(h, logged: log, today: today);
      expect(home, detail);
    });

    test('the streak expression is the same value on both surfaces', () {
      final streak = weeklyAdherenceStreak(h, logged: log, today: today);
      final card = buildConsistencyCard(
        track: ConsistencyTrack.workout,
        loading: false,
        logsAvailable: true,
        history: h,
        logged: log,
        week: weekSummary(h, logged: log, today: today),
        streak: streak,
        weekUnit: true,
        today: today,
      );
      final hero = buildStreakHero(
        track: ConsistencyTrack.workout,
        state: ConsistencyCardState.active,
        streak: streak,
        weekUnit: true,
        hasHistory: log.isNotEmpty,
        loggedToday: log.contains(key(today)),
      );
      expect(card.streak, hero.streak);
      expect(card.weekUnit, hero.weekUnit);
    });

    test('an unreadable history is a dash on both, never a zero', () {
      final card = buildConsistencyCard(
        track: ConsistencyTrack.workout,
        loading: false,
        logsAvailable: false,
        history: h,
        logged: const {},
        week: const TrackWeek(),
        streak: 0,
        weekUnit: true,
        today: today,
      );
      final hero = buildStreakHero(
        track: ConsistencyTrack.workout,
        state: ConsistencyCardState.unavailable,
        streak: 0,
        weekUnit: true,
        hasHistory: false,
        loggedToday: false,
      );
      expect(card.streakValue, '—');
      expect(hero.value, '—');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 7. BOUNDARIES — month, year, DST, travel
  // ═════════════════════════════════════════════════════════════════════════
  group('calendar boundaries', () {
    test('a streak crosses a month boundary', () {
      final t = DateTime(2026, 8, 2); // Sunday
      final h = TrackHistory(versions: [presc(rhythm: const Rhythm.daily())]);
      final log = {
        for (var i = 0; i < 6; i++)
          () {
            final d = t.subtract(Duration(days: i));
            return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
                '${d.day.toString().padLeft(2, '0')}';
          }(),
      };
      expect(dailyStreak(h, logged: log, today: t), 6,
          reason: 'July 28 → August 2 is one unbroken run');
    });

    test('a streak crosses a year boundary', () {
      final t = DateTime(2027, 1, 2);
      final h = TrackHistory(versions: [presc(rhythm: const Rhythm.daily())]);
      final log = {
        for (var i = 0; i < 5; i++)
          () {
            final d = t.subtract(Duration(days: i));
            return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
                '${d.day.toString().padLeft(2, '0')}';
          }(),
      };
      expect(dailyStreak(h, logged: log, today: t), 5);
    });

    test('the month grid covers every day of a 31-day month', () {
      const none = TrackHistory();
      final cells = monthCells(
        none,
        logged: const {},
        month: DateTime(2026, 7, 15),
        today: DateTime(2026, 7, 31),
      );
      expect(cells.length, 31);
      expect(cells.first.date.day, 1);
      expect(cells.last.date.day, 31);
    });

    test('the month grid covers February in a leap year', () {
      const none = TrackHistory();
      final cells = monthCells(
        none,
        logged: const {},
        month: DateTime(2028, 2, 10),
        today: DateTime(2028, 2, 29),
      );
      expect(cells.length, 29);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// REGRESSION — BUG 1: "Workout Consistency only paints completed days"
//
// Reproduced on a real device (6 Aug 2026, live member): the workout track had
// no prescription, so every unlogged day resolved to `unknown` and the screen
// painted exactly one of the six states its legend advertised. The nutrition
// track beside it, which had a daily prescription, painted all six.
// ═══════════════════════════════════════════════════════════════════════════

void _bug1() {
  final today = DateTime(2026, 8, 6); // Thursday
  String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  Set<String> loggedOn(List<int> back) =>
      {for (final b in back) key(today.subtract(Duration(days: b)))};

  group('BUG 1 — the two tracks share one state rule', () {
    test('identical inputs produce identical marks, whichever track', () {
      // The tracks may only differ by DATA. Given the same history and the same
      // logged days, every single mark must agree — if they ever diverge again,
      // a second engine has been introduced.
      final h = TrackHistory(versions: [
        Prescription.fromMap({
          'rhythm': {'type': 'weekdays', 'weekdays': [1, 2, 3, 4, 5]},
          'effectiveFrom': '2026-01-01',
          'startDate': '2026-01-01',
          'version': 1,
        })!,
      ]);
      final logged = loggedOn([1, 2]);
      final a = buildWeekRail(h, logged: logged, today: today);
      final b = buildWeekRail(h, logged: logged, today: today);
      expect(a, b);
      // …and the month calendar must translate the SAME rule, not a second one.
      for (final cell in monthCells(h, logged: logged, month: today, today: today)) {
        if (cell.date.isAfter(today)) continue;
        final mark = markFor(
          h.verdictOn(cell.date, logged: logged, today: today), today);
        final expected = switch (mark) {
          TodayMark.done => MonthCellState.done,
          TodayMark.missed => MonthCellState.missed,
          TodayMark.open => MonthCellState.today,
          TodayMark.rest => MonthCellState.rest,
          TodayMark.excused => MonthCellState.excused,
          TodayMark.paused => MonthCellState.paused,
          TodayMark.future => MonthCellState.future,
          TodayMark.unknown => MonthCellState.unknown,
        };
        expect(cell.state, expected,
            reason: 'month calendar and heat map disagree on ${cell.date}');
      }
    });

    test('an OPTIONAL day reads the same on both surfaces', () {
      // The one place the three copies had already drifted: only the month
      // calendar treated `optional` as rest.
      final v = DayVerdict(
        date: today.subtract(const Duration(days: 1)),
        expectation: ExpectationKind.optional,
        outcome: OutcomeKind.excluded,
      );
      expect(markFor(v, today), TodayMark.rest);
    });

    test('an unscheduled member still sees TODAY marked', () {
      // The reported symptom, at its root. Without this the member's own day is
      // indistinguishable from the days around it.
      const none = TrackHistory();
      final rail = buildWeekRail(none, logged: loggedOn([2, 1]), today: today);
      expect(rail[today.weekday - 1], TodayMark.open);
    });

    test('A FINISHED PLAN IS NOT AN OPEN DAY — Home and Consistency agree', () {
      // Home renders the server's `ended` resolution as "Plan finished"
      // (todayWorkoutPresentation → dormant). Consistency read the SAME day as
      // `open` — "today, still open" — because `ended` fell into the `_ =>
      // unknown` arm and the today-promotion then filled the gap. One member,
      // one day, two screens, opposite answers.
      final v = DayVerdict(
        date: today,
        expectation: ExpectationKind.ended,
        outcome: OutcomeKind.excluded,
      );
      expect(markFor(v, today), isNot(TodayMark.open),
          reason: 'a plan that has ended asks for nothing today');
      expect(markFor(v, today), TodayMark.unknown);
    });

    test('A PLAN THAT HAS NOT STARTED IS NOT AN OPEN DAY EITHER', () {
      // Same shape: Home says "Starts Monday", Consistency said "still open".
      final v = DayVerdict(
        date: today,
        expectation: ExpectationKind.notYetStarted,
        outcome: OutcomeKind.excluded,
      );
      expect(markFor(v, today), isNot(TodayMark.open));
      expect(markFor(v, today), TodayMark.unknown);
    });

    test('a finished plan reads the same TODAY as it does the day after', () {
      // The defect was specifically the today-promotion, so the proof is that
      // today no longer gets a state its own yesterday does not have.
      DayVerdict ended(DateTime d) => DayVerdict(
            date: d,
            expectation: ExpectationKind.ended,
            outcome: OutcomeKind.excluded,
          );
      expect(markFor(ended(today), today),
          markFor(ended(today.subtract(const Duration(days: 1))), today));
    });

    test('the UNSCHEDULED today promotion still works — the gap it fixed', () {
      // Guard against over-correcting: a member with no prescription at all
      // must still see their own day marked.
      final v = DayVerdict(
        date: today,
        expectation: ExpectationKind.unknown,
        outcome: OutcomeKind.open,
      );
      expect(markFor(v, today), TodayMark.open);
    });

    test('a REST today is still rest, and a PAUSED today still paused', () {
      // The other two definite answers must not regress into `open`.
      expect(
        markFor(
          DayVerdict(
            date: today,
            expectation: ExpectationKind.rest,
            outcome: OutcomeKind.excluded,
          ),
          today,
        ),
        TodayMark.rest,
      );
      expect(
        markFor(
          DayVerdict(
            date: today,
            expectation: ExpectationKind.paused,
            outcome: OutcomeKind.excluded,
          ),
          today,
        ),
        TodayMark.paused,
      );
    });

    test('a member who TRAINED on a finished plan still gets credit', () {
      // `ended` must not swallow a real session — the two-axis rule.
      final v = DayVerdict(
        date: today,
        expectation: ExpectationKind.ended,
        outcome: OutcomeKind.done,
      );
      expect(markFor(v, today), TodayMark.done);
    });

    test('an unscheduled past day is never fabricated into a miss', () {
      // The guard on the fix. Marking today is presentation; inventing a miss
      // for a day nobody asked for would be the defect this engine exists to
      // prevent, and it must stay impossible.
      const none = TrackHistory();
      final rail = buildWeekRail(none, logged: loggedOn([2, 1]), today: today);
      for (final m in rail) {
        expect(m, isNot(TodayMark.missed));
      }
      // …and the scoring axis is untouched: nothing is counted against them.
      final v = timeline(none, logged: loggedOn([2, 1]), today: today, days: 30);
      expect(v.where((d) => d.isMiss), isEmpty);
    });
  });
}
