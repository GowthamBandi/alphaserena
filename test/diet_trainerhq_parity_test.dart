import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/utils/diet_adherence.dart';
import 'package:alphaserena/core/domain/nutrition_targets.dart';

/// CROSS-APP PARITY — the member's numbers against the coach's.
///
/// The coach builds a plan in TrainerHQ and reads a day total there; the member
/// opens AlphaSerena and reads a day total here. If those two numbers ever
/// disagree, one of them is lying to somebody who is making decisions about
/// food, and neither app can tell which.
///
/// The fixture below is the SAME realistic athlete's day pinned in TrainerHQ's
/// `diet_builder_workflow_test.dart` — same eight foods, same grams, same
/// resolved macros, same expected totals. It is duplicated deliberately rather
/// than shared: the two apps are separate binaries with no common package, and
/// a fixture that could drift on one side without failing on the other would
/// defeat the purpose.
///
/// The structural reason parity holds is that neither side re-derives anything.
/// `buildDiet` forwards the resolved, gram-scaled values the coach's builder
/// stored, and both apps then perform a plain sum. Nothing rounds, rescales or
/// re-reads the food document in between.

/// One served food map, exactly as `getMyTraining` delivers it (key `name`, not
/// `foodName` — that rename happens in `dietItemForMember`).
Map<String, dynamic> served(
  String name,
  String meal, {
  required double kcal,
  required double p,
  required double c,
  required double f,
  double fiber = 0,
}) => {
      'name': name,
      'foodId': name.toLowerCase(),
      'meal': meal,
      'quantity': '',
      'calories': kcal,
      'protein': p,
      'carbs': c,
      'fat': f,
      'fiber': fiber,
    };

/// The identical day used by TrainerHQ's builder test.
final _day = <Map<String, dynamic>>[
  served('Oats', 'Breakfast',
      kcal: 303, p: 10.6, c: 54.1, f: 5.3, fiber: 8.1),
  served('Whole Egg', 'Breakfast',
      kcal: 155, p: 12.6, c: 1.1, f: 10.6),
  served('Banana', 'Mid-morning',
      kcal: 105, p: 1.3, c: 27, f: 0.4, fiber: 3.1),
  served('Chicken Breast', 'Lunch',
      kcal: 247.5, p: 46.5, c: 0, f: 5.4),
  served('Cooked Rice', 'Lunch',
      kcal: 260, p: 5.4, c: 56.4, f: 0.6, fiber: 0.8),
  served('Whey Shake', 'Post-workout',
      kcal: 120, p: 24, c: 3, f: 1.5, fiber: 0.5),
  served('Paneer', 'Dinner',
      kcal: 265, p: 18.3, c: 1.2, f: 20.8),
  served('Roti', 'Dinner',
      kcal: 213, p: 6.9, c: 45.9, f: 0.9, fiber: 5.4),
];

