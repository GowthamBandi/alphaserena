import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../core/domain/food_portion_math.dart';
import '../core/models/nutrition_day_model.dart';
import '../core/services/nutrition_day_service.dart';

/// One past day, reduced to what a history list needs.
class HistoryDay {
  final String dateKey;
  final DateTime date;
  final NutritionDayModel day;

  const HistoryDay({
    required this.dateKey,
    required this.date,
    required this.day,
  });

  List<FoodEntry> get entries => day.liveEntries.toList();
  int get entryCount => entries.length;

  Map<String, double> get totals => sumMacros([
        for (final e in entries)
          {
            'calories': e.consumed.calories,
            'protein': e.consumed.protein,
            'carbs': e.consumed.carbs,
            'fat': e.consumed.fat,
            'fiber': e.consumed.fiber,
            'sugar': e.consumed.sugar,
            'saturatedFat': e.consumed.saturatedFat,
          },
      ]);

  double get calories => totals['calories'] ?? 0;

  /// Entries grouped by meal, in canonical order, non-empty groups only.
  Map<String, List<FoodEntry>> get byMeal {
    final out = <String, List<FoodEntry>>{};
    for (final e in entries) {
      out.putIfAbsent(e.mealSlot, () => []).add(e);
    }
    for (final list in out.values) {
      list.sort((a, b) => (a.loggedAt ?? 0).compareTo(b.loggedAt ?? 0));
    }
    return out;
  }
}

/// PHASE 3B — the member's FOOD LOG HISTORY.
///
/// Reads a bounded window of past days by DETERMINISTIC ID (one get per day,
/// never a query), so history costs no composite index and can never scan a
/// member's entire past. Paging walks backwards a month at a time.
class FoodHistoryController extends GetxController {
  FoodHistoryController({NutritionDayService? service, DateTime? now})
      : _service = service ?? NutritionDayService(),
        _anchor = now;

  final NutritionDayService _service;

  /// Injectable clock. History is anchored to the member's LOCAL day, and a
  /// test that could not fix "today" would be a test of the machine's date.
  final DateTime? _anchor;

  final RxList<HistoryDay> days = <HistoryDay>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool loadError = false.obs;

  /// True once the lookback horizon has been reached — there is genuinely
  /// nothing further back to fetch.
  ///
  /// This is NOT set by an empty window. It used to be, and that was the
  /// defect: a member who stopped logging for a month had every earlier day
  /// permanently hidden, because `reachedEnd` blocks [loadMore] and [load]
  /// only restarts from the same empty first window. The days were never
  /// lost — they were unreachable, which to the member is the same thing.
  final RxBool reachedEnd = false.obs;

  /// How far back history will look before honestly declaring the end.
  ///
  /// A gap is not the end of history, so paging must be able to walk PAST an
  /// empty window — but it cannot walk forever, or a member with nothing
  /// logged would scan without bound. One year is the horizon: long enough
  /// that a real member's history is reachable, short enough that the
  /// worst case (a member who never logged) is a bounded one-time scan of
  /// `ceil(366 / 31) = 12` windows.
  static const int maxLookbackDays = 366;

  /// The day the member has expanded, or null for the list view.
  final Rxn<HistoryDay> selected = Rxn<HistoryDay>();

  static final DateFormat _fmt = DateFormat('yyyy-MM-dd');

  DateTime get _today {
    final n = _anchor ?? DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// How far back the next page starts, in days from today.
  int _offset = 0;
  bool _closed = false;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  @override
  void onClose() {
    _closed = true;
    super.onClose();
  }

  /// Loads (or reloads) the first page.
  Future<void> load() async {
    _offset = 0;
    reachedEnd.value = false;
    days.clear();
    isLoading.value = true;
    loadError.value = false;
    await _fetchPage();
    if (!_closed) isLoading.value = false;
  }

  /// Fetches the next window further back in time.
  Future<void> loadMore() async {
    if (isLoading.value || isLoadingMore.value || reachedEnd.value) return;
    isLoadingMore.value = true;
    await _fetchPage();
    if (!_closed) isLoadingMore.value = false;
  }

  Future<void> _fetchPage() async {
    try {
      // Keep walking back through EMPTY windows until this page has something
      // to show or the horizon is reached. A member who logged in June, took
      // July off and opens History in August must still reach June: stopping
      // at the first empty window is what hid it.
      //
      // Windows that find days stop the scan immediately, so the common case
      // still costs exactly one window's reads.
      final found = <HistoryDay>[];
      while (found.isEmpty && _offset < maxLookbackDays) {
        // TODAY IS EXCLUDED from history: it is live on the Diet screen above,
        // and showing it twice invites the member to wonder which is current.
        final start = _offset + 1;
        final keys = [
          for (var i = 0; i < NutritionDayService.maxHistoryDays; i++)
            _fmt.format(_today.subtract(Duration(days: start + i))),
        ];
        final fetched = await _service.fetchDays(keys);
        if (_closed) return;
        _offset += NutritionDayService.maxHistoryDays;
        found.addAll([
          for (final d in fetched)
            if (d.dateKey.isNotEmpty)
              HistoryDay(
                dateKey: d.dateKey,
                date: DateTime.tryParse(d.dateKey) ?? _today,
                day: d,
              ),
        ]);
      }
      if (_closed) return;
      days.addAll(found);
      // The end is the HORIZON, never merely an empty window.
      if (found.isEmpty || _offset >= maxLookbackDays) reachedEnd.value = true;
      loadError.value = false;
    } catch (_) {
      if (_closed) return;
      // An honest failure, never an empty history — claiming a member logged
      // nothing for a month because a read failed is the worst thing this
      // screen could say.
      loadError.value = true;
    }
  }

  void open(HistoryDay day) => selected.value = day;
  void closeDay() => selected.value = null;

  /// Days that actually carry a log, newest first.
  List<HistoryDay> get loggedDays =>
      days.where((d) => d.entryCount > 0).toList();

  /// Mean calories across the LOGGED days on screen.
  ///
  /// The denominator is logged days, never the calendar: four unlogged days
  /// must not dilute the three a member did record. The same rule the coach's
  /// hit-rate scoring already uses.
  double? get averageCalories {
    final logged = loggedDays;
    if (logged.isEmpty) return null;
    final total = logged.fold<double>(0, (a, d) => a + d.calories);
    return total / logged.length;
  }
}
