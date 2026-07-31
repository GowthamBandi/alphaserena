import 'package:alphaserena/core/models/served_diet.dart';
import 'package:flutter_test/flutter_test.dart';

/// NIP PHASE A — the typed view of `getMyTraining.diet`.
///
/// The model must parse BOTH wires: the NIP backend (description + `targets`
/// map + per-item entryId/grams/portions) and the legacy backend (flat targets
/// only, no additive keys) — the same binary meets both during rollout.
void main() {
  Map<String, dynamic> nipWire() => {
        'name': 'Cut Week 3',
        'description': 'High protein, low sugar. Water first thing.',
        'items': [
          {
            'name': 'Oats',
            'foodId': 'oats',
            'entryId': 'e-001',
            'quantity': '',
            'meal': 'Breakfast',
            'grams': 80,
            'portionLabel': 'bowl',
            'portionQty': 1,
            'calories': 303,
            'protein': 10.6,
            'carbs': 54.1,
            'fat': 5.3,
            'fiber': 8.1,
            'sugar': 0.8,
            'saturatedFat': 0.9,
          },
          {
            // Legacy freehand item: no foodId/entryId/grams/portions.
            'name': 'Black Coffee',
            'foodId': '',
            'quantity': '1 cup',
            'meal': 'Breakfast',
            'calories': 5,
          },
        ],
        'targetCalories': 2000,
        'targetProtein': 150,
        'targetCarbs': null,
        'targetFat': null,
        'targetFiber': null,
        'targets': {
          'calories': 2000,
          'protein': 150,
          'carbs': null,
          'fat': null,
          'fiber': null,
          'waterMl': 3000,
          'micros': {'iron': 18, 'calcium': 1000},
          'note': 'Cut phase',
          'version': 4,
          'source': 'nutritionTargets',
        },
      };

  group('NIP wire', () {
    test('parses name, description, targets map and both item shapes', () {
      final d = ServedDiet.fromMap(nipWire());
      expect(d.name, 'Cut Week 3');
      expect(d.description, contains('High protein'));
      expect(d.items.length, 2);

      final oats = d.items.first;
      expect(oats.entryId, 'e-001');
      expect(oats.foodId, 'oats');
      expect(oats.grams, 80);
      expect(oats.portionLabel, 'bowl');
      expect(oats.portionQty, 1);
      expect(oats.calories, 303);
      expect(oats.sugar, 0.8);
      expect(oats.saturatedFat, 0.9);

      final coffee = d.items[1];
      expect(coffee.entryId, isNull);
      expect(coffee.grams, isNull);
      expect(coffee.portionLabel, isNull);
      expect(coffee.protein, isNull); // absent macro stays null, not 0

      final t = d.targets!;
      expect(t.hasTargets, isTrue);
      expect(t.source, 'nutritionTargets');
      expect(t.calories, 2000);
      expect(t.carbs, isNull);
      expect(t.waterMl, 3000);
      expect(t.micros, {'iron': 18, 'calcium': 1000});
      expect(t.note, 'Cut phase');
      expect(t.version, 4);
    });

    test('flat legacy targets are carried unchanged alongside the map', () {
      final d = ServedDiet.fromMap(nipWire());
      expect(d.targetCalories, 2000);
      expect(d.targetProtein, 150);
      expect(d.targetCarbs, isNull);
    });
  });

  group('legacy wire (old backend)', () {
    test('no additive keys → description empty, targets null, items parse', () {
      final d = ServedDiet.fromMap({
        'name': 'Old Plan',
        'items': [
          {'name': 'Rice', 'meal': 'Lunch', 'calories': 260},
        ],
        'targetCalories': 1800,
      });
      expect(d.description, '');
      expect(d.targets, isNull);
      expect(d.targetCalories, 1800);
      expect(d.items.single.name, 'Rice');
      expect(d.items.single.entryId, isNull);
    });
  });

  group('malformed wire never throws', () {
    test('empty map', () {
      final d = ServedDiet.fromMap(const {});
      expect(d.name, '');
      expect(d.items, isEmpty);
      expect(d.targets, isNull);
    });

    test('junk in every slot is coerced or skipped, never thrown', () {
      final d = ServedDiet.fromMap({
        'name': 42,
        'items': [
          'not-a-map',
          {'name': 'Egg', 'calories': 'abc', 'grams': '80'},
        ],
        'targets': {'calories': 'x', 'source': 'nutritionTargets'},
        'targetCalories': 'nope',
      });
      expect(d.name, '42');
      expect(d.items.length, 1); // the string entry is skipped
      expect(d.items.single.calories, isNull);
      expect(d.items.single.grams, 80); // string numbers still parse
      expect(d.targets!.calories, isNull);
      expect(d.targetCalories, isNull);
    });

    test("a 'targets' that is not a map is treated as absent", () {
      final d = ServedDiet.fromMap({'targets': 'oops'});
      expect(d.targets, isNull);
    });
  });
}
