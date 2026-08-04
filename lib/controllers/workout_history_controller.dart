import 'package:get/get.dart';

import '../core/domain/performance.dart' show MonthCell;
import '../core/domain/workout_history.dart';
import '../core/services/workout_log_service.dart';
import '../core/utils/lifestyle_math.dart' show dayKey;
import 'performance_controller.dart';
import 'streak_controller.dart';
import 'training_controller.dart';

/// WORKOUT HISTORY — state for the member's own training record.
///
/// ── WHAT THIS CONTROLLER IS NOT ───────────────────────────────────────────
///
/// It is **not a second store of workouts.** It holds no history document, no
/// mirror, no rollup and no cache that outlives the screen. It performs the
/// SAME `authorId ==` query the streak repository already runs on every cold
/// open, over the SAME `client_workout_sessions` collection TrainerHQ reads,
/// and parses each document with the SAME parser the live session uses. If a
/// coach opened the client's file in TrainerHQ at the same moment, they would
/// be looking at these exact documents.
///
/// The only things it adds are a selection (which month, which day) and the
/// composition of two production sources — the member's logs and the coach's
/// resolved prescription — which lives in the pure `workout_history.dart`.
///
/// ── WHY THE PRESCRIPTION COMES FROM THE ENGINE ────────────────────────────
///
/// "Rest" on a past date is a claim about what the COACH asked for months ago.
/// Deriving it from the plan's CURRENT weekly schedule — the obvious shortcut —
/// would repaint history every time a coach changed a training split, marking
/// as rest days the member had actually been asked to train on. The
/// prescription engine resolves the version that was in force on each date,
/// which is the only honest source, and `PerformanceController` already owns
/// it for the consistency screens.
class WorkoutHistoryController extends GetxController {
  WorkoutHistoryController({
    WorkoutLogService? logService,
    PerformanceController? performance,
    StreakController? streaks,
  })  : _injectedLog = logService,
        _injectedPerformance = performance,
        _injectedStreaks = streaks;

  /// Every collaborator is injectable and resolved LAZILY — the house pattern.
  /// `WorkoutLogService` builds `FirebaseFirestore.instance` on construction,
  /// so an eager field would make this controller impossible to build in a
  /// plain unit test, which is exactly how the module's last read-path
  /// regression reached a device untested.
  final WorkoutLogService? _injectedLog;
  WorkoutLogService? _log;
  WorkoutLogService get log => _injectedLog ?? (_log ??= WorkoutLogService());

  final PerformanceController? _injectedPerformance;
  PerformanceController get performance =>
      _injectedPerformance ??
      (Get.isRegistered<PerformanceController>()
          ? Get.find<PerformanceController>()
          : Get.put(PerformanceController()));

  final StreakController? _injectedStreaks;
  StreakController get streaks =>
      _injectedStreaks ??
      (Get.isRegistered<StreakController>()
          ? Get.find<StreakController>()
          : Get.put(StreakController()));

  /// FIRST LOAD ONLY — the skeleton's flag.
  ///
  /// Once the member has seen real days, a refresh must never take them away
  /// and replace them with a shimmer: that destroys information they had a
  /// moment ago in order to say something [isRefreshing] can say quietly. This
  /// is the rule `premium_states.dart` states and the nutrition twin has always
  /// followed. This controller did not: [load] raised `isLoading`
  /// unconditionally, and the screen returns its skeleton on that flag — so
  /// every pull-to-refresh, and every return from the log editor, blanked the
  /// whole month the member was reading and rebuilt it from grey.
  final RxBool isLoading = true.obs;

  /// A re-read while days are already on screen.
  final RxBool isRefreshing = false.obs;

  /// True when the read FAILED, as opposed to returning nothing.
  ///
  /// A member who has never trained and a member whose network is down must
  /// not see the same screen: one is an invitation, the other is an apology.
  final RxBool loadError = false.obs;

  /// Session documents by local day key. Rebuilt wholesale on each load — there
  /// is no incremental merge to get subtly wrong.
  final RxMap<String, WorkoutDayLog> logsByDay =
      <String, WorkoutDayLog>{}.obs;

  /// The month on screen, always at its 1st.
  late final Rx<DateTime> month = Rx<DateTime>(_firstOfThisMonth());