void main() {
  group('day totals match TrainerHQ exactly', () {
    test('calories, protein, carbs, fat and fiber all agree', () {
      // These five numbers are asserted to the same tolerance, against the same
      // fixture, in the coach app. Change one side and this fails.
      expect(sumMacro(_day, 'calories'), closeTo(1668.5, 0.01));
      expect(sumMacro(_day, 'protein'), closeTo(125.6, 0.01));
      expect(sumMacro(_day, 'carbs'), closeTo(188.7, 0.01));
      expect(sumMacro(_day, 'fat'), closeTo(45.5, 0.01));
      expect(sumMacro(_day, 'fiber'), closeTo(17.9, 0.01));
    });

    test('the prescription-derived target equals the same sum', () {
      // With no coach goal set, the member's target falls back to the plan sum.
      // It must be the identical number, resolved through the canonical rule
      // rather than a second adder.
      final t = resolveNutritionTarget(
        diet: const {},
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: _day,
      );
      expect(t.source, NutritionTargetSource.prescription);
      expect(t.value, closeTo(sumMacro(_day, 'calories'), 1e-9));
    });

    test('a coach goal overrides the sum and is labelled as a real goal', () {
      final t = resolveNutritionTarget(
        diet: const {'targetCalories': 2400},
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: _day,
      );
      expect(t.value, 2400);
      expect(t.isCoachGoal, isTrue);
    });
  });

  group('meal totals partition the day', () {
    /// The screen's grouping rule, mirrored: alias the one legacy label the
    /// coach app normalizes, and bucket a blank meal under a single heading.
    String canonical(String meal) {
      final m = meal.trim();
      if (m.isEmpty) return 'Meals';
      return {'snacks': 'Evening Snack'}[m.toLowerCase()] ?? m;
    }

    Map<String, List<Map<String, dynamic>>> group(
      List<Map<String, dynamic>> foods,
    ) {
      final out = <String, List<Map<String, dynamic>>>{};
      for (final f in foods) {
        out.putIfAbsent(canonical((f['meal'] ?? '').toString()), () => []).add(f);
      }
      return out;
    }

    test('every meal total sums to the day total — nothing lost or doubled', () {
      final grouped = group(_day);
      for (final key in ['calories', 'protein', 'carbs', 'fat']) {
        final perMeal = grouped.values
            .map((foods) => sumMacro(foods, key))
            .fold<double>(0, (a, b) => a + b);
        expect(
          perMeal,
          closeTo(sumMacro(_day, key), 1e-9),
          reason: '$key: meal totals must partition the day exactly',
        );
      }
    });

    test('a meal total is the plain sum of its foods', () {
      final lunch = group(_day)['Lunch']!;
      expect(lunch.length, 2);
      expect(sumMacro(lunch, 'calories'), closeTo(507.5, 0.01));
      expect(sumMacro(lunch, 'protein'), closeTo(51.9, 0.01));
    });

    test('the legacy "Snacks" label merges into Evening Snack, as it does for the coach', () {
      // TrainerHQ declares kMealAliases = {'Snacks': 'Evening Snack'} and groups
      // accordingly. Before this alias existed here, a legacy plan showed the
      // member two headings and two smaller totals where the coach saw one.
      final legacy = [
        served('Nuts', 'Snacks', kcal: 120, p: 4, c: 5, f: 10),
        served('Fruit', 'Evening Snack', kcal: 80, p: 1, c: 20, f: 0),
      ];
      final grouped = group(legacy);
      expect(grouped.keys, ['Evening Snack']);
      expect(sumMacro(grouped['Evening Snack']!, 'calories'), 200);
    });

    test('an unrecognised meal keeps its own label and its nutrition', () {
      // "Post-workout" is not one of the coach app's six slots. The member sees
      // the real label rather than a bucket, and the nutrition still reaches
      // the day total — a shake silently vanishing from the numbers would be
      // both wrong and invisible.
      final grouped = group(_day);
      expect(grouped.containsKey('Post-workout'), isTrue);
      expect(sumMacro(grouped['Post-workout']!, 'calories'), 120);
    });
  });

  group('consumed nutrition weights the same prescribed values', () {
    test('eaten = full, partial = half, skipped and unlogged = zero', () {
      final kcal = [for (final f in _day) (f['calories'] as num).toDouble()];
      // Ate breakfast fully, half the banana, skipped the shake, logged nothing
      // else — the shape of a normal half-finished day.
      final statuses = {0: 'eaten', 1: 'eaten', 2: 'partial', 5: 'skipped'};
      expect(
        consumedMacro(kcal, statuses),
        closeTo(303 + 155 + 52.5, 0.01),
      );
    });

    test('a fully eaten day consumes exactly the prescribed total', () {
      final kcal = [for (final f in _day) (f['calories'] as num).toDouble()];
      final all = {for (var i = 0; i < _day.length; i++) i: 'eaten'};
      expect(
        consumedMacro(kcal, all),
        closeTo(sumMacro(_day, 'calories'), 1e-9),
      );
      expect(dietAdherence(all, _day.length), 1.0);
    });

    test('an index beyond the plan is ignored rather than crashing', () {
      // Defensive against a stale log meeting a shortened plan.
      final kcal = [for (final f in _day) (f['calories'] as num).toDouble()];
      expect(consumedMacro(kcal, {99: 'eaten'}), 0);
    });
  });
}
