import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/core/domain/workout_session.dart';

/// CROSS-APP PARITY — an EDITED workout log, as the coach reads it.
///
/// ── WHY THIS FILE EXISTS ──────────────────────────────────────────────────
///
/// Diet and Lifestyle both have twinned contract tests (`diet_trainerhq_parity_
/// test.dart`, `lifestyle_cross_app_contract_test.dart`). Workout sessions had
/// none — and workouts are the one collection the member app only recently
/// gained the ability to REWRITE. `saveEditedEntries` writes `entries` with
/// `SetOptions(merge: true)`, and a merge write replaces an ARRAY WHOLESALE.
/// So the first time a member corrects a rep count, every field this app fails
/// to write back is deleted from the coach's copy — silently, permanently, and
/// only for members who edit.
///
/// That is a failure mode no test on either side would have caught: the member
/// app's tests assert what the member sees, and the coach app's tests parse
/// coach-authored fixtures. Nothing exercised "what the member's editor
/// produces, read by the coach's parser".
///
/// ── WHAT IS TWINNED, AND WHY IT IS COPIED ─────────────────────────────────
///
/// The `_Coach*` classes below are a VERBATIM transcription of TrainerHQ's
/// `lib/core/models/client_workout_session_model.dart` — `SessionSet.fromMap`,
/// `SessionEntry.fromMap`, `_lowerBound`, `_num`, `hit` and
/// `SessionAdherence.from`. They are duplicated deliberately, exactly as the
/// diet parity fixture is: the two apps are separate binaries with no shared
/// package, and a fixture that could drift on one side without failing on the
/// other would defeat the purpose.
///
/// ⚠️ If TrainerHQ's model changes, THIS FILE MUST CHANGE WITH IT. That is the
/// point — the test fails loudly rather than the contract breaking quietly.
///
/// ── WHAT IS VERIFIED FROM SOURCE, NOT ASSERTED HERE ───────────────────────
///
/// TrainerHQ is READ-ONLY on `client_workout_sessions` (`ClientLogsService
/// .watchWorkoutSessions` is a `snapshots()` listener and the only reference;
/// there is no `.set`/`.update`/`.add` anywhere in the coach app), and
/// `firestore.rules` allows update only to `resource.data.authorId ==
/// request.auth.uid` with `delete: if false`. So no coach-authored field can
/// exist inside `entries` for an edit to destroy, and the coach's view is a
/// LIVE listener — an edit propagates without a refresh.

// ═══════════════════════════════════════════════════════════════════════════
// THE COACH'S PARSER — transcribed from TrainerHQ, unchanged
// ═══════════════════════════════════════════════════════════════════════════

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double? _lowerBound(String s) {
  final match = RegExp(r'-?\d+(\.\d+)?').firstMatch(s);
  return match == null ? null : double.tryParse(match.group(0)!);
}

double? _num(String s) {
  final match = RegExp(r'-?\d+(\.\d+)?').firstMatch(s);
  return match == null ? null : double.tryParse(match.group(0)!);
}

class _CoachSet {
  final int setNumber;
  final String prescribedReps;
  final String prescribedWeight;
  final String prescribedRest;
  final String actualReps;
  final String actualWeight;
  final bool completed;
  final bool skipped;
  final bool edited;

  const _CoachSet({
    this.setNumber = 0,
    this.prescribedReps = '',
    this.prescribedWeight = '',
    this.prescribedRest = '',
    this.actualReps = '',
    this.actualWeight = '',
    this.completed = false,
    this.skipped = false,
    this.edited = false,
  });

  factory _CoachSet.fromMap(Map<String, dynamic> m) => _CoachSet(
        setNumber: _toInt(m['setNumber']),
        prescribedReps: (m['prescribedReps'] ?? '').toString(),
        prescribedWeight: (m['prescribedWeight'] ?? '').toString(),
        prescribedRest: (m['prescribedRest'] ?? '').toString(),
        actualReps: (m['actualReps'] ?? '').toString(),
        actualWeight: (m['actualWeight'] ?? '').toString(),
        completed: m['completed'] == true,
        skipped: m['skipped'] == true,
        edited: m['edited'] == true,
      );

  bool get hit {
    final repsTarget = _lowerBound(prescribedReps);
    final weightTarget = _lowerBound(prescribedWeight);
    final aReps = _num(actualReps);
    final aWeight = _num(actualWeight);
    final repsOk = repsTarget == null || (aReps != null && aReps >= repsTarget);
    final weightOk =
        weightTarget == null || (aWeight != null && aWeight >= weightTarget);
    return repsOk && weightOk;
  }
}

class _CoachEntry {
  final String exerciseName;
  final String exerciseId;
  final List<_CoachSet> sets;
  final String? note;
  final bool skipped;
  final String skipReason;

