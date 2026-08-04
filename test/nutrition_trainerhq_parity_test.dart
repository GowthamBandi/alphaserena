import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/core/domain/nutrition_history.dart';
import 'package:alphaserena/core/models/nutrition_day_model.dart';

/// CROSS-APP PARITY — one nutrition day, as the member sees it and as the
/// coach sees it.
///
/// ── WHY THIS FILE EXISTS ──────────────────────────────────────────────────
///
/// Nutrition History reads `client_nutrition_days` — the same documents
/// TrainerHQ opens on the coach's side. If the two ever disagree about what a
/// member ate, one of them is lying to somebody making decisions about food,
/// and neither app can tell which. Workout logs gained this guard when the
/// member app learned to REWRITE them; nutrition needs it because the member
/// app now RE-READS them on a second surface.
///
/// ── WHAT IS TWINNED, AND WHY IT IS COPIED ─────────────────────────────────
///
/// `_CoachNutritionDay` is a VERBATIM transcription of TrainerHQ's
/// `lib/core/models/client_nutrition_day_model.dart` — `fromMap`, its live
/// entry filter, its seven-nutrient key list and `consumedForNutritionDay`.
/// Duplicated deliberately, exactly as the diet and workout parity fixtures
/// are: the two apps are separate binaries with no shared package, and a
/// fixture that could drift on one side without failing on the other would
/// defeat the purpose.
///
/// ⚠️ If TrainerHQ's model changes, THIS FILE MUST CHANGE WITH IT.
///
/// ── THE STRONGEST GUARANTEE IS STRUCTURAL, NOT TESTED HERE ────────────────
///
/// **Nutrition History writes nothing.** It has no service of its own, no
/// document of its own and no write path: the screen reads days, and its one
/// mutating affordance ("Edit Food Log", today only) navigates to the existing
/// `DietScreen`, whose `FoodLogController` owns the only writer. So there is
/// no second producer for the coach's copy to diverge from — the module is a
/// second READER of one store, which is what "no duplicate storage, no
/// parallel models" means in practice.

// ═══════════════════════════════════════════════════════════════════════════
// THE COACH'S PARSER — transcribed from TrainerHQ, unchanged
// ═══════════════════════════════════════════════════════════════════════════

double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

class _CoachNutritionDay {
  final String id;
  final String dateKey;
  final List<Map<String, double>> liveConsumed;

  const _CoachNutritionDay({
    required this.id,
    this.dateKey = '',
    this.liveConsumed = const [],
  });

  factory _CoachNutritionDay.fromMap(Map<String, dynamic> m, String id) {
    final out = <Map<String, double>>[];
    final raw = m['entries'];
    if (raw is Map) {
      for (final e in raw.values) {
        if (e is! Map) continue;
        if (e['deleted'] == true) continue;
        final c = e['consumed'];
        if (c is! Map) continue;
        final snapshot = <String, double>{};
        for (final k in const [
          'calories', 'protein', 'carbs', 'fat', 'fiber', 'sugar',
          'saturatedFat',
        ]) {
          final v = _num(c[k]);
          // ABSENT stays absent, on the coach's side.
          if (v != null) snapshot[k] = v;
        }
        if (snapshot.isNotEmpty) out.add(snapshot);
      }
    }
    return _CoachNutritionDay(
      id: id,
      dateKey: (m['dateKey'] ?? '').toString(),
      liveConsumed: out,
    );
  }

  bool get hasEntries => liveConsumed.isNotEmpty;
  int get entryCount => liveConsumed.length;

