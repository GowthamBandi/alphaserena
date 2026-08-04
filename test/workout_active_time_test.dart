import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/core/domain/workout_history.dart';
import 'package:alphaserena/core/domain/workout_session.dart';

/// ACTIVE TRAINING TIME — the one duration every surface reports.
///
/// ── WHAT THIS REPLACED ────────────────────────────────────────────────────
///
/// "Duration" was `finishedAt - startedAt`, pure wall clock, with no pause
/// control anywhere in the session screens. A member interrupted mid-workout
/// had the whole interruption recorded as training — in their history, on Home,
/// as the sole input to the calorie estimate, and in their COACH's app, which
/// renders the same `durationSeconds` field.
///
/// It was not hypothetical. The audited member's own 3 August session records
/// `5:13 PM – 7:21 PM` — 2 h 7 m — for three sets of ten reps at 12 kg. The
/// `two hours seven minutes for three sets` test below is that session.
void main() {
  group('the accumulator banks intervals between observed activity', () {
    test('the first mark contributes nothing — no interval has elapsed yet',
        () {
      expect(
        accumulateActiveMillis(
          previousActiveMillis: 0,
          lastTickMillis: null,
          nowMillis: 1000,
        ),
        0,
      );
    });

    test('an ordinary set-to-set gap is counted in full', () {
      // 90 s rest + 40 s performing the next set.
      expect(
        accumulateActiveMillis(
          previousActiveMillis: 0,
          lastTickMillis: 0,
          nowMillis: 130 * 1000,
        ),
        130 * 1000,
      );
    });

    test('gaps accumulate across marks', () {
      var total = 0;
      for (final gap in [120, 95, 130, 110]) {
        total = accumulateActiveMillis(
          previousActiveMillis: total,
          lastTickMillis: 0,
          nowMillis: gap * 1000,
        );
      }
      expect(total, (120 + 95 + 130 + 110) * 1000);
    });

    test('a single interruption is capped, however long it really ran', () {
      final oneHour = accumulateActiveMillis(
        previousActiveMillis: 0,
        lastTickMillis: 0,
        nowMillis: 60 * 60 * 1000,
      );
      final nineHours = accumulateActiveMillis(
        previousActiveMillis: 0,
        lastTickMillis: 0,
        nowMillis: 9 * 60 * 60 * 1000,
      );
      expect(oneHour, kMaxIdleGapSeconds * 1000);
      expect(nineHours, kMaxIdleGapSeconds * 1000);
      expect(oneHour, nineHours,
          reason: 'the cap makes the length of an interruption irrelevant');
    });

    test('the cap is exactly five minutes, and inclusive', () {
      expect(kMaxIdleGapSeconds, 5 * 60);
      final atCap = accumulateActiveMillis(
        previousActiveMillis: 0,
        lastTickMillis: 0,
        nowMillis: kMaxIdleGapSeconds * 1000,
      );
      final overCap = accumulateActiveMillis(
        previousActiveMillis: 0,
        lastTickMillis: 0,
        nowMillis: kMaxIdleGapSeconds * 1000 + 1,
      );
      expect(atCap, kMaxIdleGapSeconds * 1000);
      expect(overCap, atCap);
    });

    test('a backwards device clock never subtracts time already earned', () {
      expect(
        accumulateActiveMillis(
          previousActiveMillis: 600 * 1000,
          lastTickMillis: 5000,
          nowMillis: 1000, // clock moved back
        ),
        600 * 1000,
      );
    });
  });

  group('THE DEFECT THIS CLOSES — the member\'s real 3 August session', () {
    test('two hours seven minutes for three sets reports as minutes, not hours',
        () {
      // 5:13 PM – 7:21 PM. Sets 1 and 2 back to back, then the member is
      // interrupted for roughly two hours, comes back for set 3, and finishes.
      const t0 = 0;
      final set1 = t0 + 70 * 1000; // performed
      final set2 = set1 + 130 * 1000; // rest + performed
      // The interruption is sized so the whole session spans exactly the
      // 7620 s (2 h 7 m) the production document records.
      final set3 = set2 + 7395 * 1000; // ← the interruption
      final finish = set3 + 25 * 1000;

      var active = 0;
      int? last;
      for (final mark in [t0, set1, set2, set3, finish]) {
        active = accumulateActiveMillis(
          previousActiveMillis: active,
          lastTickMillis: last,
          nowMillis: mark,
        );
        last = mark;
      }

      final seconds = activeSecondsOf(active)!;
      // 70 + 130 + capped 300 + 25 = 525 s. The formatter states whole minutes
      // once past one, so the member reads "8m".
      expect(seconds, 525);
      expect(formatWorkoutDuration(seconds), '8m');

      // What the OLD wall-clock rule reported for the same session.
      final wallClock = sessionDurationSeconds(t0, finish)!;
      expect(formatWorkoutDuration(wallClock), '2h 7m');
    });

    test('and the calorie figure follows it down', () {
      const bodyWeightKg = 70.0;
      final honest =
          estimatedWorkoutCalories(durationSeconds: 525, bodyWeightKg: bodyWeightKg)!;
      final wallClock = estimatedWorkoutCalories(
          durationSeconds: 2 * 60 * 60 + 7 * 60, bodyWeightKg: bodyWeightKg)!;

      expect(honest.round(), 54);
      expect(wallClock.round(), 778);
      // The clamp never touched this session — it is under three hours. Only
      // active time closes it.
      expect(wallClock / honest, greaterThan(14));
    });
  });

  group('a real, uninterrupted session is reported faithfully', () {
    test('45 minutes of genuine training stays 45 minutes', () {
      // Twelve marks, each a plausible set-plus-rest apart.
      var active = 0;
      int? last;
      var t = 0;
      for (var i = 0; i <= 18; i++) {
        active = accumulateActiveMillis(
          previousActiveMillis: active,
          lastTickMillis: last,
          nowMillis: t,
        );
        last = t;
        t += 150 * 1000; // 2m30s per set incl. rest — none of it capped
      }
      expect(activeSecondsOf(active), 18 * 150);
      expect(formatWorkoutDuration(activeSecondsOf(active)!), '45m');
    });
  });

  group('nothing accumulated states no duration, never "0m"', () {
    test('zero and negative read as null', () {
      expect(activeSecondsOf(0), isNull);
      expect(activeSecondsOf(-1), isNull);
    });

    test('a sub-second total reads as null rather than rounding to zero', () {
      expect(activeSecondsOf(400), isNull);
    });

    test('and the calorie model declines to model it', () {
      expect(
        estimatedWorkoutCalories(
          durationSeconds: activeSecondsOf(0),
          bodyWeightKg: 70,
        ),
        isNull,
      );
    });
  });

  group('the draft carries the total across a killed process', () {
    test('activeMillis round-trips, and a v1 draft reads as zero', () {
      final draft = WorkoutDraft(
        sessionId: 'ws_c1_2026-08-04',
        dayKey: '2026-08-04',
        planName: 'Workout Plan 11',
        exercises: const [],
        activeMillis: 525 * 1000,
      );
      final back = WorkoutDraft.fromJson(draft.toJson())!;
      expect(back.activeMillis, 525 * 1000);

      // A draft written before active time existed. It must LOAD, not fail —
      // an in-flight session upgraded mid-workout simply starts counting now.
      final v1 = WorkoutDraft.fromJson({
        'v': 1,
        'sessionId': 'ws_c1_2026-08-04',
        'dayKey': '2026-08-04',
        'planName': 'Workout Plan 11',
        'currentExercise': 0,
        'exercises': <dynamic>[],
      })!;
      expect(v1.activeMillis, 0);
      expect(v1.sessionId, 'ws_c1_2026-08-04');
    });
  });

  group('elapsed time still exists — it is simply not what is reported', () {
    test('sessionDurationSeconds is unchanged and still clamps at zero', () {
      expect(sessionDurationSeconds(1000, 61000), 60);
      expect(sessionDurationSeconds(61000, 1000), 0);
      expect(sessionDurationSeconds(null, 5000), isNull);
      expect(sessionDurationSeconds(1000, null), isNull);
    });
  });
}
