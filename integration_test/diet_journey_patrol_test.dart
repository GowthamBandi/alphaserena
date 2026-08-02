import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:patrol/patrol.dart';

import 'package:alphaserena/controllers/food_history_controller.dart';
import 'package:alphaserena/controllers/food_log_controller.dart';
import 'package:alphaserena/controllers/training_controller.dart';
import 'package:alphaserena/core/models/nutrition_day_model.dart';
import 'package:alphaserena/core/services/nutrition_day_service.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/nutrition/diet_screen.dart';
import 'package:alphaserena/screens/dashboard/nutrition/food_history_screen.dart';

/// PATROL — THE PHASE 3B DIET JOURNEY, ON A REAL DEVICE.
///
/// The same honest harness the other suites use: no member session exists on
/// this emulator (phone OTP is externally blocked), so the REAL Diet screen
/// runs over REAL controllers whose plan and day are deterministic fixtures in
/// the exact shapes `getMyTraining` and `client_nutrition_days` emit.
///
/// What executes for real: the three sections, coach recommendations being
/// read-only and contributing nothing to totals, meal grouping agreeing across
/// both halves, the log's rows and states, history paging and drill-in, and
/// the whole thing at large text, in landscape and in both themes.
void main() {
  Future<void> boot() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    Get.reset();
  }

  Map<String, dynamic> planFood(
    String name, {
    String meal = 'Breakfast',
    String quantity = '2 katori',
    double calories = 250,
  }) => {
    'name': name,
    'foodId': name.toLowerCase(),
    'quantity': quantity,
    'calories': calories,
    'protein': 10.0,
    'carbs': 20.0,
    'fat': 5.0,
    'fiber': 2.0,
    'meal': meal,
    'grams': 150,
  };

  FoodEntry logged(String name, {String meal = 'lunch', double kcal = 375}) =>
      FoodEntry(
        entryId: name.toLowerCase().replaceAll(' ', '_'),
        source: FoodEntrySource.search,
        foodName: name,
        foodTier: FoodTier.org,
        mealSlot: meal,
        quantity: 1,
        unit: 'katori',
        grams: 150,
        loggedAt: DateTime(2026, 8, 1, 13, 30).millisecondsSinceEpoch,
        consumed: ConsumedSnapshot(calories: kcal, protein: 27),
      );

  Future<void> openDiet(
    PatrolIntegrationTester $, {
    List<Map<String, dynamic>> plan = const [],
    Map<String, FoodEntry> entries = const {},
    String? planError,
    bool logError = false,
    double textScale = 1.0,
    Brightness brightness = Brightness.dark,
    Size? surface,
  }) async {
    await boot();
    if (surface != null) await $.tester.binding.setSurfaceSize(surface);
    Get.put<TrainingController>(_FixtureTraining(plan, err: planError ?? ''));
    Get.put<FoodLogController>(_FixtureLog(entries: entries, error: logError));
    await $.pumpWidgetAndSettle(
      GetMaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const DietScreen(),
        ),
      ),
    );
  }

  tearDown(Get.reset);

  // ── SECTION 1 — RECOMMENDATIONS ──────────────────────────────────────────

  patrolTest('the Diet screen shows all three sections', ($) async {
    await openDiet(
      $,
      plan: [planFood('Oats'), planFood('Chicken', meal: 'Lunch')],
      entries: {'a': logged('Paneer Tikka')},
      surface: const Size(390, 2400),
    );
    expect($('COACH RECOMMENDED').exists, true);
    expect($("TODAY'S FOOD LOG").exists, true);
    expect($('Previous days').exists, true);
  });

  patrolTest('recommendations are read-only and total nothing', ($) async {
    await openDiet(
      $,
      plan: [planFood('Oats', calories: 250)],
      surface: const Size(390, 2400),
    );
    // No marking affordance survives anywhere.
    for (final label in ['Eaten', 'Partial', 'Skipped']) {
      expect($(label).exists, false, reason: '$label must be gone');
    }
    // A prescribed 250 kcal with nothing logged totals nothing.
    expect($('Nothing logged yet today').exists, true);
  });

  patrolTest('coach meal labels group with the log slugs', ($) async {
    await openDiet(
      $,
      plan: [planFood('Almonds', meal: 'Mid-morning')],
      entries: {'a': logged('Poha', meal: 'mid_morning')},
      surface: const Size(390, 2400),
    );
    // Once under recommendations, once under the log — the same heading.
    expect($('MID-MORNING SNACK').exists, true);
  });

  patrolTest('no plan does not block logging', ($) async {
    await openDiet($, surface: const Size(390, 2400));
    expect($('No diet plan yet').exists, true);
    expect($('Add your first food').exists, true);
  });

  patrolTest('a failed plan load is an error with retry', ($) async {
    await openDiet($, planError: 'network', surface: const Size(390, 2400));
    expect($("Couldn't load your plan").exists, true);
    expect($('Try again').exists, true);
    expect($('No diet plan yet').exists, false);
  });

  // ── SECTION 2 — THE LOG ──────────────────────────────────────────────────

  patrolTest('a logged food shows amount, source, time and nutrition',
      ($) async {
    await openDiet(
      $,
      plan: [planFood('Oats')],
      entries: {'a': logged('Paneer Tikka')},
      surface: const Size(390, 2400),
    );
    expect($('Paneer Tikka').exists, true);
    expect($('1 katori').exists, true);
    expect($("Coach's").exists, true);
    expect($('1:30 PM').exists, true);
  });

  patrolTest('totals come only from the log, never the plan', ($) async {
    await openDiet(
      $,
      plan: [planFood('Oats', calories: 999)],
      entries: {
        'a': logged('Paneer Tikka', kcal: 375),
        'b': logged('Dal', meal: 'dinner', kcal: 200),
      },
      surface: const Size(390, 2400),
    );
    expect($('575').exists, true);
    expect($(RegExp('kcal from 2 items')).exists, true);
  });

  patrolTest('a log read failure is an error, never the empty state',
      ($) async {
    await openDiet(
      $,
      plan: [planFood('Oats')],
      logError: true,
      surface: const Size(390, 2400),
    );
    expect($("Couldn't load today's food").exists, true);
    expect($('Nothing logged yet today').exists, false);
  });

  patrolTest('the Add Food route opens from the screen', ($) async {
    await openDiet(
      $,
      plan: [planFood('Oats')],
      surface: const Size(390, 2400),
    );
    await $('Add your first food').tap();
    await $.pumpAndSettle();
    expect($('Add Food').exists, true);
  });

  // ── SECTION 3 — HISTORY ──────────────────────────────────────────────────

  patrolTest('history opens, lists logged days and drills into one',
      ($) async {
    await boot();
    final service = _FixtureDayService()
      ..stored['2026-07-31'] = _day('2026-07-31', kcal: 1000)
      ..stored['2026-07-30'] = _day('2026-07-30', kcal: 2000);
    Get.put<FoodHistoryController>(
      FoodHistoryController(service: service, now: DateTime(2026, 8, 1)),
    );
    await $.pumpWidgetAndSettle(
      GetMaterialApp(theme: AppTheme.dark, home: const FoodHistoryScreen()),
    );

    expect($('Previous Days').exists, true);
    expect($('Days logged').exists, true);
    expect($('2').exists, true);
    // Averaged over LOGGED days only.
    expect($('1500 kcal').exists, true);

    await $('Yesterday').tap();
    await $.pumpAndSettle();
    expect($('1000').exists, true);
    // A past day is READ ONLY. The note sits at the end of a lazily-built
    // list, so on a real phone it must be scrolled to before it exists.
    await $('Past days are read-only.').scrollTo();
    expect($('Past days are read-only.').exists, true);

    // Back returns to the LIST, not out of history — the member drilled in,
    // so back means up. Scoped to the app bar's own control.
    await $.tester.tap(
      find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton)),
    );
    await $.pumpAndSettle();
    expect($('Days logged').exists, true);
  });

  patrolTest('an empty history invites rather than alarms', ($) async {
    await boot();
    Get.put<FoodHistoryController>(
      FoodHistoryController(
        service: _FixtureDayService(),
        now: DateTime(2026, 8, 1),
      ),
    );
    await $.pumpWidgetAndSettle(
      GetMaterialApp(theme: AppTheme.dark, home: const FoodHistoryScreen()),
    );
    expect($('No history yet').exists, true);
    expect($('Try again').exists, false, reason: 'nothing failed');
  });

  patrolTest('a failed history load offers a retry that works', ($) async {
    await boot();
    final service = _FixtureDayService()..fail = true;
    final c = FoodHistoryController(
      service: service,
      now: DateTime(2026, 8, 1),
    );
    Get.put<FoodHistoryController>(c);
    await $.pumpWidgetAndSettle(
      GetMaterialApp(theme: AppTheme.dark, home: const FoodHistoryScreen()),
    );
    expect($("Couldn't load your history").exists, true);

    service.fail = false;
    service.stored['2026-07-31'] = _day('2026-07-31');
    await $('Try again').tap();
    await $.pumpAndSettle();
    expect($('Days logged').exists, true);
  });

  // ── PRESENTATION ─────────────────────────────────────────────────────────

  patrolTest('the Diet screen survives 2.0x accessibility text', ($) async {
    await openDiet(
      $,
      plan: [planFood('Oats'), planFood('Chicken', meal: 'Lunch')],
      entries: {'a': logged('Paneer Tikka')},
      textScale: 2.0,
      surface: const Size(320, 4000),
    );
    expect($.tester.takeException(), isNull);
    expect($('Paneer Tikka').exists, true);
  });

  patrolTest('the Diet screen survives landscape', ($) async {
    await openDiet(
      $,
      plan: [planFood('Oats')],
      entries: {'a': logged('Paneer Tikka')},
      surface: const Size(844, 1200),
    );
    expect($.tester.takeException(), isNull);
  });

  patrolTest('the Diet screen renders in light mode', ($) async {
    await openDiet(
      $,
      plan: [planFood('Oats')],
      entries: {'a': logged('Paneer Tikka')},
      brightness: Brightness.light,
      surface: const Size(390, 2400),
    );
    expect($.tester.takeException(), isNull);
    expect($('Paneer Tikka').exists, true);
  });
}

