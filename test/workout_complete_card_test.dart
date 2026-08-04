import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/core/domain/workout_session.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/plans/workout_complete_card.dart';

SessionStats _stats({
  int completed = 12,
  int total = 12,
  int skipped = 0,
  double volume = 1240,
}) =>
    SessionStats(
      completedSets: completed,
      skippedSets: skipped,
      totalSets: total,
      skippedExercises: 0,
      completedExercises: 4,
      volumeKg: volume,
      targetHitPct: completed == 0 ? null : 1.0,
    );

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 900),
  double textScale = 1.0,
  ThemeData? theme,
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
            child: Padding(padding: const EdgeInsets.all(18), child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('a finished workout says what happened, and offers a way back in', () {
    testWidgets('the four facts the member came for', (tester) async {
      await _pump(
        tester,
        WorkoutCompleteCard(
          stats: _stats(),
          finishedAt: DateTime(2026, 8, 4, 8, 32),
          durationSeconds: 4500, // 1h 15m
          bodyWeightKg: 72,
          onEdit: () {},
        ),
      );
      expect(find.text('Workout Complete'), findsOneWidget);
      expect(find.textContaining('Completed at 8:32 AM'), findsOneWidget);
      expect(find.text('1h 15m'), findsOneWidget);
      expect(find.text('1240 kg'), findsOneWidget);
      // 5.0 MET x 3.5 x 72 / 200 x 75 min = 472.5 -> 473, marked as an estimate.
      expect(find.text('≈473'), findsOneWidget);
      expect(find.text('Edit Workout Log'), findsOneWidget);
    });

    testWidgets('the edit action actually fires', (tester) async {
      // The whole point of this card: the previous build's completion state had
      // no action at all.
      var opened = 0;
      await _pump(
        tester,
        WorkoutCompleteCard(stats: _stats(), onEdit: () => opened++),
      );
      await tester.tap(find.text('Edit Workout Log'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('no edit callback renders no action, not a dead button',
        (tester) async {
      await _pump(tester, WorkoutCompleteCard(stats: _stats()));
      expect(find.text('Edit Workout Log'), findsNothing);
    });
  });

  group('every figure is sourced, or it is absent', () {
    testWidgets('no finishedAt → no claim about when', (tester) async {
      await _pump(
        tester,
        WorkoutCompleteCard(stats: _stats(), durationSeconds: 3600),
      );
      expect(find.textContaining('Completed at'), findsNothing);
      // ...but the sets it DOES know are still stated.
      expect(find.textContaining('12 of 12 sets'), findsOneWidget);
    });

    testWidgets('no recorded duration → no Duration tile, and no "0m"',
        (tester) async {
      await _pump(tester, WorkoutCompleteCard(stats: _stats()));
      expect(find.text('Duration'), findsNothing);
      expect(find.text('0m'), findsNothing);
    });

    testWidgets('bodyweight work → no Volume tile, and no "0 kg"',
        (tester) async {
      // Volume is a LOAD metric. Zero there would read as zero effort.
      await _pump(
        tester,
        WorkoutCompleteCard(stats: _stats(volume: 0), durationSeconds: 3600),
      );
      expect(find.text('Volume'), findsNothing);
      expect(find.text('0 kg'), findsNothing);
    });

    testWidgets('no body weight on file → NO calorie figure at all',
        (tester) async {
      // This app does not own a body-weight guess. A member who has never
      // entered one sees no estimate rather than a number computed from an
      // assumed stranger.
      await _pump(
        tester,
        WorkoutCompleteCard(stats: _stats(), durationSeconds: 3600),
      );
      expect(find.text('Calories'), findsNothing);
      expect(find.textContaining('≈'), findsNothing);
      expect(find.textContaining('estimate'), findsNothing);
    });

    testWidgets('no recorded duration → no calorie figure either',
        (tester) async {
      await _pump(
        tester,
        WorkoutCompleteCard(stats: _stats(), bodyWeightKg: 72),
      );
      expect(find.text('Calories'), findsNothing);
    });

    testWidgets('the calorie estimate explains itself in words, not just "≈"',
        (tester) async {
      await _pump(
        tester,
        WorkoutCompleteCard(
          stats: _stats(),
          durationSeconds: 3600,
          bodyWeightKg: 72,
        ),
      );
      // Two mentions, deliberately: the tile qualifies its own label ("Calories
      // est.") and the sentence below it says what that means. A "≈" alone is
      // punctuation a member can miss.
      expect(find.textContaining('Calories est.'), findsOneWidget);
      expect(
        find.textContaining('estimate from this session'),
        findsOneWidget,
      );
    });
  });

  group('the tick is earned', () {
    testWidgets('a partial finish states its real fraction', (tester) async {
      await _pump(
        tester,
        WorkoutCompleteCard(stats: _stats(completed: 7, total: 12, skipped: 5)),
      );
      expect(find.text('Workout Complete'), findsNothing);
      // 7/12 = 58.33 -> floored to 58, never rounded up.
      expect(find.text('Workout finished — 58% done'), findsOneWidget);
    });

    testWidgets('an abandoned session is not dressed up as a finish',
        (tester) async {
      await _pump(
        tester,
        WorkoutCompleteCard(
          stats: _stats(completed: 3, total: 12),
          abandoned: true,
        ),
      );
      expect(find.text('Workout left unfinished'), findsOneWidget);
      expect(find.text('3 of 12 sets logged'), findsOneWidget);
    });
  });

  group('it survives the screens members actually have', () {
    testWidgets('2.0x text at 320dp does not overflow', (tester) async {
      await _pump(
        tester,
        WorkoutCompleteCard(
          stats: _stats(),
          finishedAt: DateTime(2026, 8, 4, 8, 32),
          durationSeconds: 4500,
          bodyWeightKg: 72,
          onEdit: () {},
        ),
        size: const Size(320, 1600),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('light theme renders', (tester) async {
      await _pump(
        tester,
        WorkoutCompleteCard(stats: _stats(), durationSeconds: 3600),
        theme: AppTheme.light,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
