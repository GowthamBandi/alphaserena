import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/core/domain/workout_history.dart';
import 'package:alphaserena/core/domain/workout_session.dart';

/// A session's recorded "Duration" is pure WALL CLOCK — and the calorie model
/// is no longer allowed to extrapolate from it.
///
/// `sessionDurationSeconds` is `finishedAt - startedAt` and nothing else, and
/// there is no pause concept anywhere in the session or player screens. So the
/// interval a member spends NOT training — the app backgrounded, the phone in a
/// pocket, an interrupted session finished off hours later — is counted as
/// elapsed time. That remains TRUE and is deliberately left alone: it is what
/// was measured, and it is what both this app and TrainerHQ state.
///
/// What is NOT left alone is the calorie estimate. It was linear in that figure
/// and uncapped, so nine elapsed hours turned 245 kcal into 3308 — a derived
/// claim, on a card whose own caption tells the member it comes "from this
/// session's length", that the member can personally disprove. The model input
/// is now bounded by [kMaxModelledSessionSeconds].
void main() {
  group('session duration is wall clock, not time trained', () {
    test('an interrupted session reports the whole interruption as elapsed',
        () {
      // A real morning: start at 09:00, two sets in, life happens, the member
      // comes back after work and finishes at 18:00.
      final started = DateTime(2026, 8, 4, 9).millisecondsSinceEpoch;
      final finished = DateTime(2026, 8, 4, 18).millisecondsSinceEpoch;

      final seconds = sessionDurationSeconds(started, finished);

      // Nine elapsed hours. UNCHANGED BY THE FIX, and deliberately so — the
      // recorded duration is a fact about the clock, and TrainerHQ renders the
      // same field. Clamping what was measured would be falsifying it.
      expect(seconds, 9 * 60 * 60);
      expect(formatWorkoutDuration(seconds!), '9h');
    });

    test('this is reachable WITHIN one day, which is what makes it real', () {
      // The bound on the defect, stated so nobody re-derives it: a session is
      // keyed `ws_{clientId}_{yyyy-MM-dd}` and the draft is only restored when
      // `draft.dayKey` matches today, so a session cannot be resumed across
      // midnight. The interruption must fit inside one calendar day — which
      // 09:00 → 18:00 comfortably does.
      final started = DateTime(2026, 8, 4, 0, 5).millisecondsSinceEpoch;
      final finished = DateTime(2026, 8, 4, 23, 55).millisecondsSinceEpoch;
      expect(sessionDurationSeconds(started, finished), (23 * 60 + 50) * 60);
    });
  });

  group('the calorie model refuses to extrapolate past a plausible session',
      () {
    const bodyWeightKg = 70.0;

    test('a real session is untouched — the clamp never bites normal training',
        () {
      final trained = estimatedWorkoutCalories(
        durationSeconds: 40 * 60,
        bodyWeightKg: bodyWeightKg,
      )!;
      expect(trained.round(), 245);

      // Even a long, genuine session stays exact.
      final long = estimatedWorkoutCalories(
        durationSeconds: 2 * 60 * 60,
        bodyWeightKg: bodyWeightKg,
      )!;
      expect(long.round(), 735);
    });

    test('nine elapsed hours are modelled as the bound, not as nine hours', () {
      final reported = estimatedWorkoutCalories(
        durationSeconds: 9 * 60 * 60,
        bodyWeightKg: bodyWeightKg,
      )!;
      final atBound = estimatedWorkoutCalories(
        durationSeconds: kMaxModelledSessionSeconds,
        bodyWeightKg: bodyWeightKg,
      )!;

      expect(reported, atBound);
      // Was 3308 — 13.5x the 245 kcal the member actually earned.
      expect(reported.round(), 1103);
    });

    test('an overnight clock cannot inflate the figure without limit', () {
      final overnight = estimatedWorkoutCalories(
        durationSeconds: 24 * 60 * 60,
        bodyWeightKg: bodyWeightKg,
      )!;
      // Was 8820.
      expect(overnight.round(), 1103);
    });

    test('the bound is exactly three hours, and inclusive', () {
      expect(kMaxModelledSessionSeconds, 3 * 60 * 60);
      final exactly = estimatedWorkoutCalories(
        durationSeconds: kMaxModelledSessionSeconds,
        bodyWeightKg: bodyWeightKg,
      )!;
      final oneSecondOver = estimatedWorkoutCalories(
        durationSeconds: kMaxModelledSessionSeconds + 1,
        bodyWeightKg: bodyWeightKg,
      )!;
      expect(oneSecondOver, exactly);
    });

    test('the null rules survive the clamp', () {
      // No weight → no figure. The app does not own a body-weight guess.
      expect(
        estimatedWorkoutCalories(
          durationSeconds: 24 * 60 * 60,
          bodyWeightKg: null,
        ),
        isNull,
      );
      expect(
        estimatedWorkoutCalories(durationSeconds: null, bodyWeightKg: 70),
        isNull,
      );
    });
  });
}
