import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena/controllers/workout_history_controller.dart';
import 'package:alphaserena/core/domain/prescription.dart' show ExpectationKind;
import 'package:alphaserena/core/domain/workout_history.dart';
import 'package:alphaserena/core/domain/workout_session.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/plans/workout_day_log_view.dart';
import 'package:alphaserena/screens/dashboard/plans/workout_history_screen.dart';

WorkoutDayLog _log(
  DateTime date, {
  int completed = 2,
  int total = 2,
  bool skipped = false,
  int? durationSeconds = 3600,
  String memberNote = '',
  String exerciseNote = '',
  String planName = 'Workout Plan 11',
}) =>
    parseWorkoutDayLog(
      {
        'date': date,
        'planName': planName,
        'status': kSessionCompleted,
        'durationSeconds': ?durationSeconds,
        'finishedAt': DateTime(date.year, date.month, date.day, 8, 30),
        if (memberNote.isNotEmpty) 'memberNote': memberNote,
        'entries': [
          {
            'exerciseName': 'Bench Press',
            if (exerciseNote.isNotEmpty) 'note': exerciseNote,
            'sets': [
              for (var i = 0; i < total; i++)
                {
                  'setNumber': i + 1,
                  'prescribedReps': '10',
                  'prescribedWeight': '20',
                  'prescribedRest': '90',
                  'actualReps': i < completed ? '10' : '',
                  'actualWeight': i < completed ? '20' : '',
                  'completed': i < completed,
                  if (skipped && i >= completed) 'skipped': true,
                },
            ],
          },
        ],
      },
      'ws_c1_${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}',
    )!;

/// Overrides only the two things that reach outside: the network read and the
/// composed month. Everything below them — selection, landing day, month
/// summary, the timeline, the day panel — is the REAL controller, so these
/// tests exercise production code rather than a mock of it.
class _FakeHistory extends WorkoutHistoryController {
  _FakeHistory(this._days, {this.prescribed = true});

  final List<WorkoutHistoryDay> _days;
  final bool prescribed;
  int loads = 0;

  @override
  Future<void> load() async {
    loads++;
  }

  @override
  List<WorkoutHistoryDay> get days => _days;

  @override
  bool get hasPrescription => prescribed;
}

/// A whole month built from a state-per-day map, so a test states only the
/// days it cares about.
List<WorkoutHistoryDay> _month(
  DateTime month,
  Map<int, WorkoutDayState> states, {
  Map<int, WorkoutDayLog> logs = const {},
  Map<int, ExpectationKind> expectations = const {},
}) {
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  return [
    for (var d = 1; d <= daysInMonth; d++)
      WorkoutHistoryDay(
        date: DateTime(month.year, month.month, d),
        state: states[d] ?? WorkoutDayState.unknown,
        log: logs[d],
        expectation: expectations[d] ?? ExpectationKind.unknown,
      ),
  ];
}

