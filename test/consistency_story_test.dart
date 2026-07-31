import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/consistency_pair.dart';
import 'package:alphaserena/core/domain/consistency_story.dart';
import 'package:alphaserena/core/domain/performance.dart';
import 'package:alphaserena/core/domain/prescription.dart';
import 'package:alphaserena/core/domain/workout_session.dart';

/// CONSISTENCY AS A STORY — the words, the milestones, the closing line.
///
/// This module exists to make correct numbers feel like something. These tests
/// pin the line between motivating and lying: every figure states its window,
/// an unearned zero is never dressed up as an achievement, and no branch of
/// the copy engine blames the member.
void main() {
  DayVerdict v(
    int daysAgo,
    ExpectationKind e,
    OutcomeKind o,
  ) => DayVerdict(
    date: DateTime(2026, 7, 29).subtract(Duration(days: daysAgo)),
    expectation: e,
    outcome: o,
  );

  MonthCell cell(int day, MonthCellState s) =>
      MonthCell(DateTime(2026, 7, day), s);

  group('the hero — where you stand, and what closes the next win', () {
    StreakHero hero({
      ConsistencyTrack track = ConsistencyTrack.workout,
      ConsistencyCardState state = ConsistencyCardState.active,
      int streak = 2,
      bool weekUnit = false,
      bool hasHistory = true,
      bool loggedToday = false,
    }) => buildStreakHero(
      track: track,
      state: state,
      streak: streak,
      weekUnit: weekUnit,
      hasHistory: hasHistory,
      loggedToday: loggedToday,
    );

    test('states the streak in plain words', () {
      final h = hero(streak: 2);
      expect(h.label, 'Current Streak');
      expect(h.value, '2 Days');
      expect(h.lit, isTrue);
    });

    test('one day is singular', () {
      expect(hero(streak: 1).value, '1 Day');
    });

    test('weeks-on-plan says so', () {
      expect(hero(streak: 3, weekUnit: true).value, '3 Weeks on plan');
      expect(hero(streak: 1, weekUnit: true).value, '1 Week on plan');
    });

    test('the next step is a single obvious action', () {
      // This is the whole goal-gradient mechanism: convert an abstract number
      // into one thing the member can do today.
      expect(hero(streak: 2).nextStep, 'One more workout to reach 3 days.');
      expect(hero(streak: 5).nextStep, '2 more workouts to reach 7 days.');
    });

    test('the next step adapts to the track', () {
      expect(
        hero(track: ConsistencyTrack.nutrition, streak: 2).nextStep,
        'One more day logged to reach 3 days.',
      );
    });

    test('the next step adapts to the weeks unit', () {
      expect(
        hero(streak: 3, weekUnit: true).nextStep,
        'One more week on plan to reach 4 weeks.',
      );
    });

    test('beyond the verifiable window it stops inventing goals', () {
      final h = hero(streak: 60);
      expect(h.nextStep, contains('longest run this app can verify'));
    });

    test('a live streak is encouraged; a done day is acknowledged', () {
      expect(hero(streak: 3).encouragement, 'Keep it going.');
      expect(hero(streak: 3, loggedToday: true).encouragement,
          "Today's already done.");
    });

    test('zero with history is a comeback, not a failure', () {
      expect(hero(streak: 0, hasHistory: true).encouragement,
          'Ready when you are.');
    });

    test('a brand-new member is invited, by track', () {
      expect(hero(streak: 0, hasHistory: false).encouragement,
          'Your first session starts it.');
      expect(
        hero(
          track: ConsistencyTrack.nutrition,
          streak: 0,
          hasHistory: false,
        ).encouragement,
        'Your first log starts it.',
      );
    });

    test('offline reassures and claims no number', () {
      final h = hero(state: ConsistencyCardState.unavailable);
      expect(h.value, '—');
      expect(h.lit, isFalse);
      expect(h.nextStep, contains('Nothing is lost'));
    });

    test('paused says the streak is safe', () {
      final h = hero(state: ConsistencyCardState.paused, streak: 4);
      expect(h.encouragement, 'Your coaching is paused.');
      expect(h.nextStep, contains('streak is safe'));
      expect(h.lit, isFalse);
    });

    test('the spoken label carries the whole hero', () {
      final h = hero(streak: 2);
      expect(h.semanticLabel, contains('Current Streak'));
      expect(h.semanticLabel, contains('2 Days'));
      expect(h.semanticLabel, contains('One more workout'));
    });
  });

  group('adherence — a coaching number, not an attendance number', () {
    test('is hits over hits-plus-misses', () {
      final verdicts = [
        v(1, ExpectationKind.required, OutcomeKind.done),
        v(2, ExpectationKind.required, OutcomeKind.done),
        v(3, ExpectationKind.required, OutcomeKind.missed),
      ];
      expect(adherenceOf(verdicts), closeTo(2 / 3, 0.0001));
    });

    test('rest, excused, paused and open days are OUT of the denominator', () {
      // A member on a four-day plan who hits all four is at 100%, not 57%.
      final verdicts = [
        v(1, ExpectationKind.required, OutcomeKind.done),
        v(2, ExpectationKind.rest, OutcomeKind.excluded),
        v(3, ExpectationKind.paused, OutcomeKind.excluded),
        v(4, ExpectationKind.required, OutcomeKind.excusedByCoach),
        v(0, ExpectationKind.required, OutcomeKind.open),
      ];
      expect(adherenceOf(verdicts), 1.0);
    });

    test('nothing resolved yet reports null, never a fabricated 0%', () {
      expect(adherenceOf([v(0, ExpectationKind.required, OutcomeKind.open)]),
          isNull);
      expect(adherenceOf(const []), isNull);
    });
  });

  group('monthly goal — counted from the engine cells', () {
    test('counts done against done + missed + today', () {
      final cells = [
        cell(1, MonthCellState.done),
        cell(2, MonthCellState.done),
        cell(3, MonthCellState.missed),
        cell(4, MonthCellState.today),
        cell(5, MonthCellState.rest),
        cell(6, MonthCellState.excused),
        cell(7, MonthCellState.future),
      ];
      final g = monthlyGoalOf(cells);
      expect(g.done, 2);
      expect(g.expected, 4);
    });

    test('a month asking nothing reports zero expected, not a divide', () {
      final g = monthlyGoalOf([cell(1, MonthCellState.rest)]);
      expect(g.expected, 0);
    });
  });

  group('achievements — every figure states its window', () {
    List<Achievement> build({
      bool available = true,
      int currentStreak = 5,
      int? longestStreak = 14,
      int totalLogged = 22,
      List<DayVerdict>? verdicts,
      List<MonthCell>? cells,
      bool weekUnit = false,
    }) => buildAchievements(
      track: ConsistencyTrack.workout,
      logsAvailable: available,
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalLogged: totalLogged,
      verdicts: verdicts ??
          [
            v(1, ExpectationKind.required, OutcomeKind.done),
            v(2, ExpectationKind.required, OutcomeKind.done),
            v(3, ExpectationKind.required, OutcomeKind.missed),
          ],
      monthCells: cells ??
          [cell(1, MonthCellState.done), cell(2, MonthCellState.missed)],
      weekUnit: weekUnit,
    );

    test('there are five, in a stable order', () {
      final a = build();
      expect(a.map((x) => x.kind).toList(), [
        AchievementKind.longestStreak,
        AchievementKind.currentStreak,
        AchievementKind.total,
        AchievementKind.adherence,
        AchievementKind.monthly,
      ]);
    });

    test('the longest streak states its 60-day window, never "all time"', () {
      final a = build().first;
      expect(a.value, '14 days');
      expect(a.basis, 'in 60 days');
      expect(a.basis.toLowerCase(), isNot(contains('all time')));
    });

    test('total workouts states its window too', () {
      final a = build()[2];
      expect(a.value, '22');
      expect(a.basis, 'in 60 days');
    });

    test('adherence rounds and carries a bar', () {
      final a = build()[3];
      expect(a.value, '67%');
      expect(a.fraction, closeTo(2 / 3, 0.0001));
    });

    test('the monthly goal is a fraction of the ask', () {
      final a = build().last;
      expect(a.value, '1/2');
      expect(a.fraction, 0.5);
    });

    test('an unearned figure is an em dash, never a zero', () {
      final a = build(currentStreak: 0, longestStreak: 0, totalLogged: 0);
      expect(a[0].value, '—');
      expect(a[1].value, '—');
      expect(a[2].value, '—');
      expect(a[0].isEmpty, isTrue);
    });

    test('unreadable logs blank EVERY tile rather than claim five zeroes', () {
      final a = build(available: false);
      expect(a.length, 5);
      for (final x in a) {
        expect(x.value, '—');
        expect(x.basis, 'unavailable');
      }
    });

    test('the nutrition track renames the total honestly', () {
      final a = buildAchievements(
        track: ConsistencyTrack.nutrition,
        logsAvailable: true,
        currentStreak: 3,
        longestStreak: 9,
        totalLogged: 40,
        verdicts: const [],
        monthCells: const [],
        weekUnit: false,
      );
      expect(a[2].title, 'Days Logged');
    });

    test('weeks-on-plan is reflected in the current-streak tile', () {
      final a = build(currentStreak: 3, weekUnit: true)[1];
      expect(a.value, '3 weeks');
    });
  });

  group('the closing line — earned by the data', () {
    String msg({
      ConsistencyCardState state = ConsistencyCardState.active,
      int streak = 3,
      bool hasHistory = true,
      TrackWeek week = const TrackWeek(done: 2, expected: 5),
      int lastWeekDone = 0,
      double? adherence,
    }) => motivationMessage(
      track: ConsistencyTrack.workout,
      state: state,
      streak: streak,
      hasHistory: hasHistory,
      thisWeek: week,
      lastWeekDone: lastWeekDone,
      adherence: adherence,
    );

    test('a finished week is named before anything else', () {
      expect(msg(week: const TrackWeek(done: 5, expected: 5)),
          'You have done everything your coach asked this week.');
    });

    test('beating last week is the most specific true thing', () {
      expect(msg(week: const TrackWeek(done: 3, expected: 5), lastWeekDone: 2),
          "You're ahead of where you were last week.");
    });

    test('one short of last week is a concrete invitation', () {
      expect(msg(week: const TrackWeek(done: 2, expected: 5), lastWeekDone: 3),
          'One more session and you match last week.');
    });

    test('a week-long streak is named as a habit', () {
      expect(msg(streak: 7), 'A week straight. This is what a habit looks like.');
    });

    test('a brand-new member is invited, not measured', () {
      expect(msg(hasHistory: false, streak: 0),
          contains('Everything starts with one session'));
    });

    test('a strong record protects a single off day', () {
      expect(msg(streak: 0, adherence: 0.9),
          "Your record is strong — one day off doesn't change that.");
    });

    test('offline and paused reassure instead of scoring', () {
      expect(msg(state: ConsistencyCardState.unavailable), contains('safe'));
      expect(msg(state: ConsistencyCardState.paused),
          contains('nothing is lost'));
    });

    test('loading says nothing', () {
      expect(msg(state: ConsistencyCardState.loading), isEmpty);
    });

    test('no branch blames the member', () {
      const forbidden = [
        'failed',
        'you missed',
        'behind',
        'broke',
        'lost your',
        "didn't",
        'should have',
        'only'
      ];
      final all = [
        msg(week: const TrackWeek(done: 5, expected: 5)),
        msg(lastWeekDone: 2, week: const TrackWeek(done: 3, expected: 5)),
        msg(lastWeekDone: 3, week: const TrackWeek(done: 2, expected: 5)),
        msg(streak: 7),
        msg(streak: 1),
        msg(streak: 0, hasHistory: false),
        msg(streak: 0, adherence: 0.9),
        msg(streak: 0, adherence: 0.2),
        msg(state: ConsistencyCardState.paused),
        msg(state: ConsistencyCardState.unavailable),
      ];
      for (final m in all) {
        for (final w in forbidden) {
          expect(m.toLowerCase(), isNot(contains(w)), reason: m);
        }
      }
    });
  });

  group('the tapped day', () {
    test('labels the outcome from the engine verdict', () {
      expect(outcomeLabelFor(v(1, ExpectationKind.required, OutcomeKind.done)),
          'Completed');
      expect(outcomeLabelFor(v(1, ExpectationKind.required, OutcomeKind.missed)),
          'Missed');
      expect(
        outcomeLabelFor(
            v(1, ExpectationKind.required, OutcomeKind.excusedByCoach)),
        'Excused by your coach',
      );
      expect(outcomeLabelFor(v(1, ExpectationKind.rest, OutcomeKind.excluded)),
          'Rest day');
    });

    test('labels every expectation kind', () {
      for (final k in ExpectationKind.values) {
        expect(expectationLabelFor(k), isNotEmpty);
      }
    });

    test('rhythm reasons are not surfaced as exceptions', () {
      // "rhythm" and "frequency" describe the schedule itself, not a coach's
      // exception, so showing them as a "Reason" would misattribute them.
      expect(reasonLabelFor('rhythm'), isEmpty);
      expect(reasonLabelFor('frequency'), isEmpty);
      expect(reasonLabelFor('travel'), 'Travel');
      expect(reasonLabelFor('medical'), 'Medical leave');
    });

    test('session facts come only from a real session', () {
      expect(dayFactsFrom(stats: null, durationSeconds: 900), isEmpty);
    });

    test('a session with no clock states no duration', () {
      const stats = SessionStats(
        completedSets: 9,
        skippedSets: 0,
        totalSets: 9,
        skippedExercises: 0,
        completedExercises: 3,
        volumeKg: 0,
        targetHitPct: 1,
      );
      final f = dayFactsFrom(stats: stats, durationSeconds: null);
      expect(f.map((x) => x.label), isNot(contains('Duration')));
      expect(f.map((x) => x.label), containsAll(['Exercises', 'Sets']));
    });

    test('states duration, exercises, sets and adherence when real', () {
      const stats = SessionStats(
        completedSets: 9,
        skippedSets: 0,
        totalSets: 9,
        skippedExercises: 0,
        completedExercises: 3,
        volumeKg: 800,
        targetHitPct: 0.89,
      );
      final f = {
        for (final x in dayFactsFrom(stats: stats, durationSeconds: 2730))
          x.label: x.value,
      };
      expect(f['Duration'], '45m');
      expect(f['Exercises'], '3');
      expect(f['Sets'], '9/9');
      expect(f['Adherence'], '89%');
    });

    test('a long session reads in hours', () {
      const stats = SessionStats(
        completedSets: 1,
        skippedSets: 0,
        totalSets: 1,
        skippedExercises: 0,
        completedExercises: 1,
        volumeKg: 0,
        targetHitPct: 1,
      );
      final f = dayFactsFrom(stats: stats, durationSeconds: 4500);
      expect(f.first.value, '1h 15m');
    });

    test('adherence is absent when nothing was completed to judge', () {
      const stats = SessionStats(
        completedSets: 0,
        skippedSets: 9,
        totalSets: 9,
        skippedExercises: 3,
        volumeKg: 0,
        targetHitPct: null,
      );
      final f = dayFactsFrom(stats: stats, durationSeconds: 600);
      expect(f.map((x) => x.label), isNot(contains('Adherence')));
    });
  });
}