  const _CoachEntry({
    this.exerciseName = '',
    this.exerciseId = '',
    this.sets = const [],
    this.note,
    this.skipped = false,
    this.skipReason = '',
  });

  factory _CoachEntry.fromMap(Map<String, dynamic> m) {
    final raw = m['sets'];
    final sets = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => _CoachSet.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : <_CoachSet>[];
    final note = (m['note'] ?? '').toString().trim();
    return _CoachEntry(
      exerciseName: (m['exerciseName'] ?? '').toString(),
      exerciseId: (m['exerciseId'] ?? '').toString(),
      sets: sets,
      note: note.isEmpty ? null : note,
      skipped: m['skipped'] == true,
      skipReason: (m['skipReason'] ?? '').toString(),
    );
  }
}

class _CoachAdherence {
  final int completedSets;
  final int totalSets;
  final double? targetHitPct;

  const _CoachAdherence({
    required this.completedSets,
    required this.totalSets,
    required this.targetHitPct,
  });

  factory _CoachAdherence.from(List<_CoachEntry> entries) {
    final all = entries.expand((e) => e.sets).toList();
    final completed = all.where((s) => s.completed).toList();
    final hits = completed.where((s) => s.hit).length;
    return _CoachAdherence(
      completedSets: completed.length,
      totalSets: all.length,
      targetHitPct: completed.isEmpty ? null : hits / completed.length,
    );
  }
}

/// The coach's read of what the member's editor wrote.
List<_CoachEntry> _coachReads(List<ExerciseLog> exercises) =>
    buildSessionEntries(exercises)
        .map(_CoachEntry.fromMap)
        .toList();

// ═══════════════════════════════════════════════════════════════════════════

SetLog _set({
  String pReps = '10',
  String pWeight = '40',
  String pRest = '90s',
  String actualReps = '',
  String actualWeight = '',
  SetLogState state = SetLogState.pending,
  bool edited = false,
}) =>
    SetLog(
      pReps: pReps,
      pWeight: pWeight,
      pRest: pRest,
      actualReps: actualReps,
      actualWeight: actualWeight,
      state: state,
      edited: edited,
    );

