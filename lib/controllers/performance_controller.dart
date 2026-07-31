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

  List<MonthCell> monthOf({required bool isWorkout}) => monthCells(
    historyOf(isWorkout: isWorkout),
    logged: loggedOf(isWorkout: isWorkout),
    month: DateTime.now(),
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

  DayVerdict todayVerdictOf({required bool isWorkout}) =>
      historyOf(isWorkout: isWorkout).verdictOn(
        DateTime.now(),
        logged: loggedOf(isWorkout: isWorkout),
        today: DateTime.now(),
      );

  /// The expectation detail (reason + coach note) for one day — the tap-a-day
  /// sheet's content. Resolved with the same engine as everything else.
  Expectation expectationDetailOf(
    DateTime date, {
    required bool isWorkout,
  }) => expectationFor(
    historyOf(isWorkout: isWorkout).versions,
    date,
    coachingPause: _coachingPause,
  );
}
