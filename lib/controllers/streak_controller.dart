import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:get/get.dart';

import '../core/domain/workout_session.dart';
import '../core/services/activity_history_service.dart';
import '../core/services/workout_log_service.dart';
import '../core/utils/lifestyle_math.dart' show dayKey;
import '../core/utils/streak_math.dart';
import 'member_controller.dart';

/// Repository-backed workout + diet streaks, derived from the member's OWN
/// logs (`client_workout_sessions` / `client_diet_logs`) — never fabricated.
/// A null streak means the data couldn't be read (offline / rules): the UI
/// hides that tile honestly instead of showing a fake 0.
///
/// Streak rule (see streak_math.dart): consecutive calendar days with a
/// qualifying log, ending today — or yesterday while today is still open.
/// Qualifying: workout = a saved session doc that day; diet = a day log with
/// at least one food marked. Capped at 60 days back ("60+").
class StreakController extends GetxController {
  /// Resolved LAZILY, not in a field initializer — the house pattern.
  ///
  /// `ActivityHistoryService` builds `FirebaseFirestore.instance` on
  /// construction, so an eager field ran for every subclass too and made this
  /// controller impossible to construct in a plain unit test. That is why none
  /// of its live-update behaviour was ever unit-tested, and why the duration
  /// regression reached a device. Nothing here needs the service until a
  /// `load()` actually runs.
  ActivityHistoryService? _injectedService;
  ActivityHistoryService get _service =>
      _injectedService ??= ActivityHistoryService();

  MemberController get _member => Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  static const int cap = 60;

  final RxBool isLoading = true.obs;

  /// Null = unavailable (hide, don't fake). Values are day-key sets so today's
  /// contribution and 7-day consistency derive from the same evidence.
  final Rxn<Set<String>> workoutDays = Rxn<Set<String>>();
  final Rxn<Set<String>> dietDays = Rxn<Set<String>>();

  /// TRUTHFUL COMPLETION — today's session stats, or null when no session doc
  /// exists today. Computed by the ONE engine (`computeSessionStats`) from the
  /// same document the coach reads, so Home's "N% done" and the coach's view
  /// can never disagree. Presence ([workoutToday]) keeps answering the streak
  /// question; THIS answers "how much of today's workout is actually done".
  ///
  /// DAY-STAMPED: [_statsDayKey] records which day the held stats belong to,
  /// and the public getter refuses to serve them across midnight — without
  /// this, a phone left overnight woke up with the hero claiming yesterday's
  /// "42% done — resume" against a brand-new day.
  final Rxn<SessionStats> _todayWorkoutStats = Rxn<SessionStats>();
  String _statsDayKey = '';

  /// WHERE today's session resumes — derived from the SAME document read that
  /// produces the stats above, so "42% done" and "Bench Press, set 2 of 4"
  /// can never describe different sessions. Null when nothing is left (or no
  /// session exists), and day-guarded exactly like the stats.
  final Rxn<NextUp> _todayNextUp = Rxn<NextUp>();

  NextUp? get todayNextUp {
    final held = _todayNextUp.value; // read first: registers tracking
    if (_statsDayKey != dayKey(DateTime.now())) return null;
    return held;
  }

  /// TODAY'S SESSION, EXERCISE BY EXERCISE — the same `List<ExerciseLog>` the
  /// stats above are computed FROM, so "what did I actually do today" and
  /// "how much of it is done" are two views of one read, never two reads.
  ///
  /// My Plans renders this as "Today's workout"; Home renders only the
  /// aggregate. Null means no session document exists today (or it was
  /// unreadable) — never an empty list, because an empty list would render as
  /// "you did a workout containing nothing".
  ///
  /// Day-guarded exactly like [todayWorkoutStats]: yesterday's sets must not
  /// appear under today's heading on a phone left running overnight.
  final Rxn<List<ExerciseLog>> _todayExercises = Rxn<List<ExerciseLog>>();

  List<ExerciseLog>? get todayExercises {
    final held = _todayExercises.value; // read first: registers tracking
    if (_statsDayKey != dayKey(DateTime.now())) return null;
    return held;
  }

  /// Today's recorded session length, for the finished card's "Duration".
  /// Null when the clock was never recorded — the card then states no
  /// duration rather than a fabricated "0m".
  final Rxn<int> _todayDurationSeconds = Rxn<int>();

