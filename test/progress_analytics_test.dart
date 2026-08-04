import 'package:alphaserena/core/analytics/progress_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared analytics core, tested against the behaviours it PROMISES rather
/// than against its own implementation. Every case here is a rule the twinned
/// TrainerHQ copy must satisfy identically.
void main() {
  final now = DateTime(2026, 8, 4, 12);
  DateTime ago(int days) => now.subtract(Duration(days: days));

  AnalyticsSet st({
    double? pReps,
    double? pWeight,
    double? aReps,
    double? aWeight,
    bool done = true,
  }) => AnalyticsSet(
    prescribedReps: pReps,
    prescribedWeight: pWeight,
    actualReps: aReps,
    actualWeight: aWeight,
    completed: done,
  );

  AnalyticsSession sess(
    DateTime date, {
    String name = 'Bench',
    String id = '',
    List<AnalyticsSet> sets = const [],
  }) => AnalyticsSession(
    date: date,
    entries: [AnalyticsEntry(exerciseId: id, exerciseName: name, sets: sets)],
  );

  group('set hit — parity with TrainerHQ, AlphaSerena and the backend', () {
    test('a set with no numeric target at all is a hit (nothing to miss)', () {
      expect(const AnalyticsSet(completed: true).hit, isTrue);
    });

    test('a dimension with no target is skipped, the other still decides', () {
      // Reps prescribed and missed, weight not prescribed.
      expect(st(pReps: 10, aReps: 8).hit, isFalse);
      // Weight prescribed and met, reps not prescribed.
      expect(st(pWeight: 40, aWeight: 40).hit, isTrue);
    });

    test('meeting the target exactly counts as a hit', () {
      expect(st(pReps: 10, pWeight: 40, aReps: 10, aWeight: 40).hit, isTrue);
    });

    test('a missing actual against a real target is a miss, not a pass', () {
      expect(st(pReps: 10).hit, isFalse);
    });
  });

  group('session targetHitPct', () {
    test('is null when no set is completed — nothing to judge yet', () {
      final s = sess(now, sets: [st(pReps: 10, aReps: 10, done: false)]);
      expect(s.targetHitPct, isNull);
    });

    test('scores COMPLETED sets only', () {
      final s = sess(
        now,
        sets: [
          st(pReps: 10, aReps: 10), // hit
          st(pReps: 10, aReps: 5), // miss
          st(pReps: 10, aReps: 1, done: false), // ignored
        ],
      );
      expect(s.targetHitPct, closeTo(0.5, 1e-9));
    });
  });

  group('reconciledWeightSeries', () {
    test('merges both sources and orders ascending', () {
      final series = reconciledWeightSeries(
        [AnalyticsBodyPoint(date: ago(1), weightKg: 80)],
        [AnalyticsBodyPoint(date: ago(5), weightKg: 82)],
      );
      expect(series.map((p) => p.value).toList(), [82, 80]);
      expect(series.first.date.isBefore(series.last.date), isTrue);
    });

    test('a member who ONLY weighs in via check-ins still gets a trend', () {
      // The defect this closes: the member app read transformation checkpoints
      // alone and told them to "add at least two check-ins" while their coach
      // was already looking at the trend.
      final series = reconciledWeightSeries(const [], [
        AnalyticsBodyPoint(date: ago(14), weightKg: 84),
        AnalyticsBodyPoint(date: ago(7), weightKg: 83),
      ]);
      expect(series, hasLength(2));
    });

    test('same-day duplicates collapse, primary wins', () {
      final day = DateTime(2026, 8, 1, 9);
      final series = reconciledWeightSeries(
        [AnalyticsBodyPoint(date: day, weightKg: 80)],
        [AnalyticsBodyPoint(date: DateTime(2026, 8, 1, 20), weightKg: 99)],
      );
      expect(series, hasLength(1));
      expect(series.single.value, 80);
    });

    test('a point with no weight contributes nothing', () {
      final series = reconciledWeightSeries([
        AnalyticsBodyPoint(date: ago(1), measurements: const {'waist': 80}),
      ], const []);
      expect(series, isEmpty);
    });
  });

  group('presentMeasurementKeys', () {
    test('returns only keys the member actually logged, in reading order', () {
      final keys = presentMeasurementKeys([
        AnalyticsBodyPoint(
          date: now,
          measurements: const {'waist': 80, 'neck': 38, 'leftCalf': 37},
        ),
      ]);
      expect(keys, ['neck', 'waist', 'leftCalf']);
    });

    test('an unrecognised key is KEPT and appended, never dropped', () {
      // A fixed list silently dropping a logged measurement is exactly how
      // per-side arms and calves went missing from the coach's view.
      final keys = presentMeasurementKeys([
        AnalyticsBodyPoint(
          date: now,
          measurements: const {'waist': 80, 'forearm': 30},
        ),
      ]);
      expect(keys, ['waist', 'forearm']);
    });

    test('is empty when nothing was measured', () {
      expect(presentMeasurementKeys(const []), isEmpty);
    });
  });

  group('exerciseIdentity', () {
    test('prefers the library id so a rename does not split history', () {
      const a = AnalyticsEntry(exerciseId: 'x1', exerciseName: 'Bench Press');
      const b = AnalyticsEntry(exerciseId: 'x1', exerciseName: 'Barbell Bench');
      expect(exerciseIdentity(a), exerciseIdentity(b));
    });

    test('falls back to the name for freehand/legacy logs', () {
      expect(
        exerciseIdentity(const AnalyticsEntry(exerciseName: 'Curl')),
        'name:Curl',
      );
    });
  });

  group('strengthSeries', () {
    test('takes the heaviest working set per session, ascending', () {
      final series = strengthSeries([
        sess(ago(2), sets: [st(aWeight: 60), st(aWeight: 80)]),
        sess(ago(9), sets: [st(aWeight: 70)]),
      ], 'name:Bench');
      expect(series.map((p) => p.value).toList(), [70, 80]);
    });

    test('sessions under an OLD name join the same id-keyed series', () {
      final series = strengthSeries([
        sess(ago(9), id: 'x1', name: 'Bench', sets: [st(aWeight: 60)]),
        sess(ago(2), id: 'x1', name: 'Barbell Bench', sets: [st(aWeight: 65)]),
      ], 'id:x1');
      expect(series, hasLength(2));
    });

    test('a session with no numeric weight is skipped, not plotted as 0', () {
      final series = strengthSeries([
        sess(ago(1), sets: [st(aReps: 10)]),
      ], 'name:Bench');
      expect(series, isEmpty);
    });
  });

  group('topWeightedExercise', () {
    test('is null when nothing carries a numeric weight', () {
      expect(
        topWeightedExercise([
          sess(now, sets: [st(aReps: 10)]),
        ]),
        isNull,
      );
    });

    test('labels a renamed exercise by its most recent name', () {
      final top = topWeightedExercise([
        sess(ago(9), id: 'x1', name: 'Old Name', sets: [st(aWeight: 50)]),
        sess(ago(1), id: 'x1', name: 'New Name', sets: [st(aWeight: 55)]),
      ]);
      expect(top!.name, 'New Name');
      expect(top.key, 'id:x1');
    });

    test('is deterministic under a tie rather than order-dependent', () {
      final a = topWeightedExercise([
        sess(ago(1), name: 'Bench', sets: [st(aWeight: 50)]),
        sess(ago(2), name: 'Squat', sets: [st(aWeight: 90)]),
      ]);
      final b = topWeightedExercise([
        sess(ago(2), name: 'Squat', sets: [st(aWeight: 90)]),
        sess(ago(1), name: 'Bench', sets: [st(aWeight: 50)]),
      ]);
      expect(a!.key, b!.key);
    });
  });

  group('streaks', () {
    test('current streak counts back from today', () {
      final s = [sess(now), sess(ago(1)), sess(ago(2))];
      expect(workoutStreak(s, now: now), 3);
    });

    test('a streak ending yesterday still counts (today is not over)', () {
      expect(workoutStreak([sess(ago(1)), sess(ago(2))], now: now), 2);
    });

    test('a broken streak reads as 0, never a stale count', () {
      expect(workoutStreak([sess(ago(5)), sess(ago(6))], now: now), 0);
    });

    test('two sessions on one day do not double the streak', () {
      final s = [
        sess(DateTime(2026, 8, 4, 7)),
        sess(DateTime(2026, 8, 4, 19)),
        sess(ago(1)),
      ];
      expect(workoutStreak(s, now: now), 2);
    });

    test('longest streak finds the best historic run', () {
      final s = [
        sess(ago(20)), sess(ago(19)), sess(ago(18)), sess(ago(17)),
        sess(ago(5)), sess(ago(4)),
      ];
      expect(longestWorkoutStreak(s), 4);
    });

    test('longest streak of a single session is 1, of none is 0', () {
      expect(longestWorkoutStreak([sess(now)]), 1);
      expect(longestWorkoutStreak(const []), 0);
    });
  });

  group('volume', () {
    test('sums completed weight x reps inside the window only', () {
      final s = [
        sess(ago(1), sets: [st(aWeight: 50, aReps: 10)]), // 500, in
        sess(ago(40), sets: [st(aWeight: 99, aReps: 10)]), // out of window
      ];
      expect(totalVolume(s, now: now), 500);
    });

    test('an INCOMPLETE set contributes nothing', () {
      final s = [
        sess(ago(1), sets: [st(aWeight: 50, aReps: 10, done: false)]),
      ];
      expect(totalVolume(s, now: now), 0);
    });

    test('a bodyweight session is skipped by the series, not plotted as 0', () {
      final s = [
        sess(ago(1), sets: [st(aReps: 20)]),
      ];
      expect(volumeSeries(s, now: now), isEmpty);
    });
  });

  group('distinctExercises', () {
    test('counts a renamed library exercise once', () {
      final s = [
        sess(ago(1), id: 'x1', name: 'Old', sets: [st(aWeight: 10)]),
        sess(ago(2), id: 'x1', name: 'New', sets: [st(aWeight: 10)]),
      ];
      expect(distinctExercises(s, now: now), 1);
    });
  });

  group('personalBests', () {
    test('is strongest first and carries the date it was set', () {
      final s = [
        sess(ago(3), name: 'Squat', sets: [st(aWeight: 100)]),
        sess(ago(1), name: 'Bench', sets: [st(aWeight: 60)]),
      ];
      final pbs = personalBests(s);
      expect(pbs.first.exercise, 'Squat');
      expect(pbs.first.weight, 100);
      expect(pbs.first.at, ago(3));
    });

    test('is empty when no set carries a numeric weight', () {
      expect(
        personalBests([
          sess(now, sets: [st(aReps: 10)]),
        ]),
        isEmpty,
      );
    });
  });

  group('adherence', () {
    test('summary is null when nothing is scorable — never a fabricated 0%', () {
      expect(adherenceSummary(const [], now: now), isNull);
    });

    test('two records for one day count once', () {
      final r = adherenceSummary([
        AnalyticsRatio(DateTime(2026, 8, 1, 8), 1.0),
        AnalyticsRatio(DateTime(2026, 8, 1, 20), 0.0),
      ], now: now);
      expect(r!.sample, 1);
    });

    test('a value outside 0..1 is clamped, not trusted', () {
      // `client_diet_logs.adherencePct` is member-written and unbounded in the
      // rules; the backend clamps in two places for exactly this reason.
      final r = adherenceSummary([
        AnalyticsRatio(ago(1), 999),
        AnalyticsRatio(ago(2), -5),
        AnalyticsRatio(ago(3), 0.5),
      ], now: now);
      expect(r!.value, closeTo((1.0 + 0.0 + 0.5) / 3, 1e-9));
    });

    test('direction is unknown when one half of the window is empty', () {
      final r = adherenceSummary([
        AnalyticsRatio(ago(1), 0.9),
        AnalyticsRatio(ago(2), 0.9),
      ], now: now, windowDays: 28);
      expect(r!.direction, ProgressDirection.unknown);
    });

    test('a move smaller than the band reads as steady, not a trend', () {
      final r = adherenceSummary([
        AnalyticsRatio(ago(20), 0.80),
        AnalyticsRatio(ago(19), 0.80),
        AnalyticsRatio(ago(2), 0.82),
        AnalyticsRatio(ago(1), 0.82),
      ], now: now, windowDays: 28);
      expect(r!.direction, ProgressDirection.steady);
    });

    test('a real improvement is reported', () {
      final r = adherenceSummary([
        AnalyticsRatio(ago(20), 0.50),
        AnalyticsRatio(ago(19), 0.50),
        AnalyticsRatio(ago(2), 0.90),
        AnalyticsRatio(ago(1), 0.90),
      ], now: now, windowDays: 28);
      expect(r!.direction, ProgressDirection.improving);
    });

    test('confidence gates on MIN_SAMPLE', () {
      expect(AnalyticsPolicy.confidenceFor(0), ProgressConfidence.none);
      expect(AnalyticsPolicy.confidenceFor(2), ProgressConfidence.low);
      expect(AnalyticsPolicy.confidenceFor(3), ProgressConfidence.ok);
    });
  });

  group('momentum', () {
    test('is null when nothing was logged in either half', () {
      expect(momentum(const [], now: now), isNull);
    });

    test('reports rates over the half-window and their direction', () {
      final m = momentum([
        ago(1), ago(2), ago(3), ago(4), ago(5), ago(6), ago(7),
        ago(20),
      ], now: now, windowDays: 28);
      expect(m!.halfWindow, 14);
      expect(m.recentDays, 7);
      expect(m.direction, ProgressDirection.improving);
    });

    test('the same day logged twice counts once', () {
      final m = momentum([
        DateTime(2026, 8, 3, 8),
        DateTime(2026, 8, 3, 20),
      ], now: now);
      expect(m!.recentDays, 1);
    });
  });

  group('movingAverage', () {
    test('returns the input unchanged for a window below 2', () {
      expect(movingAverage([1, 2, 3], 1), [1, 2, 3]);
    });

    test('spans the whole series, averaging what is available early', () {
      final out = movingAverage([2, 4, 6, 8], 2);
      expect(out, hasLength(4));
      expect(out[0], 2);
      expect(out[1], 3);
      expect(out[3], 7);
    });
  });

  group('netChange + direction', () {
    test('net change needs two points', () {
      expect(netChange([TrendPoint(now, 5)]), isNull);
    });

    test('weight movement inside the flat band reads as steady', () {
      final s = [TrendPoint(ago(9), 80.0), TrendPoint(ago(1), 80.2)];
      expect(weightMovement(s), ProgressDirection.steady);
    });

    test('weight movement is factual, never judged', () {
      final down = [TrendPoint(ago(9), 82.0), TrendPoint(ago(1), 80.0)];
      final up = [TrendPoint(ago(9), 80.0), TrendPoint(ago(1), 82.0)];
      // "improving" here means "went up" and "declining" means "went down" —
      // no goal weight is stored, so neither may be coloured good or bad.
      expect(weightMovement(up), ProgressDirection.improving);
      expect(weightMovement(down), ProgressDirection.declining);
    });

    test('series direction is unknown with a single point', () {
      expect(seriesDirection([TrendPoint(now, 1)]), ProgressDirection.unknown);
    });
  });

  group('overall score + verdict', () {
    ScoredDimension dim(
      double v, {
      ProgressDirection d = ProgressDirection.steady,
      ProgressConfidence c = ProgressConfidence.ok,
    }) => ScoredDimension(
      id: 'workout',
      label: 'Workout quality',
      value: v,
      direction: d,
      sample: 5,
      confidence: c,
    );

    test('score is null when no dimension is trustworthy', () {
      expect(overallScore(const []), isNull);
      expect(
        overallScore([dim(0.9, c: ProgressConfidence.none)]),
        isNull,
      );
    });

    test('a null score is "building", never 0%', () {
      expect(
        progressVerdict(score: null, overall: ProgressDirection.unknown),
        ProgressVerdict.building,
      );
    });

    test('a declining direction outranks a good score', () {
      expect(
        progressVerdict(
          score: 0.95,
          overall: ProgressDirection.declining,
          daysSinceActive: 0,
        ),
        ProgressVerdict.slipping,
      );
    });

    test('going quiet outranks a good score', () {
      expect(
        progressVerdict(
          score: 0.95,
          overall: ProgressDirection.improving,
          daysSinceActive: 11,
        ),
        ProgressVerdict.slipping,
      );
    });

    test('below the on-track band is "behind"', () {
      expect(
        progressVerdict(
          score: 0.7,
          overall: ProgressDirection.steady,
          daysSinceActive: 0,
        ),
        ProgressVerdict.behind,
      );
    });

    test('excellent needs BOTH a high score and recent activity', () {
      expect(
        progressVerdict(
          score: 0.95,
          overall: ProgressDirection.steady,
          daysSinceActive: 1,
        ),
        ProgressVerdict.excellent,
      );
      expect(
        progressVerdict(
          score: 0.95,
          overall: ProgressDirection.steady,
          daysSinceActive: 8,
        ),
        ProgressVerdict.steady,
      );
    });

    test('overall direction: mixed signals read as steady', () {
      final d = overallDirection([
        dim(0.9, d: ProgressDirection.improving),
        dim(0.5, d: ProgressDirection.declining),
      ]);
      expect(d, ProgressDirection.steady);
    });

    test('overall direction is unknown when nothing expresses one', () {
      expect(
        overallDirection([dim(0.9, d: ProgressDirection.unknown)]),
        ProgressDirection.unknown,
      );
    });
  });

  group('insights — deterministic, evidence-backed, never invented', () {
    test('says nothing when there is nothing true to say', () {
      final out = buildInsights(
        dimensions: const [],
        windowDays: 28,
        currentStreak: 0,
        longestStreak: 0,
        streakWindowDays: 0,
      );
      expect(out, isEmpty);
    });

    test('a declining dimension is reported FIRST, as a caution', () {
      final out = buildInsights(
        dimensions: const [
          ScoredDimension(
            id: 'workout',
            label: 'Workout quality',
            value: 0.9,
            direction: ProgressDirection.improving,
            sample: 5,
            confidence: ProgressConfidence.ok,
          ),
          ScoredDimension(
            id: 'nutrition',
            label: 'Nutrition',
            value: 0.4,
            direction: ProgressDirection.declining,
            sample: 8,
            confidence: ProgressConfidence.ok,
          ),
        ],
        windowDays: 28,
        currentStreak: 0,
        longestStreak: 0,
        streakWindowDays: 0,
      );
      expect(out.first.tone, InsightTone.caution);
      expect(out.first.headline, contains('Nutrition'));
      expect(out.first.headline, contains('40%'));
      expect(out.first.basis, contains('8 days recorded'));
    });

    test('a dimension with no confidence is never spoken about', () {
      final out = buildInsights(
        dimensions: const [
          ScoredDimension(
            id: 'nutrition',
            label: 'Nutrition',
            value: 0.4,
            direction: ProgressDirection.declining,
            sample: 0,
            confidence: ProgressConfidence.none,
          ),
        ],
        windowDays: 28,
        currentStreak: 0,
        longestStreak: 0,
        streakWindowDays: 0,
      );
      expect(out, isEmpty);
    });

    test('the best streak states the window it searched', () {
      final out = buildInsights(
        dimensions: const [],
        windowDays: 28,
        currentStreak: 2,
        longestStreak: 9,
        streakWindowDays: 120,
      );
      final best = out.firstWhere((i) => i.headline.contains('best run'));
      expect(best.basis, contains('120 days'));
    });

    test('a best run equal to the current streak is not repeated', () {
      final out = buildInsights(
        dimensions: const [],
        windowDays: 28,
        currentStreak: 5,
        longestStreak: 5,
        streakWindowDays: 60,
      );
      expect(out.where((i) => i.headline.contains('best run')), isEmpty);
    });

    test('weight movement is stated neutrally, never as good or bad', () {
      final out = buildInsights(
        dimensions: const [],
        windowDays: 28,
        currentStreak: 0,
        longestStreak: 0,
        streakWindowDays: 0,
        weight: [TrendPoint(DateTime(2026, 7, 1), 84), TrendPoint(now, 80)],
      );
      final w = out.firstWhere((i) => i.kind == InsightKind.body);
      expect(w.tone, InsightTone.neutral);
      expect(w.headline, contains('down 4.0 kg'));
      expect(w.basis, contains('1 Jul'));
    });

    test('weight movement inside the flat band is not reported at all', () {
      final out = buildInsights(
        dimensions: const [],
        windowDays: 28,
        currentStreak: 0,
        longestStreak: 0,
        streakWindowDays: 0,
        weight: [TrendPoint(DateTime(2026, 7, 1), 80.0), TrendPoint(now, 80.2)],
      );
      expect(out.where((i) => i.kind == InsightKind.body), isEmpty);
    });

    test('is deterministic — the same inputs give the same sentences', () {
      List<ProgressInsight> run() => buildInsights(
        dimensions: const [
          ScoredDimension(
            id: 'workout',
            label: 'Workout quality',
            value: 0.86,
            direction: ProgressDirection.improving,
            sample: 12,
            confidence: ProgressConfidence.ok,
          ),
        ],
        windowDays: 28,
        currentStreak: 4,
        longestStreak: 11,
        streakWindowDays: 90,
        bests: [(exercise: 'Squat', weight: 102.5, at: DateTime(2026, 7, 20))],
        weight: [TrendPoint(DateTime(2026, 7, 1), 84), TrendPoint(now, 81)],
      );
      final a = run().map((i) => '${i.tone}|${i.headline}|${i.basis}').toList();
      final b = run().map((i) => '${i.tone}|${i.headline}|${i.basis}').toList();
      expect(a, b);
      expect(a, isNotEmpty);
    });
  });

  group('sessionsPerWeek + activeDays', () {
    test('frequency is observed, over a stated span', () {
      final s = [sess(ago(1)), sess(ago(3)), sess(ago(5)), sess(ago(40))];
      // 3 sessions in a 28-day window = 0.75/week.
      expect(sessionsPerWeek(s, now: now), closeTo(0.75, 1e-9));
    });

    test('active days de-duplicates a double-logged day', () {
      final s = [
        sess(DateTime(2026, 8, 3, 7)),
        sess(DateTime(2026, 8, 3, 19)),
        sess(ago(2)),
      ];
      expect(activeDays(s, now: now), 2);
    });
  });
}
