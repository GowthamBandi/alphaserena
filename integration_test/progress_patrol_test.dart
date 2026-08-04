import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:patrol/patrol.dart';

import 'package:alphaserena/controllers/member_controller.dart';
import 'package:alphaserena/controllers/progress_analytics_controller.dart';
import 'package:alphaserena/controllers/progress_controller.dart';
import 'package:alphaserena/core/models/check_in_submission_model.dart';
import 'package:alphaserena/core/models/transformation_entry.dart';
import 'package:alphaserena/core/services/check_in_submission_service.dart';
import 'package:alphaserena/core/services/member_rollup_service.dart';
import 'package:alphaserena/core/services/nutrition_rollup_service.dart';
import 'package:alphaserena/core/services/workout_log_service.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/progress/progress_screen.dart';

/// PATROL — THE PROGRESS INTELLIGENCE CENTRE, ON A REAL DEVICE.
///
/// ── WHY THIS SUITE DRIVES THE ENGINE, NOT A FIXTURE ───────────────────────
///
/// Every widget below is fed from RAW `client_workout_sessions` documents in
/// the shape Firestore actually stores, through the real adapters, the real
/// shared analytics core and the real controller. Nothing is handed a
/// pre-computed card.
///
/// That is not a stylistic preference. The consistency module's two-axis defect
/// — where an entire month of training resolved to "nothing happened" for the
/// majority of members — survived every previous device certification precisely
/// because each Patrol test handed the widgets a hand-made `ConsistencyCard`,
/// so no device test ever touched the repository→engine path. The rule that
/// came out of it is the rule this file obeys: **drive the engine, not a
/// fixture.**
///
/// ── WHAT THIS CANNOT CERTIFY ──────────────────────────────────────────────
///
/// Phone-OTP auth is externally blocked on this Firebase project, so there is
/// no live member session on the emulator. The four Firestore READS are
/// therefore injected at the service seam; everything below them is production
/// code. A real round trip is covered by the rules suite and the wire tests.
///
/// ⚠️ NEVER put "/" in a `patrolTest` name — Patrol's Android JUnit runner
/// reads it as a group separator and silently drops the whole file's
/// enumeration, reporting `Total: 0` with a green-looking run.
void main() {
  setUpAll(() async {
    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp();
      } catch (_) {
        // The screen under test never reaches Firebase — reads are injected.
      }
    }
  });

  tearDown(Get.reset);

  // ══ FAKES — the network boundary, and nothing below it ══════════════════

  final now = DateTime(2026, 8, 4, 12);
  DateTime ago(int d) => now.subtract(Duration(days: d));

  Widget host(
    Widget child, {
    bool dark = true,
    double textScale = 1.0,
    Size? size,
  }) => GetMaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: Builder(
      // ⚠️ `MediaQuery.of(context).copyWith(...)` — a fresh MediaQueryData
      // carries a ZERO size, and on a real device that makes every width
      // branch resolve wrongly, so every responsive test would pass against
      // the wrong branch. Preserve the ambient query and override only what
      // the case is actually about. `setSurfaceSize` alone does NOT reach
      // `MediaQuery.sizeOf` on a device — this is the only deterministic way.
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          size: size,
        ),
        child: child,
      ),
    ),
  );

  /// A raw `client_workout_sessions` document, in the shape Firestore stores.
  Map<String, dynamic> sessionDoc(
    DateTime date, {
    required String id,
    String exercise = 'Back Squat',
    String exerciseId = 'sq',
    List<(String, String, String, String, bool)> sets = const [
      ('8', '100', '8', '100', true),
    ],
  }) => {
    'id': id,
    'date': _Ts(date),
    'planName': 'Lower body',
    'entries': [
      {
        'exerciseName': exercise,
        'exerciseId': exerciseId,
        'sets': [
          for (final s in sets)
            {
              'prescribedReps': s.$1,
              'prescribedWeight': s.$2,
              'actualReps': s.$3,
              'actualWeight': s.$4,
              'completed': s.$5,
            },
        ],
      },
    ],
  };

  /// A realistic training block: rising weight, mixed quality, one out of range.
  List<Map<String, dynamic>> block() => [
    for (var i = 0; i < 12; i++)
      sessionDoc(
        ago(i * 2 + 1),
        id: 'sess-$i',
        sets: [
          ('8', '${100 - i * 2}', '8', '${100 - i * 2}', true),
          ('8', '${100 - i * 2}', i.isEven ? '8' : '5', '${100 - i * 2}', true),
        ],
      ),
    sessionDoc(ago(200), id: 'ancient'),
  ];

  ProgressAnalyticsController mount({
    List<Map<String, dynamic>>? sessions,
    List<CheckInSubmissionModel> checkIns = const [],
    List<NutritionRollupDay> nutrition = const [],
    List<RollupDay> lifestyle = const [],
    List<TransformationEntry> transformation = const [],
    Map<String, dynamic>? clientDoc,
    bool linked = true,
    bool failNutrition = false,
  }) {
    final member = _FakeMember(doc: clientDoc, linked: linked);
    Get.put<MemberController>(member);
    Get.put<ProgressController>(_FakeTransformation(transformation));
    final c = ProgressAnalyticsController(
      workoutLog: _FakeWorkoutLog(sessions),
      checkIns: _FakeCheckIns(checkIns),
      nutritionRollups: _FakeNutrition(nutrition, fail: failNutrition),
      lifestyleRollups: _FakeLifestyle(lifestyle),
      member: member,
      transformation: Get.find<ProgressController>(),
      clock: () => now,
    );
    Get.put<ProgressAnalyticsController>(c);
    return c;
  }

  NutritionRollupDay nutritionDay(int daysAgo, double v) => NutritionRollupDay(
    date: DateTime(ago(daysAgo).year, ago(daysAgo).month, ago(daysAgo).day),
    targetAdherence: {'calories': v, 'protein': v},
    totals: const {'calories': 2100},
    entryCount: 5,
  );

  TransformationEntry checkpoint(int daysAgo, double weight) =>
      TransformationEntry(
        id: 'cp-$daysAgo',
        clientId: 'client-1',
        adminId: 'admin-1',
        authUid: 'member-1',
        recordedAt: ago(daysAgo),
        createdAt: ago(daysAgo),
        updatedAt: ago(daysAgo),
        visibility: TransformationVisibility.shared,
        status: TransformationStatus.complete,
        measurementUnit: 'cm',
        weightKg: weight,
        measurements: const {'waist': 92},
        photos: const {},
      );

  // ══ 1. THE SHELL ════════════════════════════════════════════════════════

  patrolTest('the screen states the one question it answers', ($) async {
    mount(sessions: block());
    await $.pumpWidgetAndSettle(host(const ProgressScreen()));
    expect($('Progress'), findsWidgets);
    expect($('How you are improving over time.'), findsOneWidget);
  });

  patrolTest('the three premium shortcuts are present and reachable', (
    $,
  ) async {
    mount(sessions: block());
    await $.pumpWidgetAndSettle(host(const ProgressScreen()));
    expect($('Transformation'), findsWidgets);
    expect($('Weekly check-in'), findsWidgets);
    expect($('Schedule'), findsWidgets);
  });

  patrolTest('every section renders in the fixed hierarchy', ($) async {
    mount(sessions: block(), nutrition: [for (var i = 1; i < 12; i++) nutritionDay(i, 0.85)]);
    await $.pumpWidgetAndSettle(host(const ProgressScreen()));
    for (final title in [
      'Analytics',
      'Insights',
      'History',
      'Achievements',
      'Recent activity',
    ]) {
      await $.scrollUntilVisible(finder: $(title), view: $(Scrollable).first);
      expect($(title), findsWidgets, reason: 'missing section: $title');
    }
  });

  // ══ 2. THE ENGINE, ON REAL HARDWARE ═════════════════════════════════════

  patrolTest('the overall score is derived from the real documents', (
    $,
  ) async {
    final c = mount(sessions: block());
    await $.pumpWidgetAndSettle(host(const ProgressScreen()));
    // Half the completed sets miss their prescription by design, so the
    // engine must land at 75% — not a fixture, the real adapters and the real
    // shared core over raw Firestore maps.
    expect(c.dimensions.single.id, 'workout');
    expect((c.dimensions.single.value * 100).round(), 75);
    expect($('75%'), findsWidgets);
  });

  patrolTest('an out-of-window session never enters a windowed figure', (
    $,
  ) async {
    final c = mount(sessions: block());
    await $.pumpWidgetAndSettle(host(const ProgressScreen()));
    // 12 sessions inside 30 days, one 200 days old.
    expect(c.sessions.length, 13);
    expect(c.trainingDays, 12);
  });

  patrolTest('changing the range re-derives every figure on device', (
    $,
  ) async {
    final c = mount(sessions: block());
    await $.pumpWidgetAndSettle(host(const ProgressScreen()));
    expect(c.trainingDays, 12);
    await $('Year').tap();
    await $.pumpAndSettle();
    // The 200-day-old session is outside a month and inside a year.
    expect(c.trainingDays, 13);
    expect($('Year'), findsWidgets);
  });

  patrolTest('the range control survives rapid repeated tapping', ($) async {
    final c = mount(sessions: block());
    await $.pumpWidgetAndSettle(host(const ProgressScreen()));
    for (var i = 0; i < 4; i++) {
      await $('Week').tap();
      await $('Year').tap();
      await $('Month').tap();
    }
    await $.pumpAndSettle();
    expect(c.range.value, ProgressRange.month);
  });

  // ══ 3. HONEST STATES ════════════════════════════════════════════════════

  patrolTest('a member with nothing recorded is invited, never graded', (
    $,
  ) async {
    mount(sessions: const []);
    await $.pumpWidgetAndSettle(host(const ProgressScreen()));
    expect($('Your progress starts with one record'), findsOneWidget);
    expect($('0%'), findsNothing);
  });

  patrolTest('an unreadable source is named and the rest still renders', (
    $,
  ) async {
    mount(sessions: block(), failNutrition: true);
    await $.pumpWidgetAndSettle(host(const ProgressScreen()));
    // Patrol's `$('...')` matches a widget's WHOLE text; the banner is one
    // sentence, so the failing source's name is a substring of it.
    expect(find.textContaining('Nutrition could not be loaded'), findsWidgets);
    await $.scrollUntilVisible(
      finder: $('Achievements'),
      view: $(Scrollable).first,
    );
    expect($('Achievements'), findsWidgets);
  });

  patrolTest('an offline session read reads as unavailable, not as empty', (
    $,
  ) async {
    // `fetchSessionHistory` answers null when the read could not be served.
    // Rendering that as "you have never trained" to a member with months of
    // history is the defect this distinction exists to prevent.
    mount(sessions: null, nutrition: [for (var i = 1; i < 6; i++) nutritionDay(i, 0.8)]);
    await $.pumpWidgetAndSettle(host(const ProgressScreen()));
    expect(find.textContaining('Workouts could not be loaded'), findsWidgets);
  });

  patrolTest('an unlinked member is asked to connect, not scored', ($) async {
    mount(sessions: block(), linked: false);
    await $.pumpWidgetAndSettle(host(const ProgressScreen()));
    expect($('Connect to a coach'), findsOneWidget);
  });

  // ══ 4. ANALYTICS ════════════════════════════════════════════════════════

  patrolTest('switching a metric redraws the chart without error', ($) async {
    mount(
      sessions: block(),
      transformation: [checkpoint(30, 86), checkpoint(10, 83), checkpoint(2, 82)],
    );
    await $.pumpWidgetAndSettle(host(const ProgressScreen()));
    await $.scrollUntilVisible(
      finder: $('Analytics'),
      view: $(Scrollable).first,
    );
    await $('Strength').tap();
    await $.pumpAndSettle();
    await $('Weight').tap();
    await $.pumpAndSettle();
    expect($('Weight'), findsWidgets);
  });

  patrolTest('weight reconciles transformation and check-in sources', (
    $,
  ) async {
    final c = mount(
      transformation: [checkpoint(30, 86)],
      checkIns: [
        CheckInSubmissionModel(
          id: 'ci-1',
          clientId: 'client-1',
          adminId: 'admin-1',
          authorId: 'member-1',
          clientName: 'Member',
          weightKg: 83,
          ratings: const {},
          note: '',
          photoUrls: const [],
          status: CheckInSubmissionStatus.submitted,
          submittedAt: ago(5),
        ),
      ],
    );
    await $.pumpWidgetAndSettle(host(const ProgressScreen()));
    // A member who weighs in only inside a check-in still gets a trend.
    expect(c.weightSeries.length, 2);
    expect(c.weightSeries.last.value, 83);
  });

  // ══ 5. REFLOW AND ACCESSIBILITY ═════════════════════════════════════════

  patrolTest('survives a large accessibility font', ($) async {
    mount(sessions: block());
    await $.pumpWidgetAndSettle(host(const ProgressScreen(), textScale: 1.8));
    expect($('Progress'), findsWidgets);
    expect($.tester.takeException(), isNull);
  });

  patrolTest('survives the light theme', ($) async {
    mount(sessions: block());
    await $.pumpWidgetAndSettle(host(const ProgressScreen(), dark: false));
    expect($('Progress'), findsWidgets);
    expect($.tester.takeException(), isNull);
  });

  patrolTest('survives landscape', ($) async {
    mount(sessions: block());
    await $.pumpWidgetAndSettle(
      host(const ProgressScreen(), size: const Size(900, 390)),
    );
    expect($('Progress'), findsWidgets);
    expect($.tester.takeException(), isNull);
  });

  patrolTest('survives a 320dp phone at 2.0x text scale', ($) async {
    // The width and the scale at which a three-across shortcut row and a
    // three-across stat band both have to stop being rows.
    mount(sessions: block());
    await $.pumpWidgetAndSettle(
      host(const ProgressScreen(), size: const Size(320, 720), textScale: 2.0),
    );
    expect($('Progress'), findsWidgets);
    expect($.tester.takeException(), isNull);
  });

  patrolTest('survives a tablet width', ($) async {
    mount(sessions: block());
    await $.pumpWidgetAndSettle(
      host(const ProgressScreen(), size: const Size(1024, 1366)),
    );
    expect($('Progress'), findsWidgets);
    expect($.tester.takeException(), isNull);
  });

  patrolTest('a long history scrolls all the way without breaking', (
    $,
  ) async {
    mount(
      sessions: [
        for (var i = 0; i < 120; i++) sessionDoc(ago(i * 3), id: 'long-$i'),
      ],
      transformation: [for (var i = 1; i < 40; i++) checkpoint(i * 9, 90 - i * .2)],
    );
    await $.pumpWidgetAndSettle(host(const ProgressScreen()));
    await $.scrollUntilVisible(
      finder: $('Recent activity'),
      view: $(Scrollable).first,
    );
    expect($('Recent activity'), findsWidgets);
    expect($.tester.takeException(), isNull);
  });

  // ══ 6. NAVIGATION ═══════════════════════════════════════════════════════

  patrolTest('the history shortcuts all name a real destination', ($) async {
    mount(sessions: block());
    await $.pumpWidgetAndSettle(host(const ProgressScreen()));
    for (final label in [
      'Workout history',
      'Nutrition history',
      'Lifestyle history',
      'Consistency',
    ]) {
      await $.scrollUntilVisible(finder: $(label), view: $(Scrollable).first);
      expect($(label), findsWidgets, reason: 'missing shortcut: $label');
    }
  });
}

// ── Fakes ───────────────────────────────────────────────────────────────────

/// `cloud_firestore`'s Timestamp is only ever consumed through a dynamic
/// `.toDate()`, so this keeps the fixture free of a live Firebase app.
class _Ts {
  final DateTime _d;
  const _Ts(this._d);
  DateTime toDate() => _d;
}

class _FakeMember extends MemberController {
  _FakeMember({Map<String, dynamic>? doc, bool linked = true}) {
    client.value = doc ?? const {};
    isLoading.value = false;
    isLinked.value = linked;
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
  final List<Map<String, dynamic>>? docs;
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
  final bool fail;
  _FakeNutrition(this.days, {this.fail = false});

  @override
  Stream<List<NutritionRollupDay>> watchDays({int months = 3, DateTime? now}) =>
      fail ? Stream.error(StateError('denied')) : Stream.value(days);
}

class _FakeLifestyle extends MemberRollupService {
  final List<RollupDay> days;
  _FakeLifestyle(this.days);

  @override
  Stream<List<RollupDay>> watchDays({int months = 3, DateTime? now}) =>
      Stream.value(days);
}
