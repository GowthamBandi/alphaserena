import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/core/domain/performance.dart';
import 'package:alphaserena/core/domain/prescription.dart';
import 'package:alphaserena/core/domain/workout_history.dart';
import 'package:alphaserena/core/domain/workout_session.dart';

/// The wire shape `buildSessionEntries` produces, written by hand so these
/// tests assert against the CONTRACT rather than against the writer. If the
/// writer ever drifts from this shape, the round-trip group below fails.
Map<String, dynamic> _set({
  String pReps = '10',
  String pWeight = '20',
  String pRest = '90',
  String actualReps = '',
  String actualWeight = '',
  bool completed = false,
  bool skipped = false,
  bool edited = false,
  int number = 1,
}) =>
    {
      'setNumber': number,
      'prescribedReps': pReps,
      'prescribedWeight': pWeight,
      'prescribedRest': pRest,
      'actualReps': actualReps,
      'actualWeight': actualWeight,
      'completed': completed,
      if (skipped) 'skipped': true,
      if (edited) 'edited': true,
    };

Map<String, dynamic> _doc({
  required DateTime date,
  List<Map<String, dynamic>>? entries,
  String status = kSessionCompleted,
  DateTime? startedAt,
  DateTime? finishedAt,
  int? durationSeconds,
  String planName = 'Workout Plan 11',
  String memberNote = '',
}) =>
    {
      'date': date,
      'planName': planName,
      'planId': 'wp_11',
      'status': status,
      'startedAt': ?startedAt,
      'finishedAt': ?finishedAt,
      'durationSeconds': ?durationSeconds,
      if (memberNote.isNotEmpty) 'memberNote': memberNote,
      'entries': entries ??
          [
            {
              'exerciseName': 'Bench Press',
              'exerciseId': 'ex_1',
              'sets': [
                _set(number: 1, actualReps: '10', actualWeight: '20',
                    completed: true),
                _set(number: 2, actualReps: '9', actualWeight: '20',
                    completed: true),
              ],
            },
          ],
    };

TrackHistory _dailyPlanFrom(DateTime from) => TrackHistory(
      versions: [
        Prescription(
          version: 1,
          effectiveFrom: from,
          startDate: from,
          rhythm: const Rhythm.daily(),
        ),
      ],
    );

TrackHistory _mondaysOnlyFrom(DateTime from) => TrackHistory(
      versions: [
        Prescription(
          version: 1,
          effectiveFrom: from,
          startDate: from,
          rhythm: const Rhythm.weekdays({DateTime.monday}),
        ),
      ],
    );

