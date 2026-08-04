import 'package:get/get.dart';

import '../core/domain/nutrition_history.dart';
import '../core/services/nutrition_day_service.dart';

/// NUTRITION HISTORY — state for the member's own food record.
///
/// The deliberate twin of `WorkoutHistoryController`: same selection model
/// (a month, a selected day), same honest loading/error split, same rule that
/// the controller composes production sources and owns none of its own.
///
/// ── WHAT THIS CONTROLLER IS NOT ───────────────────────────────────────────
///
/// It is **not a second store of food.** It holds no history document, no
/// mirror and no rollup. It reads `client_nutrition_days` by DETERMINISTIC ID
/// — the same documents `NutritionDayService` writes, the live Food Log
/// renders and TrainerHQ reads — and parses them with the same
/// `NutritionDayModel.fromMap`. A coach with the client's file open in
/// TrainerHQ is looking at these exact documents.
///
/// ── WHY IT FETCHES A MONTH, NOT A HISTORY ─────────────────────────────────
///
/// The workout twin can afford one `authorId ==` query because a member has at
/// most one session document per day. Food is different: `fetchDays` takes
/// explicit keys and reads each day by id, which needs **no composite index
/// and can never scan a member's entire past**. So this fetches exactly the
/// month on screen (28-31 gets), and caches it — moving back to a month
/// already seen costs nothing, and the Firestore cache serves those gets
/// offline.
class NutritionHistoryController extends GetxController {
  NutritionHistoryController({NutritionDayService? service, DateTime? now})
      : _injectedService = service,
        _injectedNow = now;

  /// Injectable and resolved LAZILY — the house pattern. `NutritionDayService`
  /// resolves Firebase and `MemberController` on use, so an eager field would
  /// make this controller impossible to build in a plain unit test.
  final NutritionDayService? _injectedService;
  NutritionDayService? _service;
  NutritionDayService get service =>
      _injectedService ?? (_service ??= NutritionDayService());

  /// Injectable clock. Three of the five day states hinge on "is this day still
  /// open?", and a controller whose today could not be pinned would be tested
  /// against the machine's date rather than against a rule.
  final DateTime? _injectedNow;
  DateTime get _now => _injectedNow ?? DateTime.now();

  DateTime get today {
    final n = _now;
    return DateTime(n.year, n.month, n.day);
  }

  /// FIRST LOAD ONLY — the skeleton's flag.
  ///
  /// Once the member has seen real days, a refresh must never take them away
  /// and replace them with a shimmer: that destroys information they had a
  /// moment ago to tell them something [isRefreshing] can say quietly. This is
  /// the rule `premium_states.dart` states and the reason the two flags are
  /// separate rather than one busy boolean.
  final RxBool isLoading = true.obs;

  /// A re-read while days are already on screen.
  final RxBool isRefreshing = false.obs;

  /// True when the read FAILED, as opposed to returning nothing.
  ///
  /// A member who has never logged food and a member whose network is down
  /// must not see the same screen: one is an invitation, the other an apology.
  final RxBool loadError = false.obs;

  /// Day documents by local day key, across every month fetched so far.
  final RxMap<String, NutritionDayLog> logsByDay =
      <String, NutritionDayLog>{}.obs;

  /// Months already fetched, so a revisit does not re-read 31 documents.
  final Set<String> _loadedMonths = {};

  late final Rx<DateTime> month = Rx<DateTime>(
    DateTime(today.year, today.month, 1),
  );

  /// The day whose log is open. Never null once a month is shown: the timeline
  /// always has a highlighted day, which is what makes the panel below it
  /// explicable rather than arbitrary.
  late final Rx<DateTime> selectedDay = Rx<DateTime>(today);

  @override
  void onInit() {
    super.onInit();
    load();
  }

  bool _inFlight = false;

  /// Loads the month on screen. [force] re-reads a month already cached — what
  /// pull-to-refresh and the error retry use.
  Future<void> load({bool force = false}) async {
    if (_inFlight) return;
    final m = month.value;
    final monthKey = '${m.year}-${m.month}';
    if (!force && _loadedMonths.contains(monthKey)) {
      // THE ERROR BELONGS TO A MONTH, NOT TO THE SCREEN.
      //
      // A month is in `_loadedMonths` only BECAUSE it read successfully, so
      // returning to one is proof there is nothing wrong with it. Without this
      // line the flag survived the move: a member whose July failed, and who
      // then went back to the August they had just been reading, was shown
      // August's month and year in the selectors above an apology about a
      // month they had left — and no amount of "Try again" could clear it,
      // because the cache hit returned before anything was retried.
      loadError.value = false;
      isLoading.value = false;
      return;
    }
    _inFlight = true;
    // Nothing on screen yet → skeleton. Something on screen → a whisper.
    final cold = logsByDay.isEmpty;
    if (cold) {
      isLoading.value = true;
    } else {
      isRefreshing.value = true;
    }
    try {
      final keys = [for (final d in daysInMonth(m)) nutritionDayKey(d)];
      final models = await service.fetchDays(keys);
      final next = Map<String, NutritionDayLog>.from(logsByDay);
      // A refetched month REPLACES its own days rather than merging into them,
      // so a food the member deleted elsewhere cannot survive as a ghost.
      for (final k in keys) {
        next.remove(k);
      }
      for (final model in models) {
        final date = _parseDayKey(model.dateKey);
        if (date == null) continue;
        next[model.dateKey] =
            NutritionDayLog(dateKey: model.dateKey, date: date, day: model);
      }
      logsByDay.value = next;
      _loadedMonths.add(monthKey);
      loadError.value = false;
    } catch (_) {
      // `fetchDays` throws only when the WHOLE window was unreadable — a
      // failure to read, which must never render as "you logged nothing".
      loadError.value = true;
    } finally {
      isLoading.value = false;
      isRefreshing.value = false;
      _inFlight = false;
    }
  }

