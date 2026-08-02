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
  _mealVocabulary();
  _phase2Entries();
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

/// PHASE 2 — the entry fields that make a logged day readable, and the
/// offline/merge properties the `entries` MAP exists to provide.
///
/// Every field asserted here is pinned byte-for-byte against the backend
/// contract in `functions/test/nutrition.test.mjs`. The two are separate
/// binaries with no shared package, so a drift on one side must fail on it.
void _phase2Entries() {
  Map<String, dynamic> raw({Map<String, dynamic> over = const {}}) => {
        'source': 'search',
        'foodId': 'food_paneer',
        'foodName': 'Paneer Bhurji',
        'foodTier': 'org',
        'mealSlot': 'Breakfast',
        'quantity': 150,
        'unit': 'g',
        'consumed': {
          'calories': 265, 'protein': 18, 'carbs': 6,
          'fat': 20, 'fiber': 1, 'sugar': 2, 'saturatedFat': 11,
        },
        'loggedAt': 1786000000000,
        'note': 'extra oil',
        ...over,
      };

  group('a logged entry carries what a coach needs to read it', () {
    test('every Phase 2 field parses', () {
      final e = FoodEntry.fromMap('e1', raw());
      expect(e.foodName, 'Paneer Bhurji');
      expect(e.foodTier, FoodTier.org);
      expect(e.quantity, 150);
      expect(e.unit, 'g');
      expect(e.loggedAt, 1786000000000);
      expect(e.note, 'extra oil');
      // Canonicalized on parse: 'Breakfast' is a LABEL, 'breakfast' is the
      // stored identity.
      expect(e.mealSlot, 'breakfast');
      expect(e.source, FoodEntrySource.search);
    });

    test('the label survives even if the library food is later deleted', () {
      // The point of snapshotting: no join, and no blank row a month later.
      final e = FoodEntry.fromMap('e1', raw(over: {'foodId': ''}));
      expect(e.foodId, isNull);
      expect(e.foodName, 'Paneer Bhurji');
    });

    test('absent optional fields degrade to safe defaults, never throw', () {
      final e = FoodEntry.fromMap('e1', {'mealSlot': 'Lunch'});
      expect(e.mealSlot, 'lunch');
      expect(e.foodName, '');
      expect(e.foodTier, isNull);
      expect(e.quantity, isNull);
      expect(e.unit, '');
      expect(e.loggedAt, isNull);
      expect(e.note, isNull);
      expect(e.source, FoodEntrySource.quick, reason: 'backend default');
    });

    test('an unknown foodTier parses to null rather than guessing', () {
      expect(FoodEntry.fromMap('e', raw(over: {'foodTier': 'usda'})).foodTier,
          isNull);
    });

    test('a blank note is null, not an empty string', () {
      expect(FoodEntry.fromMap('e', raw(over: {'note': '   '})).note, isNull);
    });
  });

  group('serialization round-trips', () {
    test('toMap → fromMap preserves every field', () {
      final original = FoodEntry.fromMap('e1', raw());
      final round = FoodEntry.fromMap('e1', original.toMap());
      expect(round.foodName, original.foodName);
      expect(round.foodTier, original.foodTier);
      expect(round.quantity, original.quantity);
      expect(round.unit, original.unit);
      expect(round.loggedAt, original.loggedAt);
      expect(round.note, original.note);
      expect(round.consumed.calories, original.consumed.calories);
      expect(round.consumed.fiber, original.consumed.fiber);
    });

    test('the entryId is the MAP KEY and is never written inside the value',
        () {
      // Duplicating it would let the two disagree after a partial merge.
      expect(FoodEntry.fromMap('e1', raw()).toMap().containsKey('entryId'),
          isFalse);
    });

    test('empty optionals are OMITTED, so a merge cannot erase a sibling', () {
      final m = const FoodEntry(entryId: 'e', mealSlot: 'Lunch').toMap();
      for (final k in ['foodName', 'foodTier', 'quantity', 'unit', 'loggedAt',
        'note', 'planStatus', 'deleted']) {
        expect(m.containsKey(k), isFalse, reason: '$k must be omitted');
      }
    });
  });

  group('offline + concurrent-edit properties of the entries MAP', () {
    test('two members-devices adding different foods merge, never clobber', () {
      // Each entry is one field path (`entries.<entryId>`), so a Firestore
      // merge of two offline writes keeps BOTH — the property an array or a
      // recomputed total cannot provide.
      final deviceA = {'e_a': raw(over: {'foodName': 'Oats'})};
      final deviceB = {'e_b': raw(over: {'foodName': 'Eggs'})};
      final merged = {...deviceA, ...deviceB};
      final entries = merged.entries
          .map((e) => FoodEntry.fromMap(e.key, e.value))
          .toList();
      expect(entries.map((e) => e.foodName), containsAll(['Oats', 'Eggs']));
    });

    test('a correction SOFT-deletes; the record is never destroyed', () {
      final e = FoodEntry.fromMap('e1', raw(over: {'deleted': true}));
      expect(e.deleted, isTrue);
      expect(e.foodName, 'Paneer Bhurji', reason: 'withdrawn, still recorded');
      expect(e.consumed.calories, 265);
    });

    test('a partial-merge delete keeps the original payload', () {
      // `{deleted:true}` merges INTO the stored entry — the same contract the
      // lifestyle events rely on, verified there against a real Firestore.
      final stored = raw();
      final afterMerge = {...stored, 'deleted': true};
      final e = FoodEntry.fromMap('e1', afterMerge);
      expect(e.deleted, isTrue);
      expect(e.quantity, 150);
      expect(e.unit, 'g');
    });
  });
}

