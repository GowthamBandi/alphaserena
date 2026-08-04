// ═══════════════════════════════════════════════════════════════════════════
// PROGRESS AT SCALE — A MEASUREMENT, NOT AN OPINION
// ═══════════════════════════════════════════════════════════════════════════
//
// Every derived value on `ProgressAnalyticsController` is a GETTER over the raw
// source lists — there is no memo anywhere. That is the right default for
// correctness (nothing can go stale) and it is free while a member has a few
// dozen sessions. This file exists to answer the question that default raises
// and that no other test asks: WHAT DOES ONE FRAME COST when the member has
// years of history?
//
// It reproduces the EXACT getter sweep `progress_screen.dart` +
// `progress_sections.dart` perform in a single build — call for call, in the
// same multiplicities, counted from the source — and times it.
//
// The budget below is not aspirational. A ListView build that runs longer than
// one 60fps frame (16.7ms) drops that frame, and Progress rebuilds its whole
// Obx on every source emission, every range change and every scroll-driven
// relayout of a section.

import 'package:alphaserena/controllers/member_controller.dart';
import 'package:alphaserena/controllers/progress_analytics_controller.dart';
import 'package:alphaserena/controllers/progress_controller.dart';
import 'package:alphaserena/core/models/check_in_submission_model.dart';
import 'package:alphaserena/core/models/transformation_entry.dart';
import 'package:alphaserena/core/services/check_in_submission_service.dart';
import 'package:alphaserena/core/services/member_rollup_service.dart';
import 'package:alphaserena/core/services/nutrition_rollup_service.dart';
import 'package:alphaserena/core/services/workout_log_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

// ── Fakes: the network, and nothing else ────────────────────────────────────

class _FakeMember extends MemberController {
  _FakeMember() {
    client.value = const {
      'lifestyleTargets': {
        'waterTargetMl': 3000,
        'glassSizeMl': 250,
        'stepsTarget': 10000,
        'sleepHoursTarget': 8,
      },
    };
    isLoading.value = false;
    isLinked.value = true;
  }

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> claim() async {}
}

class _FakeTransformation extends ProgressController {
  _FakeTransformation(List<TransformationEntry> seed) {
    entries.assignAll(seed);
    isLoading.value = false;
  }

  @override
  // ignore: must_call_super
  void onInit() {}
}

class _FakeWorkoutLog extends WorkoutLogService {
  final List<Map<String, dynamic>> docs;
  _FakeWorkoutLog(this.docs);

  @override
  Future<List<Map<String, dynamic>>?> fetchSessionHistory() async => docs;
}

class _FakeCheckIns extends CheckInSubmissionService {
  final List<CheckInSubmissionModel> mine;
  _FakeCheckIns(this.mine);

  @override
  Stream<List<CheckInSubmissionModel>> watchMine() => Stream.value(mine);
}

class _FakeNutrition extends NutritionRollupService {
  final List<NutritionRollupDay> days;
  _FakeNutrition(this.days);

  @override
  Stream<List<NutritionRollupDay>> watchDays({int months = 3, DateTime? now}) =>
      Stream.value(days);
}

class _FakeLifestyle extends MemberRollupService {
  final List<RollupDay> days;
  _FakeLifestyle(this.days);

  @override
  Stream<List<RollupDay>> watchDays({int months = 3, DateTime? now}) =>
      Stream.value(days);
}

// ── Timestamp stand-in (parseWorkoutDayLog calls .toDate() dynamically) ──────

class Timestamp {
  final DateTime _d;
  const Timestamp(this._d);
  DateTime toDate() => _d;
}

// ── Fixture generators ──────────────────────────────────────────────────────

final _now = DateTime(2026, 8, 4, 12);
DateTime _ago(int d) => _now.subtract(Duration(days: d));

/// A realistic session: 6 exercises x 4 sets, drawn from a 40-exercise library
/// so `distinctExercises` / `weightedExercises` / `personalBests` all have real
/// grouping work to do rather than collapsing to one key.
Map<String, dynamic> _session(int i) {
  final day = _ago(i);
  return {
    'id': 's$i',
    'date': Timestamp(day),
    'planName': 'Block ${i % 8}',
    'entries': [
      for (var e = 0; e < 6; e++)
        {
          'exerciseName': 'Exercise ${(i * 6 + e) % 40}',
          'exerciseId': 'ex${(i * 6 + e) % 40}',
          'sets': [
            for (var s = 0; s < 4; s++)
              {
                'prescribedReps': '8',
                'prescribedWeight': '${60 + (i % 40)}',
                'actualReps': '${8 - (s % 2)}',
                'actualWeight': '${60 + (i % 40) + s}',
                'completed': true,
              },
          ],
        },
    ],
  };
}

