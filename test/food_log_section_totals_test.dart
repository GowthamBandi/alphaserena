import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena/controllers/food_log_controller.dart';
import 'package:alphaserena/core/models/nutrition_day_model.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/nutrition/food_log_section.dart';

/// ONE STATEMENT OF THE DAY'S TOTALS PER SCREEN.
///
/// `FoodLogSection` is rendered on TWO surfaces now — the Diet screen, where its
/// "Logged today" card is the only statement of the day's totals, and My Plans,
/// where `NutritionProgressCard` states the same four macros *against the
/// coach's targets* immediately above it.
///
/// Reusing the section wholesale on My Plans therefore printed 1005 kcal,
/// protein, carbs, fat and fiber twice, a few hundred pixels apart, the second
/// time with less information. Caught on a device screenshot during this pass —
/// a duplication introduced by the very change that removed another one.
///
/// The MEALS are identical on both surfaces and must stay that way: they are
/// the reason the section is shared at all.
class _FakeLog extends FoodLogController {
  _FakeLog({bool queued = false}) {
    day.value = NutritionDayModel(
      id: 'c1_2026-08-03',
      dateKey: '2026-08-03',
      entries: {
        'e1': FoodEntry(
          entryId: 'e1',
          foodName: 'Paneer Tikka',
          mealSlot: 'lunch',
          quantity: 1,
          unit: 'katori',
          grams: 150,
          loggedAt: DateTime(2026, 8, 3, 13, 30).millisecondsSinceEpoch,
          consumed: const ConsumedSnapshot(calories: 375, protein: 27),
        ),
      },
    );
    isLoading.value = false;
    loadError.value = false;
    hasQueuedWrites.value = queued;
  }

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  void ensureFreshDay() {}
}

Future<void> _pump(
  WidgetTester tester, {
  required bool showTotals,
  bool queued = false,
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  Get.testMode = true;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: FoodLogSection(
            controller: _FakeLog(queued: queued),
            showTotals: showTotals,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  testWidgets('the Diet screen keeps its totals card — it is the only one',
      (tester) async {
    await _pump(tester, showTotals: true);
    expect(find.text('Logged today'), findsOneWidget);
    expect(find.text('375'), findsOneWidget);
    expect(find.text('kcal from 1 item'), findsOneWidget);
  });

  testWidgets('My Plans suppresses the totals card — the ring above states them',
      (tester) async {
    await _pump(tester, showTotals: false);
    expect(find.text('Logged today'), findsNothing);
    expect(find.text('kcal from 1 item'), findsNothing);
    // Nor the macro row that card carries.
    expect(find.text('Protein'), findsNothing);
    expect(find.text('Fiber'), findsNothing);
  });

  testWidgets('the MEALS are identical either way — that is the shared part',
      (tester) async {
    for (final show in [true, false]) {
      await _pump(tester, showTotals: show);
      expect(find.text('LUNCH'), findsOneWidget, reason: 'showTotals=$show');
      expect(find.text('Paneer Tikka'), findsOneWidget, reason: '$show');
      // Twice, legitimately: the LUNCH header's total and the single food's
      // own figure, which coincide because lunch holds one item.
      expect(find.text('375 kcal'), findsNWidgets(2), reason: '$show');
      // The per-meal figure and time survive; they are not part of the totals.
      expect(find.text('1:30 PM'), findsOneWidget, reason: '$show');
    }
  });

  testWidgets(
      'hiding the totals must NOT hide that writes are still queued offline',
      (tester) async {
    // "Syncing" normally lives on the totals card. Losing it would drop the
    // member's only assurance that food logged offline is safe.
    await _pump(tester, showTotals: false, queued: true);
    expect(find.text('Syncing'), findsOneWidget);
    expect(find.text('Logged today'), findsNothing);
  });

  testWidgets('no "Syncing" claim when nothing is queued', (tester) async {
    await _pump(tester, showTotals: false, queued: false);
    expect(find.text('Syncing'), findsNothing);
  });
}