Future<_FakeHistory> _open(
  WidgetTester tester,
  _FakeHistory controller, {
  Size size = const Size(390, 1400),
  double textScale = 1.0,
  ThemeData? theme,
}) async {
  Get.testMode = true;
  Get.put<WorkoutHistoryController>(controller);
  addTearDown(Get.reset);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    GetMaterialApp(
      theme: theme ?? AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const WorkoutHistoryScreen(),
      ),
    ),
  );
  controller.isLoading.value = false;
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, 1);

  group('the page states what it is, and lets the member move through time',
      () {
    testWidgets('title, month and year are all on screen', (tester) async {
      final c = _FakeHistory(_month(thisMonth, const {}));
      await _open(tester, c);
      expect(find.text('Workout History'), findsOneWidget);
      // The pills print their micro-label in caps ("MONTH" · "August"); the
      // sentence-case string is the accessibility label, not the glyph.
      expect(find.text('MONTH'), findsOneWidget);
      expect(find.text('YEAR'), findsOneWidget);
      expect(find.text('${thisMonth.year}'), findsOneWidget);
    });

    testWidgets('a future month is offered DISABLED, never hidden',
        (tester) async {
      // Hiding them reflows a 12-cell grid to however many months have happened
      // — a grid the member has to re-read every time they change year.
      final c = _FakeHistory(_month(thisMonth, const {}));
      await _open(tester, c);
      if (now.month == 12) return; // no future month exists this year
      await tester.tap(find.text('MONTH'));
      await tester.pumpAndSettle();
      expect(find.text('Dec'), findsOneWidget);
      expect(c.isFutureMonth(now.year, 12), isTrue);
    });

    testWidgets('choosing a month moves the selection with it', (tester) async {
      // Leaving the selection in a month that is no longer on screen left the
      // detail panel describing a date the timeline could not show, and no cell
      // highlighted anywhere — the member's tap appearing to be ignored.
      final c = _FakeHistory(_month(thisMonth, const {}));
      await _open(tester, c);
      c.showMonth(now.year, 1);
      expect(c.month.value.month, 1);
      expect(c.selectedDay.value.month, 1);
    });
  });

  group('the four states are drawn, and only the ones present are explained',
      () {
    testWidgets('the legend shows exactly the states in this month',
        (tester) async {
      final c = _FakeHistory(_month(thisMonth, {
        1: WorkoutDayState.completed,
        2: WorkoutDayState.partial,
        3: WorkoutDayState.skipped,
        4: WorkoutDayState.rest,
      }));
      await _open(tester, c);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Partial'), findsOneWidget);
      expect(find.text('Skipped'), findsOneWidget);
      expect(find.text('Rest'), findsOneWidget);
      // A key for a state that is nowhere on screen implies it is somewhere to
      // be found.
      expect(find.text('Paused'), findsNothing);
      expect(find.text('Excused'), findsNothing);
    });

    testWidgets('a month with nothing in it renders no legend at all',
        (tester) async {
      final c = _FakeHistory(_month(thisMonth, const {}));
      await _open(tester, c);
      expect(find.text('Completed'), findsNothing);
      expect(find.text('Rest'), findsNothing);
    });
  });

  group('tapping a day opens exactly what was logged', () {
    testWidgets('the full session — plan, sets, reps, weight, rest, volume',
        (tester) async {
      final date = DateTime(thisMonth.year, thisMonth.month, 5);
      final c = _FakeHistory(
        _month(
          thisMonth,
          {5: WorkoutDayState.completed},
          logs: {5: _log(date, memberNote: 'Felt strong')},
        ),
      );
      await _open(tester, c);
      c.select(date);
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutDayLogView), findsOneWidget);
      expect(find.text('Workout Plan 11'), findsOneWidget);
      expect(find.text('Bench Press'), findsOneWidget);
      // Prescribed → performed, verbatim, for every set.
      expect(find.text('10 reps × 20 kg'), findsWidgets);
      expect(find.text('rest 90s'), findsWidgets);
      expect(find.text('1h'), findsOneWidget); // 3600s duration
      expect(find.text('400 kg'), findsOneWidget); // 2 x (10 x 20)
      expect(find.text('Felt strong'), findsOneWidget);
    });

    testWidgets('a session with no recorded clock states NO duration',
        (tester) async {
      final date = DateTime(thisMonth.year, thisMonth.month, 5);
      final c = _FakeHistory(
        _month(
          thisMonth,
          {5: WorkoutDayState.completed},
          logs: {5: _log(date, durationSeconds: null)},
        ),
      );
      await _open(tester, c);
      c.select(date);
      await tester.pumpAndSettle();
      expect(find.text('Duration'), findsNothing);
      expect(find.text('0m'), findsNothing);
    });

    testWidgets("a coach's note on an exercise is shown, not dropped",
        (tester) async {
      final date = DateTime(thisMonth.year, thisMonth.month, 5);
      final c = _FakeHistory(
        _month(
          thisMonth,
          {5: WorkoutDayState.completed},
          logs: {5: _log(date, exerciseNote: 'Keep elbows tucked')},
        ),
      );
      await _open(tester, c);
      c.select(date);
      await tester.pumpAndSettle();
      expect(find.text('COACH NOTE'), findsOneWidget);
      expect(find.text('Keep elbows tucked'), findsOneWidget);
    });

    testWidgets('history is READ-ONLY for a past day', (tester) async {
      // The same rule the food log applies: corrections belong to the day they
      // were made on, and a list built for review invites accidental rewrites
      // of days a coach has already read.
      final date = DateTime(thisMonth.year, thisMonth.month, 5);
      final c = _FakeHistory(
        _month(thisMonth, {5: WorkoutDayState.completed},
            logs: {5: _log(date)}),
      );
      await _open(tester, c);
      c.select(date);
      await tester.pumpAndSettle();
      // Only when the selected day is not today.
      if (now.day != 5) {
        expect(find.text('Edit Workout Log'), findsNothing);
      }
    });

    testWidgets("TODAY's session is editable from history", (tester) async {
      final today = DateTime(now.year, now.month, now.day);
      final c = _FakeHistory(
        _month(thisMonth, {now.day: WorkoutDayState.completed},
            logs: {now.day: _log(today)}),
      );
      await _open(tester, c);
      c.select(today);
      await tester.pumpAndSettle();
      expect(find.text('Edit Workout Log'), findsOneWidget);
    });
  });

  group('a day with no session says WHY, from the coach or not at all', () {
    Future<void> pumpState(
      WidgetTester tester,
      WorkoutDayState state, {
      bool prescribed = true,
    }) async {
      // Day 1 is always in the past or today, never future.
      final c = _FakeHistory(
        _month(thisMonth, {1: state}),
        prescribed: prescribed,
      );
      await _open(tester, c);
      c.select(DateTime(thisMonth.year, thisMonth.month, 1));
      await tester.pumpAndSettle();
    }

    testWidgets('rest is the coach prescribing nothing, and says so',
        (tester) async {
      await pumpState(tester, WorkoutDayState.rest);
      expect(find.text('Rest day'), findsOneWidget);
      expect(find.textContaining('Recovery is part of the plan'),
          findsOneWidget);
    });

    testWidgets('paused and excused are named, never counted as misses',
        (tester) async {
      await pumpState(tester, WorkoutDayState.paused);
      expect(find.text('Coaching paused'), findsOneWidget);
    });

    testWidgets('a missed day is stated plainly, without scolding',
        (tester) async {
      await pumpState(tester, WorkoutDayState.missed);
      expect(find.text('No session logged'), findsOneWidget);
    });

    testWidgets('with NO prescription, the app admits it does not know',
        (tester) async {
      // The platform's default state. Reading it as rest would flatter; reading
      // it as missed would accuse.
      await pumpState(tester, WorkoutDayState.unknown, prescribed: false);
      expect(find.text('Nothing recorded'), findsOneWidget);
      expect(
        find.textContaining('has not set a training schedule'),
        findsOneWidget,
      );
    });
  });

  group('honest states', () {
    testWidgets('a failed read is a network apology, never an empty history',
        (tester) async {
      final c = _FakeHistory(_month(thisMonth, const {}));
      Get.testMode = true;
      Get.put<WorkoutHistoryController>(c);
      addTearDown(Get.reset);
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.dark,
          home: const WorkoutHistoryScreen(),
        ),
      );
      c.isLoading.value = false;
      c.loadError.value = true;
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load your history"), findsOneWidget);
      expect(find.textContaining('still saved'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('loading shows a skeleton, never a zero', (tester) async {
      final c = _FakeHistory(_month(thisMonth, const {}));
      Get.testMode = true;
      Get.put<WorkoutHistoryController>(c);
      addTearDown(Get.reset);
      await tester.pumpWidget(
        GetMaterialApp(
          theme: AppTheme.dark,
          home: const WorkoutHistoryScreen(),
        ),
      );
      await tester.pump();
      expect(find.text('Sessions'), findsNothing);
    });
  });

  group('it survives the screens members actually have', () {
    testWidgets('2.0x text at 320dp does not overflow', (tester) async {
      final date = DateTime(thisMonth.year, thisMonth.month, 5);
      final c = _FakeHistory(
        _month(
          thisMonth,
          {
            1: WorkoutDayState.completed,
            2: WorkoutDayState.partial,
            3: WorkoutDayState.skipped,
            4: WorkoutDayState.rest,
            5: WorkoutDayState.completed,
          },
          logs: {5: _log(date, memberNote: 'Felt strong')},
        ),
      );
      await _open(tester, c, size: const Size(320, 3000), textScale: 2.0);
      c.select(date);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('light theme renders', (tester) async {
      final c = _FakeHistory(_month(thisMonth, {1: WorkoutDayState.completed}));
      await _open(tester, c, theme: AppTheme.light);
      expect(tester.takeException(), isNull);
    });
  });
}
