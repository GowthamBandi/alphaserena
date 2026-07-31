import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/consistency.dart';

/// THE CONSISTENCY MODEL — every number a coach or member is shown.
///
/// The rules being defended:
///   1. Nothing is estimated. Every field comes from real logged days.
///   2. Days BEFORE the member's first log are not misses. Counting them would
///      make every new member's completion rate look catastrophic.
///   3. TODAY is never a miss. It is in progress until it ends.
///   4. `bestStreak` is the best run within the LOADED window, never "all time".
void main() {
  final now = DateTime(2026, 3, 20); // a Friday
  String k(int daysAgo) {
    final d = now.subtract(Duration(days: daysAgo));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  Set<String> logged(List<int> daysAgo) => daysAgo.map(k).toSet();

  group('no history — the state every new member starts in', () {
    test('an empty set claims nothing', () {
      final s = summarise({}, now);
      expect(s.hasHistory, isFalse);
      expect(s.currentStreak, 0);
      expect(s.bestStreak, 0);
      expect(s.lastMissed, isNull, reason: 'you cannot miss before you start');
      expect(
        s.completionRate,
        isNull,
        reason: '0 of 0 is not 0% — it is no data',
      );
    });

    test('an unreadable source is distinguishable from an empty one', () {
      // null = the read failed (rules/offline); {} = read fine, nothing logged.
      expect(summarise(null, now).hasHistory, isFalse);
    });

    test('the message invites a first log rather than reporting failure', () {
      expect(
        consistencyMessage(summarise({}, now), track: 'workout'),
        'Log your first workout day to start a streak.',
      );
    });
  });

  group('active days — the honest denominator', () {
    test('a member who joined 3 days ago is scored over 3 days, not 365', () {
      // THE RULE THAT MATTERS MOST. Scoring over the window would show a
      // brand-new member "1%" and lose them in week one.
      final s = summarise(logged([2, 1, 0]), now);
      expect(s.activeDays, 3);
      expect(s.totalDone, 3);
      expect(s.completionRate, 1.0);
    });

    test('a perfect week reads 100%, not 7/365', () {
      final s = summarise(logged([6, 5, 4, 3, 2, 1, 0]), now);
      expect(s.activeDays, 7);
      expect(s.completionRate, 1.0);
    });

    test('gaps inside the active span DO count against the rate', () {
      // Logged day 10 and day 0 only → 11 active days, 2 done.
      final s = summarise(logged([10, 0]), now);
      expect(s.activeDays, 11);
      expect(s.totalDone, 2);
      expect(s.completionRate, closeTo(2 / 11, 1e-9));
    });
  });

  group('current streak', () {
    test('counts consecutive days ending today', () {
      expect(summarise(logged([2, 1, 0]), now).currentStreak, 3);
    });

    test('today unlogged does NOT break a live streak', () {
      // Today is in progress. Anchoring on yesterday is what stops the app
      // telling a member at 9am that they have lost a 12-day streak.
      final s = summarise(logged([3, 2, 1]), now);
      expect(s.currentStreak, 3);
      expect(s.doneToday, isFalse);
    });

    test('a gap yesterday ends the streak', () {
      final s = summarise(logged([5, 4, 3, 0]), now);
      expect(s.currentStreak, 1);
    });

    test('the streak is zero when neither today nor yesterday is logged', () {
      expect(summarise(logged([5, 4, 3]), now).currentStreak, 0);
    });
  });

  group('best streak — window-bounded, never "all time"', () {
    test('finds a past run longer than the current one', () {
      final s = summarise(logged([20, 19, 18, 17, 16, 1, 0]), now);
      expect(s.bestStreak, 5);
      expect(s.currentStreak, 2);
    });

    test('reports the window it was computed over', () {
      expect(summarise(logged([1, 0]), now, window: 30).windowDays, 30);
    });
  });

  group('the miss, and the streak it broke', () {
    test('the last missed day and the run before it are both reported', () {
      // Logged 10..5, missed 4, logged 3..0 → last miss 4 days ago, and the
      // member was on 6 days when it broke.
      final s = summarise(logged([10, 9, 8, 7, 6, 5, 3, 2, 1, 0]), now);
      expect(s.lastMissed, now.subtract(const Duration(days: 4)));
      expect(s.streakBeforeLastMiss, 6);
      expect(
        s.recovering,
        isTrue,
        reason: 'they have logged since — that is a comeback, not a lapse',
      );
    });

    test('a member who has not logged since the miss is NOT "recovering"', () {
      final s = summarise(logged([10, 9, 8]), now);
      expect(s.recovering, isFalse);
    });

    test('a perfect member has no lastMissed at all', () {
      final s = summarise(logged([4, 3, 2, 1, 0]), now);
      expect(s.lastMissed, isNull);
      expect(s.streakBeforeLastMiss, 0);
    });

    test('TODAY unlogged is never recorded as the last miss', () {
      // The single most important guilt-avoidance rule.
      final s = summarise(logged([3, 2, 1]), now);
      expect(s.lastMissed, isNull);
    });
  });

  group('windows', () {
    test('last7 and last30 count only inside their window', () {
      final s = summarise(logged([40, 20, 6, 5, 0]), now);
      expect(s.last7, 3);
      expect(s.last30, 4);
    });
  });

  group('calendar', () {
    test('marks done, missed, today and before-start distinctly', () {
      final days = logged([3, 1]);
      final first = firstLoggedDay(days, now);
      final cal = calendar(days, now, count: 5, firstEver: first);

      expect(cal.length, 5);
      // oldest → newest: -4, -3, -2, -1, today
      expect(cal[0].state, DayState.beforeStart, reason: 'before the first log');
      expect(cal[1].state, DayState.done);
      expect(cal[2].state, DayState.missed);
      expect(cal[3].state, DayState.done);
      expect(cal[4].state, DayState.today);
    });

    test('a day before the first log is never a miss', () {
      final days = logged([1]);
      final cal = calendar(
        days,
        now,
        count: 30,
        firstEver: firstLoggedDay(days, now),
      );
      expect(cal.where((d) => d.isMiss).length, 0);
    });

    test('with no history at all, nothing is a miss', () {
      final cal = calendar({}, now, count: 30, firstEver: null);
      expect(cal.every((d) => !d.isMiss), isTrue);
    });

    test('today is always the last entry and never a miss', () {
      final cal = calendar({}, now, count: 7, firstEver: null);
      expect(cal.last.date, DateTime(now.year, now.month, now.day));
      expect(cal.last.isMiss, isFalse);
    });
  });

  group('milestones', () {
    test('the ladder is sparse and reachable', () {
      expect(kStreakMilestones, [3, 7, 14, 30, 60, 100, 365]);
    });

    test('next milestone advances correctly', () {
      expect(nextMilestone(0), 3);
      expect(nextMilestone(3), 7);
      expect(nextMilestone(29), 30);
      expect(nextMilestone(365), isNull, reason: 'nothing left to promise');
    });

    test('reached milestone reports the highest passed', () {
      expect(reachedMilestone(2), isNull);
      expect(reachedMilestone(3), 3);
      expect(reachedMilestone(45), 30);
    });
  });

  group('messaging — never guilt', () {
    const guilt = [
      'failed',
      'fail',
      'lost',
      'broke',
      'broken',
      'missed',
      "didn't",
      'should have',
    ];

    test('no message in any state uses shaming language', () {
      // Shame predicts disengagement; a low-cost re-entry point predicts
      // return. This asserts the product never takes the first path.
      final states = <ConsistencySummary>[
        summarise({}, now),
        summarise(logged([0]), now),
        summarise(logged([2, 1, 0]), now),
        summarise(logged([3, 2, 1]), now),
        summarise(logged([10, 9, 8]), now),
        summarise(logged([10, 9, 8, 7, 6, 5, 3, 2, 1, 0]), now),
      ];
      for (final s in states) {
        final m = consistencyMessage(s, track: 'workout').toLowerCase();
        for (final w in guilt) {
          expect(m.contains(w), isFalse, reason: '"$m" contains "$w"');
        }
      }
    });

    test('a live streak is protected, not celebrated prematurely', () {
      expect(
        consistencyMessage(summarise(logged([3, 2, 1]), now), track: 'workout'),
        'Log today to keep your 3-day streak.',
      );
    });

    test('a lapsed member is shown their best run, not a blank prompt', () {
      // They logged 10..5 (a 6-day run) then stopped. `recovering` is FALSE
      // here — by definition a zero streak means they have missed since their
      // last log — which is exactly why the comeback line must not be gated on
      // it, or it becomes unreachable code.
      final s = summarise(logged([10, 9, 8, 7, 6, 5]), now);
      expect(s.currentStreak, 0);
      expect(s.recovering, isFalse);
      final m = consistencyMessage(s, track: 'nutrition');
      expect(m, contains('6 days'));
      expect(m, contains('again'));
    });

    test('a member with only a trivial past run gets a clean prompt', () {
      final s = summarise(logged([10, 9]), now);
      expect(
        consistencyMessage(s, track: 'workout'),
        'Log today to start a new streak.',
      );
    });

    test('logged today points at the next milestone', () {
      final s = summarise(logged([1, 0]), now);
      expect(consistencyMessage(s, track: 'workout'), 'One more day to hit 3.');
    });
  });
  _phase2();
}

/// ── PHASE 2
/// ── PHASE 2: REST DAYS ────────────────────────────────────────────────────
///
/// The product flaw this closes: a coach prescribing Mon/Tue/Thu/Sat (the
/// ordinary Indian coaching pattern) had a member who followed it PERFECTLY
/// scored as missing three days every week. The system punished compliance.
///
/// A prescribed rest day is now transparent to the streak and absent from the
/// denominator. Where no schedule is assigned the engine behaves exactly as
/// before and reports `scheduled: false`, so the UI can disclose that rather
/// than imply a prescription nobody wrote.
void _phase2() {
  // Fixed Saturday so weekday arithmetic is unambiguous.
  final sat = DateTime(2026, 3, 21);
  String k(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  Set<String> on(List<int> daysAgo) =>
      daysAgo.map((n) => k(sat.subtract(Duration(days: n)))).toSet();

  // Mon(1) Tue(2) Thu(4) Sat(6) — Wed/Fri/Sun are prescribed rest.
  const mtts = WeeklySchedule({
    DateTime.monday,
    DateTime.tuesday,
    DateTime.thursday,
    DateTime.saturday,
  });

  group('PHASE 2 — prescribed rest days', () {
    test('a perfect Mon/Tue/Thu/Sat member is NOT punished for resting', () {
      // Sat(0) Thu(2) Tue(4) Mon(5) — every prescribed day, nothing else.
      final days = on([0, 2, 4, 5]);
      final s = summarise(days, sat, schedule: mtts);
      expect(s.scheduled, isTrue);
      expect(s.lastMissed, isNull, reason: 'they missed nothing they were asked to do');
      expect(s.completionRate, 1.0, reason: 'following the coach exactly is 100%');
    });

    test('the streak SKIPS rest days instead of breaking on them', () {
      // Without this a Mon/Tue/Thu/Sat member could never exceed 2.
      final days = on([0, 2, 4, 5]);
      expect(summarise(days, sat, schedule: mtts).currentStreak, 4);
    });

    test('the same days WITHOUT a schedule read as misses — honestly', () {
      // Unchanged legacy behaviour, and why `scheduled` must be disclosed.
      final s = summarise(on([0, 2, 4, 5]), sat);
      expect(s.scheduled, isFalse);
      expect(s.currentStreak, 1);
      expect(s.lastMissed, isNotNull);
    });

    test('missing a PRESCRIBED day still breaks the streak', () {
      // Skipped Thursday (2 days ago).
      final days = on([0, 4, 5]);
      final s = summarise(days, sat, schedule: mtts);
      expect(s.currentStreak, 1, reason: 'Saturday only');
      expect(s.lastMissed, sat.subtract(const Duration(days: 2)));
    });

    test('the denominator is SCHEDULED days, never calendar days', () {
      // Active span Mon..Sat = 6 calendar days, but only 4 were prescribed.
      final s = summarise(on([0, 2, 4, 5]), sat, schedule: mtts);
      expect(s.activeDays, 4);
      expect(s.totalDone, 4);
    });

    test('a rest day renders as REST on the calendar, never as a miss', () {
      final days = on([0, 2, 4, 5]);
      final cal = calendar(
        days,
        sat,
        count: 7,
        firstEver: firstLoggedDay(days, sat),
        schedule: mtts,
      );
      expect(cal.where((d) => d.isMiss), isEmpty);
      expect(cal.where((d) => d.isRest).length, greaterThan(0));
    });

    test('weekday pattern answers "do they always miss Mondays?"', () {
      // Three weeks of Tue/Thu/Sat logged, both Mondays skipped.
      final days = on([0, 2, 4, 7, 9, 11, 14, 16, 18]);
      final s = summarise(days, sat, schedule: mtts);
      expect(s.missesByWeekday[DateTime.monday], 2);
      expect(s.worstWeekday, DateTime.monday);
    });

    test('a single miss is an EVENT, not a pattern', () {
      // One miss on one weekday must not be reported as a behavioural trend —
      // that would send a coach chasing noise.
      final days = on([0, 2, 4]);
      final s = summarise(days, sat, schedule: mtts);
      expect(s.worstWeekday, isNull);
    });

    test('an EMPTY schedule falls back to daily, never to "no days"', () {
      // A prescription with no training days would otherwise make every day a
      // rest day and every member permanently perfect.
      const empty = WeeklySchedule({});
      final s = summarise(on([0, 1, 2]), sat, schedule: empty);
      expect(s.scheduled, isFalse);
      expect(s.currentStreak, 3);
    });
  });
}
