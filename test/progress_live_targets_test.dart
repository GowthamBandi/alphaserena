// ═══════════════════════════════════════════════════════════════════════════
// PROGRESS MUST SCORE AGAINST THE COACH'S *CURRENT* LIFESTYLE GOALS
// ═══════════════════════════════════════════════════════════════════════════
//
// The lifestyle adherence ratio is `met / asked`, where BOTH sides come from
// two different documents that change independently:
//
//   • the VALUES come from `coaching_rollups` (server-derived, changes when the
//     member logs something), and
//   • the GOALS come from `clients/{id}.lifestyleTargets` + `.supplementPlan`
//     (coach-authored, changes when the COACH edits them).
//
// `ProgressAnalyticsController._bindRollups` reads the goals INSIDE the rollup
// stream's listener. That binds the goal snapshot to the moment a rollup
// arrives, so a coach's edit cannot reach the member's score until the member
// happens to log something else.
//
// `LifestyleHistoryController` already solved exactly this — it carries a
// `_signature()` over `lifestyleTargets` + stack length and invalidates its memo
// when they change. Progress is the surface that missed it.
//
// This is also a CROSS-APP DRIFT: TrainerHQ scores the same member against the
// goals as they are NOW, so until the member logs again the two apps quote
// different lifestyle numbers for the same person on the same day.

import 'package:alphaserena/controllers/member_controller.dart';
import 'package:alphaserena/controllers/progress_analytics_controller.dart';
import 'package:alphaserena/controllers/progress_controller.dart';
import 'package:alphaserena/core/models/check_in_submission_model.dart';
import 'package:alphaserena/core/services/check_in_submission_service.dart';
import 'package:alphaserena/core/services/member_rollup_service.dart';
import 'package:alphaserena/core/services/nutrition_rollup_service.dart';
import 'package:alphaserena/core/services/workout_log_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _FakeMember extends MemberController {
  _FakeMember(Map<String, dynamic> doc) {
    client.value = doc;
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
  _FakeTransformation() {
    isLoading.value = false;
  }

  @override
  // ignore: must_call_super
  void onInit() {}
}

class _FakeWorkoutLog extends WorkoutLogService {
  @override
  Future<List<Map<String, dynamic>>?> fetchSessionHistory() async => const [];
}

class _FakeCheckIns extends CheckInSubmissionService {
  @override
  Stream<List<CheckInSubmissionModel>> watchMine() =>
      Stream.value(const <CheckInSubmissionModel>[]);
}

class _FakeNutrition extends NutritionRollupService {
  @override
  Stream<List<NutritionRollupDay>> watchDays({int months = 3, DateTime? now}) =>
      Stream.value(const <NutritionRollupDay>[]);
}

/// A rollup feed that emits ONCE and then stays quiet — which is exactly what
/// the real `coaching_rollups` listener does between member logs, and is the
/// condition the defect needs.
class _QuietLifestyle extends MemberRollupService {
  final List<RollupDay> days;
  int subscriptions = 0;
  _QuietLifestyle(this.days);

  @override
  Stream<List<RollupDay>> watchDays({int months = 3, DateTime? now}) {
    subscriptions++;
    return Stream.value(days);
  }
}

final _now = DateTime(2026, 8, 4, 12);

/// Ten days on which the member walked 9,000 steps and drank 2,000ml.
List<RollupDay> _tenDays() => [
  for (var i = 1; i <= 10; i++)
    RollupDay(
      date: DateTime(
        _now.subtract(Duration(days: i)).year,
        _now.subtract(Duration(days: i)).month,
        _now.subtract(Duration(days: i)).day,
      ),
      steps: 9000,
      waterMl: 2000,
    ),
];

Future<ProgressAnalyticsController> _boot(
  Map<String, dynamic> clientDoc,
  _QuietLifestyle lifestyle,
) async {
  Get.testMode = true;
  final member = _FakeMember(clientDoc);
  Get.put<MemberController>(member);
  Get.put<ProgressController>(_FakeTransformation());
  final c = ProgressAnalyticsController(
    workoutLog: _FakeWorkoutLog(),
    checkIns: _FakeCheckIns(),
    nutritionRollups: _FakeNutrition(),
    lifestyleRollups: lifestyle,
    member: member,
    transformation: Get.find<ProgressController>(),
    clock: () => _now,
  );
  Get.put<ProgressAnalyticsController>(c);
  c.onInit();
  c.ensureLoaded();
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return c;
}

double? _lifestyleScore(ProgressAnalyticsController c) {
  for (final d in c.dimensions) {
    if (d.id == 'lifestyle') return d.value;
  }
  return null;
}

