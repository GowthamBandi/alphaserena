import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/workout_session.dart';

/// WORKOUT EXPERIENCE Phase 1 — session integrity, the pure rules.
///
/// The invariants under test: a session exists only from meaningful activity,
/// identity is deterministic, skipped ≠ incomplete, drafts round-trip
/// perfectly (resume loses nothing), and durations can never be negative.
void main() {
  SetLog set({
    String pReps = '10',
    String pWeight = '40',
    String actualReps = '',
    SetLogState state = SetLogState.pending,
  }) => SetLog(
    pReps: pReps,
    pWeight: pWeight,
    pRest: '90',
    actualReps: actualReps,
    state: state,
  );

  ExerciseLog ex(List<SetLog> sets, {bool skipped = false, String reason = ''}) =>
      ExerciseLog(
        name: 'Bench',
        exerciseId: 'e1',
        sets: sets,
        skipped: skipped,
        skipReason: reason,
      );

  group('deterministic identity — duplicates cannot exist', () {
    test('same member, same day → same id, every time', () {
      final d = DateTime(2026, 7, 28, 6);
      final e = DateTime(2026, 7, 28, 22);
      expect(workoutSessionIdFor('c1', d), 'ws_c1_2026-07-28');
      expect(workoutSessionIdFor('c1', d), workoutSessionIdFor('c1', e));
    });

    test('a second session is a DELIBERATE suffix, never an accident', () {
      expect(workoutSessionIdFor('c1', DateTime(2026, 7, 28), run: 2),
          'ws_c1_2026-07-28_2');
    });

    test('different members and days never collide', () {
      expect(workoutSessionIdFor('c1', DateTime(2026, 7, 28)),
          isNot(workoutSessionIdFor('c2', DateTime(2026, 7, 28))));
      expect(workoutSessionIdFor('c1', DateTime(2026, 7, 28)),
          isNot(workoutSessionIdFor('c1', DateTime(2026, 7, 29))));
    });
  });

  group('the creation gate — ghost sessions cannot exist', () {
    test('opening/browsing is not activity', () {
      expect(hasMeaningfulActivity([ex([set(), set()])]), isFalse);
    });

    test('typing without completing is not activity', () {
      expect(
        hasMeaningfulActivity([ex([set(actualReps: '10')])]),
        isFalse,
      );
    });

    test('one completed set IS activity; so is one skip', () {
      expect(
        hasMeaningfulActivity([ex([set(state: SetLogState.completed)])]),
        isTrue,
      );
      expect(
        hasMeaningfulActivity([ex([set(state: SetLogState.skipped)])]),
        isTrue,
      );
      expect(
        hasMeaningfulActivity([ex([set()], skipped: true)]),
        isTrue,
      );
    });

    test('completed WORK is stricter: skips alone never mark a training day',
        () {
      expect(
        hasCompletedWork([ex([set(state: SetLogState.skipped)])]),
        isFalse,
      );
      expect(
        hasCompletedWork([ex([set(state: SetLogState.completed)])]),
        isTrue,
      );
    });
  });

  group('wire entries — skipped ≠ incomplete, additive over legacy', () {
    test('a skipped set carries the flag; a pending one does not', () {
      final entries = buildSessionEntries([
        ex([
          set(state: SetLogState.completed, actualReps: '10'),
          set(state: SetLogState.skipped),
          set(),
        ]),
      ]);
      final sets = (entries.single['sets'] as List).cast<Map>();
      expect(sets[0]['completed'], isTrue);
      expect(sets[0].containsKey('skipped'), isFalse);
      expect(sets[1]['completed'], isFalse);
      expect(sets[1]['skipped'], isTrue);
      expect(sets[2]['completed'], isFalse);
      expect(sets[2].containsKey('skipped'), isFalse);
    });

    test('a skipped exercise carries its reason to the coach', () {
      final entries = buildSessionEntries([
        ex([set(state: SetLogState.skipped)],
            skipped: true, reason: 'No equipment'),
      ]);
      expect(entries.single['skipped'], isTrue);
      expect(entries.single['skipReason'], 'No equipment');
    });

    test('the legacy fields are byte-compatible for old coach builds', () {
      final entries = buildSessionEntries([
        ex([set(state: SetLogState.completed, actualReps: '8')]),
      ]);
      final s = (entries.single['sets'] as List).cast<Map>().single;
      expect(s['setNumber'], 1);
      expect(s['prescribedReps'], '10');
      expect(s['prescribedWeight'], '40');
      expect(s['actualReps'], '8');
      expect(s['completed'], isTrue);
    });
  });

  group('draft round-trip — resume loses NOTHING', () {
    test('full fidelity through JSON', () {
      final draft = WorkoutDraft(
        sessionId: 'ws_c1_2026-07-28',
        dayKey: '2026-07-28',
        planName: 'Push Day',
        startedAtMillis: 1000,
        currentExercise: 1,
        exercises: [
          ex([
            set(state: SetLogState.completed, actualReps: '10'),
            set(actualReps: '5'), // typed, not completed — must survive
          ]),
          ex([set(state: SetLogState.skipped)],
              skipped: true, reason: 'Pain / discomfort'),
        ],
      );
      final back = WorkoutDraft.fromJson(draft.toJson())!;
      expect(back.sessionId, draft.sessionId);
      expect(back.startedAtMillis, 1000);
      expect(back.currentExercise, 1);
      expect(back.exercises[0].sets[0].state, SetLogState.completed);
      expect(back.exercises[0].sets[1].actualReps, '5');
      expect(back.exercises[1].skipped, isTrue);
      expect(back.exercises[1].skipReason, 'Pain / discomfort');
    });

    test('corrupt drafts read as null — never a corrupted session', () {
      expect(WorkoutDraft.fromJson('junk'), isNull);
      expect(WorkoutDraft.fromJson({'dayKey': ''}), isNull);
      expect(WorkoutDraft.fromJson(null), isNull);
    });
  });

  group('remote-doc resume — crash without a draft still recovers', () {
    test('entries round-trip back into resumable logs', () {
      final logs = [
        ex([
          set(state: SetLogState.completed, actualReps: '10'),
          set(state: SetLogState.skipped),
        ], skipped: false),
      ];
      final back = exercisesFromEntries(buildSessionEntries(logs));
      expect(back.single.sets[0].state, SetLogState.completed);
      expect(back.single.sets[0].actualReps, '10');
      expect(back.single.sets[0].pReps, '10'); // prescription restored too
      expect(back.single.sets[1].state, SetLogState.skipped);
    });

    test('junk entries read as empty, never invented', () {
      expect(exercisesFromEntries(null), isEmpty);
      expect(exercisesFromEntries('junk'), isEmpty);
    });
  });

  _phase2();

  group('duration — never negative, never invented', () {
    test('computed only when both ends exist', () {
      expect(sessionDurationSeconds(null, 5000), isNull);
      expect(sessionDurationSeconds(1000, null), isNull);
      expect(sessionDurationSeconds(1000, 61000), 60);
    });

    test('clock skew clamps to zero — no negative workouts', () {
      expect(sessionDurationSeconds(61000, 1000), 0);
    });
  });
}