  /// Re-reads the month on screen WITHOUT taking it off the screen.
  ///
  /// The screen calls this every time it is mounted, because the controller
  /// outlives it: `Get.put` keeps one instance for the session, so a member
  /// who opened History, went and logged lunch, and came back would otherwise
  /// be shown the cached month from before lunch — their own food missing from
  /// their own record, with no way to tell why.
  Future<void> refreshVisibleMonth() => load(force: true);

  /// A day key back to a date. Null on anything unparsable, and the day is then
  /// dropped rather than placed on today — inventing a day a member ate is the
  /// one failure this screen must not have.
  static DateTime? _parseDayKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  // ── SELECTION ────────────────────────────────────────────────────────────

  /// Every year the member could meaningfully look at: from their earliest
  /// logged day to the current year, newest first.
  ///
  /// DERIVED, never a fixed range — a member who joined this month sees one
  /// year, not a decade of empty ones.
  List<int> get years {
    final now = today.year;
    var earliest = now;
    for (final l in logsByDay.values) {
      if (l.hasEntries && l.date.year < earliest) earliest = l.date.year;
    }
    return [for (var y = now; y >= earliest; y--) y];
  }

  /// Whether a month is in the future — the selector offers it DISABLED rather
  /// than hiding it, so the 12-cell grid does not reflow as the year changes.
  bool isFutureMonth(int year, int monthNumber) =>
      DateTime(year, monthNumber, 1)
          .isAfter(DateTime(today.year, today.month, 1));

  Future<void> showMonth(int year, int monthNumber) async {
    if (isFutureMonth(year, monthNumber)) return;
    month.value = DateTime(year, monthNumber, 1);
    // MOVING MONTHS MOVES THE SELECTION WITH IT — leaving it on a day the
    // timeline no longer shows left the panel describing a date nothing was
    // highlighted for, so the member's tap looked ignored.
    selectedDay.value = _landingDayFor(month.value);
    await load();
    // The landing day is chosen again once the month's documents are in: before
    // the fetch there is nothing to look for, so a month whose only logged day
    // is the 12th would otherwise always land on the 1st.
    selectedDay.value = _landingDayFor(month.value);
  }

  /// Today when the month contains it (the member's most likely interest),
  /// otherwise the most recent day they actually logged, otherwise the 1st.
  DateTime _landingDayFor(DateTime m) {
    final t = today;
    if (m.year == t.year && m.month == t.month) return t;
    final count = DateTime(m.year, m.month + 1, 0).day;
    for (var d = count; d >= 1; d--) {
      final date = DateTime(m.year, m.month, d);
      final log = logsByDay[nutritionDayKey(date)];
      if (log != null && log.hasEntries) return date;
    }
    return DateTime(m.year, m.month, 1);
  }

  void select(DateTime date) =>
      selectedDay.value = DateTime(date.year, date.month, date.day);

  // ── DERIVATIONS ──────────────────────────────────────────────────────────

  /// The month on screen. One pure function, injected with the clock, so every
  /// state on this calendar is reproducible in a unit test.
  List<NutritionHistoryDay> get days => composeNutritionMonth(
        month: month.value,
        logsByDay: logsByDay,
        today: today,
      );

  NutritionHistoryDay? get selected {
    final key = nutritionDayKey(selectedDay.value);
    for (final d in days) {
      if (nutritionDayKey(d.date) == key) return d;
    }
    return null;
  }

  /// Index of [selectedDay] within [days] — drives the timeline's centring.
  int get selectedIndex {
    final key = nutritionDayKey(selectedDay.value);
    final all = days;
    for (var i = 0; i < all.length; i++) {
      if (nutritionDayKey(all[i].date) == key) return i;
    }
    return 0;
  }

  NutritionMonthSummary get monthSummary => summariseNutritionMonth(days);

  /// Today is the ONLY editable day, exactly as in Workout History: the member
  /// corrects what they are logging now, and a past day is a record.
  bool get isTodaySelected => selectedDay.value == today;
}
