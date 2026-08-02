import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:alphaserena/controllers/food_log_controller.dart';
import 'package:alphaserena/controllers/training_controller.dart';
import 'package:alphaserena/core/models/nutrition_day_model.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/nutrition/diet_screen.dart';

/// PHASE 3B — THE DIET SCREEN.
///
/// Two things the member must never be able to confuse: what their coach
/// RECOMMENDED, and what they ACTUALLY ate. These pin that the two live in
/// separate sections, that recommendations are read-only and contribute
/// nothing to any total, and that both halves file a meal under the same name.
class _FakeTraining extends TrainingController {
  _FakeTraining(this._items, {Map<String, dynamic>? plan, String err = ''}) {
    diet.value = plan ?? {'name': 'Cut Phase 1', 'items': _items};
    error.value = err;
    isLoading.value = false;
  }
  final List<Map<String, dynamic>> _items;

  @override
  List<Map<String, dynamic>> get dietItems => _items;

  @override
  Future<void> load() async {}

  // Deliberately does NOT call super: the real onInit issues a getMyTraining
  // call, which is exactly what this fixture exists to avoid. GetX invokes
  // onInit on registration, so it has to be overridden rather than skipped.
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _FakeLog extends FoodLogController {
  _FakeLog({Map<String, FoodEntry> entries = const {}, this.error = false}) {
    day.value = NutritionDayModel(
      id: 'c1_2026-08-01',
      dateKey: '2026-08-01',
      entries: entries,
    );
    isLoading.value = false;
    loadError.value = error;
  }
  final bool error;

  // Deliberately does NOT call super: the real onInit binds a Firestore
  // stream, and this fixture holds a fixed day.
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  void ensureFreshDay() {}
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

FoodEntry logged(
  String name, {
  String meal = 'lunch',
  double kcal = 375,
}) => FoodEntry(
  entryId: name.toLowerCase(),
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

void main() {
  tearDown(Get.reset);

  Future<void> pump(
    WidgetTester tester, {
    required TrainingController training,
    required FoodLogController log,
    Size size = const Size(390, 2400),
    double textScale = 1.0,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Get.testMode = true;
    Get.put<TrainingController>(training);
    Get.put<FoodLogController>(log);
    await tester.pumpWidget(
      GetMaterialApp(
        theme: theme ?? AppTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const DietScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('section 1 — coach recommendations are READ ONLY', () {
    testWidgets('meals render with foods, quantities and the plan note',
        (tester) async {
      await pump(
        tester,
        training: _FakeTraining(
          [
            planFood('Oats', meal: 'Breakfast', quantity: '1 bowl'),
            planFood('Grilled Chicken', meal: 'Lunch', quantity: '150 g'),
          ],
          plan: {
            'name': 'Cut Phase 1',
            'description': 'Keep protein high on training days.',
            'items': const [],
          },
        ),
        log: _FakeLog(),
      );
      expect(find.text('COACH RECOMMENDED'), findsOneWidget);
      expect(find.text('Oats'), findsOneWidget);
      expect(find.text('1 bowl'), findsOneWidget);
      expect(find.text('Grilled Chicken'), findsOneWidget);
      expect(find.text('150 g'), findsOneWidget);
      expect(find.text('Cut Phase 1'), findsOneWidget);
      // The coach note is PLAN-level — the data model has no per-meal note.
      expect(find.text('Keep protein high on training days.'), findsOneWidget);
    });

    testWidgets('a recommendation cannot be marked or edited', (tester) async {
      await pump(
        tester,
        training: _FakeTraining([planFood('Oats')]),
        log: _FakeLog(),
      );
      // No eaten/partial/skipped affordance survives anywhere on the screen:
      // a recommendation is the coach's statement, not an input.
      for (final label in ['Eaten', 'Partial', 'Skipped', 'Mark']) {
        expect(find.text(label), findsNothing, reason: '$label must be gone');
      }
      // The only action offered on a meal is to LOG against it.
      expect(find.text('Log'), findsOneWidget);
    });

    testWidgets('recommendations contribute NOTHING to the totals',
        (tester) async {
      // A 250 kcal prescribed food with nothing logged must total zero: a
      // recommendation nobody ate is not nutrition.
      await pump(
        tester,
        training: _FakeTraining([planFood('Oats', calories: 250)]),
        log: _FakeLog(),
      );
      expect(find.text('Nothing logged yet today'), findsOneWidget);
      expect(find.text('250'), findsNothing);
    });

    testWidgets('the coach free-text meal maps to the SAME slug the log uses',
        (tester) async {
      // The coach types labels ("Mid-morning", legacy "Snacks"); the log
      // stores slugs. Both halves of this screen must file them together, or
      // one meal appears under two headings.
      await pump(
        tester,
        training: _FakeTraining([
          planFood('Almonds', meal: 'Mid-morning'),
          planFood('Bhel', meal: 'Snacks'),
        ]),
        log: _FakeLog(entries: {'a': logged('Poha', meal: 'mid_morning')}),
      );
      expect(find.text('MID-MORNING SNACK'), findsNWidgets(2),
          reason: 'once in recommendations, once in the log');
      expect(find.text('EVENING SNACK'), findsOneWidget);
    });

    testWidgets('no plan is not a blocker — logging still works',
        (tester) async {
      await pump(tester, training: _FakeTraining(const []), log: _FakeLog());
      expect(find.text('No diet plan yet'), findsOneWidget);
      expect(
        find.textContaining('You can still log what you eat'),
        findsOneWidget,
      );
      expect(find.text('Add your first food'), findsOneWidget);
    });

    testWidgets('a failed plan load is an error with Retry, not "no plan"',
        (tester) async {
      await pump(
        tester,
        training: _FakeTraining(const [], err: 'network'),
        log: _FakeLog(),
      );
      expect(find.text("Couldn't load your plan"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('No diet plan yet'), findsNothing);
    });
  });

  group("section 2 — today's food log", () {
    testWidgets('logged foods show food, amount, source, time and nutrition',
        (tester) async {
      await pump(
        tester,
        training: _FakeTraining([planFood('Oats')]),
        log: _FakeLog(entries: {'a': logged('Paneer Tikka')}),
      );
      expect(find.text("TODAY'S FOOD LOG"), findsOneWidget);
      expect(find.text('Paneer Tikka'), findsOneWidget);
      expect(find.text('1 katori'), findsOneWidget);
      expect(find.text("Coach's"), findsOneWidget);
      // Once on the entry row, once as the meal's own subtotal.
      expect(find.text('375 kcal'), findsNWidgets(2));
      // The meal time is DERIVED from the earliest entry, never stored.
      expect(find.text('1:30 PM'), findsOneWidget);
    });

    testWidgets('totals come only from the log', (tester) async {
      await pump(
        tester,
        training: _FakeTraining([planFood('Oats', calories: 999)]),
        log: _FakeLog(entries: {
          'a': logged('Paneer Tikka', kcal: 375),
          'b': logged('Dal', meal: 'dinner', kcal: 200),
        }),
      );
      expect(find.text('575'), findsOneWidget);
      expect(find.textContaining('kcal from 2 items'), findsOneWidget);
    });

    testWidgets('an empty log invites, and never claims a failure',
        (tester) async {
      await pump(
        tester,
        training: _FakeTraining([planFood('Oats')]),
        log: _FakeLog(),
      );
      expect(find.text('Nothing logged yet today'), findsOneWidget);
      expect(find.text("Couldn't load today's food"), findsNothing);
    });

    testWidgets('a read failure is an error, never the empty state',
        (tester) async {
      await pump(
        tester,
        training: _FakeTraining([planFood('Oats')]),
        log: _FakeLog(error: true),
      );
      // The empty state is a claim about the member's behaviour; this is a
      // claim about the network. They must never render the same.
      expect(find.text("Couldn't load today's food"), findsOneWidget);
      expect(find.text('Nothing logged yet today'), findsNothing);
    });
  });

  group('section 3 — previous days', () {
    testWidgets('history is reachable from the section and the app bar',
        (tester) async {
      await pump(
        tester,
        training: _FakeTraining([planFood('Oats')]),
        log: _FakeLog(),
      );
      expect(find.text('Previous days'), findsOneWidget);
      expect(find.byIcon(Icons.history_rounded), findsNWidgets(2));
    });
  });

  group('presentation', () {
    testWidgets('renders at 2.0x accessibility text without overflow',
        (tester) async {
      await pump(
        tester,
        training: _FakeTraining([planFood('Oats'), planFood('Whey', meal: 'Lunch')]),
        log: _FakeLog(entries: {'a': logged('Paneer Tikka')}),
        size: const Size(320, 4000),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in light mode', (tester) async {
      await pump(
        tester,
        training: _FakeTraining([planFood('Oats')]),
        log: _FakeLog(entries: {'a': logged('Paneer Tikka')}),
        theme: AppTheme.light,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Paneer Tikka'), findsOneWidget);
    });

    testWidgets('renders in landscape', (tester) async {
      await pump(
        tester,
        training: _FakeTraining([planFood('Oats')]),
        log: _FakeLog(entries: {'a': logged('Paneer Tikka')}),
        size: const Size(844, 1200),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