NutritionRollupDay _nutritionDay(int i) => NutritionRollupDay(
  date: DateTime(_ago(i).year, _ago(i).month, _ago(i).day),
  targetAdherence: {'calories': .8 + (i % 20) / 100, 'protein': .9},
  totals: const {'calories': 2100},
  entryCount: 4,
);

RollupDay _lifestyleDay(int i) => RollupDay(
  date: DateTime(_ago(i).year, _ago(i).month, _ago(i).day),
  waterMl: 2000 + (i % 1000).toDouble(),
  steps: 7000 + (i % 5000).toDouble(),
  sleepHours: 6.5 + (i % 12) / 10,
  supplementItems: 2,
  supplementDoses: 3,
);

TransformationEntry _checkpoint(int i) => TransformationEntry(
  id: 'c$i',
  clientId: 'client-1',
  adminId: 'admin-1',
  authUid: 'uid-1',
  recordedAt: _ago(i * 3),
  createdAt: _ago(i * 3),
  updatedAt: _ago(i * 3),
  visibility: TransformationVisibility.shared,
  status: TransformationStatus.complete,
  measurementUnit: 'cm',
  measurements: {'waist': 90 - i % 10, 'chest': 100 + i % 8, 'hips': 95},
  photos: const {},
  weightKg: 82 - (i % 12) * .3,
);

// ── The sweep ───────────────────────────────────────────────────────────────

/// EXACTLY the derived reads one Progress build performs, at the same
/// multiplicities counted from `progress_screen.dart` + `progress_sections.dart`.
///
/// Keep this in step with those two files. If a section starts reading a new
/// derived value, add it here — the whole point is that the budget below is
/// measured against what the screen really does, not a sample of it.
void _oneBuild(ProgressAnalyticsController c) {
  // progress_screen.dart — _overview
  c.score;
  c.dimensions;
  c.verdict;
  c.direction;
  c.momentumOf;
  // progress_screen.dart — _statBand
  c.currentStreak;
  c.currentStreak;
  c.currentStreak;
  c.currentStreak;
  c.trainingDays;
  c.weeklyFrequency;
  // progress_screen.dart — insights section
  c.insights;
  // progress_sections.dart — analytics
  c.workoutSeries;
  c.nutritionSeries;
  c.lifestyleSeries;
  c.weightSeries;
  c.volumeTrend;
  c.volume;
  c.volume;
  c.measurementKeys;
  for (final k in c.measurementKeys) {
    c.measurementFor(k);
  }
  c.exerciseVariety;
  c.exerciseVariety;
  c.strengthOptions;
  c.strengthOptions;
  c.strengthOptions;
  c.strengthExercise;
  c.strengthExercise;
  c.strengthTrend;
  // progress_sections.dart — achievements
  c.bestStreak;
  c.bestStreak;
  c.bestStreak;
  c.bests;
  c.loadedHistoryDays;
}

/// The SAME distinct getters as [_oneBuild], each read EXACTLY ONCE.
///
/// The gap between this and [_oneBuild] is pure redundant recomputation: the
/// screen asks for the same derived value repeatedly and every ask re-walks the
/// member's whole history, because nothing on the controller is memoized.
void _onePassDeduped(ProgressAnalyticsController c) {
  c.score;
  c.dimensions;
  c.verdict;
  c.direction;
  c.momentumOf;
  c.currentStreak;
  c.trainingDays;
  c.weeklyFrequency;
  c.insights;
  c.workoutSeries;
  c.nutritionSeries;
  c.lifestyleSeries;
  c.weightSeries;
  c.volumeTrend;
  c.volume;
  c.measurementKeys;
  for (final k in c.measurementKeys) {
    c.measurementFor(k);
  }
  c.exerciseVariety;
  c.strengthOptions;
  c.strengthExercise;
  c.strengthTrend;
  c.bestStreak;
  c.bests;
  c.loadedHistoryDays;
}