  int? get todayDurationSeconds {
    final held = _todayDurationSeconds.value;
    if (_statsDayKey != dayKey(DateTime.now())) return null;
    return held;
  }

  /// Today's deterministic session id — lets Home open the summary for a
  /// finished session without re-deriving the id anywhere else.
  String get todaySessionId => _member.clientId.isEmpty
      ? ''
      : workoutSessionIdFor(_member.clientId, DateTime.now());

  /// Plain nullable getter (NOT the Rxn itself) so the day guard applies on
  /// every read while an enclosing Obx still tracks the backing observable —
  /// returning a throwaway Rxn on mismatch would silently detach reactivity.
  SessionStats? get todayWorkoutStats {
    final held = _todayWorkoutStats.value; // read first: registers tracking
    if (_statsDayKey != dayKey(DateTime.now())) {
      // Stale day: report nothing rather than yesterday's fraction. The next
      // load()/ensureFreshDay() repopulates for the real today.
      return null;
    }
    return held;
  }

  /// Forces the day the held session stats are stamped with.
  ///
  /// Exists so the midnight-rollover guard is testable without waiting for
  /// midnight: every one of the four views must go null together, or one of
  /// them renders yesterday's work under a "today" heading.
  @visibleForTesting
  void forceStatsDayForTest(String key) => _statsDayKey = key;

  /// Day-rollover guard, same contract as the diet/lifestyle/training
  /// controllers' ensureFreshDay: called on app resume so a phone left
  /// overnight re-anchors to the new calendar day.
  Future<void> ensureFreshDay() async {
    if (_statsDayKey == dayKey(DateTime.now())) return;
    await _loadTodayStats();
  }

  Worker? _linkWorker;
  Worker? _clientWorker;
  bool _loadedOnce = false;

  int? get workoutStreak => _streakOf(workoutDays.value);
  int? get dietStreak => _streakOf(dietDays.value);
  bool get workoutToday {
    final d = workoutDays.value;
    return d != null && loggedToday(d, DateTime.now());
  }

  bool get dietToday {
    final d = dietDays.value;
    return d != null && loggedToday(d, DateTime.now());
  }

  int? get workoutDays7 => _week(workoutDays.value);
  int? get dietDays7 => _week(dietDays.value);

  /// Best consecutive run within the fetched [cap]-day window (honest scope —
  /// never claims all-time). Null while unavailable.
  int? get workoutBest => _bestOf(workoutDays.value);
  int? get dietBest => _bestOf(dietDays.value);

  static int? _bestOf(Set<String>? days) =>
      days == null ? null : bestStreakInWindow(days, DateTime.now(), cap);

  /// Anything to show at all? (Both unavailable → the section hides.)
  bool get hasAny => workoutDays.value != null || dietDays.value != null;

  static int? _streakOf(Set<String>? days) =>
      days == null ? null : currentStreak(days, DateTime.now(), cap: cap);

  static int? _week(Set<String>? days) =>
      days == null ? null : daysLoggedInWindow(days, DateTime.now(), 7);

  @override
  void onInit() {
    super.onInit();
    load();
    // Same rebind pattern as Diet/CheckIn/Lifestyle: on first init the claim()
    // may not have resolved (clientId empty → reads no-op). Reload on link.
    _linkWorker = ever(_member.isLinked, (_) => load());
    // isLinked can already be true BEFORE this controller registers (`ever`
    // then never fires) while clientId resolves a beat later — retry when the
    // client doc lands until a load has actually produced data.
    _clientWorker = ever(_member.client, (_) {
      if (!hasAny) load();
    });
  }

  bool _inFlight = false;

  /// One-shot load (called on init, link, client-doc arrival and
  /// pull-to-refresh). Re-entrant calls are dropped while a load is running.
  Future<void> load() async {
    if (_inFlight) return;
    if (_member.clientId.isEmpty) {
      isLoading.value = false;
      return;
    }
    _inFlight = true;
    if (!_loadedOnce) isLoading.value = true;
    final results = await Future.wait([
      _service.workoutDayKeys(windowDays: cap),
      _service.dietDayKeys(windowDays: cap),
    ]);
    workoutDays.value = results[0];
    dietDays.value = results[1];
    await _loadTodayStats();
    if (results[0] == null || results[1] == null) {
      // Abnormal: a source couldn't be read (rules/offline) — its tile hides.
      debugPrint(
        'StreakController: unavailable — workout=${results[0] != null} '
        'diet=${results[1] != null}',
      );
    }
    _loadedOnce = true;
    _inFlight = false;
    isLoading.value = false;
  }

