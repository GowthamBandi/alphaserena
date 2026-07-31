import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/home_workout_card.dart';
import 'package:alphaserena/core/domain/today_expectation.dart';
import 'package:alphaserena/core/domain/workout_session.dart';

/// TODAY'S WORKOUT — the execution card's contract.
///
/// The three states a member is actually in — hasn't started, part-way,
/// finished — plus every day the coach did not ask for training. The pinned
/// promises: progress comes from SessionStats and nowhere else, one finished
/// exercise never flips the card to complete, "Logged today" does not exist,
/// and a finished session is never offered a Start button.
void main() {
  SessionStats stats({
    required int completed,
    required int total,
    int skipped = 0,
    int completedExercises = 0,
    double? hit,
  }) => SessionStats(
    completedSets: completed,
    skippedSets: skipped,
    totalSets: total,
    skippedExercises: 0,
    completedExercises: completedExercises,
    volumeKg: 0,
    targetHitPct: hit,
  );

  const training = TodayWorkoutPresentation(
    mode: TodayWorkoutMode.training,
    showContent: true,
    cta: 'Start Full Workout',
  );

  HomeWorkoutCard build({
    bool loading = false,
    bool loadFailed = false,
    bool hasCachedPlan = true,
    TodayWorkoutPresentation presentation = training,
    String planName = 'Upper Body',
    String coachNote = '',
    List<WorkoutFact> facts = const [
      WorkoutFact('exercises', '6 exercises'),
      WorkoutFact('duration', '≈45 min'),
    ],
    SessionStats? todayStats,
    NextUp? nextUp,
    int? durationSeconds,
  }) => buildHomeWorkoutCard(
    loading: loading,
    loadFailed: loadFailed,
    hasCachedPlan: hasCachedPlan,
    presentation: presentation,
    planName: planName,
    coachLabel: 'Ravi',
    coachNote: coachNote,
    facts: facts,
    todayStats: todayStats,
    nextUp: nextUp,
    durationSeconds: durationSeconds,
  );

  group('NOT STARTED', () {
    test('names the plan, credits the coach, and offers ONE button', () {
      final c = build();
      expect(c.mode, WorkoutCardMode.ready);
      expect(c.title, 'Upper Body');
      expect(c.subtitle, 'Prepared by Ravi');
      expect(c.cta, 'Start Workout');
      expect(c.secondaryCta, isEmpty);
    });

    test('carries the coach note verbatim, and never invents one', () {
      expect(build(coachNote: 'Slow negatives — 3s down.').coachNote,
          'Slow negatives — 3s down.');
      expect(build().coachNote, isEmpty);
    });

    test('an untouched session draws NO progress bar', () {
      // A 0% bar reads as failure before the member has done anything.
      final c = build(todayStats: stats(completed: 0, total: 12));
      expect(c.mode, WorkoutCardMode.ready);
      expect(c.hasProgress, isFalse);
      expect(c.progressPercent, isNull);
      expect(c.results, isEmpty);
    });

    test('a flexible week starts a session, not "the" workout', () {
      const flexible = TodayWorkoutPresentation(
        mode: TodayWorkoutMode.flexible,
        title: 'Flexible week',
        body: '2 of 4 sessions done this week — you pick the days.',
        showContent: true,
        cta: 'Start a Session',
      );
      final c = build(presentation: flexible);
      expect(c.mode, WorkoutCardMode.flexible);
      expect(c.cta, 'Start a Session');
      expect(c.subtitle, contains('you pick the days'));
    });
  });

  group('PARTIALLY COMPLETED — progress is truthful', () {
    test('2 of 9 sets is 22%, never rounded up', () {
      final c = build(todayStats: stats(completed: 2, total: 9));
      expect(c.mode, WorkoutCardMode.inProgress);
      expect(c.progressPercent, 22);
      expect(c.cta, 'Resume Workout');
    });

    test('6 of 12 sets is 50%', () {
      expect(build(todayStats: stats(completed: 6, total: 12)).progressPercent,
          50);
    });

    test('one finished exercise of three does NOT flip the card', () {
      // 3 of 9 sets = one whole exercise done. The card must read 33% and
      // stay in progress — flipping to "completed" here was the exact bug
      // this state exists to prevent.
      final c = build(
        todayStats: stats(completed: 3, total: 9, completedExercises: 1),
      );
      expect(c.mode, WorkoutCardMode.inProgress);
      expect(c.progressPercent, 33);
    });

    test('17 of 18 sets is 94, never a rounded 100', () {
      expect(build(todayStats: stats(completed: 17, total: 18)).progressPercent,
          94);
    });

    test('names the next exercise AND the next set', () {
      final c = build(
        todayStats: stats(completed: 5, total: 12),
        nextUp: const NextUp(
          exerciseName: 'Bench Press',
          exerciseIndex: 1,
          setNumber: 2,
          totalSets: 4,
          prescribedReps: '12',
          prescribedWeight: '60',
        ),
      );
      expect(c.nextUp!.exerciseName, 'Bench Press');
      expect(c.nextUp!.setNumber, 2);
      expect(c.nextUp!.totalSets, 4);
      expect(c.nextUp!.targetLine, '12 reps × 60 kg');
      expect(c.semanticLabel, contains('Next exercise Bench Press, set 2 of 4'));
    });

    test('resuming without a known next set still resumes', () {
      final c = build(todayStats: stats(completed: 5, total: 12));
      expect(c.mode, WorkoutCardMode.inProgress);
      expect(c.nextUp, isNull);
      expect(c.cta, 'Resume Workout');
    });

    test('an in-progress card shows no results block', () {
      expect(build(todayStats: stats(completed: 5, total: 12)).results,
          isEmpty);
    });
  });

  group('COMPLETED', () {
    test('replaces Start with Review, and offers Edit Log', () {
      final c = build(
        todayStats: stats(
            completed: 12, total: 12, completedExercises: 4, hit: 0.92),
        durationSeconds: 2730,
      );
      expect(c.mode, WorkoutCardMode.completed);
      expect(c.progressPercent, 100);
      expect(c.subtitle, 'Completed');
      expect(c.cta, 'Review Workout');
      expect(c.secondaryCta, 'Edit Workout Log');
      expect(c.cta, isNot('Start Workout'));
    });

    test('states duration, exercises, sets and adherence', () {
      final c = build(
        todayStats: stats(
            completed: 12, total: 12, completedExercises: 4, hit: 0.92),
        durationSeconds: 2730,
      );
      final byLabel = {for (final r in c.results) r.label: r.value};
      expect(byLabel['Duration'], '45m');
      expect(byLabel['Exercises'], '4');
      expect(byLabel['Sets'], '12/12');
      expect(byLabel['Adherence'], '92%');
    });

    test('a session with no recorded clock states NO duration', () {
      final c = build(
        todayStats: stats(completed: 12, total: 12, completedExercises: 4),
      );
      expect(c.results.map((r) => r.label), isNot(contains('Duration')));
    });

    test('adherence is absent when nothing was completed to judge', () {
      final c = build(todayStats: stats(completed: 0, total: 9, skipped: 9));
      expect(c.results.map((r) => r.label), isNot(contains('Adherence')));
    });

    test('a long session reads in hours and minutes', () {
      final c = build(
        todayStats: stats(completed: 12, total: 12),
        durationSeconds: 4500,
      );
      expect(c.results.first.value, '1h 15m');
    });

    test('the card never says "Logged today", in any state', () {
      for (final s in [
        stats(completed: 1, total: 9),
        stats(completed: 9, total: 9, completedExercises: 3, hit: 1),
        stats(completed: 0, total: 9, skipped: 9),
      ]) {
        final c = build(todayStats: s);
        final all =
            '${c.title} ${c.subtitle} ${c.cta} ${c.semanticLabel}'.toLowerCase();
        expect(all, isNot(contains('logged today')));
      }
    });
  });

  group('CLOSED BY SKIPPING — over, but not complete', () {
    test('does not claim completion and does not ask to start again', () {
      final c = build(
        todayStats: stats(
            completed: 4, total: 12, skipped: 8, completedExercises: 1, hit: 1),
      );
      expect(c.mode, WorkoutCardMode.closed);
      expect(c.subtitle, '8 sets skipped');
      expect(c.progressPercent, 33);
      expect(c.cta, 'Review Workout');
    });

    test('one skipped set is singular', () {
      final c = build(todayStats: stats(completed: 11, total: 12, skipped: 1));
      expect(c.subtitle, '1 set skipped');
    });
  });

  group('days the coach did not ask for training', () {
    test('a rest day is a positive state with an optional offer', () {
      const rest = TodayWorkoutPresentation(
        mode: TodayWorkoutMode.rest,
        title: 'Rest day',
        body: 'Recovery is part of the program.',
        trainAnyway: true,
      );
      final c = build(presentation: rest);
      expect(c.mode, WorkoutCardMode.rest);
      expect(c.cta, isEmpty); // never a demand
      expect(c.secondaryCta, 'Train anyway');
      expect(c.showsContent, isFalse);
    });

    test('an excused day offers, never expects', () {
      const excused = TodayWorkoutPresentation(
        mode: TodayWorkoutMode.excused,
        title: 'Today is excused',
        body: 'Ravi excused today.',
        trainAnyway: true,
      );
      final c = build(presentation: excused);
      expect(c.mode, WorkoutCardMode.excused);
      expect(c.cta, isEmpty);
    });

    test('a paused day asks for nothing at all', () {
      const paused = TodayWorkoutPresentation(
        mode: TodayWorkoutMode.paused,
        title: 'Coaching paused',
        body: 'Your streak is safe.',
      );
      final c = build(presentation: paused);
      expect(c.cta, isEmpty);
      expect(c.secondaryCta, isEmpty);
    });

    test('a plan not started or finished reads dormant', () {
      const ended = TodayWorkoutPresentation(
        mode: TodayWorkoutMode.ended,
        title: 'Plan finished',
        body: 'Ask Ravi for your next one.',
      );
      expect(build(presentation: ended).mode, WorkoutCardMode.dormant);
    });
  });

  group('honest failure states', () {
    test('loading is loading, not an empty plan', () {
      expect(build(loading: true).mode, WorkoutCardMode.loading);
    });

    test('a network failure never reads as "your coach assigned nothing"', () {
      final c = build(loadFailed: true, hasCachedPlan: false);
      expect(c.mode, WorkoutCardMode.unavailable);
      expect(c.subtitle, contains('Your plan is safe'));
      expect(c.cta, 'Retry');
    });

    test('a failure WITH a cached plan still shows the plan', () {
      expect(build(loadFailed: true).mode, WorkoutCardMode.ready);
    });

    test('no plan assigned credits the coach with preparing one', () {
      const waiting = TodayWorkoutPresentation(mode: TodayWorkoutMode.waiting);
      final c = build(presentation: waiting);
      expect(c.subtitle, contains('Ravi is preparing'));
      expect(c.cta, isEmpty);
    });

    test('the unknown-schedule disclosure survives onto the card', () {
      const unknown = TodayWorkoutPresentation(
        mode: TodayWorkoutMode.unknownDisclosed,
        showContent: true,
        cta: 'Start Full Workout',
        disclosure: 'No schedule set — showing your plan daily.',
      );
      expect(build(presentation: unknown).disclosure,
          'No schedule set — showing your plan daily.');
    });
  });

  group('fact chips come from real data only', () {
    test('every available fact renders, duration wearing its ≈', () {
      final f = workoutFacts(
        exerciseCount: 6,
        estimatedMinutes: 45,
        difficulty: ['Intermediate'],
        equipment: ['Barbell', 'Bench'],
      );
      expect(f.map((e) => e.label).toList(),
          ['6 exercises', '≈45 min', 'Intermediate', 'Barbell · Bench']);
    });

    test('absent data produces NO chip', () {
      expect(
        workoutFacts(
          exerciseCount: 0,
          estimatedMinutes: null,
          difficulty: const [],
          equipment: const [],
        ),
        isEmpty,
      );
    });

    test('a long equipment list is summarised, not silently truncated', () {
      final f = workoutFacts(
        exerciseCount: 1,
        estimatedMinutes: null,
        difficulty: const [],
        equipment: ['Barbell', 'Bench', 'Dumbbell', 'Cable'],
      );
      expect(f.last.label, 'Barbell · Bench +2');
    });

    test('one exercise is singular', () {
      final f = workoutFacts(
        exerciseCount: 1,
        estimatedMinutes: null,
        difficulty: const [],
        equipment: const [],
      );
      expect(f.single.label, '1 exercise');
    });
  });
}
