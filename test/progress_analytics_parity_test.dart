// ═══════════════════════════════════════════════════════════════════════════
// CROSS-APP PARITY GUARD FOR THE SHARED ANALYTICS CORE
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️  THIS FILE IS TWINNED, exactly like the file it guards. The identical test
//     lives at:
//        alphaserena/test/progress_analytics_parity_test.dart
//        trainersHQ/test/progress_analytics_parity_test.dart
//
// ── WHY A HASH AND NOT JUST BEHAVIOUR ──────────────────────────────────────
//
// A behaviour fixture alone is not enough, and this repository already proved
// it: `transformation_comparison.dart` was documented as a twin of TrainerHQ's
// copy, drifted anyway (TrainerHQ grew `transformationMeasurementKeys`,
// AlphaSerena never received it), and every test on both sides stayed green —
// because each side was self-consistent about its own version.
//
// So this guard has TWO independent halves:
//
//   1. THE SOURCE HASH. Both repos pin the SAME SHA-256 of
//      `progress_analytics.dart`. Editing the file in one repo and not the
//      other fails HERE, immediately, whatever the edit was — including one
//      that adds a function and breaks nothing.
//   2. THE BEHAVIOUR MATRIX. Fixed inputs, literal expected outputs. This
//      catches the subtler case: both files edited, one of them wrongly.
//
// ── WHEN THIS TEST FAILS ───────────────────────────────────────────────────
//
// It is telling you the two apps are about to disagree in front of a member and
// their coach on the same call. The fix is NEVER to update one side's constant.
// Copy the file to the other repo, re-run `shasum -a 256`, and update the
// constant in BOTH.

import 'dart:convert';
import 'dart:io';

import 'package:alphaserena/core/analytics/progress_analytics.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// SHA-256 of `lib/core/analytics/progress_analytics.dart`, identical in both
/// repositories. Regenerate with:
///
///   shasum -a 256 lib/core/analytics/progress_analytics.dart
///
/// and update it in BOTH repos in the same change.
const String kSharedAnalyticsSha256 =
    'bdd700fb42d24222424cfd8287613fb5950effdbe1b73d67b439b2c8c55c1797';