  /// The day whose log is open. Never null once a month is shown: the timeline
  /// always has a highlighted day, which is what makes the detail panel below
  /// it explicable rather than arbitrary.
  late final Rx<DateTime> selectedDay = Rx<DateTime>(_today());

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _firstOfThisMonth() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, 1);
  }

  @override
  void onInit() {
    super.onInit();
    load();
  }

  bool _inFlight = false;

  Future<void> load() async {
    if (_inFlight) return;
    _inFlight = true;
    // Nothing on screen yet → skeleton. Something on screen → a whisper.
    final cold = logsByDay.isEmpty;
    if (cold) {
      isLoading.value = true;
    } else {
      isRefreshing.value = true;
    }
    // The prescription material and the logged-day set both live on
    // controllers this screen does not own. Refreshing the streaks here keeps
    // the calendar's non-logged states (missed / rest / paused) resolved
    // against the same evidence the rest of the app is using, rather than
    // whatever was loaded when the dashboard booted.
    final docs = await log.fetchSessionHistory();
    if (docs == null) {
      // A FAILED RE-READ MUST NOT DESTROY A GOOD MONTH.
      //
      // `loadError` is what the screen turns into an apology, and raising it on
      // a background refresh would replace days the member is reading — days
      // that are still perfectly valid — with a network error. The failure is
      // only reported when there was nothing on screen to lose.
      if (cold) loadError.value = true;
      isLoading.value = false;
      isRefreshing.value = false;
      _inFlight = false;
      return;
    }
    final parsed = <WorkoutDayLog>[];
    for (final doc in docs) {
      final id = (doc['id'] ?? '').toString();
      final one = parseWorkoutDayLog(doc, id);
      // A document with no readable date is DROPPED, not placed on "today":
      // inventing a training day is the one failure this screen must never
      // have.
      if (one != null) parsed.add(one);
    }
    logsByDay.value = indexWorkoutLogs(parsed);
    loadError.value = false;
    isLoading.value = false;
    isRefreshing.value = false;
    _inFlight = false;
  }

  // ── SELECTION ────────────────────────────────────────────────────────────

  /// Every year the member could meaningfully look at: from their earliest
  /// logged session to the current year, newest first.
  ///
  /// DERIVED, never a fixed range. A member who joined this month sees one
  /// year, not a decade of empty ones — and a member with three years of
  /// training can reach all three.
  List<int> get years {
    final now = DateTime.now().year;
    var earliest = now;
    for (final l in logsByDay.values) {
      if (l.date.year < earliest) earliest = l.date.year;
    }
    return [for (var y = now; y >= earliest; y--) y];
  }

  /// Whether a month is in the future — the selector offers it disabled rather
  /// than hiding it, so the grid of months does not reflow as the year changes.
  bool isFutureMonth(int year, int month) {
    final now = DateTime.now();
    return DateTime(year, month, 1).isAfter(DateTime(now.year, now.month, 1));
  }

  void showMonth(int year, int monthNumber) {
    if (isFutureMonth(year, monthNumber)) return;
    month.value = DateTime(year, monthNumber, 1);
    // MOVING MONTHS MOVES THE SELECTION WITH IT.
    //
    // Leaving the selection on a day in a month that is no longer on screen
    // left the detail panel describing a date the timeline could not show, and
    // no cell highlighted anywhere — the member's own tap appeared to have
    // been ignored. The landing day is today when the month contains it (the
    // member's most likely interest), otherwise the most recent day they
    // actually trained, otherwise the 1st.
    selectedDay.value = _landingDayFor(month.value);
  }

  DateTime _landingDayFor(DateTime m) {
    final today = _today();
    if (m.year == today.year && m.month == today.month) return today;
    final daysInMonth = DateTime(m.year, m.month + 1, 0).day;
    for (var d = daysInMonth; d >= 1; d--) {
      final date = DateTime(m.year, m.month, d);
      if (logsByDay.containsKey(dayKey(date))) return date;
    }
    return DateTime(m.year, m.month, 1);
  }

  void select(DateTime date) =>
      selectedDay.value = DateTime(date.year, date.month, date.day);

  // ── DERIVATIONS ──────────────────────────────────────────────────────────

  /// The month on screen, composed from the coach's prescription and the
  /// member's own logs. Both halves come from production engines; this
  /// controller only hands them to each other.
  List<WorkoutHistoryDay> get days {
    final List<MonthCell> cells =
        performance.monthOfDate(isWorkout: true, month: month.value);
    return composeHistoryMonth(cells: cells, logsByDay: logsByDay);
  }

  WorkoutHistoryDay? get selected {
    final key = dayKey(selectedDay.value);
    for (final d in days) {
      if (dayKey(d.date) == key) return d;
    }
    return null;
  }

  /// Index of [selectedDay] within [days], or of today when the month holds it.
  /// Drives the timeline's initial scroll — see the screen.
  int get selectedIndex {
    final key = dayKey(selectedDay.value);
    final all = days;
    for (var i = 0; i < all.length; i++) {
      if (dayKey(all[i].date) == key) return i;
    }
    return 0;
  }

  /// Whether the coach has authored any prescription at all for this member.
  ///
  /// Without one, "rest" and "missed" are unanswerable, every unlogged day is
  /// honestly [WorkoutDayState.unknown], and the screen says so once at the
  /// bottom instead of leaving the member to wonder why most of their calendar
  /// is grey. This is the platform's DEFAULT state, not an error.
  bool get hasPrescription => performance.workoutHistory.hasPrescription;

  /// Sessions inside the month on screen — the month's own summary.
  Iterable<WorkoutDayLog> get monthLogs {
    final m = month.value;
    return logsByDay.values
        .where((l) => l.date.year == m.year && l.date.month == m.month);
  }

  int get monthSessionCount => monthLogs.length;

  /// Total completed sets logged this month. Zero is a real answer here (the
  /// member trained and completed nothing), so unlike a duration it is shown.
  int get monthCompletedSets =>
      monthLogs.fold(0, (a, l) => a + l.stats.completedSets);

  /// Σ volume over the month's sessions, or null when NOT ONE session produced
  /// a load figure — bodyweight-only training is not zero-volume training.
  double? get monthVolumeKg {
    var total = 0.0;
    var any = false;
    for (final l in monthLogs) {
      if (l.stats.hasVolume) {
        any = true;
        total += l.stats.volumeKg;
      }
    }
    return any ? total : null;
  }

  /// The training controller is where the coach's plan name lives, for the day
  /// sheet's fallback when a session document predates `planName`.
  TrainingController? get training => Get.isRegistered<TrainingController>()
      ? Get.find<TrainingController>()
      : null;
}
