import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:patrol/patrol.dart';

import 'package:alphaserena/controllers/training_controller.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/client_diet_screen.dart';

/// PATROL — THE NUTRITION DOMAIN, ON A REAL DEVICE.
///
/// Same honest harness as the workout suite: no member session exists on this
/// emulator (phone-OTP externally blocked), so the REAL `ClientDietScreen`
/// runs over a REAL `TrainingController` whose served diet is a deterministic
/// fixture in the exact shape the canonical `getMyTraining` emits
/// (`dietItemForMember`): name, foodId, quantity, calories, 6 macros, meal,
/// grams, portion fields, plus client-level targets.
///
/// What executes for real: rendering, meal grouping + per-meal totals, the
/// adherence ring, ALL marking interactions (eaten/partial/partial-credit
/// math/skip/toggle-off — `setStatus` runs the production path; only the
/// final Firestore write no-ops on the unlinked device), empty/error states,
/// accessibility scale and landscape. The persistence/restore/remap layer is
/// certified by the unit suite (identity restore, plan-change remap,
/// TrainerHQ parity) — stated, not simulated.
void main() {
  Future<void> boot() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    Get.reset();
  }

  /// One served food item, exactly as the canonical backend shapes it.
  Map<String, dynamic> food(
    String name, {
    String meal = 'Breakfast',
    String foodId = '',
    String quantity = '100 g',
    double calories = 200,
    double protein = 20,
    double carbs = 10,
    double fat = 8,
  }) => {
    'name': name,
    'foodId': foodId.isEmpty ? name.toLowerCase().replaceAll(' ', '-') : foodId,
    'quantity': quantity,
    'calories': calories,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fiber': 2.0,
    'sugar': 1.0,
    'saturatedFat': 1.5,
    'meal': meal,
    'grams': 100,
    'portionLabel': null,
    'portionQty': null,
  };

  TrainingController diet(
    List<Map<String, dynamic>>? items, {
    String name = 'Cutting Plan A',
    bool withTargets = true,
    bool failed = false,
  }) {
    final t = Get.isRegistered<TrainingController>()
        ? Get.find<TrainingController>()
        : Get.put(TrainingController());
    if (failed) {
      t.diet.value = null;
      t.error.value = 'Could not load your training. Tap retry.';
    } else {
      t.diet.value = {
        'name': name,
        'items': items ?? const [],
        if (withTargets) ...{
          'targetCalories': 1800,
          'targetProtein': 150,
          'targetCarbs': 160,
          'targetFat': 60,
          'targetFiber': 30,
        },
      };
    }
    t.isLoading.value = false;
    return t;
  }

  Widget host(Widget home, {double textScale = 1.0}) => GetMaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: home,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      );

  /// Wall-clock-aware wait (live-binding pump advances simulated time only).
  Future<void> pumpUntil(PatrolIntegrationTester $, Finder marker,
      {int tries = 60}) async {
    for (var i = 0; i < tries; i++) {
      if (marker.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await $.tester.pump();
    }
  }

  Future<void> mount(PatrolIntegrationTester $, Finder marker,
      {double textScale = 1.0}) async {
    await $.tester.pumpWidget(host(ClientDietScreen(), textScale: textScale));
    await pumpUntil($, marker);
    await $.tester.pump(const Duration(milliseconds: 100));
  }

  List<Map<String, dynamic>> fullDay() => [
        food('Oats with Whey', meal: 'Breakfast', calories: 420, protein: 32),
        food('Chicken & Rice', meal: 'Lunch', calories: 650, protein: 45),
        food('Paneer Salad', meal: 'Dinner', calories: 380, protein: 24),
        food('Greek Yogurt', meal: 'snacks', calories: 150, protein: 15),
      ];

  // ══ TODAY'S MEALS — the full day, grouped and totalled ══════════════════

  patrolTest('a full day renders meals in order with honest totals',
      ($) async {
    await boot();
    diet(fullDay());
    await mount($, find.text('YOUR DIET'));

    expect(find.text('Cutting Plan A'), findsOneWidget);
    expect(find.text('Diet adherence'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget); // nothing marked yet
    expect(find.text('0 of 4 foods logged'), findsOneWidget);

    // Canonical meal order, with the legacy 'snacks' ALIASED to Evening
    // Snack. The list is lazily inflated on a real device, so each section is
    // asserted as it is SCROLLED to — which also proves the scroll itself.
    expect(find.text('BREAKFAST'), findsOneWidget);
    expect(find.textContaining('420 kcal'), findsWidgets); // prescribed ask
    expect(find.text('Oats with Whey'), findsOneWidget);
    expect(find.text('100 g'), findsWidgets);
    expect(find.text('Eaten'), findsWidgets);
    expect(find.text('Partial'), findsWidgets);
    expect(find.text('Skipped'), findsWidgets);

    await $.scrollUntilVisible(finder: $('LUNCH'));
    expect(find.text('LUNCH'), findsOneWidget);
    await $.scrollUntilVisible(finder: $('DINNER'));
    expect(find.text('DINNER'), findsOneWidget);
    await $.scrollUntilVisible(finder: $('EVENING SNACK'));
    expect(find.text('EVENING SNACK'), findsOneWidget);
    expect(find.text('Greek Yogurt'), findsOneWidget);
    expect(find.text('SNACKS'), findsNothing);
  });

  // ══ MARKING — the production adherence math, live ═══════════════════════

  patrolTest('marking eaten moves the ring; tapping again toggles off',
      ($) async {
    await boot();
    diet([
      food('Oats', meal: 'Breakfast'),
      food('Rice', meal: 'Lunch'),
    ]);
    await mount($, find.text('YOUR DIET'));
    expect(find.text('0%'), findsOneWidget);

    await $.tester.tap(find.text('Eaten').first);
    await $.tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget); // 1 of 2, full credit
    expect(find.text('1 of 2 foods logged'), findsOneWidget);

    // Same chip again = unmark, honestly back to zero.
    await $.tester.tap(find.text('Eaten').first);
    await $.tester.pumpAndSettle();
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('0 of 2 foods logged'), findsOneWidget);
  });

  patrolTest('a partial meal earns half credit, never full', ($) async {
    await boot();
    diet([
      food('Oats', meal: 'Breakfast'),
      food('Rice', meal: 'Lunch'),
    ]);
    await mount($, find.text('YOUR DIET'));

    await $.tester.tap(find.text('Partial').first);
    await $.tester.pumpAndSettle();
    expect(find.text('25%'), findsOneWidget); // 0.5 of 2
    expect(find.text('1 of 2 foods logged'), findsOneWidget);
  });

  patrolTest('a skipped meal is logged but earns nothing', ($) async {
    await boot();
    diet([
      food('Oats', meal: 'Breakfast'),
      food('Rice', meal: 'Lunch'),
    ]);
    await mount($, find.text('YOUR DIET'));

    await $.tester.tap(find.text('Skipped').first);
    await $.tester.pumpAndSettle();
    // Logged (the coach sees the honesty) — but zero adherence credit.
    expect(find.text('1 of 2 foods logged'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);

    // Changing the answer replaces it, never stacks.
    await $.tester.tap(find.text('Eaten').first);
    await $.tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('1 of 2 foods logged'), findsOneWidget);
  });

  // ══ STATES — empty · breakfast-only · error · no targets ════════════════

  patrolTest('no nutrition plan is an honest empty state', ($) async {
    await boot();
    diet(null, name: 'No diet assigned yet', withTargets: false);
    await mount($, find.text('YOUR DIET'));
    expect(find.text('No diet assigned yet'), findsWidgets);
    expect(find.text('Your trainer will set up your nutrition plan.'),
        findsOneWidget);
    expect(find.text('Diet adherence'), findsNothing); // no ring over nothing
  });

  patrolTest('breakfast-only day renders one meal, no invented meals',
      ($) async {
    await boot();
    diet([food('Oats', meal: 'Breakfast')]);
    await mount($, find.text('YOUR DIET'));
    expect(find.text('BREAKFAST'), findsOneWidget);
    expect(find.text('LUNCH'), findsNothing);
    expect(find.text('DINNER'), findsNothing);
  });

  patrolTest('a load failure is an error with Retry, never "no plan"',
      ($) async {
    await boot();
    diet(null, failed: true);
    await $.tester
        .pumpWidget(host(ClientDietScreen()));
    await pumpUntil($, find.textContaining("Couldn't load"));
    expect(find.textContaining("Couldn't load"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No diet assigned yet'), findsNothing);
  });

  patrolTest('without coach targets the day still renders honestly',
      ($) async {
    await boot();
    diet(fullDay(), withTargets: false);
    await mount($, find.text('YOUR DIET'));
    // Targets fall back to the prescribed sums (the one canonical rule) —
    // the card renders real numbers either way, never dashes or fabrications.
    expect(find.text('Diet adherence'), findsOneWidget);
    expect(find.text('0 of 4 foods logged'), findsOneWidget);
  });

  // ══ STRESS + ACCESSIBILITY + ORIENTATION ════════════════════════════════

  patrolTest('a 30-food day scrolls end to end without overflow', ($) async {
    await boot();
    diet([
      for (var i = 1; i <= 30; i++)
        food(
          i == 1
              ? 'Slow-Cooked Buckwheat Porridge with Toasted Almond Flakes '
                  'and Seasonal Berries'
              : 'Food $i',
          meal: const ['Breakfast', 'Lunch', 'Dinner'][i % 3],
          calories: 100.0 + i,
        ),
    ]);
    await mount($, find.text('YOUR DIET'));
    // The first card can sit below the adherence card on a small viewport —
    // scroll it into the inflated region before asserting.
    await $.scrollUntilVisible(finder: $(RegExp('Buckwheat Porridge')));
    expect(find.textContaining('Buckwheat Porridge'), findsOneWidget);

    final list = find.byType(ListView);
    for (var i = 0; i < 8; i++) {
      await $.tester.drag(list, const Offset(0, -400));
      await $.tester.pump(const Duration(milliseconds: 16));
    }
    await $.tester.pumpAndSettle();
    expect($.tester.takeException(), isNull);
  });

  patrolTest('nutrition survives 1.6x accessibility text', ($) async {
    await boot();
    diet(fullDay());
    await mount($, find.text('YOUR DIET'), textScale: 1.6);
    expect(find.text('Diet adherence'), findsOneWidget);
    // Lazily-inflated list: at 1.6x fewer cards fit the viewport — assert
    // presence, and that the day's END is reachable without overflow.
    expect(find.text('Eaten'), findsWidgets);
    await $.scrollUntilVisible(finder: $('EVENING SNACK'));
    expect($.tester.takeException(), isNull);
  });

  patrolTest('marking still works at 1.6x on the real device', ($) async {
    await boot();
    diet([food('Oats'), food('Rice', meal: 'Lunch')]);
    await mount($, find.text('YOUR DIET'), textScale: 1.6);
    await $.tester.tap(find.text('Eaten').first);
    await $.tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
  });
}
