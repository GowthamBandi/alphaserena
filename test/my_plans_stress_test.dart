import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena/controllers/food_log_controller.dart';
import 'package:alphaserena/core/domain/workout_session.dart';
import 'package:alphaserena/core/models/nutrition_day_model.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/nutrition/coach_recommended_meals.dart';
import 'package:alphaserena/screens/dashboard/nutrition/food_log_section.dart';
import 'package:alphaserena/screens/dashboard/plans/today_workout_section.dart';

/// STRESS — the sizes a real member can actually reach.
///
/// Every section of My Plans renders inside ONE `ListView` item, so none of
/// them get lazy building for free: a 100-exercise session or a 200-food day is
/// built in a single frame. These tests pin that those sizes render at all, and
/// that they render in a time a phone can absorb.
///
/// The budgets are deliberately loose. They are regression tripwires for an
/// accidental O(n²) — a nested scan, a per-row `firstWhere` over the whole list —
/// not performance targets. A CI machine under load is allowed to be slow; it is
/// not allowed to be quadratic.

class _Log extends FoodLogController {
  _Log(Map<String, FoodEntry> entries) {
    day.value = NutritionDayModel(
      id: 'c1_2026-08-03',
      dateKey: '2026-08-03',
      entries: entries,
    );
    isLoading.value = false;
    loadError.value = false;
  }

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  void ensureFreshDay() {}
}

List<ExerciseLog> _bigSession(int exercises, int setsEach) => [
      for (var e = 0; e < exercises; e++)
        ExerciseLog(
          name: 'Exercise ${e + 1}',
          exerciseId: 'ex$e',
          sets: [
            for (var s = 0; s < setsEach; s++)
              SetLog(
                pReps: '10',
                pWeight: '${20 + s}',
                pRest: '60s',
                actualReps: e.isEven ? '10' : '',
                actualWeight: e.isEven ? '${20 + s}' : '',
                state:
                    e.isEven ? SetLogState.completed : SetLogState.pending,
              ),
          ],
        ),
    ];

Map<String, FoodEntry> _bigDay(int n) => {
      for (var i = 0; i < n; i++)
        'e$i': FoodEntry(
          entryId: 'e$i',
          foodId: 'f$i',
          foodName: 'Food $i',
          mealSlot: const ['breakfast', 'lunch', 'dinner', 'snack'][i % 4],
          quantity: 1,
          unit: 'katori',
          grams: 150,
          loggedAt: DateTime(2026, 8, 3, 8 + (i % 12)).millisecondsSinceEpoch,
          consumed: const ConsumedSnapshot(calories: 120, protein: 8, carbs: 12),
        ),
    };

Future<int> _measure(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  Get.testMode = true;

  final sw = Stopwatch()..start();
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
  sw.stop();
  expect(tester.takeException(), isNull);
  return sw.elapsedMilliseconds;
}

void main() {
  tearDown(Get.reset);

  testWidgets('100 exercises × 4 sets — 400 prescribed sets', (tester) async {
    final logs = _bigSession(100, 4);
    final ms = await _measure(
      tester,
      TodayWorkoutSection(
        exercises: logs,
        stats: computeSessionStats(logs),
        durationSeconds: 3600,
        nextUp: nextUpFrom(logs),
        items: [
          for (var e = 0; e < 100; e++)
            {
              'name': 'Exercise ${e + 1}',
              'exerciseId': 'ex$e',
              'muscleGroup': 'Chest',
              'equipment': 'Dumbbell',
            },
        ],
      ),
    );
    // Collapsed by default, so only the ONE exercise holding the next set
    // expands — the wall of 400 rows is never built at all.
    expect(find.text('Exercise 1'), findsOneWidget);
    expect(find.text('Exercise 100'), findsOneWidget);
    expect(ms, lessThan(8000), reason: '100 exercises took ${ms}ms');
  });

  testWidgets('the served-item lookup does not degrade with plan size',
      (tester) async {
    // `_servedFor` scans `items` per exercise. At 100×100 a careless
    // implementation is 10 000 comparisons per build; this pins that the whole
    // render still lands inside the same budget as the smaller case.
    final logs = _bigSession(100, 4);
    final ms = await _measure(
      tester,
      TodayWorkoutSection(
        exercises: logs,
        stats: computeSessionStats(logs),
        durationSeconds: null,
        nextUp: null,
        items: [
          for (var e = 0; e < 100; e++)
            {'name': 'Exercise ${e + 1}', 'exerciseId': 'ex$e'},
        ],
      ),
    );
    expect(ms, lessThan(8000), reason: 'lookup took ${ms}ms');
  });

  testWidgets('200 logged foods across four meals', (tester) async {
    final ms = await _measure(
      tester,
      FoodLogSection(controller: _Log(_bigDay(200)), showTotals: false),
    );
    expect(find.text('BREAKFAST'), findsOneWidget);
    expect(find.text('Food 0'), findsOneWidget);
    expect(ms, lessThan(12000), reason: '200 foods took ${ms}ms');
  });

  testWidgets('100 prescribed meals', (tester) async {
    final ms = await _measure(
      tester,
      CoachRecommendedMeals(
        items: [
          for (var i = 0; i < 100; i++)
            {
              'name': 'Plan Food $i',
              'foodId': 'f$i',
              'meal': const ['Breakfast', 'Lunch', 'Dinner', 'Snack'][i % 4],
              'calories': 120.0,
              'protein': 8.0,
              'carbs': 12.0,
              'fat': 4.0,
              'grams': 100,
            },
        ],
        // Half already logged — exercises the marker path at scale too.
        loggedFoodIds: {for (var i = 0; i < 100; i += 2) 'f$i'},
      ),
    );
    expect(find.text('BREAKFAST'), findsOneWidget);
    expect(ms, lessThan(12000), reason: '100 plan meals took ${ms}ms');
  });

  testWidgets('a big day and a big plan on screen together', (tester) async {
    // What the Diet tab actually is: the coach's plan AND the member's log.
    final ms = await _measure(
      tester,
      Column(
        children: [
          CoachRecommendedMeals(
            items: [
              for (var i = 0; i < 60; i++)
                {
                  'name': 'Plan Food $i',
                  'foodId': 'f$i',
                  'meal': const ['Breakfast', 'Lunch', 'Dinner'][i % 3],
                  'calories': 120.0,
                }
            ],
            loggedFoodIds: const {'f0', 'f3', 'f6'},
          ),
          FoodLogSection(controller: _Log(_bigDay(120)), showTotals: false),
        ],
      ),
    );
    expect(ms, lessThan(15000), reason: 'combined took ${ms}ms');
  });
}
