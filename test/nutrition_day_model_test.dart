import 'package:alphaserena/core/models/nutrition_day_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// NIP PHASE B WIRE CONTRACT — member-side mirror of
/// `client_nutrition_days/{clientId}_{dateKey}` (docs are NOT written in
/// Phase A; these tests pin the contract so Phase B plugs in schema-free).
///
/// Rules mirrored from the backend core (`lib/nutrition.ts`):
///  - `entries` is a MAP keyed by entryId;
///  - unknown `source` parses as 'quick' (never dropped);
///  - `foodId` '' means "no library food" → null;
///  - `computed` is server-owned: parsed, never serialized back.
void main() {
  Map<String, dynamic> entryWire({
    String source = 'plan',
    String? planStatus = 'eaten',
  }) =>
      {
        'source': source,
        'planEntryId': 'pe-1',
        'foodId': 'oats',
        'mealSlot': 'breakfast',
        'consumed': {
          'calories': 303,
          'protein': 10.6,
          'carbs': 54.1,
          'fat': 5.3,
          'fiber': 8.1,
          'sugar': 0.8,
          'saturatedFat': 0.9,
        },
        'planStatus': ?planStatus,
        'portionFactor': 0.5,
      };

  group('FoodEntry parsing', () {
    test('full plan-sourced entry round-trips through toMap/fromMap', () {
      final e = FoodEntry.fromMap('e-1', entryWire(planStatus: 'partial'));
      expect(e.entryId, 'e-1');
      expect(e.source, FoodEntrySource.plan);
      expect(e.planEntryId, 'pe-1');
      expect(e.foodId, 'oats');
      expect(e.mealSlot, 'breakfast');
      expect(e.consumed.calories, 303);
      expect(e.consumed.saturatedFat, 0.9);
      expect(e.planStatus, PlanEntryStatus.partial);
      expect(e.portionFactor, 0.5);
      expect(e.deleted, isFalse);

      final again = FoodEntry.fromMap('e-1', e.toMap());
      expect(again.source, e.source);
      expect(again.planEntryId, e.planEntryId);
      expect(again.foodId, e.foodId);
      expect(again.mealSlot, e.mealSlot);
      expect(again.consumed.toMap(), e.consumed.toMap());
      expect(again.planStatus, e.planStatus);
      expect(again.portionFactor, e.portionFactor);
      expect(again.deleted, e.deleted);
    });

    test("unknown source parses as 'quick' — data is never dropped", () {
      final e = FoodEntry.fromMap('x', entryWire(source: 'telepathy'));
      expect(e.source, FoodEntrySource.quick);
    });

    test("empty foodId means no library food (null), '' never leaks", () {
      final e = FoodEntry.fromMap('x', {'source': 'custom', 'foodId': ''});
      expect(e.foodId, isNull);
      expect(e.toMap().containsKey('foodId'), isFalse);
    });

    test('sparse entry: every absent field takes its safe default', () {
      final e = FoodEntry.fromMap('x', const {});
      expect(e.source, FoodEntrySource.quick);
      expect(e.planEntryId, isNull);
      expect(e.mealSlot, 'other');
      expect(e.consumed.calories, 0);
      expect(e.planStatus, isNull);
      expect(e.portionFactor, isNull);
      expect(e.deleted, isFalse);
    });

    test('unknown planStatus parses as null, not a guess', () {
      final e = FoodEntry.fromMap('x', entryWire(planStatus: 'devoured'));
      expect(e.planStatus, isNull);
    });

    test('deleted survives the round trip', () {
      final e = FoodEntry.fromMap('x', {'deleted': true});
      expect(e.deleted, isTrue);
      expect(FoodEntry.fromMap('x', e.toMap()).deleted, isTrue);
    });
  });

  group('NutritionDayModel', () {
    Map<String, dynamic> dayWire() => {
          'clientId': 'c1', // unknown-to-model fields must be tolerated
          'schemaVersion': 1,
          'dateKey': '2026-07-29',
          'entries': {
            'e-1': entryWire(),
            'e-2': entryWire(source: 'search', planStatus: null),
            'e-bad': 'not-a-map', // malformed value: skipped, never thrown
          },
          'computed': {
            'totals': {'calories': 606, 'protein': 21.2},
            'targetAdherence': {'calories': 0.303, 'protein': 0.141},
            'planCompliance': 1,
            'entryCount': 2,
          },
        };

    test('parses the entries MAP keyed by entryId', () {
      final day = NutritionDayModel.fromMap(dayWire(), 'c1_2026-07-29');
      expect(day.id, 'c1_2026-07-29');
      expect(day.dateKey, '2026-07-29');
      expect(day.entries.length, 2); // e-bad skipped
      expect(day.entries['e-1']!.source, FoodEntrySource.plan);
      expect(day.entries['e-2']!.source, FoodEntrySource.search);
      expect(day.liveEntries.length, 2);
    });

    test('server computed map parses read-only, sparse totals default to 0', () {
      final day = NutritionDayModel.fromMap(dayWire(), 'id');
      final c = day.computed!;
      expect(c.totals.calories, 606);
      expect(c.totals.fat, 0); // absent macro → 0, mirrors zeroTotals()
      expect(c.targetAdherence, {'calories': 0.303, 'protein': 0.141});
      expect(c.planCompliance, 1);
      expect(c.entryCount, 2);
    });

    test('toMap round-trips entries and NEVER writes computed', () {
      final day = NutritionDayModel.fromMap(dayWire(), 'id');
      final wire = day.toMap();
      expect(wire.containsKey('computed'), isFalse,
          reason: 'computed is server-owned; a member write must not claim it');
      final again = NutritionDayModel.fromMap(wire, 'id');
      expect(again.entries.keys.toSet(), day.entries.keys.toSet());
      expect(
        again.entries['e-1']!.consumed.toMap(),
        day.entries['e-1']!.consumed.toMap(),
      );
      expect(again.computed, isNull);
    });

    test('an empty or malformed doc parses to an empty day', () {
      expect(NutritionDayModel.fromMap(const {}, 'id').entries, isEmpty);
      final junk = NutritionDayModel.fromMap(
        {'entries': 'oops', 'computed': 42},
        'id',
      );
      expect(junk.entries, isEmpty);
      expect(junk.computed, isNull);
    });

    test('soft-deleted entries stay in the map but leave liveEntries', () {
      final day = NutritionDayModel.fromMap({
        'entries': {
          'e-1': entryWire(),
          'e-2': {...entryWire(), 'deleted': true},
        },
      }, 'id');
      expect(day.entries.length, 2);
      expect(day.liveEntries.map((e) => e.entryId), ['e-1']);
    });
  });
}