void main() {
  group('every field the member logs survives the trip to the coach', () {
    test('a completed set arrives whole — prescription AND performance', () {
      final entries = _coachReads([
        ExerciseLog(
          name: 'Bench Press',
          exerciseId: 'ex_bench',
          sets: [
            _set(
              actualReps: '10',
              actualWeight: '40',
              state: SetLogState.completed,
            ),
          ],
        ),
      ]);

      expect(entries, hasLength(1));
      final e = entries.single;
      expect(e.exerciseName, 'Bench Press');
      expect(e.exerciseId, 'ex_bench');

      final s = e.sets.single;
      // setNumber is POSITIONAL and 1-based on the way out; the coach's grid
      // orders rows by it, so an off-by-one here renumbers a member's session.
      expect(s.setNumber, 1);
      expect(s.prescribedReps, '10');
      expect(s.prescribedWeight, '40');
      expect(s.prescribedRest, '90s');
      expect(s.actualReps, '10');
      expect(s.actualWeight, '40');
      expect(s.completed, isTrue);
      expect(s.skipped, isFalse);
      expect(s.edited, isFalse);
    });

    test('setNumber counts EVERY set, including skipped ones', () {
      final entries = _coachReads([
        ExerciseLog(
          name: 'Squat',
          exerciseId: 'ex_squat',
          sets: [
            _set(
                actualReps: '8',
                actualWeight: '60',
                state: SetLogState.completed),
            _set(state: SetLogState.skipped),
            _set(
                actualReps: '8',
                actualWeight: '60',
                state: SetLogState.completed),
          ],
        ),
      ]);
      // A skipped set keeps its slot. Renumbering around it would tell the
      // coach the member did sets 1 and 2 of 3 when they did 1 and 3.
      expect(entries.single.sets.map((s) => s.setNumber), [1, 2, 3]);
      expect(entries.single.sets[1].skipped, isTrue);
      expect(entries.single.sets[1].completed, isFalse);
    });

    test("a COACH'S note on an exercise survives a member's edit", () {
      // THE MERGE-WRITE HAZARD, pinned. `entries` is an array; a merge write
      // replaces it wholesale. `note` is parsed in and written back out for
      // exactly this reason — if it were dropped, the first correction a
      // member made would delete their coach's instruction.
      final entries = _coachReads([
        ExerciseLog(
          name: 'Deadlift',
          exerciseId: 'ex_dl',
          sets: [_set(state: SetLogState.completed, actualReps: '5')],
          note: 'Keep the bar over midfoot',
        ),
      ]);
      expect(entries.single.note, 'Keep the bar over midfoot');
    });

    test('an exercise with no note does not invent an empty one', () {
      final entries = _coachReads([
        ExerciseLog(
          name: 'Row',
          exerciseId: 'ex_row',
          sets: [_set(state: SetLogState.completed, actualReps: '10')],
        ),
      ]);
      // null, not '' — the coach's UI shows a note row only when there is one.
      expect(entries.single.note, isNull);
    });

    test('a skipped exercise arrives with its reason', () {
      final entries = _coachReads([
        ExerciseLog(
          name: 'Cable Fly',
          exerciseId: 'ex_fly',
          sets: [_set()],
          skipped: true,
          skipReason: 'Pain / discomfort',
        ),
      ]);
      expect(entries.single.skipped, isTrue);
      expect(entries.single.skipReason, 'Pain / discomfort');
    });
  });

  group('an EDIT is visible as an edit, never disguised as live data', () {
    test('the edited flag reaches the coach', () {
      final entries = _coachReads([
        ExerciseLog(
          name: 'Bench Press',
          exerciseId: 'ex_bench',
          sets: [
            _set(
              actualReps: '8',
              actualWeight: '40',
              state: SetLogState.completed,
              edited: true,
            ),
          ],
        ),
      ]);
      // The coach sees the member's real number AND that it was revised. An
      // honest correction must not look like it was logged live.
      expect(entries.single.sets.single.edited, isTrue);
      expect(entries.single.sets.single.actualReps, '8');
    });

    test('correcting a rep count changes the coach\'s adherence with it', () {
      // BEFORE: 10 of a prescribed 10 → on target.
      final before = _coachReads([
        ExerciseLog(
          name: 'Bench Press',
          exerciseId: 'ex_bench',
          sets: [
            _set(
                actualReps: '10',
                actualWeight: '40',
                state: SetLogState.completed),
          ],
        ),
      ]);
      expect(_CoachAdherence.from(before).targetHitPct, 1.0);

      // AFTER: the member corrects a typo — it was really 6.
      final after = _coachReads([
        ExerciseLog(
          name: 'Bench Press',
          exerciseId: 'ex_bench',
          sets: [
            _set(
              actualReps: '6',
              actualWeight: '40',
              state: SetLogState.completed,
              edited: true,
            ),
          ],
        ),
      ]);
      // The coach's adherence is DERIVED on read, so it moves with the
      // correction. Nothing has to be recomputed or re-written for the coach's
      // dashboard to tell the truth.
      expect(_CoachAdherence.from(after).targetHitPct, 0.0);
    });
  });

  group('both apps compute the SAME adherence from the same document', () {
    test('a mixed session agrees set-for-set and in the aggregate', () {
      final session = [
        ExerciseLog(
          name: 'Bench Press',
          exerciseId: 'ex_bench',
          sets: [
            // On target.
            _set(
                actualReps: '10',
                actualWeight: '40',
                state: SetLogState.completed),
            // Under on reps → a miss for both apps.
            _set(
                actualReps: '7',
                actualWeight: '40',
                state: SetLogState.completed),
            // Skipped: never counted as completed, never judged.
            _set(state: SetLogState.skipped),
          ],
        ),
        ExerciseLog(
          name: 'Plank',
          exerciseId: 'ex_plank',
          sets: [
            // A range prescription: "8-12" lower-bounds to 8, so 9 hits.
            _set(
              pReps: '8-12',
              pWeight: 'bodyweight',
              actualReps: '9',
              actualWeight: '',
              state: SetLogState.completed,
            ),
          ],
        ),
      ];

      final mine = computeSessionStats(session);
      final theirs = _CoachAdherence.from(_coachReads(session));

      // If these two ever disagree, the member and their coach are reading
      // different truths off ONE document.
      expect(theirs.completedSets, mine.completedSets);
      expect(theirs.totalSets, mine.totalSets);
      expect(theirs.targetHitPct, mine.targetHitPct);

      // And the absolute values, so a shared bug cannot make both agree on
      // something wrong.
      expect(mine.completedSets, 3);
      expect(mine.totalSets, 4);
      expect(mine.targetHitPct, closeTo(2 / 3, 1e-9));
    });

    test('nothing completed → NEITHER app reports an adherence figure', () {
      final session = [
        ExerciseLog(
          name: 'Bench Press',
          exerciseId: 'ex_bench',
          sets: [_set(), _set(state: SetLogState.skipped)],
        ),
      ];
      // Null on both sides. A 0% here would read as total failure rather than
      // as "there is nothing to judge yet".
      expect(computeSessionStats(session).targetHitPct, isNull);
      expect(_CoachAdherence.from(_coachReads(session)).targetHitPct, isNull);
    });

    test('a bodyweight set with no numeric target counts as a hit for both',
        () {
      final session = [
        ExerciseLog(
          name: 'Push Up',
          exerciseId: 'ex_pu',
          sets: [
            _set(
              pReps: 'max',
              pWeight: 'bodyweight',
              actualReps: '22',
              actualWeight: '',
              state: SetLogState.completed,
            ),
          ],
        ),
      ];
      expect(computeSessionStats(session).targetHitPct, 1.0);
      expect(_CoachAdherence.from(_coachReads(session)).targetHitPct, 1.0);
    });
  });

  group('the round trip is lossless — parse, edit, write, re-parse', () {
    test('a document survives being read and re-written unchanged', () {
      final original = [
        ExerciseLog(
          name: 'Bench Press',
          exerciseId: 'ex_bench',
          sets: [
            _set(
                actualReps: '10',
                actualWeight: '40',
                state: SetLogState.completed),
            _set(state: SetLogState.skipped),
          ],
          note: 'Coach: pause at the chest',
        ),
        ExerciseLog(
          name: 'Cable Fly',
          exerciseId: 'ex_fly',
          sets: [_set()],
          skipped: true,
          skipReason: 'Equipment unavailable',
        ),
      ];

      // The exact path the editor takes: write → read back → write again.
      final wire1 = buildSessionEntries(original);
      final reparsed = wire1
          .map((m) => ExerciseLog.fromJson({
                'name': m['exerciseName'],
                'exerciseId': m['exerciseId'] ?? '',
                'sets': (m['sets'] as List)
                    .map((s) => {
                          'pReps': (s as Map)['prescribedReps'],
                          'pWeight': s['prescribedWeight'],
                          'pRest': s['prescribedRest'],
                          'actualReps': s['actualReps'],
                          'actualWeight': s['actualWeight'],
                          'state': s['completed'] == true
                              ? 'completed'
                              : s['skipped'] == true
                                  ? 'skipped'
                                  : 'pending',
                          'edited': s['edited'] ?? false,
                        })
                    .toList(),
                'skipped': m['skipped'] ?? false,
                'skipReason': m['skipReason'] ?? '',
                'note': m['note'] ?? '',
              }))
          .toList();
      final wire2 = buildSessionEntries(reparsed);

      // Byte-identical. A second edit must not quietly shed a field the first
      // one carried — which is precisely how a merge-written array decays.
      expect(wire2, equals(wire1));
    });
  });

  // ── DURATION — ONE NUMBER, BOTH APPS ─────────────────────────────────────
  //
  // TrainerHQ renders a session's length through `durationLabel`, transcribed
  // verbatim below from `client_workout_session_model.dart`. It reads
  // `durationSeconds` and NOTHING else — verified from source: the coach app
  // parses `startedAt`/`finishedAt` into fields, but no surface anywhere
  // derives a duration from them.
  //
  // That is what makes "both apps show the same duration" a STRUCTURAL fact
  // rather than a promise: the member app writes exactly one duration field,
  // and the coach app reads exactly that field. When the member app switched
  // that field from wall clock to ACTIVE TIME, the coach's view followed with
  // no coach-side change at all.
  group('the coach reads the same duration the member does', () {
    // VERBATIM from TrainerHQ `ClientWorkoutSessionModel.durationLabel`.
    String? coachDurationLabel(int? durationSeconds) {
      final s = durationSeconds;
      if (s == null || s <= 0) return null;
      final mins = (s / 60).round();
      return mins < 1 ? '<1 min' : '$mins min';
    }

    test('active time is what reaches the coach, not elapsed time', () {
      // The member's real 3 August session: 5:13 PM – 7:21 PM wall clock, but
      // three sets with one long interruption.
      const t0 = 0;
      final marks = <int>[
        t0,
        t0 + 70 * 1000,
        t0 + 200 * 1000,
        t0 + 7595 * 1000, // ← the interruption
        t0 + 7620 * 1000,
      ];
      var active = 0;
      int? last;
      for (final m in marks) {
        active = accumulateActiveMillis(
          previousActiveMillis: active,
          lastTickMillis: last,
          nowMillis: m,
        );
        last = m;
      }

      final written = activeSecondsOf(active);
      // What the member app now writes, and therefore what the coach reads.
      expect(coachDurationLabel(written), '9 min');
      // What the coach used to read for the very same session.
      expect(coachDurationLabel(sessionDurationSeconds(t0, marks.last)),
          '127 min');
    });

    test('a session with no accumulated time states nothing on either side',
        () {
      final written = activeSecondsOf(0);
      expect(written, isNull);
      // Absent, never "0 min" — the coach sees no duration rather than a
      // fabricated zero, exactly as the member does.
      expect(coachDurationLabel(written), isNull);
    });

    test('a genuine session is reported identically on both sides', () {
      const seconds = 45 * 60;
      expect(formatWorkoutDuration(seconds), '45m');
      expect(coachDurationLabel(seconds), '45 min');
    });
  });
}
