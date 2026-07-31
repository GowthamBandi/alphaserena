import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/workout_session.dart';

/// HOME/WORKOUT REFINEMENT — "where do I continue?", as a pure rule.
///
/// A member who left mid-session should be told the ONE thing that gets them
/// moving again: which exercise, which set, what the coach asked for. These
/// tests pin the honesty rules around that answer:
///
///  • a skipped SET is resolved — it is never offered as "next";
///  • a skipped EXERCISE is skipped whole — none of its sets are next;
///  • an exhausted session has no next (the summary is the answer, not a set);
///  • prescription text is passed through VERBATIM ('8-12', 'bodyweight'),
///    never parsed into a number the coach did not write.
void main() {
  SetLog s({
    String reps = '12',
    String weight = '60',
    SetLogState state = SetLogState.pending,
  }) => SetLog(pReps: reps, pWeight: weight, pRest: '90', state: state);

  ExerciseLog ex(
    String name,
    List<SetLog> sets, {
    bool skipped = false,
  }) => ExerciseLog(
    name: name,
    exerciseId: name.toLowerCase(),
    sets: sets,
    skipped: skipped,
  );

  group('nextUpFrom — the resume answer', () {
    test('a fresh session points at the first set of the first exercise', () {
      final n = nextUpFrom([
        ex('Bench Press', [s(), s(), s()]),
        ex('Row', [s()]),
      ]);
      expect(n, isNotNull);
      expect(n!.exerciseName, 'Bench Press');
      expect(n.setNumber, 1);
      expect(n.totalSets, 3);
      expect(n.exerciseIndex, 0);
    });

    test('a part-done exercise points at its first PENDING set', () {
      final n = nextUpFrom([
        ex('Bench Press', [
          s(state: SetLogState.completed),
          s(),
          s(),
          s(),
        ]),
      ]);
      expect(n!.setNumber, 2);
      expect(n.totalSets, 4);
    });

    test('a skipped set is resolved — the next PENDING set is offered', () {
      final n = nextUpFrom([
        ex('Bench Press', [
          s(state: SetLogState.completed),
          s(state: SetLogState.skipped),
          s(),
        ]),
      ]);
      expect(n!.setNumber, 3);
    });

    test('a skipped exercise is stepped over entirely', () {
      final n = nextUpFrom([
        ex('Bench Press', [s(), s()], skipped: true),
        ex('Row', [s()]),
      ]);
      expect(n!.exerciseName, 'Row');
      expect(n.exerciseIndex, 1);
      expect(n.setNumber, 1);
    });

    test('an exercise with every set resolved yields to the next exercise', () {
      final n = nextUpFrom([
        ex('Bench Press', [
          s(state: SetLogState.completed),
          s(state: SetLogState.skipped),
        ]),
        ex('Row', [s(), s()]),
      ]);
      expect(n!.exerciseName, 'Row');
      expect(n.setNumber, 1);
      expect(n.totalSets, 2);
    });

    test('a fully resolved session has no next — null, never set 1', () {
      final n = nextUpFrom([
        ex('Bench Press', [s(state: SetLogState.completed)]),
        ex('Row', [s(state: SetLogState.skipped)]),
      ]);
      expect(n, isNull);
    });

    test('an empty session has no next', () {
      expect(nextUpFrom(const []), isNull);
      expect(nextUpFrom([ex('Bench Press', const [])]), isNull);
    });

    test('prescription text passes through verbatim, never parsed', () {
      final n = nextUpFrom([
        ex('Pull Up', [s(reps: '8-12', weight: 'bodyweight')]),
      ]);
      expect(n!.prescribedReps, '8-12');
      expect(n.prescribedWeight, 'bodyweight');
    });
  });

  group('NextUp.targetLine — the one-line prescription', () {
    test('reps and weight combine with a multiplication sign', () {
      final n = nextUpFrom([
        ex('Bench Press', [s(reps: '12', weight: '60')]),
      ]);
      expect(n!.targetLine, '12 reps × 60 kg');
    });

    test('a weight that already carries its unit is not double-suffixed', () {
      final n = nextUpFrom([
        ex('Bench Press', [s(reps: '12', weight: '60 kg')]),
      ]);
      expect(n!.targetLine, '12 reps × 60 kg');
    });

    test('a non-numeric weight is quoted as the coach wrote it', () {
      final n = nextUpFrom([
        ex('Pull Up', [s(reps: '10', weight: 'bodyweight')]),
      ]);
      expect(n!.targetLine, '10 reps × bodyweight');
    });

    test('reps alone renders alone — no orphan separator', () {
      final n = nextUpFrom([
        ex('Plank', [s(reps: '60s', weight: '')]),
      ]);
      expect(n!.targetLine, '60s reps');
    });

    test('no prescription at all renders empty, never a fabricated target', () {
      final n = nextUpFrom([
        ex('Mobility', [s(reps: '', weight: '')]),
      ]);
      expect(n!.targetLine, '');
    });

    test('lbs is respected as written', () {
      final n = nextUpFrom([
        ex('Bench Press', [s(reps: '5', weight: '135 lbs')]),
      ]);
      expect(n!.targetLine, '5 reps × 135 lbs');
    });
  });
}
