import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:alphaserena/controllers/connectivity_controller.dart';
import 'package:alphaserena/controllers/food_search_controller.dart';
import 'package:alphaserena/core/models/member_food.dart';
import 'package:alphaserena/core/services/member_food_service.dart';

/// A service double: no Firebase, no network, full control over timing.
class _FakeFoodService extends MemberFoodService {
  _FakeFoodService();

  final List<String> queries = [];

  /// Queued outcomes, consumed in call order. Falls back to [defaultOutcome].
  final List<FoodSearchOutcome> scripted = [];
  FoodSearchOutcome defaultOutcome = const FoodSearchOutcome();

  /// Per-query artificial latency, used to force out-of-order responses.
  final Map<String, Duration> delays = {};

  List<MemberFood> storedRecents = const [];
  final List<MemberFood> remembered = [];

  @override
  Future<FoodSearchOutcome> search(String query, {int limit = 24}) async {
    queries.add(query);
    final delay = delays[query];
    if (delay != null) await Future<void>.delayed(delay);
    if (scripted.isNotEmpty) return scripted.removeAt(0);
    return defaultOutcome;
  }

  @override
  Future<List<MemberFood>> recents() async => storedRecents;

  @override
  Future<void> remember(MemberFood food) async => remembered.add(food);
}

MemberFood _food(String name, {MemberFoodTier tier = MemberFoodTier.global}) =>
    MemberFood(
      foodId: name.toLowerCase().replaceAll(' ', '_'),
      name: name,
      tier: tier,
      per100: const {'calories': 100, 'protein': 5},
    );

