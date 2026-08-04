import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/food_portion_math.dart';
import 'package:alphaserena/core/models/member_food.dart';
import 'package:alphaserena/core/models/nutrition_day_model.dart';
import 'package:alphaserena/core/services/nutrition_day_service.dart';

/// THE FOOD-LOG WIRE SHAPE — what actually reaches `client_nutrition_days`.
///
/// These assert the SERIALIZED entry, not the widget that produced it, because
/// every guarantee this feature makes lives in the bytes: the frozen snapshot,
/// the snapshotted label, the canonical meal slug, the human-readable amount,
/// and the soft delete.
void main() {
  _payloadContract();
  _massContract();

  MemberFood food({
    String name = 'Paneer Tikka',
    MemberFoodTier tier = MemberFoodTier.org,
    Map<String, double>? per100,
  }) =>
      MemberFood(
        foodId: 'food_1',
        name: name,
        tier: tier,
        per100: per100 ??
            const {
              'calories': 250,
              'protein': 18,
              'carbs': 6,
              'fat': 18,
              'fiber': 1,
              'sugar': 2,
              'saturatedFat': 9,
            },
      );

  FoodEntry buildEntry({
    required MemberFood f,
    required PortionSelection selection,
    String mealSlot = 'lunch',
    String? note,
  }) {
    final consumed = scaleMacros(f.per100, selection.totalGrams);
    return FoodEntry(
      entryId: 'e1',
      source: FoodEntrySource.search,
      foodId: f.foodId,
      foodName: f.name,
      foodTier: f.tier == MemberFoodTier.org ? FoodTier.org : FoodTier.global,
      mealSlot: canonicalMealSlot(mealSlot),
      quantity: selection.storedQuantity,
      unit: selection.storedUnit,
      consumed: ConsumedSnapshot(
        calories: consumed['calories']!,
        protein: consumed['protein']!,
        carbs: consumed['carbs']!,
        fat: consumed['fat']!,
        fiber: consumed['fiber']!,
        sugar: consumed['sugar']!,
        saturatedFat: consumed['saturatedFat']!,
      ),
      loggedAt: 1754006400000,
      note: note,
    );
  }

  group('the serialized entry', () {
    test('carries a FROZEN consumed snapshot, not a reference to the food', () {
      final e = buildEntry(
        f: food(),
        selection: const PortionSelection.grams(200),
      );
      final m = e.toMap();
      // Doubling 100 g doubles every macro, and the numbers are STORED.
      expect((m['consumed'] as Map)['calories'], 500);
      expect((m['consumed'] as Map)['protein'], 36);
      // Re-costing the food tomorrow cannot reach this map.
      expect(m.containsKey('consumed'), isTrue);
    });

    test('SNAPSHOTS the food label so a rename cannot orphan the row', () {
      final e = buildEntry(
        f: food(name: 'Paneer Tikka'),
        selection: const PortionSelection.grams(100),
      );
      expect(e.toMap()['foodName'], 'Paneer Tikka');
      // The id is kept too, but the label is what makes the row readable when
      // the food is later archived or removed from the org library.
      expect(e.toMap()['foodId'], 'food_1');
    });

    test('stores the amount in HUMAN terms beside the macros', () {
      final e = buildEntry(
        f: food(),
        selection: const PortionSelection(
          mode: PortionMode.portion,
          quantity: 2,
          portionLabel: 'katori',
          gramsPerPortion: 150,
        ),
      );
      final m = e.toMap();
      expect(m['quantity'], 2);
      expect(m['unit'], 'katori');
      // 2 x 150 g = 300 g of a 250 kcal/100 g food.
      expect((m['consumed'] as Map)['calories'], 750);
    });

    test('stores the meal as a canonical SLUG, never a label', () {
      for (final input in [
        'Lunch', 'lunch', ' LUNCH ', 'Afternoon',
      ]) {
        expect(
          buildEntry(
            f: food(),
            selection: const PortionSelection.grams(100),
            mealSlot: input,
          ).toMap()['mealSlot'],
          'lunch',
          reason: '"$input" must normalize to the stored slug',
        );
      }
      // The legacy four-slot taxonomy agrees with TrainerHQ's own alias table.
      expect(
        buildEntry(
          f: food(),
          selection: const PortionSelection.grams(100),
          mealSlot: 'Snacks',
        ).toMap()['mealSlot'],
        'evening_snack',
      );
      // Anything unrecognised is FILED, never lost and never a seventh meal.
      expect(
        buildEntry(
          f: food(),
          selection: const PortionSelection.grams(100),
          mealSlot: 'Elevenses',
        ).toMap()['mealSlot'],
        'other',
      );
    });

    test('records which library the food came from', () {
      expect(
        buildEntry(f: food(), selection: const PortionSelection.grams(100))
            .toMap()['foodTier'],
        'org',
      );
      expect(
        buildEntry(
          f: food(tier: MemberFoodTier.global),
          selection: const PortionSelection.grams(100),
        ).toMap()['foodTier'],
        'global',
      );
    });

    test('an absent note is OMITTED, not stored as an empty string', () {
      final m = buildEntry(
        f: food(),
        selection: const PortionSelection.grams(100),
      ).toMap();
      expect(m.containsKey('note'), isFalse);
      expect(m.containsKey('deleted'), isFalse,
          reason: 'a live entry carries no deleted flag at all');
    });

    test('source is `search` — how the entry got onto the day', () {
      // Orthogonal to foodTier, which says which LIBRARY it came from. An org
      // food can arrive by plan or by search; one field cannot answer both.
      final m = buildEntry(
        f: food(),
        selection: const PortionSelection.grams(100),
      ).toMap();
      expect(m['source'], 'search');
      expect(m['foodTier'], 'org');
    });
  });

  group('round trip', () {
    test('an entry survives write → read unchanged', () {
      final original = buildEntry(
        f: food(),
        selection: const PortionSelection(
          mode: PortionMode.portion,
          quantity: 1.5,
          portionLabel: 'bowl',
          gramsPerPortion: 200,
        ),
        note: 'Ate out',
      );
      final reread = FoodEntry.fromMap('e1', original.toMap());
      expect(reread.foodName, original.foodName);
      expect(reread.mealSlot, original.mealSlot);
      expect(reread.quantity, original.quantity);
      expect(reread.unit, original.unit);
      expect(reread.consumed.calories, original.consumed.calories);
      expect(reread.note, 'Ate out');
      expect(reread.deleted, isFalse);
      expect(reread.foodTier, FoodTier.org);
    });
  });

  group('soft delete', () {
    test('a deleted entry leaves the day totals but keeps its data', () {
      final live = buildEntry(
        f: food(),
        selection: const PortionSelection.grams(100),
      );
      final day = NutritionDayModel(
        id: 'c1_2026-08-01',
        dateKey: '2026-08-01',
        entries: {
          'e1': live,
          'e2': FoodEntry.fromMap('e2', {
            ...live.toMap(),
            'deleted': true,
            'foodName': 'Removed Food',
          }),
        },
      );
      expect(day.liveEntries.map((e) => e.entryId), ['e1']);
      // The row is still THERE — nothing was destroyed.
      expect(day.entries['e2']!.foodName, 'Removed Food');
      expect(day.entries['e2']!.deleted, isTrue);
    });
  });

  group('day totals come from LOGGED foods only', () {
    test('totals sum live entries and skip deleted ones', () {
      final e = buildEntry(
        f: food(),
        selection: const PortionSelection.grams(100),
      );
      final day = NutritionDayModel(
        id: 'c1_2026-08-01',
        entries: {
          'a': e,
          'b': e,
          'c': FoodEntry.fromMap('c', {...e.toMap(), 'deleted': true}),
        },
      );
      final totals = sumMacros([
        for (final x in day.liveEntries)
          {
            'calories': x.consumed.calories,
            'protein': x.consumed.protein,
            'carbs': x.consumed.carbs,
            'fat': x.consumed.fat,
            'fiber': x.consumed.fiber,
            'sugar': x.consumed.sugar,
            'saturatedFat': x.consumed.saturatedFat,
          },
      ]);
      expect(totals['calories'], 500, reason: 'two live, one deleted');
      expect(totals['protein'], 36);
    });

    test('a day with only a plan and nothing logged totals ZERO', () {
      // The product rule: a recommendation nobody ate contributes nothing.
      const day = NutritionDayModel(id: 'c1_2026-08-01');
      expect(day.liveEntries, isEmpty);
      expect(sumMacros(const [])['calories'], 0);
    });
  });

  group('the same food logged twice', () {
    test('produces two independent entries, not one overwritten', () {
      final e = buildEntry(
        f: food(),
        selection: const PortionSelection.grams(100),
      );
      // Distinct ids are what makes "I had two coffees" expressible. Keying by
      // foodId would silently collapse them.
      final day = NutritionDayModel(
        id: 'c1_2026-08-01',
        entries: {
          'id_a': FoodEntry.fromMap('id_a', e.toMap()),
          'id_b': FoodEntry.fromMap('id_b', e.toMap()),
        },
      );
      expect(day.liveEntries.length, 2);
      expect(day.liveEntries.map((x) => x.foodId).toSet(), {'food_1'});
    });
  });

  group('meal ordering and derived meal time', () {
    test('meals sort in the canonical order, other last', () {
      final slots = [...kMealSlots, kOtherMealSlot]..shuffle();
      slots.sort((a, b) => mealSlotOrder(a).compareTo(mealSlotOrder(b)));
      expect(slots, [
        'breakfast', 'mid_morning', 'lunch', 'evening_snack', 'dinner',
        'bedtime', 'other',
      ]);
    });

    test('a meal time is DERIVED from its earliest live entry', () {
      final base = buildEntry(
        f: food(),
        selection: const PortionSelection.grams(100),
      );
      final early = FoodEntry.fromMap('a', {...base.toMap(), 'loggedAt': 100});
      final late = FoodEntry.fromMap('b', {...base.toMap(), 'loggedAt': 900});
      expect(mealStartedAt([late, early]), 100);
      // A withdrawn entry cannot set the meal's time.
      final deletedEarlier = FoodEntry.fromMap(
        'c',
        {...base.toMap(), 'loggedAt': 50, 'deleted': true},
      );
      expect(mealStartedAt([deletedEarlier, late, early]), 100);
      // A meal nobody timed has NO time, not a fabricated zero.
      final untimed = FoodEntry.fromMap('d', {...base.toMap()}..remove('x'));
      expect(mealStartedAt([FoodEntry.fromMap('e', {
        ...untimed.toMap(),
      }..remove('loggedAt'))]), isNull);
    });
  });
}

