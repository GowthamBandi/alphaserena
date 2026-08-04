import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena/controllers/member_controller.dart';
import 'package:alphaserena/controllers/streak_controller.dart';
import 'package:alphaserena/core/domain/workout_session.dart';
import 'package:alphaserena/core/utils/lifestyle_math.dart' show dayKey;

/// TODAY'S SESSION IS ONE READ, PUBLISHED AS FOUR VIEWS.
///
/// `StreakController` holds today's stats, resume point, per-exercise detail
/// and duration. They are derived from a single document read, and updated live
/// by the session screen through `markWorkoutToday`. Anything the live path
/// forgets to carry silently falls back to whatever the last COLD read held —
/// which is how the duration bug shipped: the summary screen displayed
/// "2h 8m" while My Plans and Home rendered a completed session with no
/// duration at all, until the next app restart.
class _Streak extends StreakController {
  _Streak() {
    workoutDays.value = <String>{};
    isLoading.value = false;
  }

  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Member extends MemberController {
  @override
  String? get linkedClientId => 'c1';

  @override
  // ignore: must_call_super
  void onInit() {}
}

List<ExerciseLog> _logs({required int completed, int total = 3}) => [
      ExerciseLog(
        name: 'Dumbbell Chest Press',
        exerciseId: 'ex1',
        sets: List.generate(
          total,
          (i) => SetLog(
            pReps: '10',
            pWeight: '12',
            pRest: '90s',
            actualReps: i < completed ? '10' : '',
            actualWeight: i < completed ? '12' : '',
            state: i < completed ? SetLogState.completed : SetLogState.pending,
          ),
        ),
      ),
    ];

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<MemberController>(_Member());
  });
  tearDown(Get.reset);

  test('finishing a session publishes its DURATION immediately', () {
    final c = _Streak();
    final mid = _logs(completed: 1);

    // Mid-session: no finishedAt yet, so no duration exists to state.
    c.markWorkoutToday(
      stats: computeSessionStats(mid),
      nextUp: nextUpFrom(mid),
      exercises: mid,
      durationSeconds: null,
    );
    expect(c.todayDurationSeconds, isNull);

    // Finished.
    final done = _logs(completed: 3);
    c.markWorkoutToday(
      stats: computeSessionStats(done),
      nextUp: null,
      exercises: done,
      durationSeconds: 7680, // 2h 8m — what the summary screen states
    );
    expect(
      c.todayDurationSeconds,
      7680,
      reason: 'the surfaces must not wait for an app restart to state it',
    );
    expect(c.todayWorkoutStats!.isComplete, isTrue);
    expect(c.todayNextUp, isNull);
  });

  test('a later in-progress save never ERASES a recorded duration', () {
    // Editing a set on a finished session saves again with no finishedAt.
    final c = _Streak();
    final done = _logs(completed: 3);
    c.markWorkoutToday(
      stats: computeSessionStats(done),
      exercises: done,
      durationSeconds: 7680,
    );
    expect(c.todayDurationSeconds, 7680);

    c.markWorkoutToday(
      stats: computeSessionStats(done),
      exercises: done,
      durationSeconds: null,
    );
    expect(c.todayDurationSeconds, 7680);
  });

  test('the per-exercise detail and the aggregate describe ONE session', () {
    final c = _Streak();
    final logs = _logs(completed: 2);
    c.markWorkoutToday(
      stats: computeSessionStats(logs),
      nextUp: nextUpFrom(logs),
      exercises: logs,
    );

    expect(c.todayExercises, isNotNull);
    final completedInDetail = c.todayExercises!
        .expand((e) => e.sets)
        .where((s) => s.state == SetLogState.completed)
        .length;
    expect(completedInDetail, c.todayWorkoutStats!.completedSets);
    expect(c.todayNextUp!.setNumber, 3);
  });

  test('a caller that omits the detail does not WIPE it mid-session', () {
    final c = _Streak();
    final logs = _logs(completed: 1);
    c.markWorkoutToday(stats: computeSessionStats(logs), exercises: logs);
    expect(c.todayExercises, isNotNull);

    c.markWorkoutToday(stats: computeSessionStats(logs));
    expect(c.todayExercises, isNotNull);
  });

  test('every view is day-guarded together — no yesterday under a today heading',
      () {
    final c = _Streak();
    final logs = _logs(completed: 3);
    c.markWorkoutToday(
      stats: computeSessionStats(logs),
      exercises: logs,
      durationSeconds: 3600,
    );
    expect(c.todayWorkoutStats, isNotNull);

    // Simulate the phone crossing midnight while the app stayed open.
    c.forceStatsDayForTest('${dayKey(DateTime.now())}-stale');
    expect(c.todayWorkoutStats, isNull);
    expect(c.todayExercises, isNull);
    expect(c.todayNextUp, isNull);
    expect(c.todayDurationSeconds, isNull);
  });
}