void main() {
  group('the shared core is byte-identical across both apps', () {
    test('progress_analytics.dart matches the pinned hash', () {
      final file = File('lib/core/analytics/progress_analytics.dart');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'The shared analytics core is missing from this repository.',
      );
      final digest = sha256.convert(file.readAsBytesSync()).toString();
      expect(
        digest,
        kSharedAnalyticsSha256,
        reason:
            '\n\nTHE SHARED ANALYTICS CORE HAS DRIFTED.\n\n'
            'This file is twinned with the other app. It was edited here and\n'
            'either (a) not copied to the other repository, or (b) copied but\n'
            'the pinned hash was not updated in both.\n\n'
            'Fix: copy lib/core/analytics/progress_analytics.dart to the other\n'
            'repo, run `shasum -a 256` on it, and update\n'
            'kSharedAnalyticsSha256 in BOTH copies of this test.\n\n'
            'Do NOT update only this repository\'s constant. That is exactly\n'
            'how transformation_comparison.dart diverged while staying green.\n',
      );
    });
  });

  // ── THE BEHAVIOUR MATRIX ──────────────────────────────────────────────────
  //
  // Fixed inputs, literal outputs. Every expectation below is a number a member
  // and their coach must BOTH see. Deliberately built from constructor calls
  // rather than loaded from a JSON fixture: a fixture file can be regenerated
  // by whichever side is wrong, whereas these values had to be reasoned about.

  final now = DateTime(2026, 8, 4, 12);
  DateTime ago(int d) => now.subtract(Duration(days: d));

  AnalyticsSession session(
    DateTime date,
    String name,
    List<List<double?>> sets, {
    String id = '',
  }) => AnalyticsSession(
    date: date,
    entries: [
      AnalyticsEntry(
        exerciseId: id,
        exerciseName: name,
        sets: [
          for (final s in sets)
            AnalyticsSet(
              prescribedReps: s[0],
              prescribedWeight: s[1],
              actualReps: s[2],
              actualWeight: s[3],
              completed: s[4] == 1,
            ),
        ],
      ),
    ],
  );

  // A fixed four-week training block. [pReps, pWeight, aReps, aWeight, done]
  final matrix = <AnalyticsSession>[
    session(ago(1), 'Squat', [
      [8, 100, 8, 100, 1],
      [8, 100, 7, 100, 1],
    ], id: 'sq'),
    session(ago(3), 'Squat', [
      [8, 95, 8, 95, 1],
      [8, 95, 8, 95, 1],
    ], id: 'sq'),
    session(ago(8), 'Squat', [
      [8, 90, 6, 90, 1],
    ], id: 'sq'),
    session(ago(15), 'Bench', [
      [10, 60, 10, 60, 1],
      [10, 60, 9, 60, 0],
    ]),
    session(ago(24), 'Squat', [
      [8, 85, 8, 85, 1],
    ], id: 'sq'),
    // Outside a 28-day window — must never enter a windowed figure.
    session(ago(40), 'Squat', [
      [8, 200, 8, 200, 1],
    ], id: 'sq'),
  ];

  group('training derivations agree across apps', () {
    test('workout adherence summary', () {
      final s = workoutAdherenceSummary(matrix, now: now)!;
      // In-window scorable sessions: ago1 (1/2), ago3 (2/2), ago8 (0/1),
      // ago15 (1/1 — only the completed set counts), ago24 (1/1).
      expect(s.sample, 5);
      expect(s.value, closeTo((0.5 + 1.0 + 0.0 + 1.0 + 1.0) / 5, 1e-9));
      expect(s.confidence, ProgressConfidence.ok);
    });

    test('workout adherence series is ascending and window-clipped', () {
      final series = workoutAdherenceSeries(matrix, now: now);
      expect(series, hasLength(5));
      expect(series.first.date, ago(24));
      expect(series.last.date, ago(1));
    });

    test('top weighted exercise', () {
      final top = topWeightedExercise(matrix)!;
      expect(top.key, 'id:sq');
      expect(top.name, 'Squat');
    });

    test('strength series takes the heaviest set per session', () {
      final series = strengthSeries(matrix, 'id:sq');
      expect(series.map((p) => p.value).toList(), [200, 85, 90, 95, 100]);
    });

    test('total volume inside the window', () {
      // ago1 8*100 + 7*100 = 1500 · ago3 8*95 + 8*95 = 1520 · ago8 6*90 = 540
      // ago15 10*60 = 600 (the incomplete set contributes nothing)
      // ago24 8*85 = 680 · ago40 excluded
      expect(totalVolume(matrix, now: now), closeTo(4840, 1e-9));
    });

    test('distinct exercises inside the window', () {
      expect(distinctExercises(matrix, now: now), 2);
    });

    test('personal bests, strongest first', () {
      final pbs = personalBests(matrix);
      expect(pbs.first.exercise, 'Squat');
      expect(pbs.first.weight, 200);
      expect(pbs.first.at, ago(40));
      expect(pbs[1].exercise, 'Bench');
      expect(pbs[1].weight, 60);
    });

    test('sessions per week is observed frequency over a stated span', () {
      expect(sessionsPerWeek(matrix, now: now), closeTo(5 / 4, 1e-9));
    });

    test('active days inside the window', () {
      expect(activeDays(matrix, now: now), 5);
    });

    test('streaks', () {
      // Yesterday is a LIVE streak — today is not over yet, so a member who
      // trained yesterday and has not trained today has not broken anything.
      // No two sessions in this block are on consecutive days, so the run
      // stops at one and the historic best is also one.
      expect(workoutStreak(matrix, now: now), 1);
      expect(longestWorkoutStreak(matrix), 1);
    });
  });

  group('body derivations agree across apps', () {
    final body = [
      AnalyticsBodyPoint(
        date: ago(30),
        weightKg: 84,
        measurements: const {'waist': 92, 'neck': 39},
      ),
      AnalyticsBodyPoint(
        date: ago(10),
        weightKg: 82,
        measurements: const {'waist': 90},
      ),
    ];
    final checkIns = [
      AnalyticsBodyPoint(date: ago(20), weightKg: 83),
      AnalyticsBodyPoint(date: ago(10), weightKg: 999), // same day as a log
    ];

    test('weight reconciles both sources, the body log winning a tie', () {
      final series = reconciledWeightSeries(body, checkIns);
      expect(series.map((p) => p.value).toList(), [84, 83, 82]);
    });

    test('net change and movement', () {
      final series = reconciledWeightSeries(body, checkIns);
      expect(netChange(series), closeTo(-2, 1e-9));
      expect(weightMovement(series), ProgressDirection.declining);
    });

    test('measurement keys present, in reading order', () {
      expect(presentMeasurementKeys(body), ['neck', 'waist']);
    });

    test('measurement series for one key', () {
      final s = measurementSeries(body, 'waist');
      expect(s.map((p) => p.value).toList(), [92, 90]);
    });
  });

  group('scoring and verdict agree across apps', () {
    test('overall score is the mean of trustworthy dimensions', () {
      const dims = [
        ScoredDimension(
          id: 'workout',
          label: 'Workout quality',
          value: 0.9,
          direction: ProgressDirection.steady,
          sample: 5,
          confidence: ProgressConfidence.ok,
        ),
        ScoredDimension(
          id: 'nutrition',
          label: 'Nutrition',
          value: 0.7,
          direction: ProgressDirection.improving,
          sample: 9,
          confidence: ProgressConfidence.ok,
        ),
      ];
      expect(overallScore(dims), closeTo(0.8, 1e-9));
      expect(overallDirection(dims), ProgressDirection.improving);
      expect(
        progressVerdict(
          score: overallScore(dims),
          overall: overallDirection(dims),
          daysSinceActive: 1,
        ),
        ProgressVerdict.improving,
      );
    });

    test('the shared thresholds match the backend contract', () {
      // MUST equal functions/src/lib/progress_config.ts. Changing either
      // without the other lets the in-app figure and the server rollup on the
      // clients document disagree about the same member.
      expect(AnalyticsPolicy.windowDays, 28); // ADHERENCE_WINDOW_DAYS
      expect(AnalyticsPolicy.minSample, 3); // MIN_SAMPLE
      expect(AnalyticsPolicy.onTrackPct, 0.8); // ON_TRACK_PCT
    });
  });

  group('smoothing agrees across apps', () {
    test('moving average over a fixed series', () {
      final out = movingAverage([10, 20, 30, 40, 50], 3);
      expect(out.map((v) => v.toStringAsFixed(2)).toList(), [
        '10.00',
        '15.00',
        '20.00',
        '30.00',
        '40.00',
      ]);
    });
  });

  group('insight sentences agree across apps', () {
    test('a fixed input produces byte-identical copy', () {
      final out = buildInsights(
        dimensions: const [
          ScoredDimension(
            id: 'nutrition',
            label: 'Nutrition',
            value: 0.42,
            direction: ProgressDirection.declining,
            sample: 11,
            confidence: ProgressConfidence.ok,
          ),
        ],
        windowDays: 28,
        currentStreak: 3,
        longestStreak: 9,
        streakWindowDays: 120,
        bests: [(exercise: 'Squat', weight: 102.5, at: DateTime(2026, 7, 20))],
        weight: [
          TrendPoint(DateTime(2026, 7, 1), 84),
          TrendPoint(DateTime(2026, 8, 4), 81),
        ],
      );
      final rendered = jsonEncode([
        for (final i in out)
          {
            'kind': i.kind.name,
            'tone': i.tone.name,
            'headline': i.headline,
            'basis': i.basis,
          },
      ]);
      expect(rendered, '''
[{"kind":"nutrition","tone":"caution","headline":"Nutrition is trending down — 42% this period.","basis":"Compared with the previous 28 days · 11 days recorded"},{"kind":"record","tone":"positive","headline":"Heaviest logged set: 102.5 kg on Squat.","basis":"Set on 20 Jul · within the loaded history"},{"kind":"streak","tone":"positive","headline":"3-day training streak, and it is still running.","basis":"Consecutive days with a logged session"},{"kind":"streak","tone":"neutral","headline":"Your best run so far is 9 days.","basis":"Longest in the last 120 days"},{"kind":"body","tone":"neutral","headline":"Weight has moved down 3.0 kg.","basis":"1 Jul → 4 Aug · 2 check-ins"}]'''
          .trim());
    });
  });
}