/// THE WRITE PAYLOAD — pinned at the shape level.
///
/// `set()` does NOT interpret dots as field paths (only `update()` does). A
/// payload of `{'entries.abc': {...}}` therefore writes ONE field whose literal
/// NAME contains a dot, and no `entries` map ever exists — which is exactly the
/// defect that shipped twice in this platform's rollup writers and returned
/// empty analytics for every member. These assert the shape, not the database.
void _payloadContract() {
  group('the write payload', () {
    Map<String, dynamic> write({
      String entryId = 'e1',
      Map<String, dynamic> patch = const {'foodName': 'Oats'},
      String adminId = 'orgA',
    }) =>
        NutritionDayService.buildEntryWrite(
          clientId: 'c1',
          adminId: adminId,
          authorUid: 'uid_1',
          dateKey: '2026-08-01',
          entryId: entryId,
          patch: patch,
        );

    test('entries is a NESTED map, never a dotted key', () {
      final w = write();
      expect(w.containsKey('entries'), isTrue,
          reason: 'readers look up `entries`; it must exist as a field');
      expect(w.keys.any((k) => k.contains('.')), isFalse,
          reason: 'a dotted key would become one literal field name');
      expect((w['entries'] as Map)['e1'], {'foodName': 'Oats'});
    });

    test('REGRESSION: the broken form is structurally different', () {
      // Kept as an executable description of the defect class.
      final broken = <String, dynamic>{'entries.e1': {'foodName': 'Oats'}};
      expect(broken.containsKey('entries'), isFalse);
      expect(write().containsKey('entries'), isTrue);
    });

    test('carries the full identity block the rules validate', () {
      final w = write();
      // `create` requires these to match the ownership get(); `update`
      // requires them UNCHANGED. Sending them on every write is what lets one
      // set(merge:true) satisfy whichever rule applies — the client cannot
      // know whether the doc exists while offline.
      expect(w['clientId'], 'c1');
      expect(w['adminId'], 'orgA');
      expect(w['authorUid'], 'uid_1');
      expect(w['dateKey'], '2026-08-01');
    });

    test('never writes a server-owned field', () {
      final w = write();
      // The rules REJECT any client write to these. A payload carrying them
      // would fail the whole day's write, not just that field.
      expect(w.containsKey('computed'), isFalse);
      expect(w.containsKey('coachReview'), isFalse);
    });

    test('a soft delete sends ONLY the flag', () {
      final w = write(patch: const {'deleted': true});
      final entry = (w['entries'] as Map)['e1'] as Map;
      expect(entry, {'deleted': true});
      // A full-entry rewrite would resurrect whatever stale copy the deleting
      // device happened to hold.
      expect(entry.containsKey('consumed'), isFalse);
      expect(entry.containsKey('foodName'), isFalse);
    });

    test('two entries in one day occupy independent paths', () {
      final a = write(entryId: 'e1');
      final b = write(entryId: 'e2');
      expect((a['entries'] as Map).keys, ['e1']);
      expect((b['entries'] as Map).keys, ['e2']);
      // Deep merge means writing e2 leaves e1 untouched — two devices adding
      // different foods to the same meal both land.
      expect((a['entries'] as Map).containsKey('e2'), isFalse);
    });

    test('the day keeps the org it was OPENED under', () {
      // A member who transfers gyms mid-day gets a new adminId on their client
      // doc, but the rules pin adminId immutable on update. Writing the new
      // one would be DENIED and the rest of their day would stop saving.
      expect(write(adminId: 'orgA')['adminId'], 'orgA');
    });
  });
}

