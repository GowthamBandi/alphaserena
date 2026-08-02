import 'dart:async';

import 'package:get/get.dart';

import '../core/domain/food_portion_math.dart';
import '../core/models/member_food.dart';
import '../core/models/nutrition_day_model.dart' show canonicalMealSlot;
import '../core/services/member_food_service.dart';
import 'connectivity_controller.dart';
import 'training_controller.dart';

/// What the results area should be showing right now.
///
/// An explicit state machine rather than a pile of booleans: "loading AND
/// error AND empty" is representable with booleans and renders as three
/// stacked contradictions, which is how a search screen ends up telling a
/// member both that it is working and that nothing was found.
enum FoodSearchState {
  /// No query yet — recents, plan foods and the browse page.
  browse,

  /// A request is in flight and there is nothing to show underneath.
  loading,

  results,

  /// The search succeeded and genuinely matched nothing.
  empty,

  /// The search could not run. Distinct from [empty] on purpose.
  failed,

  /// No connection. Distinct from [failed] because the remedy differs.
  offline,
}

/// NIP PHASE 3A — the Add Food search experience.
///
/// Owns debounce, request ordering, paging state and the three sources that
/// fill the browse screen. Holds no widgets and no BuildContext, so all of it
/// is testable without pumping a frame.
class FoodSearchController extends GetxController {
  FoodSearchController({
    MemberFoodService? service,
    TrainingController? training,
    ConnectivityController? connectivity,
  })  : _service = service ?? MemberFoodService(),
        _training = training ??
            (Get.isRegistered<TrainingController>()
                ? Get.find<TrainingController>()
                : null),
        _connectivity = connectivity ??
            (Get.isRegistered<ConnectivityController>()
                ? Get.find<ConnectivityController>()
                : null);

  final MemberFoodService _service;
  final TrainingController? _training;
  final ConnectivityController? _connectivity;

  /// How long the member must stop typing before a request goes out.
  ///
  /// 280ms is comfortably below the threshold where typing feels laggy and
  /// comfortably above a fast typist's inter-key interval, so "chicken" costs
  /// ONE round trip rather than seven.
  static const Duration debounce = Duration(milliseconds: 280);

  final RxString query = ''.obs;
  final RxList<MemberFood> results = <MemberFood>[].obs;
  final RxList<MemberFood> recents = <MemberFood>[].obs;
  final Rx<FoodSearchState> state = FoodSearchState.browse.obs;

  /// The org library predates the search backfill — results may be partial.
  final RxBool orgResultsPartial = false.obs;

  /// The query is too short to search; browse rows are shown instead.
  final RxBool keepTyping = false.obs;

  Timer? _debounce;
  bool _closed = false;

  /// Monotonic request id. Every response checks it before touching state, so
  /// a slow "chi" landing after a fast "chicken" cannot overwrite the newer
  /// results — the classic search race that makes a list flicker back to
  /// stale rows.
  int _requestId = 0;

  @override
  void onInit() {
    super.onInit();
    _loadRecents();
    // Fill the browse page immediately: opening Add Food to an empty screen
    // wastes the most common interaction, which is logging something the
    // member has logged before.
    runSearch('');
  }

  @override
  void onClose() {
    _closed = true;
    _debounce?.cancel();
    super.onClose();
  }

  Future<void> _loadRecents() async {
    final r = await _service.recents();
    if (!_closed) recents.assignAll(r);
  }

