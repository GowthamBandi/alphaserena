import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/core/domain/workout_session.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/plans/today_workout_section.dart';

/// TODAY'S WORKOUT — the half of My Plans that did not exist.
///
/// My Plans is supposed to answer two questions: what did my coach assign, and
/// what have I completed today. Before this section it answered only the first,
/// so more than half the screen was empty on a device while the member's own
/// logged sets sat in a document nothing on the screen read.
///
/// Every test here pins an HONESTY rule, not a layout: a pending set states no
/// result, a skipped set is not counted as done, a percentage is floored, and a
/// figure that was never recorded is absent rather than zero.

Future<void> _pump(
  WidgetTester tester,
  List<ExerciseLog> exercises, {
  int? durationSeconds,
  NextUp? nextUp,
  Size size = const Size(390, 1400),
  double textScale = 1.0,
  ThemeData? theme,
  List<Map<String, dynamic>> items = const [],
  bool expandAll = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: TodayWorkoutSection(
              exercises: exercises,
              // The ONE engine. This widget is never allowed to compute its own
              // idea of "done", so the test feeds it the same way production does.
              stats: computeSessionStats(exercises),
              durationSeconds: durationSeconds,
              nextUp: nextUp,
              items: items,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Exercises COLLAPSE by default (only the one holding the next set opens),
  // so any test asserting on set-level content must open them first — exactly
  // as a member would.
  if (expandAll) {
    for (final ex in exercises) {
      final header = find.text(ex.name);
      if (header.evaluate().isEmpty) continue;
      await tester.tap(header, warnIfMissed: false);
      await tester.pumpAndSettle();
    }
  }
}

SetLog _set({
  String pReps = '10',
  String pWeight = '20',
  String actualReps = '',
  String actualWeight = '',
  SetLogState state = SetLogState.pending,
  bool edited = false,
}) =>
    SetLog(
      pReps: pReps,
      pWeight: pWeight,
      pRest: '60s',
      actualReps: actualReps,
      actualWeight: actualWeight,
      state: state,
      edited: edited,
    );

ExerciseLog _ex(String name, List<SetLog> sets,
        {bool skipped = false, String reason = ''}) =>
    ExerciseLog(
      name: name,
      exerciseId: 'x',
      sets: sets,
      skipped: skipped,
      skipReason: reason,
    );

void main() {
  group('what the member actually did', () {
    testWidgets('a completed set states the prescription AND the result',
        (tester) async {
      await _pump(tester, [
        _ex('Dumbbell Chest Press', [
          _set(
            actualReps: '12',
            actualWeight: '22.5',
            state: SetLogState.completed,
          ),
        ]),
      ]);

      expect(find.text('Dumbbell Chest Press'), findsOneWidget);
      expect(find.text('Set 1'), findsOneWidget);
      // The coach's words, and the member's, side by side.
      expect(find.text('10 reps × 20 kg'), findsOneWidget);
      expect(find.text('12 reps × 22.5 kg'), findsOneWidget);
    });

    testWidgets(
        'a PENDING set states its target and NO result — never a fabricated one',
        (tester) async {
      await _pump(tester, [
        _ex('Squat', [
          _set(
            pReps: '5',
            pWeight: '80',
            actualReps: '5',
            actualWeight: '80',
            state: SetLogState.completed,
          ),
          // Not reached. Distinct prescription so its row is identifiable.
          _set(pReps: '3', pWeight: '90'),
        ]),
      ]);

      // Set 1 states both halves: the ask, and the result.
      expect(find.text('5 reps × 80 kg'), findsNWidgets(2));
      expect(find.text('Set 2'), findsOneWidget);
      // Set 2 states its prescription EXACTLY ONCE — as the target. A second
      // copy would mean the widget echoed the target into the result column,
      // claiming the member lifted something they have not lifted yet.
      expect(find.text('3 reps × 90 kg'), findsOneWidget);
    });

    testWidgets('a skipped exercise shows the reason the member gave',
        (tester) async {
      await _pump(tester, [
        _ex('Barbell Row', [_set()], skipped: true, reason: 'No equipment'),
      ]);

      expect(find.text('Skipped'), findsOneWidget);
      expect(find.text('No equipment'), findsOneWidget);
    });

    testWidgets('a skipped exercise with NO reason invents none', (tester) async {
      await _pump(tester, [
        _ex('Barbell Row', [_set()], skipped: true),
      ]);

      expect(find.text('Skipped'), findsOneWidget);
      for (final r in kSkipReasons) {
        expect(find.text(r), findsNothing);
      }
    });

    testWidgets('a corrected set is labelled as edited', (tester) async {
      await _pump(tester, [
        _ex('Curl', [
          _set(
            state: SetLogState.completed,
            actualReps: '8',
            actualWeight: '15',
            edited: true,
          ),
        ]),
      ]);
      expect(find.text('edited'), findsOneWidget);
    });
  });

  group('the summary never flatters the member', () {
    testWidgets('17 of 18 sets reads 94%, not a rounded-up 100%',
        (tester) async {
      final sets = [
        for (var i = 0; i < 17; i++)
          // Deliberately UNDER target, so the only 100% this widget could show
          // would be a progress figure it rounded up — adherence cannot supply
          // one and mask the bug.
          _set(state: SetLogState.completed, actualReps: '8', actualWeight: '20'),
        _set(),
      ];
      await _pump(tester, [_ex('Press', sets)]);

      expect(find.text('94%'), findsOneWidget);
      expect(find.text('100%'), findsNothing);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Workout complete'), findsNothing);
    });

    testWidgets('SKIPPED sets count against completion, not toward it',
        (tester) async {
      await _pump(tester, [
        _ex('Press', [
          _set(state: SetLogState.completed, actualReps: '10', actualWeight: '20'),
          _set(state: SetLogState.skipped),
        ]),
      ]);

      // Every set is resolved, so the session is OVER — but it is not COMPLETE.
      expect(find.text('Workout closed'), findsOneWidget);
      expect(find.text('Workout complete'), findsNothing);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('Skipped'), findsOneWidget);
    });

    testWidgets('every prescribed set completed reads complete, at 100%',
        (tester) async {
      await _pump(tester, [
        _ex('Press', [
          _set(state: SetLogState.completed, actualReps: '10', actualWeight: '20'),
          // One set under target: progress is 100% (both sets DONE) while
          // adherence is 50%. The two figures are different questions and the
          // card must not conflate them.
          _set(state: SetLogState.completed, actualReps: '6', actualWeight: '20'),
        ]),
      ]);

      expect(find.text('Workout complete'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget); // progress
      expect(find.text('50%'), findsOneWidget); // adherence
      // Twice, legitimately: the session total ("Sets 2/2") and this one
      // exercise's own count. They coincide only because there is a single
      // exercise; with two they diverge.
      expect(find.text('2/2'), findsNWidgets(2));
      expect(find.text('Sets'), findsOneWidget);
    });
  });

  group('a figure that was never recorded is absent, never zero', () {
    testWidgets('no recorded clock → no Duration row at all', (tester) async {
      await _pump(
        tester,
        [
          _ex('Press', [
            _set(state: SetLogState.completed, actualReps: '10', actualWeight: '20')
          ])
        ],
        durationSeconds: null,
      );
      expect(find.text('Duration'), findsNothing);
      expect(find.text('0m'), findsNothing);
      expect(find.text('0s'), findsNothing);
    });

    testWidgets('a recorded clock renders as h/m, not raw seconds',
        (tester) async {
      await _pump(
        tester,
        [
          _ex('Press', [
            _set(state: SetLogState.completed, actualReps: '10', actualWeight: '20')
          ])
        ],
        durationSeconds: 3900, // 1h 5m
      );
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('1h 5m'), findsOneWidget);
    });

    testWidgets('bodyweight work states NO volume rather than 0 kg',
        (tester) async {
      await _pump(tester, [
        _ex('Push-up', [
          _set(
            pReps: '15',
            pWeight: 'bodyweight',
            actualReps: '15',
            actualWeight: 'bodyweight',
            state: SetLogState.completed,
          ),
        ]),
      ]);
      // Volume is a LOAD metric; there is none here, and "0 kg" would read as a
      // measurement rather than an absence.
      expect(find.text('Volume'), findsNothing);
      expect(find.text('0 kg'), findsNothing);
      // The coach's own word for the weight survives untouched — and is not
      // suffixed with a second unit.
      expect(find.text('15 reps × bodyweight'), findsNWidgets(2));
    });

    testWidgets('nothing completed → NO adherence figure (nothing to judge)',
        (tester) async {
      await _pump(tester, [
        _ex('Press', [_set(state: SetLogState.skipped), _set()]),
      ]);
      expect(find.text('On target'), findsNothing);
    });
  });

  group('the resume point', () {
    testWidgets('names the exact next exercise and set', (tester) async {
      await _pump(
        tester,
        [
          _ex('Bench Press', [
            _set(state: SetLogState.completed, actualReps: '10', actualWeight: '60'),
            _set(),
          ])
        ],
        nextUp: const NextUp(
          exerciseName: 'Bench Press',
          exerciseIndex: 0,
          setNumber: 2,
          totalSets: 4,
          prescribedReps: '10',
          prescribedWeight: '60',
        ),
      );
      expect(
        find.textContaining('Next: Bench Press · set 2 of 4'),
        findsOneWidget,
      );
    });

    testWidgets('is absent when nothing is left', (tester) async {
      await _pump(
        tester,
        [
          _ex('Press', [
            _set(state: SetLogState.completed, actualReps: '10', actualWeight: '20')
          ])
        ],
        nextUp: null,
      );
      expect(find.textContaining('Next:'), findsNothing);
    });
  });

  group('accessibility and layout', () {
    testWidgets('renders at 2.0x text on a 320dp screen without overflow',
        (tester) async {
      await _pump(
        tester,
        [
          _ex('Dumbbell Incline Chest Press', [
            _set(
              pReps: '10-12',
              pWeight: '22.5',
              actualReps: '12',
              actualWeight: '22.5',
              state: SetLogState.completed,
              edited: true,
            ),
            _set(state: SetLogState.skipped),
          ]),
          _ex('Cable Fly', [_set()], skipped: true, reason: 'Pain / discomfort'),
        ],
        size: const Size(320, 2400),
        textScale: 2.0,
        durationSeconds: 2700,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in the light theme', (tester) async {
      await _pump(
        tester,
        [
          _ex('Press', [
            _set(state: SetLogState.completed, actualReps: '10', actualWeight: '20')
          ])
        ],
        theme: AppTheme.light,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Workout complete'), findsOneWidget);
    });
  });

  group('the session is ranked, not dumped', () {
    testWidgets('exercises COLLAPSE — a long session is not a wall of sets',
        (tester) async {
      await _pump(
        tester,
        [
          _ex('Bench Press', [_set(), _set()]),
          _ex('Barbell Row', [_set(), _set()]),
        ],
        expandAll: false,
      );
      // Both are listed with their progress...
      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('Barbell Row'), findsOneWidget);
      // Three times, all legitimate: one per collapsed exercise card, plus the
      // header's own "Exercises 0/2".
      expect(find.text('0/2'), findsNWidgets(3));
      expect(find.text('Exercises'), findsOneWidget);
      // ...and neither dumps its sets.
      expect(find.text('Set 1'), findsNothing);
    });

    testWidgets('the exercise holding the NEXT set opens itself', (tester) async {
      await _pump(
        tester,
        [
          _ex('Bench Press', [
            _set(state: SetLogState.completed, actualReps: '10', actualWeight: '60')
          ]),
          _ex('Barbell Row', [_set(pReps: '8', pWeight: '50'), _set()]),
        ],
        nextUp: const NextUp(
          exerciseName: 'Barbell Row',
          exerciseIndex: 1,
          setNumber: 1,
          totalSets: 2,
          prescribedReps: '8',
          prescribedWeight: '50',
        ),
        expandAll: false,
      );
      // Row is open — its first set's prescription is on screen...
      expect(find.text('8 reps × 50 kg'), findsWidgets);
      // ...while the finished Bench Press stays shut: it is answered.
      expect(find.text('10 reps × 60 kg'), findsNothing);
    });

    testWidgets('a member can open any card, and it stays open', (tester) async {
      await _pump(
        tester,
        [
          _ex('Bench Press', [
            _set(state: SetLogState.completed, actualReps: '10', actualWeight: '60')
          ]),
        ],
        expandAll: false,
      );
      expect(find.text('Set 1'), findsNothing);
      await tester.tap(find.text('Bench Press'));
      await tester.pumpAndSettle();
      expect(find.text('Set 1'), findsOneWidget);
      expect(find.text('10 reps × 60 kg'), findsOneWidget);
    });

    testWidgets('every card announces itself as an expandable control',
        (tester) async {
      await _pump(
        tester,
        [_ex('Bench Press', [_set(), _set()])],
        expandAll: false,
      );
      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(
            RegExp(r'Bench Press, 0 of 2 sets done\. Tap to expand')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('facts the backend serves and this section used to drop', () {
    testWidgets('muscle group and equipment, matched by exerciseId',
        (tester) async {
      await _pump(
        tester,
        [_ex('Dumbbell Chest Press', [_set()])],
        items: const [
          {
            'name': 'Dumbbell Chest Press',
            'exerciseId': 'x',
            'muscleGroup': 'Chest',
            'equipment': 'Dumbbell',
          }
        ],
        expandAll: false,
      );
      expect(find.textContaining('Chest'), findsWidgets);
      expect(find.textContaining('Dumbbell'), findsWidgets);
    });

    testWidgets('NO chips when the library knows nothing', (tester) async {
      await _pump(
        tester,
        [_ex('Freehand Move', [_set()])],
        items: const [],
        expandAll: false,
      );
      expect(find.text('Freehand Move'), findsOneWidget);
      expect(find.textContaining('  ·  '), findsNothing);
    });

    testWidgets("the coach's prescribed REST, shown at last", (tester) async {
      await _pump(tester, [_ex('Press', [_set()])]);
      expect(find.text('rest 60s'), findsOneWidget);
    });
  });
}
