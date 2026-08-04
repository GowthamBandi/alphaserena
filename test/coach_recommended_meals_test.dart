import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/nutrition/coach_recommended_meals.dart';
import 'package:alphaserena/screens/dashboard/plans/plan_segmented_control.dart';

/// THE COACH'S PLAN — one implementation, two surfaces.
///
/// My Plans' whole first job is *"what has my trainer assigned me?"*, and on
/// the Diet tab it answered with two number chips (`Plan items 2 · Meals 1`)
/// while the prescribed foods lived on a screen the member had to go and find.
/// This section is now on both, and it is the SAME widget — the coach's own
/// words are the last thing that should be phrased two ways.

Map<String, dynamic> _food(
  String name, {
  String meal = 'Breakfast',
  String quantity = '',
  num? grams,
  double calories = 116,
}) =>
    {
      'name': name,
      'meal': meal,
      if (quantity.isNotEmpty) 'quantity': quantity,
      'grams': ?grams,
      'calories': calories,
    };

Future<void> _pump(
  WidgetTester tester,
  List<Map<String, dynamic>> items, {
  String note = '',
  String planName = '',
  Color? accent,
  Size size = const Size(390, 1400),
  double textScale = 1.0,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  Get.testMode = true;
  await tester.pumpWidget(
    GetMaterialApp(
      theme: theme ?? AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: CoachRecommendedMeals(
              items: items,
              note: note,
              planName: planName,
              accent: accent,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  testWidgets('the prescribed foods, with the coach\'s own amounts',
      (tester) async {
    await _pump(tester, [
      _food('Boiled Egg', quantity: '1.5 egg (75 g)', calories: 116),
      _food('Whole Cow Milk', grams: 100, calories: 73),
    ]);

    expect(find.text('BREAKFAST'), findsOneWidget);
    expect(find.text('Boiled Egg'), findsOneWidget);
    // The coach's PORTION is preferred over grams — it is what they chose.
    expect(find.text('1.5 egg (75 g)'), findsOneWidget);
    // Grams are the fallback where no portion was authored.
    expect(find.text('100 g'), findsOneWidget);
    // The meal header sums its foods.
    expect(find.text('189 kcal'), findsOneWidget);
  });

  testWidgets('meals render in CANONICAL order, not the order authored',
      (tester) async {
    await _pump(tester, [
      _food('Chicken', meal: 'Dinner'),
      _food('Oats', meal: 'Breakfast'),
      _food('Rice', meal: 'Lunch'),
    ]);

    final headers = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((d) => d == 'BREAKFAST' || d == 'LUNCH' || d == 'DINNER')
        .toList();
    expect(headers, ['BREAKFAST', 'LUNCH', 'DINNER']);
  });

  testWidgets('free-text coach meal labels land in canonical buckets',
      (tester) async {
    // "Snacks" is a legacy label; the food log files it under the canonical
    // snack slot. If this section used the raw string the same meal would
    // appear under two different headings on one screen.
    await _pump(tester, [
      _food('Almonds', meal: 'Snacks'),
      _food('Walnuts', meal: 'snack'),
    ]);
    expect(find.text('Almonds'), findsOneWidget);
    expect(find.text('Walnuts'), findsOneWidget);
    // Both landed in ONE group, so there is a single header and a single total.
    expect(find.text('232 kcal'), findsOneWidget);
  });

  testWidgets('the coach\'s note renders, verbatim', (tester) async {
    await _pump(tester, [_food('Oats')],
        note: 'Keep protein high on training days.');
    expect(find.text('Keep protein high on training days.'), findsOneWidget);
  });

  testWidgets('NO note is invented when the coach wrote none', (tester) async {
    await _pump(tester, [_food('Oats')]);
    expect(find.byIcon(Icons.format_quote_rounded), findsNothing);
  });

  testWidgets('nothing at all renders with no plan items', (tester) async {
    await _pump(tester, const []);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a food with no calories states none rather than "0 kcal"',
      (tester) async {
    await _pump(tester, [_food('Water', calories: 0)]);
    expect(find.text('Water'), findsOneWidget);
    // The meal header still totals (to zero); the FOOD row must not claim a
    // measured zero the coach never entered.
    expect(find.text('0 kcal'), findsOneWidget); // header only
  });

  group('the action wears the colour of the surface it sits on', () {
    testWidgets('default is the brand accent — correct on the Diet screen',
        (tester) async {
      await _pump(tester, [_food('Oats')]);
      final button = tester.widget<TextButton>(find.byType(TextButton));
      final fg = button.style!.foregroundColor!.resolve({});
      expect(fg, isNot(PlanSegmentedControl.dietFill));
    });

    testWidgets('My Plans passes its green — no red button in a green tab',
        (tester) async {
      await _pump(
        tester,
        [_food('Oats')],
        accent: PlanSegmentedControl.dietFill,
      );
      final button = tester.widget<TextButton>(find.byType(TextButton));
      expect(
        button.style!.foregroundColor!.resolve({}),
        PlanSegmentedControl.dietFill,
      );
    });
  });

  testWidgets('renders at 2.0x text on a 320dp screen without overflow',
      (tester) async {
    await _pump(
      tester,
      [
        _food('Boiled Egg', quantity: '1.5 egg (75 g)'),
        _food('Whole Cow Milk', grams: 100, calories: 73),
        _food('Grilled Chicken Breast', meal: 'Lunch', grams: 200,
            calories: 330),
      ],
      note: 'Keep protein high on training days and hydrate between meals.',
      size: const Size(320, 2200),
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in the light theme', (tester) async {
    await _pump(tester, [_food('Oats')], theme: AppTheme.light);
    expect(tester.takeException(), isNull);
    expect(find.text('Oats'), findsOneWidget);
  });
}