  /// Called on every keystroke. Debounced; the empty query is NOT debounced
  /// because clearing the box should snap back to browse instantly.
  void onQueryChanged(String value) {
    query.value = value;
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      runSearch('');
      return;
    }
    // Show the spinner immediately when there is nothing underneath it, so a
    // slow network reads as "working", not as "broken".
    if (results.isEmpty) state.value = FoodSearchState.loading;
    _debounce = Timer(debounce, () => runSearch(value));
  }

  /// Issues a search now, bypassing the debounce (submit, retry, initial load).
  Future<void> runSearch(String value) async {
    final id = ++_requestId;
    _debounce?.cancel();

    if (_connectivity != null && !_connectivity.isOnline.value) {
      // Offline with rows already on screen: keep them. They are still true —
      // a food's macros do not change because the radio dropped — and blanking
      // the list would destroy work in progress.
      if (results.isEmpty) state.value = FoodSearchState.offline;
      return;
    }

    if (results.isEmpty) state.value = FoodSearchState.loading;

    final outcome = await _service.search(value);
    if (_closed || id != _requestId) return; // a newer query already won

    orgResultsPartial.value = outcome.orgFallback;
    keepTyping.value = outcome.tooShort;

    if (outcome.failed) {
      state.value = (_connectivity != null && !_connectivity.isOnline.value)
          ? FoodSearchState.offline
          : FoodSearchState.failed;
      return;
    }

    results.assignAll(outcome.foods);
    if (outcome.foods.isEmpty) {
      state.value =
          value.trim().isEmpty ? FoodSearchState.browse : FoodSearchState.empty;
    } else {
      state.value =
          value.trim().isEmpty ? FoodSearchState.browse : FoodSearchState.results;
    }
  }

  void clear() {
    query.value = '';
    runSearch('');
  }

  Future<void> retry() => runSearch(query.value);

  /// Refreshes recents after a successful log, so the food the member just
  /// added is at the top when they come back for the next one.
  Future<void> refreshRecents() => _loadRecents();

  /// FOODS THE COACH PRESCRIBED FOR THIS MEAL.
  ///
  /// The best "popular foods" list a member can be shown is the one their own
  /// coach wrote for them, and it costs nothing: the plan is already in memory
  /// from `getMyTraining`. Platform-wide popularity was considered and
  /// rejected — it ranks by what other gyms' coaches chose, which is a weaker
  /// signal than what THIS member was told to eat.
  ///
  /// Returned as [MemberFood] so the quantity sheet, the preview and the write
  /// path are the same code for a plan food as for a searched one.
  List<MemberFood> planFoodsFor(String mealSlot) {
    final items = _training?.dietItems ?? const <Map<String, dynamic>>[];
    final out = <MemberFood>[];
    final seen = <String>{};
    for (final item in items) {
      final name = (item['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      // The plan stores free-text meal labels; the log stores canonical slugs.
      // Normalizing here is what lets "Mid-morning" on the plan line up with
      // `mid_morning` on the log without either side changing its storage.
      if (canonicalMealSlot(item['meal']) != mealSlot) continue;
      final key = name.toLowerCase();
      if (!seen.add(key)) continue;
      out.add(_planFoodToCard(item));
    }
    return out;
  }

  /// A plan item projected into a food card.
  ///
  /// Plan items carry RESOLVED macros for their prescribed portion, not
  /// per-100 values — `getMyTraining` scales them by the item's grams before
  /// serving. So the card is built by converting back to a per-100 basis using
  /// the item's own grams; without grams the values are already per-serving and
  /// are used as-is, which is exactly what `scaleHydratedMacros` does for the
  /// same legacy items.
  MemberFood _planFoodToCard(Map<String, dynamic> item) {
    final grams = _num(item['grams']);
    final factor = grams > 0 ? 100 / grams : 1.0;
    return MemberFood(
      foodId: (item['foodId'] ?? '').toString(),
      name: (item['name'] ?? '').toString().trim(),
      tier: MemberFoodTier.org,
      serving: (item['quantity'] ?? '').toString().trim().isEmpty
          ? null
          : item['quantity'].toString().trim(),
      per100: {
        'calories': _num(item['calories']) * factor,
        'protein': _num(item['protein']) * factor,
        'carbs': _num(item['carbs']) * factor,
        'fat': _num(item['fat']) * factor,
        'fiber': _num(item['fiber']) * factor,
        'sugar': _num(item['sugar']) * factor,
        'saturatedFat': _num(item['saturatedFat']) * factor,
      },
      portions: [
        if (grams > 0)
          FoodPortionOption(
            label: (item['portionLabel'] ?? '').toString().trim().isEmpty
                ? 'serving'
                : item['portionLabel'].toString().trim(),
            grams: grams,
          ),
      ],
    );
  }

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
