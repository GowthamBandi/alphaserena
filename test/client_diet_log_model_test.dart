import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/models/client_diet_log_model.dart';

/// V2A: a logged food carries a stable [DietLogItem.foodId] so downstream
/// readers (coach review, analytics, restore) address it by identity, not name
/// or array position. Additive + wire-safe: legacy logs without foodId read ''.
void main() {
  group('DietLogItem foodId (V2A identity)', () {
    test('round-trips foodId through toMap/fromMap', () {
      const item = DietLogItem(
        idx: 0,
        foodId: 'food-123',
        foodName: 'Oats',
        meal: 'Breakfast',
        status: 'eaten',
        calories: 150,
      );
      final map = item.toMap();
      expect(map['foodId'], 'food-123');

      final back = DietLogItem.fromMap(map);
      expect(back.foodId, 'food-123');
      expect(back.foodName, 'Oats');
      expect(back.meal, 'Breakfast');
      expect(back.idx, 0);
    });

    test('legacy item without foodId reads as empty (wire-safe)', () {
      final back = DietLogItem.fromMap(
        {'foodName': 'Rice', 'status': 'eaten', 'idx': 1},
      );
      expect(back.foodId, '');
    });

    test('omits foodId from the map when empty (no wire bloat)', () {
      const item = DietLogItem(
        idx: 0,
        foodId: '',
        foodName: 'X',
        status: 'eaten',
      );
      expect(item.toMap().containsKey('foodId'), isFalse);
    });
  });

  group('DietLogItem consumed-nutrition snapshot (V2B)', () {
    test('round-trips all 7 macros through toMap/fromMap', () {
      const item = DietLogItem(
        idx: 0,
        foodId: 'f',
        foodName: 'Oats',
        status: 'eaten',
        calories: 150,
        protein: 5,
        carbs: 27,
        fat: 3,
        fiber: 4,
        sugar: 1,
        saturatedFat: 0.5,
      );
      final back = DietLogItem.fromMap(item.toMap());
      expect(back.calories, 150);
      expect(back.protein, 5);
      expect(back.carbs, 27);
      expect(back.fat, 3);
      expect(back.fiber, 4);
      expect(back.sugar, 1);
      expect(back.saturatedFat, 0.5);
    });

    test('legacy item without macros reads null (wire-safe)', () {
      final back = DietLogItem.fromMap(
        {'foodName': 'Rice', 'status': 'eaten', 'idx': 1},
      );
      expect(back.protein, isNull);
      expect(back.carbs, isNull);
      expect(back.fat, isNull);
      expect(back.fiber, isNull);
      expect(back.sugar, isNull);
      expect(back.saturatedFat, isNull);
    });

    test('omits null macros from the map (no wire bloat)', () {
      const item = DietLogItem(idx: 0, foodName: 'X', status: 'eaten');
      final map = item.toMap();
      for (final k in ['protein', 'carbs', 'fat', 'fiber', 'sugar', 'saturatedFat']) {
        expect(map.containsKey(k), isFalse, reason: '$k must be omitted when null');
      }
    });
  });

  group('DietLogItem.fromServedFood (V2B write-path mapping)', () {
    test('copies identity + all 7 nutrients from the served food map', () {
      // Mirrors the getMyTraining served-item shape (key "name", not "foodName").
      final f = <String, dynamic>{
        'foodId': 'f1',
        'name': 'Oats',
        'quantity': '1 bowl',
        'meal': 'Breakfast',
        'calories': 150,
        'protein': 5,
        'carbs': 27,
        'fat': 3,
        'fiber': 4,
        'sugar': 1,
        'saturatedFat': 0.5,
      };
      final item = DietLogItem.fromServedFood(f, idx: 2, status: 'eaten');
      expect(item.idx, 2);
      expect(item.status, 'eaten');
      expect(item.foodId, 'f1');
      expect(item.foodName, 'Oats');
      expect(item.quantity, '1 bowl');
      expect(item.meal, 'Breakfast');
      expect(item.calories, 150);
      expect(item.protein, 5);
      expect(item.carbs, 27);
      expect(item.fat, 3);
      expect(item.fiber, 4);
      expect(item.sugar, 1);
      expect(item.saturatedFat, 0.5);
    });

    test('leaves macros null for a legacy served food without them', () {
      final item = DietLogItem.fromServedFood(
        {'name': 'Rice'},
        idx: 0,
        status: 'skipped',
      );
      expect(item.foodName, 'Rice');
      expect(item.foodId, '');
      expect(item.calories, isNull);
      expect(item.protein, isNull);
      expect(item.saturatedFat, isNull);
    });

    test('defaults the food name when the served map has none', () {
      final item = DietLogItem.fromServedFood({}, idx: 0, status: 'eaten');
      expect(item.foodName, 'Food');
    });
  });
}