void main() {
  tearDown(Get.reset);

  test('baseline: a 10,000-step goal the member misses scores 0', () async {
    final lifestyle = _QuietLifestyle(_tenDays());
    final c = await _boot({
      'adminId': 'admin-1',
        'lifestyleTargets': {'stepsTarget': 10000},
    }, lifestyle);
    expect(_lifestyleScore(c), 0.0);
  });

  test('baseline: an 8,000-step goal the member beats scores 1', () async {
    final lifestyle = _QuietLifestyle(_tenDays());
    final c = await _boot({
      'adminId': 'admin-1',
        'lifestyleTargets': {'stepsTarget': 8000},
    }, lifestyle);
    expect(_lifestyleScore(c), 1.0);
  });

  test(
    'a coach LOWERING the step goal reaches the member without a new rollup',
    () async {
      final lifestyle = _QuietLifestyle(_tenDays());
      final member = _FakeMember({
        'adminId': 'admin-1',
        'lifestyleTargets': {'stepsTarget': 10000},
      });
      Get.testMode = true;
      Get.put<MemberController>(member);
      Get.put<ProgressController>(_FakeTransformation());
      final c = ProgressAnalyticsController(
        workoutLog: _FakeWorkoutLog(),
        checkIns: _FakeCheckIns(),
        nutritionRollups: _FakeNutrition(),
        lifestyleRollups: lifestyle,
        member: member,
        transformation: Get.find<ProgressController>(),
        clock: () => _now,
      );
      Get.put<ProgressAnalyticsController>(c);
      c.onInit();
      c.ensureLoaded();
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(_lifestyleScore(c), 0.0, reason: 'baseline: goal is missed');

      // THE COACH EDITS THE TARGET. `clients/{id}` is a LIVE listener in
      // production, so this is exactly what the member's device receives —
      // the same document identity, a new targets map, and NO new rollup.
      member.client.value = {
        'adminId': 'admin-1',
        'lifestyleTargets': {'stepsTarget': 8000},
      };
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        _lifestyleScore(c),
        1.0,
        reason:
            'The coach lowered the step goal to 8,000 and the member walked '
            '9,000 every day. Progress still scores them against the OLD '
            '10,000 goal, so the member sees 0% Lifestyle while their coach '
            'sees 100% for the same days.',
      );
    },
  );

  test(
    'a coach ADDING a supplement stack reaches the member without a new rollup',
    () async {
      final lifestyle = _QuietLifestyle(_tenDays());
      final member = _FakeMember({
        'adminId': 'admin-1',
        'lifestyleTargets': {'stepsTarget': 8000},
      });
      Get.testMode = true;
      Get.put<MemberController>(member);
      Get.put<ProgressController>(_FakeTransformation());
      final c = ProgressAnalyticsController(
        workoutLog: _FakeWorkoutLog(),
        checkIns: _FakeCheckIns(),
        nutritionRollups: _FakeNutrition(),
        lifestyleRollups: lifestyle,
        member: member,
        transformation: Get.find<ProgressController>(),
        clock: () => _now,
      );
      Get.put<ProgressAnalyticsController>(c);
      c.onInit();
      c.ensureLoaded();
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(_lifestyleScore(c), 1.0);

      // A stack the member has taken NONE of: the denominator grows, so the
      // honest score halves.
      member.client.value = {
        'adminId': 'admin-1',
        'lifestyleTargets': {'stepsTarget': 8000},
        'supplementPlan': [
          {'id': 'a', 'name': 'Creatine'},
        ],
      };
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        _lifestyleScore(c),
        0.5,
        reason:
            'The coach prescribed a supplement the member is not taking. '
            'Progress still scores only the step goal, so it reports 100% '
            'against an ask the member is only half meeting.',
      );
    },
  );

  test(
    'a client-document change that touches NO goal costs no re-subscription',
    () async {
      final lifestyle = _QuietLifestyle(_tenDays());
      final member = _FakeMember({
        'adminId': 'admin-1',
        'lifestyleTargets': {'stepsTarget': 8000},
        'clientName': 'Old',
      });
      Get.testMode = true;
      Get.put<MemberController>(member);
      Get.put<ProgressController>(_FakeTransformation());
      final c = ProgressAnalyticsController(
        workoutLog: _FakeWorkoutLog(),
        checkIns: _FakeCheckIns(),
        nutritionRollups: _FakeNutrition(),
        lifestyleRollups: lifestyle,
        member: member,
        transformation: Get.find<ProgressController>(),
        clock: () => _now,
      );
      Get.put<ProgressAnalyticsController>(c);
      c.onInit();
      c.ensureLoaded();
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final before = lifestyle.subscriptions;

      // A coach renaming the member, or ANY unrelated field landing on the
      // live `clients` listener, must not cost a Firestore re-read.
      member.client.value = {
        'adminId': 'admin-1',
        'lifestyleTargets': {'stepsTarget': 8000},
        'clientName': 'New',
      };
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        lifestyle.subscriptions,
        before,
        reason:
            'An unrelated field change re-subscribed the rollup listener — '
            'every coach edit would cost the member a fresh read.',
      );
      expect(_lifestyleScore(c), 1.0);
    },
  );
}