// ── Phase 2 (guided experience): stats, estimates, served-item parsing ─────

void _phase2() {
  SetLog s({
    String pReps = '10',
    String pWeight = '40',
    String pRest = '90',
    String aReps = '',
    String aWeight = '',
    SetLogState state = SetLogState.pending,
    bool edited = false,
  }) => SetLog(
    pReps: pReps,
    pWeight: pWeight,
    pRest: pRest,
    actualReps: aReps,
    actualWeight: aWeight,
    state: state,
    edited: edited,
  );

  ExerciseLog ex(List<SetLog> sets, {bool skipped = false}) => ExerciseLog(
    name: 'Bench',
    exerciseId: 'e1',
    sets: sets,
    skipped: skipped,
  );

  group('truthful completion — the ENGINE decides, never the UI', () {
    // Regression guard for "one completed set → Logged today ✓": Home used to
    // flip to done at the first saved set; the fraction is now the authority.

    test('progress is completed ÷ prescribed, floored — never rounded up', () {
      final stats = computeSessionStats([
        ex([
          s(state: SetLogState.completed),
          s(state: SetLogState.completed),
          s(),
          s(),
          s(),
          s(),
        ]),
      ]);
      expect(stats.progressFraction, closeTo(2 / 6, 1e-9));
      expect(stats.progressPercent, 33);
      expect(stats.isComplete, isFalse);
      expect(stats.isFullyResolved, isFalse);
    });

    test('one set of eighteen is 5%, not "done"', () {
      final sets = [
        s(state: SetLogState.completed),
        for (var i = 0; i < 17; i++) s(),
      ];
      final stats = computeSessionStats([ex(sets)]);
      expect(stats.progressPercent, 5);
      expect(stats.isComplete, isFalse);
    });

    test('SKIPS count against completion — a skipped set is not done work', () {
      final stats = computeSessionStats([
        ex([
          s(state: SetLogState.completed),
          s(state: SetLogState.completed),
          s(state: SetLogState.skipped),
          s(state: SetLogState.skipped),
        ]),
      ]);
      expect(stats.progressPercent, 50);
      expect(stats.isComplete, isFalse, reason: 'skips are honest, not done');
      expect(stats.isFullyResolved, isTrue, reason: 'nothing left pending');
    });

    test('100% and Complete only when EVERY prescribed set was done', () {
      final stats = computeSessionStats([
        ex([
          s(state: SetLogState.completed),
          s(state: SetLogState.completed),
        ]),
        ex([s(state: SetLogState.completed)]),
      ]);
      expect(stats.progressPercent, 100);
      expect(stats.isComplete, isTrue);
      expect(stats.isFullyResolved, isTrue);
    });

    test('17 of 18 floors to 94 — 100 is reserved for finishing', () {
      final sets = [
        for (var i = 0; i < 17; i++) s(state: SetLogState.completed),
        s(),
      ];
      final stats = computeSessionStats([ex(sets)]);
      expect(stats.progressPercent, 94);
    });

    test('an empty session claims nothing', () {
      final stats = computeSessionStats([]);
      expect(stats.progressFraction, 0);
      expect(stats.isComplete, isFalse);
      expect(stats.isFullyResolved, isFalse);
    });
  });

  group('session stats — the summary the coach also computes', () {
    test('volume counts only completed sets with BOTH numbers', () {
      final stats = computeSessionStats([
        ex([
          s(aReps: '10', aWeight: '40', state: SetLogState.completed), // 400
          s(aReps: '8', aWeight: '50', state: SetLogState.completed), //  400
          s(aReps: '10', aWeight: '40'), // not completed → excluded
          s(aReps: '12', aWeight: '', state: SetLogState.completed), // no load
        ]),
      ]);
      expect(stats.volumeKg, 800);
      expect(stats.completedSets, 3);
      expect(stats.totalSets, 4);
    });

    test('bodyweight work reports NO volume rather than zero effort', () {
      final stats = computeSessionStats([
        ex([
          s(pWeight: '', aReps: '20', aWeight: '',
              state: SetLogState.completed),
        ]),
      ]);
      expect(stats.hasVolume, isFalse);
      expect(stats.completedSets, 1);
    });

    test('adherence matches the coach app rule exactly', () {
      // Lower-bound targets: "8-12" → 8. A set with no numeric target hits.
      expect(
        setHitTarget(s(pReps: '8-12', pWeight: '40', aReps: '9',
            aWeight: '40', state: SetLogState.completed)),
        isTrue,
      );
      expect(
        setHitTarget(s(pReps: '10', pWeight: '40', aReps: '7',
            aWeight: '40', state: SetLogState.completed)),
        isFalse,
      );
      expect(
        setHitTarget(s(pReps: '', pWeight: 'bodyweight', aReps: '',
            aWeight: '', state: SetLogState.completed)),
        isTrue,
      );
    });

    test('targetHitPct is null when nothing was completed — never 0%', () {
      final stats = computeSessionStats([ex([s(), s()])]);
      expect(stats.targetHitPct, isNull);
      expect(stats.completedSets, 0);
    });

    test('skips are counted at both set and exercise level', () {
      final stats = computeSessionStats([
        ex([s(state: SetLogState.skipped), s(state: SetLogState.skipped)],
            skipped: true),
        ex([s(state: SetLogState.completed, aReps: '10', aWeight: '40')]),
      ]);
      expect(stats.skippedSets, 2);
      expect(stats.skippedExercises, 1);
      expect(stats.completedSets, 1);
    });
  });

  group('briefing estimate — labelled a guess, never a promise', () {
    test('scales with sets and rest, rounded to 5 minutes', () {
      // 4 sets × (45s work + 90s rest) = 540s = 9 min → 10
      final mins = estimatedMinutes([ex([s(), s(), s(), s()])]);
      expect(mins, 10);
    });

    test('an empty plan has NO estimate rather than a fake zero', () {
      expect(estimatedMinutes(const []), isNull);
      expect(estimatedMinutes([ex(const [])]), isNull);
    });

    test('a skipped exercise leaves the estimate', () {
      final all = estimatedMinutes([ex([s(), s()]), ex([s(), s()])]);
      final one = estimatedMinutes([
        ex([s(), s()]),
        ex([s(), s()], skipped: true),
      ]);
      expect(one, lessThan(all!));
    });
  });

  group('served-item parsing — one shared implementation', () {
    test('setRows drive the sets', () {
      final logs = exercisesFromServedItems([
        {
          'name': 'Squat',
          'exerciseId': 'e9',
          'setRows': [
            {'reps': '5', 'weight': '60', 'rest': '120'},
            {'reps': '5', 'weight': '65', 'rest': '120'},
          ],
        },
      ]);
      expect(logs.single.sets, hasLength(2));
      expect(logs.single.sets[1].pWeight, '65');
      expect(logs.single.exerciseId, 'e9');
    });

    test('a legacy flat item synthesizes its sets', () {
      final logs = exercisesFromServedItems([
        {'name': 'Curl', 'sets': 3, 'reps': '12', 'weight': '10'},
      ]);
      expect(logs.single.sets, hasLength(3));
      expect(logs.single.sets.every((x) => x.pReps == '12'), isTrue);
    });

    test('nothing prescribed yields no sets — never a fabricated one', () {
      final logs = exercisesFromServedItems([
        {'name': 'Mystery'},
      ]);
      expect(logs.single.sets, isEmpty);
    });
  });

  group('edited sets survive the wire and the draft', () {
    test('the edited flag round-trips both ways', () {
      final logs = [
        ex([s(aReps: '9', aWeight: '40', state: SetLogState.completed,
            edited: true)]),
      ];
      final wire = buildSessionEntries(logs);
      expect((wire.single['sets'] as List).cast<Map>().single['edited'], isTrue);
      expect(exercisesFromEntries(wire).single.sets.single.edited, isTrue);

      final draft = WorkoutDraft(
        sessionId: 'ws_c1_2026-07-28',
        dayKey: '2026-07-28',
        planName: 'Push',
        exercises: logs,
      );
      expect(
        WorkoutDraft.fromJson(draft.toJson())!.exercises.single.sets.single
            .edited,
        isTrue,
      );
    });

    test('an unedited set carries no flag at all', () {
      final wire = buildSessionEntries([
        ex([s(state: SetLogState.completed)]),
      ]);
      expect(
        (wire.single['sets'] as List).cast<Map>().single.containsKey('edited'),
        isFalse,
      );
    });
  });
}