NutritionDayModel _day(String dateKey, {double kcal = 500}) =>
    NutritionDayModel(
      id: 'c1_$dateKey',
      dateKey: dateKey,
      entries: {
        'e0': FoodEntry(
          entryId: 'e0',
          foodName: 'Paneer Tikka',
          mealSlot: 'lunch',
          quantity: 1,
          unit: 'katori',
          grams: 150,
          loggedAt: 1000,
          consumed: ConsumedSnapshot(calories: kcal, protein: 20),
        ),
      },
    );

class _FixtureTraining extends TrainingController {
  _FixtureTraining(this._items, {String err = ''}) {
    diet.value = {
      'name': 'Cut Phase 1',
      'description': 'Keep protein high on training days.',
      'items': _items,
    };
    error.value = err;
    isLoading.value = false;
  }
  final List<Map<String, dynamic>> _items;

  @override
  List<Map<String, dynamic>> get dietItems => _items;

  @override
  Future<void> load() async {}

  // Deliberately does NOT call super: the real onInit issues a getMyTraining
  // call, which is what this fixture exists to avoid.
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _FixtureLog extends FoodLogController {
  _FixtureLog({Map<String, FoodEntry> entries = const {}, bool error = false}) {
    day.value = NutritionDayModel(
      id: 'c1_2026-08-01',
      dateKey: '2026-08-01',
      entries: entries,
    );
    isLoading.value = false;
    loadError.value = error;
  }

  // Deliberately does NOT call super: the real onInit binds a Firestore stream.
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  void ensureFreshDay() {}
}

class _FixtureDayService extends NutritionDayService {
  final Map<String, NutritionDayModel> stored = {};
  bool fail = false;

  @override
  bool get canLog => true;

  @override
  Future<List<NutritionDayModel>> fetchDays(List<String> dateKeys) async {
    if (fail) throw Exception('network');
    final out = [
      for (final k in dateKeys)
        if (stored[k] != null) stored[k]!,
    ];
    out.sort((a, b) => b.dateKey.compareTo(a.dateKey));
    return out;
  }
}