  double? sumOf(String key) {
    var sum = 0.0;
    var any = false;
    for (final entry in liveConsumed) {
      final v = entry[key];
      if (v == null) continue;
      any = true;
      sum += v;
    }
    return any ? sum : null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════

/// One wire document, in the exact shape `NutritionDayService` writes.
Map<String, dynamic> _wireDay({
  required String dateKey,
  required List<Map<String, dynamic>> entries,
}) =>
    {
      'dateKey': dateKey,
      'adminId': 'admin_1',
      'entries': {
        for (var i = 0; i < entries.length; i++) 'e$i': entries[i],
      },
    };

Map<String, dynamic> _wireEntry({
  required String foodName,
  String mealSlot = 'lunch',
  double? calories = 300,
  double? protein = 20,
  double? carbs = 30,
  double? fat = 10,
  double? fiber = 4,
  bool deleted = false,
  int? loggedAt,
}) =>
    {
      'foodName': foodName,
      'mealSlot': mealSlot,
      'quantity': 1,
      'unit': 'katori',
      'loggedAt': ?loggedAt,
      if (deleted) 'deleted': true,
      // A null macro is OMITTED from the wire map, which is the whole point of
      // the divergence group below: the coach's parser then never sees the key.
      'consumed': {
        'calories': ?calories,
        'protein': ?protein,
        'carbs': ?carbs,
        'fat': ?fat,
        'fiber': ?fiber,
      },
    };

/// The member's read of the document.
NutritionDayLog _member(Map<String, dynamic> doc, String dateKey) {
  final model = NutritionDayModel.fromMap(doc, 'c1_$dateKey');
  final parts = dateKey.split('-').map(int.parse).toList();
  return NutritionDayLog(
    dateKey: dateKey,
    date: DateTime(parts[0], parts[1], parts[2]),
    day: model,
  );
}

/// The coach's read of the SAME document.
_CoachNutritionDay _coach(Map<String, dynamic> doc, String dateKey) =>
    _CoachNutritionDay.fromMap(doc, 'c1_$dateKey');

void main() {
  const key = '2026-08-02';

  group('both apps read the same day the same way', () {
    test('a straightforward day agrees on every macro', () {
      final doc = _wireDay(dateKey: key, entries: [
        _wireEntry(
            foodName: 'Oats',
            mealSlot: 'breakfast',
            calories: 200,
            protein: 8,
            carbs: 35,
            fat: 4,
            fiber: 6),
        _wireEntry(
            foodName: 'Paneer Tikka',
            calories: 400,
            protein: 27,
            carbs: 12,
            fat: 24,
            fiber: 2),
      ]);
      final mine = _member(doc, key);
      final theirs = _coach(doc, key);

      // If these ever disagree, the member and their coach are reading
      // different truths off ONE document.
      expect(mine.calories, theirs.sumOf('calories'));
      expect(mine.protein, theirs.sumOf('protein'));
      expect(mine.carbs, theirs.sumOf('carbs'));
      expect(mine.fat, theirs.sumOf('fat'));
      expect(mine.fiber, theirs.sumOf('fiber'));
      expect(mine.entryCount, theirs.entryCount);

      // And the absolute values, so a shared bug cannot make both agree on
      // something wrong.
      expect(mine.calories, 600);
      expect(mine.protein, 35);
    });

    test('a soft-deleted entry is excluded by BOTH', () {
      final doc = _wireDay(dateKey: key, entries: [
        _wireEntry(foodName: 'Rice', calories: 300),
        _wireEntry(foodName: 'Cake', calories: 500, deleted: true),
      ]);
      final mine = _member(doc, key);
      final theirs = _coach(doc, key);

      // The data is never destroyed, but a removed food is not part of what
      // the member ate — on either side.
      expect(mine.entryCount, 1);
      expect(theirs.entryCount, 1);
      expect(mine.calories, 300);
      expect(theirs.sumOf('calories'), 300);
    });

    test('a day emptied of live entries reads as empty on BOTH', () {
      final doc = _wireDay(dateKey: key, entries: [
        _wireEntry(foodName: 'Cake', deleted: true),
      ]);
      expect(_member(doc, key).hasEntries, isFalse);
      expect(_coach(doc, key).hasEntries, isFalse);
    });

    test('a document with no entries map at all is survivable on BOTH', () {
      final doc = {'dateKey': key, 'adminId': 'admin_1'};
      // Nothing throws, and neither side invents a day.
      expect(_member(doc, key).hasEntries, isFalse);
      expect(_coach(doc, key).hasEntries, isFalse);
    });

    test('string-encoded macros parse identically', () {
      // Both sides tolerate a number that arrived as a string — a legacy
      // shape, and one neither app may reject.
      final doc = {
        'dateKey': key,
        'entries': {
          'e0': {
            'foodName': 'Rice',
            'mealSlot': 'lunch',
            'consumed': {'calories': '250', 'protein': '9'},
          },
        },
      };
      expect(_member(doc, key).calories, 250);
      expect(_coach(doc, key).sumOf('calories'), 250);
      expect(_member(doc, key).protein, 9);
      expect(_coach(doc, key).sumOf('protein'), 9);
    });
  });

  group('the fields only the MEMBER renders still survive the wire', () {
    test('meal, food name, amount and time all parse', () {
      // TrainerHQ needs only the day's totals, so it parses none of these.
      // The member's history renders all four, and they must come off the
      // document rather than being reconstructed.
      final doc = _wireDay(dateKey: key, entries: [
        _wireEntry(
          foodName: 'Paneer Tikka',
          mealSlot: 'lunch',
          loggedAt: DateTime(2026, 8, 2, 13, 30).millisecondsSinceEpoch,
        ),
      ]);
      final mine = _member(doc, key);
      final meal = mine.meals.single;
      expect(meal.slot, 'lunch');
      expect(meal.label, 'Lunch');
      expect(meal.entries.single.foodName, 'Paneer Tikka');
      expect(entryAmountLabel(meal.entries.single), '1 katori');
      expect(meal.time, DateTime(2026, 8, 2, 13, 30));
    });

    test('a free-text meal slug is canonicalised, never lost', () {
      final doc = _wireDay(dateKey: key, entries: [
        _wireEntry(foodName: 'Tea', mealSlot: 'Tea Time'),
      ]);
      // `canonicalMealSlot` files it rather than dropping it — a member's food
      // is never lost to a spelling.
      expect(_member(doc, key).meals.single.slot, 'evening_snack');
      // And the coach still counts it, because totals do not care about slots.
      expect(_coach(doc, key).entryCount, 1);
    });
  });

  group('KNOWN DIVERGENCE — an unrecorded nutrient', () {
    test('the coach reads null where the member reads zero', () {
      // ⚠️ PINNED DELIBERATELY, because it is real and it is NOT introduced by
      // this module.
      //
      // TrainerHQ keeps a nutrient ABSENT when no entry recorded it, so its
      // UI can say "unknown". The member app's `ConsumedSnapshot.fromMap`
      // coerces every missing macro to 0 at PARSE time — app-wide, and long
      // before Nutrition History existed — so by the time any member surface
      // holds the model, "nobody recorded fiber" and "ate no fiber" are the
      // same value and cannot be told apart.
      //
      // The bounded consequence: a day whose foods carry no fiber figure reads
      // "Fiber 0 g" here and "unknown" on the coach's screen. Every other
      // macro, and every food in the library that carries a full set, agrees
      // exactly — see the group above.
      //
      // Fixing it properly means making `ConsumedSnapshot`'s fields nullable,
      // which changes Home, the Diet screen and My Plans as well. That is a
      // model change, not a history change, so it is documented here rather
      // than half-done inside one screen.
      final doc = _wireDay(dateKey: key, entries: [
        _wireEntry(foodName: 'Chicken', calories: 250, protein: 46, fiber: null),
      ]);
      expect(_coach(doc, key).sumOf('fiber'), isNull);
      expect(_member(doc, key).fiber, 0);

      // The macros that WERE recorded still agree exactly, which bounds the
      // divergence to the unrecorded one.
      expect(_member(doc, key).calories, _coach(doc, key).sumOf('calories'));
      expect(_member(doc, key).protein, _coach(doc, key).sumOf('protein'));
    });
  });

  group('the module adds no writer', () {
    test('a day read and re-read is unchanged — history mutates nothing', () {
      final doc = _wireDay(dateKey: key, entries: [
        _wireEntry(foodName: 'Rice', calories: 300),
        _wireEntry(foodName: 'Dal', mealSlot: 'dinner', calories: 200),
      ]);
      final first = _member(doc, key);
      final second = _member(doc, key);
      // The history path is pure READ: parsing twice yields the same figures,
      // and nothing on this path serialises a document back.
      expect(second.calories, first.calories);
      expect(second.entryCount, first.entryCount);
      expect(second.meals.map((m) => m.slot), first.meals.map((m) => m.slot));
    });
  });
}
