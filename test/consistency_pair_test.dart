import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/consistency_pair.dart';
import 'package:alphaserena/core/domain/performance.dart';
import 'package:alphaserena/core/domain/prescription.dart';

/// THE HOME CONSISTENCY CARD — two tracks, one rule set.
///
/// After the redesign the card renders exactly five things: track, streak,
/// unit, one line of copy, and seven circles. These tests pin what those five
/// are allowed to say — and, just as importantly, that the two tracks never
/// read each other's data.
void main() {
  final today = DateTime(2026, 7, 29); // Wednesday
  String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  TrackHistory daily({Set<String> excused = const {}}) => TrackHistory(
    versions: [
      Prescription(
        version: 1,
        effectiveFrom: DateTime(2026, 1, 1),
        startDate: DateTime(2026, 1, 1),
        rhythm: const Rhythm.daily(),
      ),
    ],
    excusedDays: excused,
  );

  TrackHistory weekdaysOnly(Set<int> days) => TrackHistory(
    versions: [
      Prescription(
        version: 1,
        effectiveFrom: DateTime(2026, 1, 1),
        startDate: DateTime(2026, 1, 1),
        rhythm: Rhythm.weekdays(days),
      ),
    ],
  );

  ConsistencyCard build({
    ConsistencyTrack track = ConsistencyTrack.workout,
    bool loading = false,
    bool logsAvailable = true,
    TrackHistory? history,
    Set<String> logged = const {},
    TrackWeek week = const TrackWeek(done: 2, expected: 5),
    int streak = 5,
    bool weekUnit = false,
  }) => buildConsistencyCard(
    track: track,
    loading: loading,
    logsAvailable: logsAvailable,
    history: history ?? daily(),
    logged: logged,
    week: week,
    streak: streak,
    weekUnit: weekUnit,
    today: today,
  );

  group('milestones are only offered when they can be verified', () {
    test('the next target is the first rung above the streak', () {
      expect(nextMilestone(0, weekUnit: false)!.target, 3);
      expect(nextMilestone(3, weekUnit: false)!.target, 7);
      expect(nextMilestone(29, weekUnit: false)!.target, 30);
    });

    test('nothing is offered beyond the 60-day fetch window', () {
      // A "100-day streak" goal would be a promise the data cannot keep.
      expect(nextMilestone(60, weekUnit: false), isNull);
      expect(nextMilestone(75, weekUnit: false), isNull);
      expect(kDayMilestones.last, kLogWindowDays);
    });

    test('week milestones stop inside the same window', () {
      expect(nextMilestone(7, weekUnit: true)!.target, 8);
      expect(nextMilestone(8, weekUnit: true), isNull);
      expect(kWeekMilestones.last * 7, lessThanOrEqualTo(kLogWindowDays));
    });

    test('the label counts down in the right unit and pluralises', () {
      expect(nextMilestone(5, weekUnit: false)!.label, '2 days to 7');
      expect(nextMilestone(6, weekUnit: false)!.label, '1 day to 7');
      expect(nextMilestone(3, weekUnit: true)!.label, '1 week to 4');
    });

    test('progress toward the milestone is a real fraction', () {
      expect(nextMilestone(5, weekUnit: false)!.fraction, 5 / 7);
      expect(nextMilestone(0, weekUnit: false)!.fraction, 0);
    });
  });

  group('the two tracks are genuinely independent', () {
    test('each card names itself', () {
      expect(build().title, 'WORKOUT');
      expect(build(track: ConsistencyTrack.nutrition).title, 'NUTRITION');
    });

    test('one track can be paused while the other is active', () {
      expect(build(week: const TrackWeek(paused: true)).state,
          ConsistencyCardState.paused);
      expect(build(track: ConsistencyTrack.nutrition).state,
          ConsistencyCardState.active);
    });

    test('one track can be unreadable while the other is live', () {
      expect(build(logsAvailable: false).state,
          ConsistencyCardState.unavailable);
      expect(build(track: ConsistencyTrack.nutrition).state,
          ConsistencyCardState.active);
    });

    test('the copy adapts to the track for a brand-new member', () {
      expect(build(streak: 0, logged: const {}).motivation,
          'Start your first session.');
      expect(
        build(
          track: ConsistencyTrack.nutrition,
          streak: 0,
          logged: const {},
        ).motivation,
        'Log your first day.',
      );
    });
  });

  group('the one line of copy', () {
    test('a live streak is invited to continue', () {
      expect(build(streak: 5).motivation, 'Keep it going.');
    });

    test('a zero streak with history is a comeback, never a failure', () {
      final c = build(
        streak: 0,
        logged: {key(today.subtract(const Duration(days: 9)))},
      );
      expect(c.motivation, 'Ready when you are.');
    });

    test('a coach-approved rest day is celebrated before any progress', () {
      final c = build(
        history: weekdaysOnly({1, 2, 4, 5}), // Wednesday is rest
        week: const TrackWeek(done: 1, expected: 4),
      );
      expect(c.motivation, 'Rest day. Recovery counts.');
    });

    test('an excused day outranks everything and reads warmly', () {
      final c = build(history: daily(excused: {key(today)}));
      expect(c.motivation, 'Excused today. Costs you nothing.');
    });

    test('a finished week is named', () {
      final c = build(
        logged: {key(today)},
        week: const TrackWeek(done: 5, expected: 5),
      );
      expect(c.motivation, 'Perfect week.');
    });

    test('logging today is acknowledged', () {
      final c = build(
        logged: {key(today)},
        week: const TrackWeek(done: 3, expected: 5),
      );
      expect(c.motivation, 'Done today. Nice.');
    });

    test('paused and offline both reassure', () {
      expect(build(week: const TrackWeek(paused: true)).motivation,
          contains('streak is safe'));
      expect(build(logsAvailable: false).motivation, contains('safe'));
    });

    test('loading says nothing at all', () {
      expect(build(loading: true).motivation, isEmpty);
    });

    test('no line anywhere blames the member', () {
      const forbidden = [
        'failed',
        'you missed',
        'behind',
        'broke',
        'lost your',
        "didn't",
        'should have',
      ];
      final cards = [
        build(streak: 0, logged: const {}),
        build(streak: 0, logged: {key(today.subtract(const Duration(days: 9)))}),
        build(streak: 5),
        build(week: const TrackWeek(paused: true)),
        build(logsAvailable: false),
        build(history: const TrackHistory(), week: const TrackWeek(unknown: true)),
        build(logged: {key(today)}, week: const TrackWeek(done: 5, expected: 5)),
        build(history: weekdaysOnly({1, 2, 4, 5})),
        build(history: daily(excused: {key(today)})),
      ];
      for (final c in cards) {
        final copy = c.motivation.toLowerCase();
        for (final w in forbidden) {
          expect(copy, isNot(contains(w)), reason: 'copy: "$copy"');
        }
      }
    });

    test('the card NEVER says "Logged today"', () {
      for (final c in [
        build(logged: {key(today)}),
        build(logged: {key(today)}, week: const TrackWeek(done: 5, expected: 5)),
        build(streak: 0),
      ]) {
        expect(c.motivation.toLowerCase(), isNot(contains('logged today')));
        expect(c.semanticLabel.toLowerCase(), isNot(contains('logged today')));
      }
    });
  });

  group('honest states', () {
    test('loading claims no number', () {
      final c = build(loading: true);
      expect(c.streakValue, '—');
      expect(c.showWeekRail, isFalse);
    });

    test('unreadable history never reads as a lost streak', () {
      final c = build(logsAvailable: false);
      expect(c.streakValue, '—');
      expect(c.weekLine, 'History unavailable');
      expect(c.semanticLabel, contains('streak is safe'));
    });

    test('no prescription is disclosed and drops the weeks unit', () {
      final c = build(
        history: const TrackHistory(),
        week: const TrackWeek(unknown: true),
        weekUnit: true,
      );
      expect(c.state, ConsistencyCardState.unscheduled);
      expect(c.weekLine, 'No schedule set');
      expect(c.weekUnit, isFalse);
    });

    test('a flexible week counts sessions, not days', () {
      final c = build(
        week: const TrackWeek(done: 2, expected: 4, isFrequency: true),
      );
      expect(c.weekLine, '2 of 4 sessions');
    });

    test('a week that asks nothing says so instead of 0 of 0', () {
      expect(build(week: const TrackWeek(done: 0, expected: 0)).weekLine,
          'Nothing asked this week');
    });

    test('weeks-on-plan pluralises in its own unit', () {
      expect(build(streak: 1, weekUnit: true).streakUnit, 'week on plan');
      expect(build(streak: 6, weekUnit: true).streakUnit, 'weeks on plan');
      expect(build(streak: 6).streakUnit, 'day streak');
    });
  });

  group('the week rail — every state distinct', () {
    test('is Monday-first and seven long', () {
      expect(build().week.length, 7);
    });

    test('a logged past day is done', () {
      final monday = today.subtract(const Duration(days: 2));
      expect(build(logged: {key(monday)}).week.first, TodayMark.done);
    });

    test('a required unlogged ended day is MISSED, distinctly', () {
      // Previously folded into `open`. The detail screen must be able to show
      // it plainly — a member who cannot see a missed day cannot learn from it.
      expect(build(logged: const {}).week.first, TodayMark.missed);
    });

    test('future days are FUTURE, distinct from unknown', () {
      expect(build().week[6], TodayMark.future); // Sunday
      expect(build().week[3], TodayMark.future); // Thursday
    });

    test('today is open while the day is still running', () {
      expect(build(logged: const {}).week[2], TodayMark.open);
    });

    test('a prescribed rest day is rest, never a miss', () {
      final c = build(history: weekdaysOnly({1, 2, 4, 5}));
      expect(c.week[2], TodayMark.rest);
      expect(c.todayChip, 'Rest day');
    });

    test('an excused past day is excused, never a miss', () {
      final monday = today.subtract(const Duration(days: 2));
      expect(build(history: daily(excused: {key(monday)})).week.first,
          TodayMark.excused);
    });

    test('exactly one slot is today', () {
      expect(build().todayIndex, today.weekday - 1);
    });
  });

  group('accessibility', () {
    test('the spoken label describes what is RENDERED', () {
      final c = build(streak: 5);
      expect(c.semanticLabel, contains('Workout consistency: 5 day streak'));
      expect(c.semanticLabel, contains('Keep it going.'));
      expect(c.semanticLabel, contains('2 of 5 this week'));
    });

    test('it does not voice rows the redesign removed', () {
      final c = build(streak: 5);
      expect(c.semanticLabel, isNot(contains('Next:')));
      expect(c.semanticLabel, isNot(contains('% today')));
    });

    test('a rest day speaks its state', () {
      expect(build(history: weekdaysOnly({1, 2, 4, 5})).semanticLabel,
          contains('Today: Rest day'));
    });
  });
}
