import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/food_portion_math.dart';
import 'package:alphaserena/core/models/member_food.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/nutrition/food_quantity_sheet.dart';

/// THE QUANTITY SHEET — "never surprise the user".
///
/// The contract these tests defend is that the number the member READS before
/// tapping Add is the number that gets WRITTEN. Not approximately; the same
/// arithmetic, from the same [scaleMacros] the write path calls.
void main() {
  final paneer = MemberFood(
    foodId: 'f1',
    name: 'Paneer Tikka',
    tier: MemberFoodTier.org,
    serving: '1 plate',
    per100: const {
      'calories': 250,
      'protein': 18,
      'carbs': 6,
      'fat': 18,
      'fiber': 1,
      'sugar': 2,
      'saturatedFat': 9,
    },
    portions: const [
      FoodPortionOption(label: 'katori', grams: 150),
      FoodPortionOption(label: 'plate', grams: 300),
    ],
  );

  Future<FoodQuantityResult?> pump(
    WidgetTester tester, {
    required MemberFood food,
    String mealSlot = 'lunch',
    Size size = const Size(390, 844),
    double textScale = 1.0,
    ThemeData? theme,
    PortionSelection? initialSelection,
    bool isEdit = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    FoodQuantityResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showModalBottomSheet<FoodQuantityResult>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => FoodQuantitySheet(
                        food: food,
                        mealSlot: mealSlot,
                        initialSelection: initialSelection,
                        isEdit: isEdit,
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  group('the preview is the truth', () {
    testWidgets('opens on the first portion and previews its exact macros',
        (tester) async {
      await pump(tester, food: paneer);
      // 1 katori = 150 g of a 250 kcal/100 g food = 375 kcal.
      expect(find.text('375 kcal'), findsOneWidget);
      expect(find.text('You will log'), findsOneWidget);
      // The Add button repeats the number, so it is visible at the moment of
      // commitment and not only at the top of a scrolled sheet.
      expect(
        find.textContaining('Add to Lunch · 375 kcal'),
        findsOneWidget,
      );
      // 150 g x 18 g protein/100 g = 27 g. Fat scales to 27 g too — both are
      // shown, which is why this counts widgets rather than asserting one.
      expect(find.text('27 g'), findsNWidgets(2));
      // 150 g x 6 g carbs/100 g = 9 g, formatted with a decimal below 10.
      expect(find.text('9.0 g'), findsOneWidget);
    });

    testWidgets('the previewed number equals scaleMacros exactly',
        (tester) async {
      await pump(tester, food: paneer);
      final expected = scaleMacros(paneer.per100, 150);
      expect(find.text('${expected['calories']!.round()} kcal'),
          findsOneWidget);
    });

    testWidgets('changing the portion re-previews immediately',
        (tester) async {
      await pump(tester, food: paneer);
      await tester.tap(find.textContaining('plate · 300 g'));
      await tester.pumpAndSettle();
      // 300 g → 750 kcal.
      expect(find.text('750 kcal'), findsOneWidget);
      expect(find.textContaining('750 kcal'), findsWidgets);
    });

    testWidgets('the stepper adjusts the amount and the preview together',
        (tester) async {
      await pump(tester, food: paneer);
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();
      // 1.5 katori = 225 g → 562.5 → 563 kcal displayed.
      expect(find.text('563 kcal'), findsOneWidget);
    });

    testWidgets('grams mode carries the current amount across', (tester) async {
      await pump(tester, food: paneer);
      await tester.tap(find.text('Grams'));
      await tester.pumpAndSettle();
      // Switching from 1 katori (150 g) keeps 150 g rather than resetting.
      expect(find.text('375 kcal'), findsOneWidget);
    });
  });

  group('what the sheet returns', () {
    testWidgets('the returned selection scales to the previewed macros',
        (tester) async {
      FoodQuantityResult? captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    captured = await showModalBottomSheet<FoodQuantityResult>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) =>
                          FoodQuantitySheet(food: paneer, mealSlot: 'dinner'),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Add to Dinner'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.mealSlot, 'dinner');
      expect(captured!.selection.totalGrams, 150);
      expect(captured!.selection.storedUnit, 'katori');
      // The write path will produce exactly the previewed 375 kcal.
      expect(
        scaleMacros(paneer.per100, captured!.selection.totalGrams)['calories'],
        375,
      );
    });

    testWidgets('changing the meal inside the sheet is honoured',
        (tester) async {
      FoodQuantityResult? captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    captured = await showModalBottomSheet<FoodQuantityResult>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) =>
                          FoodQuantitySheet(food: paneer, mealSlot: 'lunch'),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bedtime'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Add to Bedtime'));
      await tester.pumpAndSettle();
      expect(captured!.mealSlot, 'bedtime');
    });
  });

  group('guard rails', () {
    testWidgets('an invalid amount disables Add rather than logging nothing',
        (tester) async {
      await pump(tester, food: paneer);
      await tester.enterText(find.byType(TextField).first, '0');
      await tester.pumpAndSettle();
      final button = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.textContaining('Add to Lunch'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull,
          reason: 'a zero-gram entry must be impossible to submit');
    });

    testWidgets('an over-limit amount warns before it is logged',
        (tester) async {
      // Tall viewport so the whole sheet is laid out — the warning sits below
      // the preview and a lazily-built list would not construct it otherwise.
      await pump(tester, food: paneer, size: const Size(390, 1400));
      await tester.tap(find.text('Grams'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '6000');
      await tester.pumpAndSettle();
      expect(find.textContaining('over 5000 g'), findsOneWidget);
      // And it is still refused, not merely warned about.
      final button = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.textContaining('Add to Lunch'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a food with NO portions still opens on a sane default',
        (tester) async {
      final bare = MemberFood(
        foodId: 'f2',
        name: 'Olive Oil',
        per100: const {'calories': 884, 'fat': 100},
      );
      await pump(tester, food: bare);
      // Defaults to 100 g, which is exactly what the stored numbers mean, so
      // the member never has to reverse-engineer the basis.
      expect(find.text('884 kcal'), findsOneWidget);
      expect(find.text('Grams'), findsNothing,
          reason: 'no portion chips when there are no portions to choose');
    });
  });

  group('mass is stated only when it is MEASURED', () {
    testWidgets('a library food shows its gram basis', (tester) async {
      await pump(tester, food: paneer);
      expect(find.text('= 150 g'), findsOneWidget);
      expect(find.textContaining('katori · 150 g'), findsOneWidget);
      expect(find.text('Grams'), findsOneWidget);
    });

    testWidgets('a LEGACY entry states no mass and cannot switch to grams',
        (tester) async {
      // Editing an entry logged before `grams` existed: the gram basis is a
      // scaling pivot, not a measurement. Showing "= 100 g" for what was 2
      // katori (300 g) was a confident wrong figure, and switching to grams
      // wrote that pivot back as the member's amount.
      final legacy = MemberFood(
        foodId: 'f1',
        name: 'Paneer Tikka',
        tier: MemberFoodTier.org,
        per100: const {'calories': 750},
        portions: const [FoodPortionOption(label: 'katori', grams: 50)],
        massKnown: false,
      );
      await pump(
        tester,
        food: legacy,
        size: const Size(390, 1400),
        isEdit: true,
        initialSelection: const PortionSelection(
          mode: PortionMode.portion,
          quantity: 2,
          portionLabel: 'katori',
          gramsPerPortion: 50,
        ),
      );
      expect(find.textContaining('= '), findsNothing,
          reason: 'no fabricated gram readout');
      expect(find.text('Grams'), findsNothing,
          reason: 'the pivot must not be writable back as an amount');
      // The portion chip names the portion without claiming a weight (the
      // amount field's suffix carries the same word, hence findsWidgets).
      expect(find.text('katori'), findsWidgets);
      expect(find.textContaining('katori · '), findsNothing);
      // And the numbers it CAN state are still exact.
      expect(find.text('750 kcal'), findsOneWidget);
    });

    testWidgets('a legacy entry still re-scales its count correctly',
        (tester) async {
      // Faithful to the real edit entry point: the member logged "2 katori"
      // = 750 kcal before `grams` existed. The reconstruction pivots on 100 g,
      // giving per100 = 750 and 1 katori = 50 g — a valid reparameterization,
      // so quantity x pivot x per100/100 stays EXACT.
      final legacy = MemberFood(
        foodId: 'f1',
        name: 'Paneer Tikka',
        per100: const {'calories': 750},
        portions: const [FoodPortionOption(label: 'katori', grams: 50)],
        massKnown: false,
      );
      await pump(
        tester,
        food: legacy,
        size: const Size(390, 1400),
        isEdit: true,
        initialSelection: const PortionSelection(
          mode: PortionMode.portion,
          quantity: 2,
          portionLabel: 'katori',
          gramsPerPortion: 50,
        ),
      );
      // Opens on exactly what was logged.
      expect(find.text('750 kcal'), findsOneWidget);
      // Correcting 2 katori to 3: the true value is 3 x 150 g x 2.5 kcal/g.
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('1125 kcal'), findsOneWidget);
    });
  });

  group('presentation', () {
    testWidgets('the food source is stated on the sheet', (tester) async {
      await pump(tester, food: paneer);
      // Which library it came from is what tells the member whether this is
      // the food their coach planned against.
      expect(find.text("Your coach's"), findsOneWidget);
    });

    testWidgets('all six meals are offered', (tester) async {
      await pump(tester, food: paneer);
      for (final label in [
        'Breakfast', 'Mid-Morning Snack', 'Lunch', 'Evening Snack',
        'Dinner', 'Bedtime',
      ]) {
        expect(find.text(label), findsWidgets, reason: '$label must be offered');
      }
    });

    testWidgets('a small phone at 2.0x accessibility text does not overflow',
        (tester) async {
      await pump(
        tester,
        food: paneer,
        size: const Size(320, 900),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('You will log'), findsOneWidget);
    });

    // Separate tests, not two pumps in one: the first sheet's route survives a
    // second pumpWidget and would cover the button the helper taps.
    testWidgets('in landscape the figure is still visible at the moment of '
        'commitment', (tester) async {
      // A 390dp-tall viewport caps the sheet at ~351dp, so the preview CARD
      // scrolls below the fold. The guarantee is not "the card is visible" —
      // it is that the member never commits to a number they have not seen.
      // The action bar is PINNED and repeats the figure, which is why it
      // repeats it at all.
      await pump(tester, food: paneer, size: const Size(844, 390));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Add to Lunch · 375 kcal'), findsOneWidget);
    });

    testWidgets('tablet renders cleanly', (tester) async {
      await pump(tester, food: paneer, size: const Size(1024, 1366));
      expect(tester.takeException(), isNull);
      expect(find.text('375 kcal'), findsOneWidget);
    });

    testWidgets('light mode renders cleanly', (tester) async {
      await pump(tester, food: paneer, theme: AppTheme.light);
      expect(tester.takeException(), isNull);
      expect(find.text('375 kcal'), findsOneWidget);
    });
  });
}