Future<ProgressAnalyticsController> _boot({
  required int sessions,
  required int nutritionDays,
  required int lifestyleDays,
  required int checkpoints,
}) async {
  Get.testMode = true;
  Get.put<MemberController>(_FakeMember());
  Get.put<ProgressController>(
    _FakeTransformation([for (var i = 0; i < checkpoints; i++) _checkpoint(i)]),
  );

  final c = ProgressAnalyticsController(
    workoutLog: _FakeWorkoutLog([for (var i = 0; i < sessions; i++) _session(i)]),
    checkIns: _FakeCheckIns(const []),
    nutritionRollups: _FakeNutrition([
      for (var i = 0; i < nutritionDays; i++) _nutritionDay(i),
    ]),
    lifestyleRollups: _FakeLifestyle([
      for (var i = 0; i < lifestyleDays; i++) _lifestyleDay(i),
    ]),
    clock: () => _now,
  );
  Get.put<ProgressAnalyticsController>(c);
  c.ensureLoaded();
  // Let the fetch + the three stream subscriptions deliver.
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return c;
}

int _medianMicros(
  ProgressAnalyticsController c, {
  int runs = 9,
  void Function(ProgressAnalyticsController)? sweep,
}) {
  final run = sweep ?? _oneBuild;
  final samples = <int>[];
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    run(c);
    sw.stop();
    samples.add(sw.elapsedMicroseconds);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

void main() {
  tearDown(Get.reset);

  test('the sources actually loaded (the measurement is of real data)', () async {
    final c = await _boot(
      sessions: 500,
      nutritionDays: 500,
      lifestyleDays: 500,
      checkpoints: 300,
    );
    expect(c.sessions.length, 500, reason: 'workout sessions did not load');
    expect(c.nutrition.length, 500, reason: 'nutrition rollups did not load');
    expect(c.lifestyle.length, 500, reason: 'lifestyle rollups did not load');
    expect(c.bodyPoints.length, 300, reason: 'transformation did not load');
    expect(c.isLoading, isFalse);
    expect(c.hasPartialFailure, isFalse);
  });

  test('one build recomputes the same answers over and over', () async {
    final c = await _boot(
      sessions: 1000,
      nutritionDays: 500,
      lifestyleDays: 500,
      checkpoints: 300,
    );
    // Warm both paths before timing either, so JIT compilation lands on
    // neither side of the comparison.
    _oneBuild(c);
    _onePassDeduped(c);

    final real = _medianMicros(c);
    final deduped = _medianMicros(c, sweep: _onePassDeduped);
    final waste = real / deduped;
    // ignore: avoid_print
    print(
      'BENCH redundancy @1000: real=${real}us deduped=${deduped}us '
      '${waste.toStringAsFixed(2)}x',
    );

    // A RATIO, not a wall-clock budget: absolute microseconds depend on the
    // machine and make a flaky gate, but "how many times over does one build
    // redo the same work" is a property of the CODE and is stable anywhere.
    expect(
      waste,
      lessThan(1.6),
      reason:
          'One Progress build costs ${waste.toStringAsFixed(2)}x what its own '
          'distinct answers cost, so most of the work is the same derivation '
          'repeated. Every repeat re-walks the member\'s entire history.',
    );
  });

  test('cost grows LINEARLY with history, not quadratically', () async {
    final small = await _boot(
      sessions: 250,
      nutritionDays: 250,
      lifestyleDays: 250,
      checkpoints: 150,
    );
    final smallMicros = _medianMicros(small);
    Get.reset();
    final big = await _boot(
      sessions: 1000,
      nutritionDays: 1000,
      lifestyleDays: 1000,
      checkpoints: 600,
    );
    final bigMicros = _medianMicros(big);
    // ignore: avoid_print
    print('BENCH ratio: 250=${smallMicros}us 1000=${bigMicros}us '
        'factor=${(bigMicros / smallMicros).toStringAsFixed(2)}x for 4x data');
    // 4x the data must not cost more than ~8x the time. Above that the sweep
    // has an O(n^2) term and a heavy user's screen will fall off a cliff.
    expect(
      bigMicros,
      lessThan(smallMicros * 8 + 2000),
      reason:
          '4x the history cost ${(bigMicros / smallMicros).toStringAsFixed(2)}x '
          'the time — superlinear.',
    );
  });
}