void main() {
  late _FakeFoodService service;

  setUp(() {
    service = _FakeFoodService();
    Get.testMode = true;
  });

  tearDown(Get.reset);

  FoodSearchController build({ConnectivityController? connectivity}) {
    final c = FoodSearchController(
      service: service,
      connectivity: connectivity,
    );
    c.onInit();
    return c;
  }

  group('states are distinct and honest', () {
    test('a failed search is NOT reported as "no results"', () async {
      // The whole point: "couldn't reach the library" and "nothing matches
      // quinoa" call for different actions from the member. Reporting a
      // network failure as an empty result tells them their gym has no foods.
      service.defaultOutcome = const FoodSearchOutcome.failure();
      final c = build();
      await c.runSearch('quinoa');
      expect(c.state.value, FoodSearchState.failed);
      expect(c.state.value, isNot(FoodSearchState.empty));
    });

    test('a genuinely empty result reports empty', () async {
      service.defaultOutcome = const FoodSearchOutcome(foods: []);
      final c = build();
      await c.runSearch('zzzzz');
      expect(c.state.value, FoodSearchState.empty);
    });

    test('an empty BROWSE is browse, not "no results"', () async {
      // A gym with no org foods and an unseeded global library must not read
      // as a failed search the member could retry.
      service.defaultOutcome = const FoodSearchOutcome(foods: []);
      final c = build();
      await c.runSearch('');
      expect(c.state.value, FoodSearchState.browse);
    });

    test('offline is distinguished from failed', () async {
      final conn = ConnectivityController();
      conn.isOnline.value = false;
      final c = build(connectivity: conn);
      await c.runSearch('rice');
      expect(c.state.value, FoodSearchState.offline);
      expect(service.queries, isNot(contains('rice')),
          reason: 'no point spending a round trip with no radio');
    });

    test('going offline KEEPS results already on screen', () async {
      final conn = ConnectivityController();
      service.defaultOutcome = FoodSearchOutcome(foods: [_food('Rice')]);
      final c = build(connectivity: conn);
      await c.runSearch('rice');
      expect(c.results, hasLength(1));

      conn.isOnline.value = false;
      await c.runSearch('rice');
      // A food's macros do not change because the radio dropped. Blanking the
      // list would destroy the member's work in progress.
      expect(c.results, hasLength(1));
      expect(c.state.value, isNot(FoodSearchState.offline));
    });
  });

  group('request ordering', () {
    test('a slow EARLIER query cannot overwrite a fast later one', () async {
      // The classic search race: "chi" is issued, then "chicken"; "chicken"
      // returns first, then "chi" lands and flickers the list back to stale
      // rows. The monotonic request id is what prevents it.
      service.delays['chi'] = const Duration(milliseconds: 60);
      service.scripted.addAll([
        FoodSearchOutcome(foods: [_food('Chickpea'), _food('Chia')]), // 'chi'
        FoodSearchOutcome(foods: [_food('Chicken Breast')]),          // 'chicken'
      ]);

      final c = build();
      final slow = c.runSearch('chi');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await c.runSearch('chicken');
      expect(c.results.single.name, 'Chicken Breast');

      await slow; // the stale response finally lands
      expect(c.results.single.name, 'Chicken Breast',
          reason: 'the newer query must win regardless of arrival order');
    });

    test('a response arriving after dispose touches nothing', () async {
      service.delays['rice'] = const Duration(milliseconds: 40);
      service.defaultOutcome = FoodSearchOutcome(foods: [_food('Rice')]);
      final c = build();
      final pending = c.runSearch('rice');
      c.onClose();
      await pending;
      expect(c.results, isEmpty);
    });
  });

  group('debounce', () {
    test('typing a word costs ONE request, not one per keystroke', () async {
      service.defaultOutcome = FoodSearchOutcome(foods: [_food('Chicken')]);
      final c = build();
      service.queries.clear(); // drop the initial browse load

      for (final partial in ['c', 'ch', 'chi', 'chic', 'chicken']) {
        c.onQueryChanged(partial);
      }
      // Nothing has gone out yet.
      expect(service.queries, isEmpty);

      await Future<void>.delayed(
        FoodSearchController.debounce + const Duration(milliseconds: 60),
      );
      expect(service.queries, ['chicken']);
    });

    test('clearing the box is NOT debounced', () async {
      service.defaultOutcome = const FoodSearchOutcome(foods: []);
      final c = build();
      service.queries.clear();
      c.onQueryChanged('');
      // Snapping back to browse must feel instant.
      expect(service.queries, ['']);
    });

    test('a pending debounce is cancelled by a newer keystroke', () async {
      service.defaultOutcome = const FoodSearchOutcome(foods: []);
      final c = build();
      service.queries.clear();
      c.onQueryChanged('ric');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      c.onQueryChanged('rice');
      await Future<void>.delayed(
        FoodSearchController.debounce + const Duration(milliseconds: 60),
      );
      expect(service.queries, ['rice']);
    });
  });

  group('degraded-result signalling', () {
    test('a too-short query keeps rows and asks the member to keep typing',
        () async {
      service.defaultOutcome = FoodSearchOutcome(
        foods: [_food('Almonds')],
        tooShort: true,
      );
      final c = build();
      await c.runSearch('a');
      expect(c.keepTyping.value, isTrue);
      expect(c.results, isNotEmpty, reason: 'browse rows are still useful');
    });

    test('a partial org library is surfaced, not hidden', () async {
      // The gym predates the searchTokens backfill. Silently serving fewer
      // foods would look like the coach never added them.
      service.defaultOutcome = FoodSearchOutcome(
        foods: [_food('Paneer', tier: MemberFoodTier.org)],
        orgFallback: true,
      );
      final c = build();
      await c.runSearch('paneer');
      expect(c.orgResultsPartial.value, isTrue);
    });
  });

  group('plan foods — the member-specific suggestion list', () {
    test('with no training controller, there are simply none', () {
      final c = build();
      expect(c.planFoodsFor('lunch'), isEmpty);
    });
  });

  group('the screen can always say a search is happening', () {
    test('refining a search with rows already on screen still reads as busy',
        () async {
      // THE DEFECT THIS PINS: `state` only becomes `loading` when there is
      // nothing to draw, so refining a query left the previous rows up with no
      // indicator at all — typing looked like the app had frozen.
      service.defaultOutcome = FoodSearchOutcome(foods: [_food('Rice')]);
      final c = build();
      await Future<void>.delayed(Duration.zero);
      expect(c.results, isNotEmpty, reason: 'browse rows must be on screen');

      service.delays['paneer'] = const Duration(milliseconds: 40);
      service.defaultOutcome = FoodSearchOutcome(foods: [_food('Paneer')]);
      c.onQueryChanged('paneer');

      // Armed at the KEYSTROKE — the debounce window is part of the wait.
      expect(c.isSearching.value, isTrue);
      expect(c.state.value, isNot(FoodSearchState.loading),
          reason: 'rows are still on screen, so the skeleton must not take over');

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(c.isSearching.value, isFalse);
      expect(c.results.single.name, 'Paneer');
    });

    test('a superseded response does not clear the flag for the live one',
        () async {
      service.defaultOutcome = FoodSearchOutcome(foods: [_food('Rice')]);
      final c = build();
      await Future<void>.delayed(Duration.zero);

      // 'chi' is slow, 'chicken' is issued after it and returns first.
      service.delays['chi'] = const Duration(milliseconds: 120);
      service.defaultOutcome = FoodSearchOutcome(foods: [_food('Chicken')]);
      c.runSearch('chi');
      c.runSearch('chicken');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      // The live query has landed, so the bar is down.
      expect(c.isSearching.value, isFalse);
      expect(c.resultsQuery.value, 'chicken');

      // The superseded 'chi' response now arrives. It must change nothing —
      // in particular it must not re-caption the rows for a query the member
      // has already moved on from.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(c.isSearching.value, isFalse);
      expect(c.resultsQuery.value, 'chicken');
    });

    test('offline clears the flag rather than spinning forever', () async {
      final conn = ConnectivityController();
      conn.isOnline.value = false;
      final c = build(connectivity: conn);
      await c.runSearch('paneer');
      expect(c.isSearching.value, isFalse);
    });
  });

  group('rows are never captioned as answers to a query they predate', () {
    test('resultsQuery tracks the rows, not the text field', () async {
      // `query` moves on every keystroke; the browse rows underneath do not.
      // Describing them from `query` relabelled the whole A-to-Z browse list
      // "RESULTS" for "paneer" the instant the member typed it.
      service.defaultOutcome = FoodSearchOutcome(foods: [_food('Almonds')]);
      final c = build();
      await Future<void>.delayed(Duration.zero);
      expect(c.resultsQuery.value, '', reason: 'these are browse rows');

      service.delays['paneer'] = const Duration(milliseconds: 40);
      service.defaultOutcome = FoodSearchOutcome(foods: [_food('Paneer')]);
      c.onQueryChanged('paneer');

      expect(c.query.value, 'paneer');
      expect(c.resultsQuery.value, '',
          reason: 'the rows on screen are still the browse page');

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(c.resultsQuery.value, 'paneer');
    });

    test('clearing the box returns the rows to browse provenance', () async {
      service.defaultOutcome = FoodSearchOutcome(foods: [_food('Paneer')]);
      final c = build();
      await c.runSearch('paneer');
      expect(c.resultsQuery.value, 'paneer');

      c.clear();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(c.resultsQuery.value, '');
    });
  });

  group('recents', () {
    test('are loaded on open', () async {
      service.storedRecents = [_food('Oats')];
      final c = build();
      await Future<void>.delayed(Duration.zero);
      expect(c.recents.single.name, 'Oats');
    });

    test('corrupt or absent recents are simply empty', () async {
      service.storedRecents = const [];
      final c = build();
      await Future<void>.delayed(Duration.zero);
      expect(c.recents, isEmpty);
    });
  });
}
