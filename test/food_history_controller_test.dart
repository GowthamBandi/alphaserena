import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:alphaserena/controllers/food_history_controller.dart';
import 'package:alphaserena/core/models/nutrition_day_model.dart';
import 'package:alphaserena/core/services/nutrition_day_service.dart';

/// A service double: no Firebase, deterministic days.
class _FakeDayService extends NutritionDayService {
  _FakeDayService();

  /// dateKey → the day document that exists for it. Absent = never logged.
  final Map<String, NutritionDayModel> stored = {};
  final List<List<String>> requestedPages = [];
  bool fail = false;

  @override
  bool get canLog => true;

  @override
  Future<List<NutritionDayModel>> fetchDays(List<String> dateKeys) async {
    requestedPages.add(dateKeys);
    if (fail) throw Exception('network');
    // Mirrors the real service: days with no document are simply ABSENT.
    final out = [
      for (final k in dateKeys)
        if (stored[k] != null) stored[k]!,
    ];
    out.sort((a, b) => b.dateKey.compareTo(a.dateKey));
    return out;
  }
}

NutritionDayModel day(String dateKey, {int items = 1, double kcal = 500}) =>
    NutritionDayModel(
      id: 'c1_$dateKey',
      dateKey: dateKey,
      entries: {
        for (var i = 0; i < items; i++)
          'e$i': FoodEntry(
            entryId: 'e$i',
            foodName: 'Food $i',
            mealSlot: i.isEven ? 'lunch' : 'dinner',
            quantity: 1,
            unit: 'katori',
            grams: 150,
            loggedAt: 1000 + i,
            consumed: ConsumedSnapshot(calories: kcal / items, protein: 10),
          ),
      },
    );

void main() {
  late _FakeDayService service;
  // A fixed "today" — a test that could not pin the date would be testing the
  // machine's clock.
  final now = DateTime(2026, 8, 1);

  setUp(() {
    service = _FakeDayService();
    Get.testMode = true;
  });
  tearDown(Get.reset);

  FoodHistoryController build() {
    final c = FoodHistoryController(service: service, now: now);
    c.onInit();
    return c;
  }

  group('what history covers', () {
    test('TODAY is excluded — it is live on the Diet screen above', () async {
      service.stored['2026-08-01'] = day('2026-08-01');
      service.stored['2026-07-31'] = day('2026-07-31');
      final c = build();
      await Future<void>.delayed(Duration.zero);
      expect(service.requestedPages.first.contains('2026-08-01'), isFalse,
          reason: 'showing today twice invites "which one is current?"');
      expect(service.requestedPages.first.first, '2026-07-31');
      expect(c.days.map((d) => d.dateKey), ['2026-07-31']);
    });

    test('a page is bounded to the service cap', () async {
      build();
      await Future<void>.delayed(Duration.zero);
      expect(service.requestedPages.first.length,
          NutritionDayService.maxHistoryDays);
    });

    test('unlogged days are ABSENT, never rows of zeroes', () async {
      service.stored['2026-07-31'] = day('2026-07-31');
      service.stored['2026-07-28'] = day('2026-07-28');
      final c = build();
      await Future<void>.delayed(Duration.zero);
      // The three untouched days in between produce no rows: "no row" is the
      // truth, "0 kcal" would be a claim about the member's eating.
      expect(c.days.map((d) => d.dateKey), ['2026-07-31', '2026-07-28']);
    });

    test('days arrive newest first', () async {
      for (final k in ['2026-07-20', '2026-07-31', '2026-07-25']) {
        service.stored[k] = day(k);
      }
      final c = build();
      await Future<void>.delayed(Duration.zero);
      expect(c.days.map((d) => d.dateKey),
          ['2026-07-31', '2026-07-25', '2026-07-20']);
    });
  });

  group('per-day figures', () {
    test('totals sum the frozen snapshots of live entries', () async {
      service.stored['2026-07-31'] = day('2026-07-31', items: 2, kcal: 600);
      final c = build();
      await Future<void>.delayed(Duration.zero);
      final d = c.days.single;
      expect(d.calories, 600);
      expect(d.entryCount, 2);
      expect(d.totals['protein'], 20);
    });

    test('entries group by meal in canonical order', () async {
      service.stored['2026-07-31'] = day('2026-07-31', items: 3);
      final c = build();
      await Future<void>.delayed(Duration.zero);
      final byMeal = c.days.single.byMeal;
      expect(byMeal.keys.toSet(), {'lunch', 'dinner'});
      expect(byMeal['lunch']!.length, 2);
    });

    test('the average is over LOGGED days, never the calendar', () async {
      // Two logged days in a 31-day window average to their own mean; the 29
      // untouched days are not zeroes to divide into.
      service.stored['2026-07-31'] = day('2026-07-31', kcal: 1000);
      service.stored['2026-07-30'] = day('2026-07-30', kcal: 2000);
      final c = build();
      await Future<void>.delayed(Duration.zero);
      expect(c.averageCalories, 1500);
    });

    test('no logged days means no average, not zero', () async {
      final c = build();
      await Future<void>.delayed(Duration.zero);
      expect(c.averageCalories, isNull);
    });
  });

  group('paging', () {
    test('loadMore walks further back and stops when nothing remains',
        () async {
      service.stored['2026-07-31'] = day('2026-07-31');
      final c = build();
      await Future<void>.delayed(Duration.zero);
      expect(c.reachedEnd.value, isFalse);

      await c.loadMore();
      expect(service.requestedPages.length, 2);
      // Page 1 ran 31 Jul → 1 Jul; page 2 resumes at 30 Jun. CONTIGUOUS —
      // an off-by-one here would silently skip a day of a member's history.
      expect(service.requestedPages[0].last, '2026-07-01');
      expect(service.requestedPages[1].first, '2026-06-30');
      expect(c.reachedEnd.value, isTrue);

      await c.loadMore();
      expect(service.requestedPages.length, 2,
          reason: 'past the end, further paging costs no reads');
    });

    test('loadMore is ignored while a page is already in flight', () async {
      final c = build();
      await Future<void>.delayed(Duration.zero);
      c.isLoadingMore.value = true;
      await c.loadMore();
      expect(service.requestedPages.length, 1);
    });
  });

  group('failure is honest', () {
    test('a failed load reports an error, never an empty history', () async {
      service.fail = true;
      final c = build();
      await Future<void>.delayed(Duration.zero);
      // Claiming a member logged nothing for a month because a read failed is
      // the worst thing this screen could say.
      expect(c.loadError.value, isTrue);
      expect(c.days, isEmpty);
      expect(c.reachedEnd.value, isFalse);
    });

    test('retrying after a failure recovers', () async {
      service.fail = true;
      final c = build();
      await Future<void>.delayed(Duration.zero);
      expect(c.loadError.value, isTrue);

      service.fail = false;
      service.stored['2026-07-31'] = day('2026-07-31');
      await c.load();
      expect(c.loadError.value, isFalse);
      expect(c.days.single.dateKey, '2026-07-31');
    });
  });

  group('opening a day', () {
    test('open and close move between list and detail', () async {
      service.stored['2026-07-31'] = day('2026-07-31');
      final c = build();
      await Future<void>.delayed(Duration.zero);
      expect(c.selected.value, isNull);
      c.open(c.days.single);
      expect(c.selected.value!.dateKey, '2026-07-31');
      c.closeDay();
      expect(c.selected.value, isNull);
    });
  });
}