/// MEAL VOCABULARY — pinned byte-for-byte against the backend's
/// `MEAL_SLOTS` / `MEAL_LABELS` / `canonicalMealSlot` (twin assertions live in
/// `functions/test/nutrition.test.mjs`). Separate binaries, no shared package:
/// a drift on either side must fail on that side.
void _mealVocabulary() {
  group('one taxonomy, one ordering, one alias table', () {
    test('the six canonical slots in canonical order', () {
      expect(kMealSlots, [
        'breakfast', 'mid_morning', 'lunch', 'evening_snack', 'dinner',
        'bedtime',
      ]);
      expect(kMealSlots.map(mealSlotOrder), [0, 1, 2, 3, 4, 5]);
      expect(mealSlotOrder(kOtherMealSlot), kMealSlots.length);
    });

    test('labels live in one place, so a rename touches no document', () {
      expect(kMealLabels['mid_morning'], 'Mid-Morning Snack');
      expect(canonicalMealSlot('Mid-morning'), 'mid_morning');
      expect(canonicalMealSlot('Mid-Morning Snack'), 'mid_morning');
    });

    test('case, spacing and punctuation normalize to one slug', () {
      for (final s in ['Breakfast', 'BREAKFAST', '  Breakfast ',
        'Morning Breakfast']) {
        expect(canonicalMealSlot(s), 'breakfast', reason: s);
      }
      for (final s in ['MidMorning', 'Mid Morning', 'mid-morning snack']) {
        expect(canonicalMealSlot(s), 'mid_morning', reason: s);
      }
    });

    test("legacy 'Snacks' folds into Evening Snack, as TrainerHQ does", () {
      expect(canonicalMealSlot('Snacks'), 'evening_snack');
      expect(canonicalMealSlot('Evening Snack'), 'evening_snack');
    });

    test('an unknown meal becomes Other, never an arbitrary string', () {
      expect(canonicalMealSlot('Second Elevenses'), kOtherMealSlot);
      expect(canonicalMealSlot(''), kOtherMealSlot);
      expect(canonicalMealSlot(null), kOtherMealSlot);
    });

    test('a parsed entry is always canonical', () {
      expect(FoodEntry.fromMap('e', {'mealSlot': 'Tea Time'}).mealSlot,
          'evening_snack');
      expect(FoodEntry.fromMap('e', {}).mealSlot, kOtherMealSlot);
    });
  });

  group('meal time is DERIVED, never stored', () {
    FoodEntry at(int? ms, {bool deleted = false}) => FoodEntry(
          entryId: 'e$ms',
          mealSlot: 'lunch',
          loggedAt: ms,
          deleted: deleted,
        );

    test('the meal started at its EARLIEST logged entry', () {
      expect(mealStartedAt([at(300), at(100), at(200)]), 100);
    });

    test('entries with no stated time are skipped, not treated as zero', () {
      expect(mealStartedAt([at(null), at(500)]), 500);
    });

    test('a meal nobody timed has no time — not a fabricated zero', () {
      expect(mealStartedAt([at(null), at(null)]), isNull);
      expect(mealStartedAt(const []), isNull);
    });

    test('a withdrawn entry cannot set the meal time', () {
      expect(mealStartedAt([at(100, deleted: true), at(400)]), 400);
    });
  });
}