  /// Called by the diet logger after a successful save — keeps "today's
  /// contribution" live without a refetch. No-op while data is unavailable
  /// (an unloaded set must stay honest-unavailable, not become a fake {today}).
  void markDietToday() {
    final d = dietDays.value;
    if (d != null) dietDays.value = {...d, dayKey(DateTime.now())};
  }

  /// Called by the workout session screen after a successful save.
  /// [stats] carries the session's live progress so the Home chip updates the
  /// moment a set is saved — no refetch, no drift (same engine, same numbers).
  /// [nextUp] rides along so Home's resume line stays live as sets are logged;
  /// null legitimately means "nothing left", which is why it is passed
  /// explicitly rather than inferred from a null check on [stats].
  /// [trained] carries THE rule ([hasCompletedWork] / [sessionCountsAsTrainingDay]),
  /// and the day-key set follows it in BOTH directions. Undoing the only
  /// completed set of a session used to leave today marked done until the next
  /// refetch — so Home said "1 day streak" and a restart said 0, which is the
  /// same across-a-restart flip the repository fix closes on the read side.
  void markWorkoutToday({
    SessionStats? stats,
    NextUp? nextUp,
    List<ExerciseLog>? exercises,
    int? durationSeconds,
    bool trained = true,
  }) {
    final d = workoutDays.value;
    final today = dayKey(DateTime.now());
    if (d != null) {
      workoutDays.value = trained ? {...d, today} : ({...d}..remove(today));
    }
    if (stats != null) {
      _statsDayKey = dayKey(DateTime.now());
      _todayWorkoutStats.value = stats;
      _todayNextUp.value = nextUp;
      // Carried on the SAME call as the stats so My Plans' per-set view and
      // Home's percentage can never describe different sessions. A caller that
      // does not supply them leaves the held list untouched rather than
      // clearing it — losing the detail would silently empty "Today's workout"
      // mid-session.
      if (exercises != null) _todayExercises.value = exercises;
      // THE CLOCK, on the same call as everything else.
      //
      // It was the one figure `_loadTodayStats` read from the document and
      // nothing ever wrote back live. A session has no `finishedAt` until it is
      // finished, so the held value was null all through the workout — and
      // FINISHING did not update it. The summary screen computed and displayed
      // "2h 8m", and both My Plans and Home then rendered a completed session
      // with NO duration at all until the next app restart re-read the doc.
      // Observed on device.
      //
      // Null is not written back: an in-progress save legitimately has no
      // duration, and letting it clear a real one would reintroduce the bug
      // from the other direction.
      if (durationSeconds != null && durationSeconds > 0) {
        _todayDurationSeconds.value = durationSeconds;
      }
    }
  }

  /// Cold-open fetch of today's session (deterministic id — the Session
  /// Integrity work made one-doc-per-day the rule, which is what makes this a
  /// single cheap read). Absent doc → null → the chip simply doesn't render.
  Future<void> _loadTodayStats() async {
    final clientId = _member.clientId;
    if (clientId.isEmpty) return;
    final today = dayKey(DateTime.now());
    try {
      final id = workoutSessionIdFor(clientId, DateTime.now());
      final doc = await WorkoutLogService().fetchSession(id);
      _statsDayKey = today;
      if (doc == null) {
        _todayWorkoutStats.value = null;
        _todayNextUp.value = null;
        _todayExercises.value = null;
        _todayDurationSeconds.value = null;
        return;
      }
      final logs = exercisesFromEntries(doc['entries']);
      _todayWorkoutStats.value =
          logs.isEmpty ? null : computeSessionStats(logs);
      _todayNextUp.value = logs.isEmpty ? null : nextUpFrom(logs);
      _todayExercises.value = logs.isEmpty ? null : logs;
      final d = doc['durationSeconds'];
      _todayDurationSeconds.value = d is num && d > 0 ? d.toInt() : null;
    } catch (_) {
      // Unavailable stays unavailable — never a fabricated 0%.
      _statsDayKey = today;
      _todayWorkoutStats.value = null;
      _todayNextUp.value = null;
      _todayExercises.value = null;
      _todayDurationSeconds.value = null;
    }
  }

  @override
  void onClose() {
    _linkWorker?.dispose();
    _clientWorker?.dispose();
    super.onClose();
  }
}
