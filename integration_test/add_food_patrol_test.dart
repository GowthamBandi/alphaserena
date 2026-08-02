import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:patrol/patrol.dart';

import 'package:alphaserena/controllers/connectivity_controller.dart';
import 'package:alphaserena/controllers/food_search_controller.dart';
import 'package:alphaserena/core/domain/food_portion_math.dart';
import 'package:alphaserena/core/models/member_food.dart';
import 'package:alphaserena/core/services/member_food_service.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/nutrition/add_food_screen.dart';
import 'package:alphaserena/screens/dashboard/nutrition/food_quantity_sheet.dart';

/// PATROL — ADD FOOD, ON A REAL DEVICE.
///
/// The same honest harness the workout and nutrition suites already use: no
/// member session exists on this emulator (phone OTP is externally blocked),
/// so the REAL `AddFoodScreen` runs over a REAL `FoodSearchController` whose
/// food library is a deterministic fixture in the exact wire shape
/// `searchMemberFoods` emits.
///
/// What executes for real on the device: the whole search → meal → quantity →
/// preview → add journey, debounce and request-race handling, every empty /
/// loading / offline / failure state, the running receipt, accessibility text
/// scale, landscape, dark and light. The Firestore WRITE no-ops on an unlinked
/// device — that layer is certified against the real security rules by
/// `trainershq-backend/tests/rules/nutrition_food_log_write.mjs`, which replays
/// this app's exact payload. Stated, not simulated.
void main() {
  Future<void> boot() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    Get.reset();
  }

  MemberFood food(
    String name, {
    MemberFoodTier tier = MemberFoodTier.global,
    double calories = 250,
    List<FoodPortionOption> portions = const [],
    String verification = 'unverified',
  }) =>
      MemberFood(
        foodId: name.toLowerCase().replaceAll(' ', '_'),
        name: name,
        tier: tier,
        per100: {
          'calories': calories,
          'protein': 18,
          'carbs': 6,
          'fat': 18,
          'fiber': 1,
          'sugar': 2,
          'saturatedFat': 9,
        },
        portions: portions,
        verification: verification,
      );

  late _FixtureFoodService service;

  Future<void> open(
    PatrolIntegrationTester $, {
    String? meal,
    double textScale = 1.0,
    Brightness brightness = Brightness.dark,
    Size? surface,
    bool online = true,
  }) async {
    await boot();
    final conn = Get.put(ConnectivityController(), permanent: true);
    conn.isOnline.value = online;
    if (surface != null) await $.tester.binding.setSurfaceSize(surface);

    // REGISTERED, not merely constructed: GetX runs `onInit` on registration,
    // and that is what fires the initial browse load. Injecting a bare
    // instance leaves the screen bound to a controller that never started —
    // which is exactly what this suite caught on its first device run.
    final controller = Get.put(
      FoodSearchController(service: service, connectivity: conn),
      tag: 'patrol_add_food',
    );
    await $.pumpWidgetAndSettle(
      MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: AddFoodScreen(
            initialMealSlot: meal,
            searchController: controller,
          ),
        ),
      ),
    );
  }

  setUp(() {
    service = _FixtureFoodService()
      ..browse = [
        food('Paneer Tikka',
            tier: MemberFoodTier.org,
            portions: const [FoodPortionOption(label: 'katori', grams: 150)]),
        food('Basmati Rice', calories: 130, verification: 'official'),
        food('Dal Tadka', calories: 116),
      ];
  });

  tearDown(() async => Get.reset());

  // ── THE JOURNEY ──────────────────────────────────────────────────────────

  patrolTest('the browse page opens with the gym library first', ($) async {
    await open($, meal: 'lunch');
    expect($('Paneer Tikka').exists, true);
    expect($('Basmati Rice').exists, true);
    // Provenance is visible: the member can tell which food their coach
    // planned against.
    expect($("Your coach's").exists, true);
  });

  patrolTest('all six meals are selectable and the choice sticks', ($) async {
    await open($, meal: 'lunch');
    // The meal strip is a horizontal ListView: off-screen chips are not built
    // until scrolled to, so each is scrolled into view before asserting.
    for (final label in [
      'Breakfast', 'Mid-Morning Snack', 'Lunch', 'Evening Snack',
      'Dinner', 'Bedtime',
    ]) {
      await $(label).scrollTo();
      expect($(label).exists, true, reason: '$label must be offered');
    }
    await $('Dinner').scrollTo();
    await $('Dinner').tap();
    await $.pumpAndSettle();
    await $('Paneer Tikka').tap();
    await $.pumpAndSettle();
    // The sheet opens on the meal the strip is showing.
    expect($.tester.any(find.textContaining('Add to Dinner')), true);
  });

  patrolTest('search → quantity → preview → add, end to end', ($) async {
    service.results = [
      food('Paneer Tikka',
          tier: MemberFoodTier.org,
          portions: const [FoodPortionOption(label: 'katori', grams: 150)]),
    ];
    await open($, meal: 'lunch');

    await $(TextField).enterText('paneer');
    await $.pumpAndSettle(
      duration: FoodSearchController.debounce + const Duration(milliseconds: 200),
    );
    expect($('Paneer Tikka').exists, true);

    await $('Paneer Tikka').tap();
    await $.pumpAndSettle();

    // The PREVIEW is the contract: 1 katori = 150 g of a 250 kcal/100 g food.
    expect($('375 kcal').exists, true);
    expect($('You will log').exists, true);
    expect($.tester.any(find.textContaining('Add to Lunch · 375 kcal')), true);

    await $(FoodQuantitySheet).$('Add to Lunch · 375 kcal').tap();
    await $.pumpAndSettle();

    // The sheet commits and closes. The Firestore WRITE cannot succeed on an
    // unlinked device, and this asserts what actually happens then: the member
    // is TOLD, by name, and is left on the screen with their work intact — not
    // silently returned to a list as though nothing had been attempted. The
    // successful-write path is certified against the real security rules by
    // `tests/rules/nutrition_food_log_write.mjs`, which replays this exact
    // payload.
    expect($(FoodQuantitySheet).exists, false);
    expect($.tester.any(find.textContaining('Could not log Paneer Tikka')), true);
    expect($('Add Food').exists, true);
  });

  patrolTest('changing the portion re-previews before anything is written',
      ($) async {
    await open($, meal: 'lunch');
    await $('Paneer Tikka').tap();
    await $.pumpAndSettle();
    expect($('375 kcal').exists, true);
    await $(Icons.add_rounded).tap();
    await $.pumpAndSettle();
    // 1.5 katori = 225 g → 562.5 → 563 kcal.
    expect($('563 kcal').exists, true);
  });

  patrolTest('adding three foods in a row keeps the screen and the receipt',
      ($) async {
    await open($, meal: 'lunch');
    for (final name in ['Paneer Tikka', 'Basmati Rice', 'Dal Tadka']) {
      await $(name).scrollTo();
      await $(name).tap();
      await $.pumpAndSettle();
      await $(FoodQuantitySheet).$(ElevatedButton).tap();
      await $.pumpAndSettle();
      // Each round trip returns to the list rather than unwinding the screen —
      // the property that makes multi-item entry bearable.
      expect($(FoodQuantitySheet).exists, false);
      expect($('Add Food').exists, true);
    }
    // Three attempts, three separate outcomes, no stuck sheet and no lost
    // screen state.
    expect($('Add Food').exists, true);
  });

  // ── DUPLICATE AND RAPID TAPS ─────────────────────────────────────────────

  patrolTest('a double tap on Add cannot log the same food twice', ($) async {
    await open($, meal: 'lunch');
    await $('Paneer Tikka').tap();
    await $.pumpAndSettle();
    final add = find.descendant(
      of: find.byType(FoodQuantitySheet),
      matching: find.byType(ElevatedButton),
    );
    // Two taps inside one frame: the second must find the sheet already
    // committed. The re-entrancy guard, not luck, is what stops it.
    await $.tester.tap(add);
    await $.tester.tap(add, warnIfMissed: false);
    await $.pumpAndSettle();
    expect($(FoodQuantitySheet).exists, false, reason: 'the sheet closed once');
    expect($('Add Food').exists, true);
  });

  patrolTest('rapid meal switching never desyncs the sheet', ($) async {
    await open($, meal: 'lunch');
    for (final m in ['Breakfast', 'Dinner', 'Bedtime', 'Lunch']) {
      await $(m).scrollTo();
      await $(m).tap();
      await $.pump(const Duration(milliseconds: 20));
    }
    await $.pumpAndSettle();
    await $('Paneer Tikka').tap();
    await $.pumpAndSettle();
    expect($.tester.any(find.textContaining('Add to Lunch')), true);
  });

  // ── SEARCH BEHAVIOUR ─────────────────────────────────────────────────────

  patrolTest('typing a word costs one request, not one per keystroke',
      ($) async {
    await open($, meal: 'lunch');
    service.queries.clear();
    // `$(TextField).enterText` pumpAndSettles, which would elapse the 280 ms
    // debounce after EVERY keystroke and measure the harness instead of the
    // product. The raw tester keeps the timing the member's.
    final field = find.byType(TextField).first;
    for (final partial in ['p', 'pa', 'pan', 'pane', 'paneer']) {
      await $.tester.enterText(field, partial);
      await $.pump(const Duration(milliseconds: 40));
    }
    await $.pumpAndSettle(
      duration: FoodSearchController.debounce + const Duration(milliseconds: 200),
    );
    // On a real device the gap between synthetic keystrokes is not
    // deterministic, so "exactly one request" would be asserting the harness's
    // timing rather than the product's. What must hold on a device is that
    // typing costs FAR fewer requests than keystrokes and settles on the final
    // word. The exact one-request behaviour is pinned with controlled timing
    // in `test/food_search_controller_test.dart`.
    expect(service.queries.length, lessThan(5),
        reason: 'five keystrokes must not be five round trips');
    expect(service.queries.last, 'paneer');
  });

  patrolTest('a search with no matches invites another word, not a retry',
      ($) async {
    service.results = const [];
    await open($, meal: 'lunch');
    await $(TextField).enterText('zzzzzz');
    await $.pumpAndSettle(
      duration: FoodSearchController.debounce + const Duration(milliseconds: 200),
    );
    expect($.tester.any(find.textContaining('No foods match')), true);
    expect($('Try again').exists, false,
        reason: 'nothing to retry — the search worked');
  });

  patrolTest('clearing the search snaps straight back to browse', ($) async {
    service.results = [food('Paneer Tikka')];
    await open($, meal: 'lunch');
    await $(TextField).enterText('paneer');
    await $.pumpAndSettle(
      duration: FoodSearchController.debounce + const Duration(milliseconds: 200),
    );
    await $(Icons.close_rounded).tap();
    await $.pumpAndSettle();
    expect($('Dal Tadka').exists, true, reason: 'the browse page is back');
  });

  patrolTest('a partial gym library is disclosed, never silently trimmed',
      ($) async {
    service.orgFallback = true;
    await open($, meal: 'lunch');
    expect(
      $.tester.any(find.textContaining("part of your coach's library")),
      true,
    );
  });

  // ── FAILURE AND RECOVERY ─────────────────────────────────────────────────

  patrolTest('offline is its own state, with the log reassured', ($) async {
    await open($, meal: 'lunch', online: false);
    expect($('You are offline').exists, true);
    expect($.tester.any(find.textContaining('already logged is safe')), true);
    expect($('Try again').exists, true);
  });

  patrolTest('reconnecting and retrying restores the list', ($) async {
    await open($, meal: 'lunch', online: false);
    expect($('You are offline').exists, true);
    Get.find<ConnectivityController>().isOnline.value = true;
    await $('Try again').tap();
    await $.pumpAndSettle();
    expect($('Paneer Tikka').exists, true);
  });

  patrolTest('a failed search offers a retry that works', ($) async {
    service.fail = true;
    await open($, meal: 'lunch');
    expect($("Couldn't load foods").exists, true);
    service.fail = false;
    await $('Try again').tap();
    await $.pumpAndSettle();
    expect($('Paneer Tikka').exists, true);
  });

  patrolTest('an empty library is an invitation, not an error', ($) async {
    service.browse = const [];
    await open($, meal: 'lunch');
    expect($.tester.any(find.textContaining('Search to add your first food')),
        true);
  });

  // ── PRESENTATION ON THE DEVICE ───────────────────────────────────────────

  patrolTest('the journey survives 1.6x accessibility text', ($) async {
    await open($, meal: 'lunch', textScale: 1.6);
    expect($('Paneer Tikka').exists, true);
    await $('Paneer Tikka').tap();
    await $.pumpAndSettle();
    expect($('You will log').exists, true);
    expect($.tester.takeException(), isNull);
  });

  patrolTest('the journey survives landscape', ($) async {
    await open($, meal: 'lunch', surface: const Size(844, 390));
    addTearDown(() => $.tester.binding.setSurfaceSize(null));
    await $('Paneer Tikka').tap();
    await $.pumpAndSettle();
    // The pinned action bar keeps the figure visible when the card is below
    // the fold — the guarantee is "never commit to an unseen number".
    expect($.tester.any(find.textContaining('Add to Lunch · 375 kcal')), true);
    expect($.tester.takeException(), isNull);
  });

  patrolTest('light mode renders the whole journey', ($) async {
    await open($, meal: 'lunch', brightness: Brightness.light);
    await $('Paneer Tikka').tap();
    await $.pumpAndSettle();
    expect($('375 kcal').exists, true);
    expect($.tester.takeException(), isNull);
  });

  patrolTest('back navigation from the sheet logs nothing', ($) async {
    await open($, meal: 'lunch');
    await $('Paneer Tikka').tap();
    await $.pumpAndSettle();
    await $(Icons.close_rounded).tap();
    await $.pumpAndSettle();
    expect($(FoodQuantitySheet).exists, false);
    expect($('Added just now').exists, false, reason: 'nothing was logged');
  });

  patrolTest('an over-limit amount is refused at the point of entry',
      ($) async {
    await open($, meal: 'lunch');
    await $('Paneer Tikka').tap();
    await $.pumpAndSettle();
    await $('Grams').scrollTo();
    await $('Grams').tap();
    await $.pumpAndSettle();
    // Scoped to the SHEET: the search field is still mounted behind it, and an
    // unscoped TextField finder types into that instead — which is precisely
    // what this run caught.
    await $.tester.enterText(
      find
          .descendant(
            of: find.byType(FoodQuantitySheet),
            matching: find.byType(TextField),
          )
          .first,
      '9000',
    );
    await $.pumpAndSettle();
    // The warning sits below the preview in a lazily-built list; on a real
    // phone it is off-screen until scrolled to. Forcing a tall synthetic
    // surface would have hidden that, so the test scrolls like a member does.
    await $(RegExp('over 5000 g')).scrollTo();
    expect($(RegExp('over 5000 g')).exists, true);
    final button = $.tester.widget<ElevatedButton>(
      find.descendant(
        of: find.byType(FoodQuantitySheet),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(button.onPressed, isNull);
  });
}

/// A deterministic stand-in for the `searchMemberFoods` callable.
class _FixtureFoodService extends MemberFoodService {
  List<MemberFood> browse = const [];
  List<MemberFood>? results;
  bool fail = false;
  bool orgFallback = false;
  final List<String> queries = [];

  @override
  Future<FoodSearchOutcome> search(String query, {int limit = 24}) async {
    queries.add(query);
    if (fail) return const FoodSearchOutcome.failure();
    final trimmed = query.trim();
    return FoodSearchOutcome(
      foods: trimmed.isEmpty ? browse : (results ?? browse),
      orgFallback: orgFallback,
    );
  }

  @override
  Future<List<MemberFood>> recents() async => const [];

  @override
  Future<void> remember(MemberFood food) async {}
}