void main() {
  group('a session document is parsed, never invented', () {
    test('every lifecycle fact comes off the wire', () {
      final started = DateTime(2026, 8, 3, 7, 15);
      final finished = DateTime(2026, 8, 3, 8, 30);
      final log = parseWorkoutDayLog(
        _doc(
          date: DateTime(2026, 8, 3),
          startedAt: started,
          finishedAt: finished,
          durationSeconds: 4500,
          memberNote: 'Shoulder felt tight',
        ),
        'ws_c1_2026-08-03',
      )!;

      expect(log.sessionId, 'ws_c1_2026-08-03');
      expect(log.dayKey, '2026-08-03');
      expect(log.planName, 'Workout Plan 11');
      expect(log.startedAt, started);
      expect(log.finishedAt, finished);
      expect(log.durationSeconds, 4500);
      expect(log.memberNote, 'Shoulder felt tight');
      expect(log.isFinished, isTrue);
    });

    test('a document with no readable date is DROPPED, never placed on today',
        () {
      // Placing an undated session on "today" would invent a training day the
      // member never had — on their streak, their calendar and their coach's
      // screen.
      expect(parseWorkoutDayLog({'entries': []}, 'x'), isNull);
      expect(parseWorkoutDayLog({'date': 'not a date'}, 'x'), isNull);
    });

    test('a zero or absent duration is NULL, never 0', () {
      final a = parseWorkoutDayLog(
          _doc(date: DateTime(2026, 8, 3), durationSeconds: 0), 'a')!;
      final b =
          parseWorkoutDayLog(_doc(date: DateTime(2026, 8, 3)), 'b')!;
      expect(a.durationSeconds, isNull);
      expect(b.durationSeconds, isNull);
    });

    test('stats come from the ONE engine, not a local re-derivation', () {
      final log =
          parseWorkoutDayLog(_doc(date: DateTime(2026, 8, 3)), 'a')!;
      expect(log.stats.completedSets, 2);
      expect(log.stats.totalSets, 2);
      expect(log.stats.isComplete, isTrue);
      // 10x20 + 9x20
      expect(log.stats.volumeKg, 380);
    });

    test('an in-progress session from a past day reads as abandoned', () {
      final log = parseWorkoutDayLog(
        _doc(date: DateTime(2026, 8, 3), status: kSessionInProgress),
        'a',
      )!;
      expect(log.wasAbandonedOn(DateTime(2026, 8, 4)), isTrue);
      // ...but not while its own day is still running.
      expect(log.wasAbandonedOn(DateTime(2026, 8, 3, 23, 59)), isFalse);
      expect(log.isFinished, isFalse);
    });
  });

  group('the entries array round-trips without losing a field', () {
    test('a coach note on an exercise survives an edit', () {
      // THE REGRESSION THIS PINS: `buildSessionEntries` rebuilds the whole
      // array and a merge write replaces an array wholesale, so any field the
      // member app parsed but did not write back would be DELETED the first
      // time a member corrected a rep count. TrainerHQ's `SessionEntry` has
      // read `note` since the model was written.
      final parsed = exercisesFromEntries([
        {
          'exerciseName': 'Squat',
          'exerciseId': 'ex_2',
          'note': 'Keep the bar over mid-foot',
          'sets': [_set(actualReps: '8', completed: true)],
        },
      ]);
      expect(parsed.single.note, 'Keep the bar over mid-foot');

      final rewritten = buildSessionEntries(parsed);
      expect(rewritten.single['note'], 'Keep the bar over mid-foot');
    });

    test('an exercise with no note does not write an empty one', () {
      final parsed = exercisesFromEntries([
        {
          'exerciseName': 'Squat',
          'sets': [_set()],
        },
      ]);
      expect(buildSessionEntries(parsed).single.containsKey('note'), isFalse);
    });

    test('skip, skip reason and the edited flag all survive a rewrite', () {
      final parsed = exercisesFromEntries([
        {
          'exerciseName': 'Deadlift',
          'skipped': true,
          'skipReason': 'Pain / discomfort',
          'sets': [_set(edited: true, completed: true, actualReps: '5')],
        },
      ]);
      final out = buildSessionEntries(parsed).single;
      expect(out['skipped'], isTrue);
      expect(out['skipReason'], 'Pain / discomfort');
      expect((out['sets'] as List).single['edited'], isTrue);
    });
  });

  group('one cell per day, even when a day holds two sessions', () {
    test('the run with more completed work wins', () {
      final light = parseWorkoutDayLog(
        _doc(date: DateTime(2026, 8, 3), entries: [
          {
            'exerciseName': 'A',
            'sets': [_set(actualReps: '1', completed: true)],
          },
        ]),
        'ws_c1_2026-08-03',
      )!;
      final heavy = parseWorkoutDayLog(
        _doc(date: DateTime(2026, 8, 3)),
        'ws_c1_2026-08-03_2',
      )!;

      final indexed = indexWorkoutLogs([light, heavy]);
      expect(indexed.length, 1);
      expect(indexed['2026-08-03']!.sessionId, 'ws_c1_2026-08-03_2');
      // Order of arrival must not decide it.
      expect(indexWorkoutLogs([heavy, light])['2026-08-03']!.sessionId,
          'ws_c1_2026-08-03_2');
    });
  });

  group('the four states the mission asks for', () {
    final month = DateTime(2026, 8, 1);
    final today = DateTime(2026, 8, 10);

    List<WorkoutHistoryDay> compose(
      TrackHistory history,
      Set<String> logged,
      Map<String, WorkoutDayLog> logs,
    ) =>
        composeHistoryMonth(
          cells: monthCells(history, logged: logged, month: month, today: today),
          logsByDay: logs,
        );

    WorkoutHistoryDay dayOf(List<WorkoutHistoryDay> days, int d) =>
        days.firstWhere((x) => x.date.day == d);

    test('every prescribed set done → completed', () {
      final log = parseWorkoutDayLog(_doc(date: DateTime(2026, 8, 3)), 'a')!;
      final days = compose(
        _dailyPlanFrom(DateTime(2026, 8, 1)),
        {'2026-08-03'},
        {'2026-08-03': log},
      );
      expect(dayOf(days, 3).state, WorkoutDayState.completed);
    });

    test('some sets done → partial', () {
      final log = parseWorkoutDayLog(
        _doc(date: DateTime(2026, 8, 3), entries: [
          {
            'exerciseName': 'Bench',
            'sets': [
              _set(number: 1, actualReps: '10', completed: true),
              _set(number: 2),
            ],
          },
        ]),
        'a',
      )!;
      final days = compose(
        _dailyPlanFrom(DateTime(2026, 8, 1)),
        {'2026-08-03'},
        {'2026-08-03': log},
      );
      expect(dayOf(days, 3).state, WorkoutDayState.partial);
    });

    test('a session with NOT ONE completed set → skipped, never missed', () {
      // THE DISTINCTION THAT MATTERS. `sessionCountsAsTrainingDay` deliberately
      // excludes an all-skips session from the logged-day set, so the
      // prescription engine alone resolves this day as MISSED — telling a
      // member who opened their workout and skipped through it that they never
      // showed up. Holding the document is what lets history tell the truth.
      final log = parseWorkoutDayLog(
        _doc(date: DateTime(2026, 8, 3), entries: [
          {
            'exerciseName': 'Bench',
            'sets': [_set(skipped: true), _set(number: 2, skipped: true)],
          },
        ]),
        'a',
      )!;
      final history = _dailyPlanFrom(DateTime(2026, 8, 1));
      // The engine's own answer, with no log in hand:
      final withoutLog = compose(history, const {}, const {});
      expect(dayOf(withoutLog, 3).state, WorkoutDayState.missed);
      // ...and with the document:
      final withLog = compose(history, const {}, {'2026-08-03': log});
      expect(dayOf(withLog, 3).state, WorkoutDayState.skipped);
    });

    test('rest comes from the COACH, resolved for that date', () {
      // A Mondays-only prescription. 2026-08-03 is a Monday, 2026-08-04 is not.
      final days = compose(
        _mondaysOnlyFrom(DateTime(2026, 8, 1)),
        const {},
        const {},
      );
      expect(dayOf(days, 3).state, WorkoutDayState.missed);
      expect(dayOf(days, 4).state, WorkoutDayState.rest);
      expect(dayOf(days, 4).expectation, ExpectationKind.rest);
    });

    test('no prescription at all → unknown, never rest and never missed', () {
      // The platform's DEFAULT state. Reading it as rest would flatter; reading
      // it as missed would accuse. It is neither: nothing was asked and nothing
      // was recorded.
      final days = compose(const TrackHistory(), const {}, const {});
      expect(dayOf(days, 3).state, WorkoutDayState.unknown);
    });

    test('future days stay future, and today stays open', () {
      final days = compose(
        _dailyPlanFrom(DateTime(2026, 8, 1)),
        const {},
        const {},
      );
      expect(dayOf(days, 10).state, WorkoutDayState.today);
      expect(dayOf(days, 11).state, WorkoutDayState.future);
      expect(dayOf(days, 31).state, WorkoutDayState.future);
    });

    test('a bonus session on a rest day is still a completed session', () {
      final log = parseWorkoutDayLog(_doc(date: DateTime(2026, 8, 4)), 'a')!;
      final days = compose(
        _mondaysOnlyFrom(DateTime(2026, 8, 1)),
        {'2026-08-04'},
        {'2026-08-04': log},
      );
      expect(dayOf(days, 4).state, WorkoutDayState.completed);
      // ...and the coach's ask is still carried, so the sheet can say it was a
      // rest day the member trained on.
      expect(dayOf(days, 4).expectation, ExpectationKind.rest);
    });

    test('the month covers every day of the month, and only that month', () {
      final days = compose(const TrackHistory(), const {}, const {});
      expect(days.length, 31);
      expect(days.first.date, DateTime(2026, 8, 1));
      expect(days.last.date, DateTime(2026, 8, 31));
    });

    test('only a day with a session is openable', () {
      final log = parseWorkoutDayLog(_doc(date: DateTime(2026, 8, 3)), 'a')!;
      final days = compose(
        _dailyPlanFrom(DateTime(2026, 8, 1)),
        {'2026-08-03'},
        {'2026-08-03': log},
      );
      expect(dayOf(days, 3).isOpenable, isTrue);
      expect(dayOf(days, 4).isOpenable, isFalse);
    });
  });

  group('calories are a MODEL, and refuse to guess', () {
    test('null without a recorded duration', () {
      expect(
        estimatedWorkoutCalories(durationSeconds: null, bodyWeightKg: 72),
        isNull,
      );
      expect(
        estimatedWorkoutCalories(durationSeconds: 0, bodyWeightKg: 72),
        isNull,
      );
    });

    test('null without the MEMBER\'S OWN body weight', () {
      // The one rule that matters here: this app does not own a body-weight
      // guess. A member who has never entered their weight sees no calorie
      // figure — not one computed from an assumed 70 kg stranger.
      expect(
        estimatedWorkoutCalories(durationSeconds: 3600, bodyWeightKg: null),
        isNull,
      );
      expect(
        estimatedWorkoutCalories(durationSeconds: 3600, bodyWeightKg: 0),
        isNull,
      );
    });

    test('the standard MET formula, and nothing cleverer', () {
      // 5.0 MET x 3.5 x 72 kg / 200 x 60 min = 378 kcal
      final kcal =
          estimatedWorkoutCalories(durationSeconds: 3600, bodyWeightKg: 72);
      expect(kcal, closeTo(378, 0.001));
      // Linear in both inputs — half the time is half the estimate.
      expect(
        estimatedWorkoutCalories(durationSeconds: 1800, bodyWeightKg: 72),
        closeTo(189, 0.001),
      );
    });
  });
}
