import 'package:get/get.dart';

import '../core/domain/performance.dart';
import '../core/domain/prescription.dart';
import 'streak_controller.dart';
import 'training_controller.dart';

/// PRESCRIPTION ENGINE (Phase 4) — glue between the served prescription
/// material, the member's logged day-keys, and the performance UI.
///
/// Holds NO logic of its own: every number is computed by the pure, tested
/// domain (`performance.dart` on the certified Step-1 engine). Getters are
/// re-evaluated inside Obx whenever the underlying observables change, so a
/// pull-to-refresh or a new log flows straight through.
class PerformanceController extends GetxController {
  final TrainingController training = Get.find<TrainingController>();
  final StreakController streaks = Get.find<StreakController>();

  PrescriptionException? get _coachingPause {
    final raw = training.prescriptionData.value?['coachingPause'];
    if (raw is! Map) return null;
    return PrescriptionException.fromMap(Map<String, dynamic>.from(raw));
  }

  TrackHistory _historyFor(String track) => TrackHistory.fromServed(
    training.prescriptionData.value?[track],
    coachingPause: _coachingPause,
  );

  TrackHistory get workoutHistory => _historyFor('workout');
  TrackHistory get dietHistory => _historyFor('diet');

  Set<String> get workoutDays => streaks.workoutDays.value ?? const {};
  Set<String> get dietDays => streaks.dietDays.value ?? const {};

  /// Whether the day-key sets loaded at all (null = unavailable, never 0).
  bool get workoutLogsAvailable => streaks.workoutDays.value != null;
  bool get dietLogsAvailable => streaks.dietDays.value != null;

  TrackHistory historyOf({required bool isWorkout}) =>
      isWorkout ? workoutHistory : dietHistory;

  Set<String> loggedOf({required bool isWorkout}) =>
      isWorkout ? workoutDays : dietDays;

  // ── Derivations (thin passthroughs to the pure domain) ──────────────────

  List<DayVerdict> timelineOf({required bool isWorkout, int days = 30}) =>
      timeline(
        historyOf(isWorkout: isWorkout),
        logged: loggedOf(isWorkout: isWorkout),
        today: DateTime.now(),
        days: days,
      );

  TrackWeek weekOf({required bool isWorkout}) => weekSummary(
    historyOf(isWorkout: isWorkout),
    logged: loggedOf(isWorkout: isWorkout),
    today: DateTime.now(),
  );

  List<MonthCell> monthOf({required bool isWorkout}) =>
      monthOfDate(isWorkout: isWorkout, month: DateTime.now());

  /// The resolved cells for ANY month — what Workout History's month and year
  /// selectors move over.
  ///
  /// The engine has always been able to answer for a past month (that is the
  /// whole point of versioned prescriptions: a past date resolves the version
  /// that was in force THEN, so moving a member from 6 days a week to 4 cannot
  /// retroactively improve last month). Only this controller was hardcoded to
  /// `DateTime.now()`. Exposing the parameter is what lets History reuse the
  /// production engine instead of growing a second, weekday-pattern answer of
  /// its own — which would have painted "rest" over months the coach actually
  /// prescribed work for.
  List<MonthCell> monthOfDate({
    required bool isWorkout,
    required DateTime month,
  }) =>
      monthCells(
        historyOf(isWorkout: isWorkout),
        logged: loggedOf(isWorkout: isWorkout),
        month: month,
        today: DateTime.now(),
      );

  List<Insight> insightsOf({required bool isWorkout}) => insightsFor(
    historyOf(isWorkout: isWorkout),
    logged: loggedOf(isWorkout: isWorkout),
    today: DateTime.now(),
    trackLabel: isWorkout ? 'workouts' : 'meals',
  );

  int weeklyStreakOf({required bool isWorkout}) => weeklyAdherenceStreak(
    historyOf(isWorkout: isWorkout),
    logged: loggedOf(isWorkout: isWorkout),
    today: DateTime.now(),
  );

  int dailyStreakOf({required bool isWorkout}) => dailyStreak(
    historyOf(isWorkout: isWorkout),
    logged: loggedOf(isWorkout: isWorkout),
    today: DateTime.now(),
  );

  /// The LONGEST run in the window, in the SAME unit and from the SAME engine
  /// as the current streak. The detail screen used to take this from
  /// `StreakController`'s raw calendar-day math, which meant "Longest Streak"
  /// and "Current Streak" sat side by side answering different questions —
  /// and a compliant 4x-week member read *Current 6 weeks · Longest 1 day*.
  int bestWeeklyStreakOf({required bool isWorkout}) =>
      bestWeeklyAdherenceStreak(
        historyOf(isWorkout: isWorkout),
        logged: loggedOf(isWorkout: isWorkout),
        today: DateTime.now(),
      );

  int bestDailyStreakOf({required bool isWorkout}) => bestDailyStreak(
    historyOf(isWorkout: isWorkout),
    logged: loggedOf(isWorkout: isWorkout),
    today: DateTime.now(),
  );

  DayVerdict todayVerdictOf({required bool isWorkout}) =>
      historyOf(isWorkout: isWorkout).verdictOn(
        DateTime.now(),
        logged: loggedOf(isWorkout: isWorkout),
        today: DateTime.now(),
      );

  /// The expectation detail (reason + coach note) for one day — the tap-a-day
  /// sheet's content.
  ///
  /// DELEGATES to `TrackHistory.expectationOn`, the one entry point. It used to
  /// call `expectationFor` on `versions` directly, and so resolved from a
  /// strictly smaller set of facts than the calendar cell that opens it: it
  /// could see neither the assignment-level pause (F4) nor the coach's excuse.
  /// A paused or excused day therefore read "Session expected" in the detail
  /// while the cell it came from read "Coaching paused".
  Expectation expectationDetailOf(
    DateTime date, {
    required bool isWorkout,
  }) => historyOf(
    isWorkout: isWorkout,
  ).expectationOn(date, today: DateTime.now());
}