/// `grams` — the MASS an entry represents (added during Phase 3A certification).
///
/// `quantity` + `unit` cannot answer "how much was that?" for a named portion.
/// Without a stored mass the edit path had to fabricate a gram basis: calories
/// stayed correct (the reparameterization is exact) but every gram figure shown
/// was wrong, and switching such an edit to grams mode wrote the fabricated
/// number back as the member's amount.
void _massContract() {
  MemberFood paneer() => const MemberFood(
        foodId: 'f1',
        name: 'Paneer Tikka',
        tier: MemberFoodTier.org,
        per100: {
          'calories': 250, 'protein': 18, 'carbs': 6, 'fat': 18,
          'fiber': 1, 'sugar': 2, 'saturatedFat': 9,
        },
      );

  FoodEntry logged(PortionSelection s) {
    final consumed = scaleMacros(paneer().per100, s.totalGrams);
    return FoodEntry(
      entryId: 'e1',
      source: FoodEntrySource.search,
      foodName: 'Paneer Tikka',
      mealSlot: 'lunch',
      quantity: s.storedQuantity,
      unit: s.storedUnit,
      grams: s.totalGrams,
      consumed: ConsumedSnapshot(
        calories: consumed['calories']!, protein: consumed['protein']!,
        carbs: consumed['carbs']!, fat: consumed['fat']!,
        fiber: consumed['fiber']!, sugar: consumed['sugar']!,
        saturatedFat: consumed['saturatedFat']!,
      ),
    );
  }

  group('a logged entry records its mass', () {
    test('a portion entry stores BOTH the human amount and the grams', () {
      final e = logged(const PortionSelection(
        mode: PortionMode.portion,
        quantity: 2,
        portionLabel: 'katori',
        gramsPerPortion: 150,
      ));
      final m = e.toMap();
      expect(m['quantity'], 2);
      expect(m['unit'], 'katori');
      // The number a coach could not previously recover from the entry alone.
      expect(m['grams'], 300);
      expect((m['consumed'] as Map)['calories'], 750);
    });

    test('a grams entry stores the same value in both places', () {
      final m = logged(const PortionSelection.grams(180)).toMap();
      expect(m['quantity'], 180);
      expect(m['unit'], 'g');
      expect(m['grams'], 180);
    });

    test('mass round-trips through write → read', () {
      final e = logged(const PortionSelection(
        mode: PortionMode.portion,
        quantity: 1.5,
        portionLabel: 'bowl',
        gramsPerPortion: 200,
      ));
      expect(FoodEntry.fromMap('e1', e.toMap()).grams, 300);
    });

    test('a LEGACY entry has no mass, and that reads as UNKNOWN', () {
      // Absent must never coerce to 0 — "0 g eaten" is a claim, "unknown" is
      // the truth, and the UI declines to state a mass rather than guess one.
      final legacy = FoodEntry.fromMap('e1', {
        'foodName': 'Paneer Tikka', 'quantity': 2, 'unit': 'katori',
        'consumed': {'calories': 750},
      });
      expect(legacy.grams, isNull);
      expect(legacy.quantity, 2);
      expect(legacy.consumed.calories, 750);
      // And it is omitted on write rather than serialized as null.
      expect(legacy.toMap().containsKey('grams'), isFalse);
    });
  });

  group('re-scaling an edited entry stays exact', () {
    test('changing the count scales the macros correctly', () {
      final e = logged(const PortionSelection(
        mode: PortionMode.portion,
        quantity: 2,
        portionLabel: 'katori',
        gramsPerPortion: 150,
      ));
      // The edit path rebuilds a per-100 basis from the frozen snapshot and
      // the stored mass — never by re-reading the food, which may have been
      // re-costed since.
      final factor = kFoodBaseGrams / e.grams!;
      final per100 = {'calories': e.consumed.calories * factor};
      expect(per100['calories'], 250, reason: 'the original per-100 recovered');
      // Three katori = 450 g.
      expect(scaleMacros(per100, 450)['calories'], 1125);
    });

    test('the legacy 100 g pivot still re-scales the COUNT correctly', () {
      // Proof that legacy entries remain editable: the fabricated basis is a
      // valid reparameterization, so quantity x pivot x per100/100 is exact.
      // Only the gram FIGURE was wrong, which is why it is no longer shown.
      final legacy = FoodEntry.fromMap('e1', {
        'foodName': 'Paneer Tikka', 'quantity': 2, 'unit': 'katori',
        'consumed': {'calories': 750},
      });
      const pivot = kFoodBaseGrams; // 100
      final per100 = {'calories': legacy.consumed.calories * (kFoodBaseGrams / pivot)};
      final perUnit = pivot / legacy.quantity!; // 50
      // Three of the same portion must read 1125 kcal, as with a real mass.
      expect(scaleMacros(per100, 3 * perUnit)['calories'], 1125);
    });
  });

  // THE DEFECT: `fetchDays` issued 31 gets under `Future.wait`, which rejects
  // as a whole if ANY of them errors. Its own doc comment promised "one
  // unreadable day must not blank the whole month", and the `Source.cache`
  // fallback could not deliver that — a day that was never cached throws from
  // the cache too, so the rejection propagated and the entire history page
  // failed on a single bad day.
  //
  // But full tolerance would be its own lie: if EVERY day is unreadable, an
  // empty result would render as "this member logged nothing", which is the
  // one thing the history screen must never say on the strength of a failure.
  // So partial failure degrades and total failure reports.
  group('a window of unreadable days', () {
    test('a single bad day does not fail the window', () {
      expect(
        NutritionDayService.windowUnreadable(requested: 31, unreadable: 1),
        isFalse,
      );
      expect(
        NutritionDayService.windowUnreadable(requested: 31, unreadable: 30),
        isFalse,
      );
    });

    test('a window nothing could be read from is an error, not an absence', () {
      expect(
        NutritionDayService.windowUnreadable(requested: 31, unreadable: 31),
        isTrue,
      );
    });

    test('a window that was simply never logged is not a failure', () {
      // Every day ABSENT is the normal state of a month off — zero unreadable.
      expect(
        NutritionDayService.windowUnreadable(requested: 31, unreadable: 0),
        isFalse,
      );
      // And an empty request can never be a failure.
      expect(
        NutritionDayService.windowUnreadable(requested: 0, unreadable: 0),
        isFalse,
      );
    });
  });
}
