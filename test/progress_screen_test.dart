
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
import 'package:alphaserena/screens/dashboard/progress/progress_sections.dart';
import 'package:alphaserena/screens/dashboard/progress/progress_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// THE PROGRESS SCREEN, driven by the REAL controller and the REAL shared
/// analytics core. Only the four Firestore reads are faked — everything below
/// them (the adapters, the window maths, the confidence gate, the verdict, the
/// insight sentences) is production code.
///
/// That is deliberate, and it is the lesson this repository has already paid
/// for twice: a suite that hands a widget a hand-made view-model passes against
/// a path production never takes. The consistency engine's two-axis defect and
/// the sleep-history outage both survived full green suites for exactly that
/// reason.

// ── Fakes: the network, and nothing else ────────────────────────────────────

class _FakeMember extends MemberController {
  _FakeMember({Map<String, dynamic>? doc, bool linked = true}) {
    client.value = doc ?? const {};
    isLoading.value = false;
    isLinked.value = linked;
  }

  // Deliberately does NOT call super: the real onInit starts the auth and
  // Firestore listeners this fixture exists to avoid.
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> claim() async {}
}

/// The transformation stream's owner, seeded rather than bound.
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
  final bool fail;
  _FakeCheckIns(this.mine, {this.fail = false});

  @override
  Stream<List<CheckInSubmissionModel>> watchMine() =>
      fail ? Stream.error(StateError('denied')) : Stream.value(mine);
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

// ── Fixtures ────────────────────────────────────────────────────────────────

final _now = DateTime(2026, 8, 4, 12);
DateTime _ago(int d) => _now.subtract(Duration(days: d));

/// A raw `client_workout_sessions` document, in the shape Firestore stores.
Map<String, dynamic> _sessionDoc(
  DateTime date, {
  String id = 's',
  String exercise = 'Squat',
  String exerciseId = 'sq',
  List<(String pReps, String pWeight, String aReps, String aWeight, bool done)>
  sets = const [('8', '100', '8', '100', true)],
}) => {
  'id': id,
  'date': Timestamp(date),
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

/// A stand-in for `cloud_firestore`'s Timestamp — `parseWorkoutDayLog` calls
/// `.toDate()` dynamically, so a plain object with that method is enough and
/// keeps the test free of a Firebase app.
class Timestamp {
  final DateTime _d;
  const Timestamp(this._d);
  DateTime toDate() => _d;
}

NutritionRollupDay _nutritionDay(int daysAgo, double adherence) =>
    NutritionRollupDay(
      date: DateTime(
        _ago(daysAgo).year,
        _ago(daysAgo).month,
        _ago(daysAgo).day,
      ),
      targetAdherence: {'calories': adherence, 'protein': adherence},
      totals: const {'calories': 2000},
      entryCount: 4,
    );

TransformationEntry _checkpoint(int daysAgo, {double? weight}) =>
    TransformationEntry(
      id: 'c$daysAgo',
      clientId: 'client-1',
      adminId: 'admin-1',
      authUid: 'uid-1',
      recordedAt: _ago(daysAgo),
      createdAt: _ago(daysAgo),
      updatedAt: _ago(daysAgo),
      visibility: TransformationVisibility.shared,
      status: TransformationStatus.complete,
      measurementUnit: 'cm',
      measurements: const {'waist': 90},
      photos: const {},
      weightKg: weight,
    );

// ── Harness ─────────────────────────────────────────────────────────────────

Future<ProgressAnalyticsController> mount(
  WidgetTester tester, {
  List<Map<String, dynamic>>? sessions = const [],
  List<CheckInSubmissionModel> checkIns = const [],
  List<NutritionRollupDay> nutrition = const [],
  List<RollupDay> lifestyle = const [],
  List<TransformationEntry> transformation = const [],
  Map<String, dynamic>? clientDoc,
  bool linked = true,
  bool failNutrition = false,
  bool failCheckIns = false,
  /// A TALL viewport by default so every section BUILDS. The screen is a lazy
  /// `ListView`, so a phone-height viewport only builds what is above the fold
  /// and a section that is genuinely present would read as absent. The tests
  /// that specifically exercise a real phone, tablet or landscape size pass
  /// their own.
  Size size = const Size(390, 4200),
  double textScale = 1.0,
}) async {
  Get.testMode = true;
  final member = _FakeMember(doc: clientDoc, linked: linked);
  Get.put<MemberController>(member);
  Get.put<ProgressController>(_FakeTransformation(transformation));

  final c = ProgressAnalyticsController(
    workoutLog: _FakeWorkoutLog(sessions),
    checkIns: _FakeCheckIns(checkIns, fail: failCheckIns),
    nutritionRollups: _FakeNutrition(nutrition, fail: failNutrition),
    lifestyleRollups: _FakeLifestyle(lifestyle),
    member: member,
    transformation: Get.find<ProgressController>(),
    clock: () => _now,
  );
  Get.put<ProgressAnalyticsController>(c);

  // THE SURFACE IS SET ON THE VIEW, NOT WRAPPED AROUND THE APP.
  //
  // `GetMaterialApp` builds its OWN `MediaQuery` from the window, so an outer
  // `MediaQuery` widget is silently discarded — every screen below it kept
  // rendering at the harness default (800x600) and every section past the fold
  // read as absent while being perfectly present. Driving `tester.view` is the
  // only thing the app's own MediaQuery inherits. Same class of trap this repo
  // already recorded for Patrol: a hand-made MediaQueryData does not reach
  // `MediaQuery.sizeOf`.
  const dpr = 1.0;
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = size * dpr;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  await tester.pumpWidget(
    GetMaterialApp(theme: AppTheme.dark, home: const ProgressScreen()),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  tearDown(Get.reset);

  group('the shell', () {
    testWidgets('states the one question it answers', (tester) async {
      await mount(tester, sessions: [_sessionDoc(_ago(1))]);
      expect(find.text('Progress'), findsOneWidget);
      expect(find.text('How you are improving over time.'), findsOneWidget);
    });

    testWidgets('offers the three premium shortcuts', (tester) async {
      await mount(tester, sessions: [_sessionDoc(_ago(1))]);
      expect(find.text('Transformation'), findsOneWidget);
      expect(find.text('Weekly check-in'), findsOneWidget);
      expect(find.text('Schedule'), findsOneWidget);
    });

    testWidgets('renders every section in the fixed hierarchy', (tester) async {
      await mount(
        tester,
        sessions: [
          _sessionDoc(_ago(1), id: 'a'),
          _sessionDoc(_ago(3), id: 'b'),
          _sessionDoc(_ago(6), id: 'c'),
        ],
      );
      for (final title in [
        'Analytics',
        'Insights',
        'History',
        'Achievements',
        'Recent activity',
      ]) {
        expect(find.text(title), findsOneWidget, reason: 'missing $title');
      }
    });

    testWidgets('offers all four ranges', (tester) async {
      await mount(tester, sessions: [_sessionDoc(_ago(1))]);
      for (final label in ['Week', 'Month', '3 Months', 'Year']) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });

  group('honest states', () {
    testWidgets('a member with no records is invited, never shown zeroes', (
      tester,
    ) async {
      await mount(tester);
      expect(
        find.text('Your progress starts with one record'),
        findsOneWidget,
      );
      // The cardinal rule: no fabricated grade for a member who has not begun.
      expect(find.text('0%'), findsNothing);
      expect(find.text('Analytics'), findsNothing);
    });

    testWidgets('an unlinked member is asked to connect, not scored', (
      tester,
    ) async {
      await mount(tester, linked: false, sessions: [_sessionDoc(_ago(1))]);
      expect(find.text('Connect to a coach'), findsOneWidget);
      expect(find.text('Analytics'), findsNothing);
    });

    testWidgets('a failing source is NAMED and the rest still renders', (
      tester,
    ) async {
      await mount(
        tester,
        sessions: [
          _sessionDoc(_ago(1), id: 'a'),
          _sessionDoc(_ago(3), id: 'b'),
          _sessionDoc(_ago(6), id: 'c'),
        ],
        failNutrition: true,
      );
      expect(find.byType(ProgressPartialBanner), findsOneWidget);
      expect(find.textContaining('Nutrition could not be loaded'), findsOneWidget);
      // A partial view must still be a useful one.
      expect(find.text('Analytics'), findsOneWidget);
      expect(find.text('Achievements'), findsOneWidget);
    });

    testWidgets('two failing sources are both named', (tester) async {
      await mount(
        tester,
        sessions: [_sessionDoc(_ago(1))],
        failNutrition: true,
        failCheckIns: true,
      );
      expect(
        find.textContaining('Check-ins and Nutrition could not be loaded'),
        findsOneWidget,
      );
    });

    testWidgets('an UNREADABLE session history is a failure, not an empty one', (
      tester,
    ) async {
      // `fetchSessionHistory` answers null when the read could not be served —
      // offline `get()` returns an empty CACHE without throwing. Rendering that
      // as "you have never trained" is the defect this distinction prevents.
      await mount(tester, sessions: null, nutrition: [_nutritionDay(1, 0.9)]);
      expect(find.byType(ProgressPartialBanner), findsOneWidget);
      expect(find.textContaining('Workouts could not be loaded'), findsOneWidget);
    });
  });

  group('the overall card', () {
    testWidgets('shows a real score with its dimension breakdown', (
      tester,
    ) async {
      await mount(
        tester,
        sessions: [
          _sessionDoc(_ago(1), id: 'a'),
          _sessionDoc(_ago(3), id: 'b'),
          _sessionDoc(_ago(6), id: 'c'),
        ],
      );
      // Three perfect sessions = 100% workout quality. It appears twice by
      // design: once as a scored dimension in the overall card, once as a
      // selectable metric in Analytics. Same name, same number, two jobs.
      expect(find.text('Workout quality'), findsWidgets);
      expect(find.textContaining('3 days'), findsWidgets);
    });

    testWidgets('below the sample gate the dimension says "building"', (
      tester,
    ) async {
      await mount(tester, sessions: [_sessionDoc(_ago(1))]);
      expect(find.text('Workout quality'), findsWidgets);
      // One session is under MIN_SAMPLE, so the number is not headlined as
      // trustworthy — it says so instead of quietly presenting itself.
      expect(find.text('building'), findsOneWidget);
    });

    testWidgets('a nutrition-only member is scored on nutrition alone', (
      tester,
    ) async {
      await mount(
        tester,
        nutrition: [
          _nutritionDay(1, 0.9),
          _nutritionDay(2, 0.8),
          _nutritionDay(3, 0.85),
        ],
      );
      expect(find.text('Nutrition'), findsWidgets);
      // A dimension with no data is ABSENT, never present at 0%.
      expect(find.text('Workout quality'), findsNothing);
      expect(find.text('Lifestyle'), findsNothing);
    });

    testWidgets('reports observed training frequency, never a target', (
      tester,
    ) async {
      await mount(
        tester,
        sessions: [
          _sessionDoc(_ago(1), id: 'a'),
          _sessionDoc(_ago(3), id: 'b'),
          _sessionDoc(_ago(6), id: 'c'),
        ],
      );
      expect(find.text('Per week'), findsOneWidget);
      expect(find.text('observed'), findsOneWidget);
      expect(find.text('Training days'), findsOneWidget);
    });
  });

  group('analytics', () {
    testWidgets('a single record shows no trend and says why', (tester) async {
      await mount(tester, sessions: [_sessionDoc(_ago(1))]);
      // One point is not a trend; the section must not draw a line through it.
      expect(find.text('No trends yet'), findsOneWidget);
    });

    testWidgets('a real series becomes a selectable metric', (tester) async {
      await mount(
        tester,
        sessions: [
          _sessionDoc(_ago(1), id: 'a'),
          _sessionDoc(_ago(3), id: 'b'),
        ],
      );
      expect(find.text('Workout quality'), findsWidgets);
      expect(find.textContaining('days recorded'), findsWidgets);
    });

    testWidgets('weight reconciles transformation AND check-in sources', (
      tester,
    ) async {
      // The defect this closes: a member whose weight lives only in check-in
      // packets was told to add more check-ins while their coach saw a trend.
      await mount(
        tester,
        checkIns: [
          CheckInSubmissionModel(
            id: '1',
            clientId: 'c',
            adminId: 'a',
            authorId: 'u',
            clientName: 'Member',
            weightKg: 84,
            ratings: const {},
            note: '',
            photoUrls: const [],
            status: CheckInSubmissionStatus.submitted,
            submittedAt: _ago(20),
          ),
          CheckInSubmissionModel(
            id: '2',
            clientId: 'c',
            adminId: 'a',
            authorId: 'u',
            clientName: 'Member',
            weightKg: 82,
            ratings: const {},
            note: '',
            photoUrls: const [],
            status: CheckInSubmissionStatus.submitted,
            submittedAt: _ago(6),
          ),
        ],
      );
      expect(find.text('Weight'), findsWidgets);
      expect(find.textContaining('Down 2.0 kg'), findsOneWidget);
    });

    testWidgets('a scalar metric carries its unit and its span', (
      tester,
    ) async {
      await mount(
        tester,
        transformation: [
          _checkpoint(20, weight: 84),
          _checkpoint(4, weight: 81.5),
        ],
      );
      expect(find.textContaining('across 2 check-ins'), findsOneWidget);
    });
  });

  group('insights', () {
    testWidgets('every insight shows the evidence behind it', (tester) async {
      await mount(
        tester,
        sessions: [
          _sessionDoc(_ago(1), id: 'a'),
          _sessionDoc(_ago(2), id: 'b'),
          _sessionDoc(_ago(3), id: 'c'),
        ],
      );
      expect(find.byType(ProgressInsightsSection), findsOneWidget);
      // An insight that cannot show its work is an opinion.
      expect(find.textContaining('Consecutive days'), findsOneWidget);
    });

    testWidgets('says nothing rather than inventing something', (
      tester,
    ) async {
      await mount(
        tester,
        nutrition: [_nutritionDay(1, 0.9), _nutritionDay(2, 0.9)],
      );
      // Two nutrition days support a chart but no proven claim.
      expect(find.text('No insights yet'), findsOneWidget);
    });
  });

  group('achievements', () {
    testWidgets('every tile states the window it is true for', (tester) async {
      await mount(
        tester,
        sessions: [
          _sessionDoc(_ago(1), id: 'a'),
          _sessionDoc(_ago(2), id: 'b'),
        ],
      );
      expect(find.text('Workouts'), findsOneWidget);
      expect(find.text('All time'), findsOneWidget);
      // A "best streak" that does not say how far back it looked is a claim
      // the app cannot support.
      expect(find.textContaining('Longest in'), findsOneWidget);
    });

    testWidgets('a personal best carries the date it was set', (tester) async {
      await mount(
        tester,
        sessions: [
          _sessionDoc(_ago(1), id: 'a'),
          _sessionDoc(_ago(2), id: 'b'),
        ],
      );
      expect(find.textContaining('Heaviest set ·'), findsOneWidget);
    });

    testWidgets('nothing recorded means nothing awarded', (tester) async {
      await mount(tester, nutrition: [_nutritionDay(1, 0.9)]);
      expect(find.text('Nothing earned yet'), findsOneWidget);
    });
  });

  group('history shortcuts', () {
    testWidgets('offers all four destinations', (tester) async {
      await mount(tester, sessions: [_sessionDoc(_ago(1))]);
      for (final label in [
        'Workout history',
        'Nutrition history',
        'Lifestyle history',
        'Consistency',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'missing $label');
      }
    });
  });

  group('recent activity', () {
    testWidgets('merges every source, newest first', (tester) async {
      await mount(
        tester,
        sessions: [_sessionDoc(_ago(3), id: 'a')],
        transformation: [_checkpoint(1, weight: 82)],
      );
      expect(find.text('Transformation check-in'), findsOneWidget);
      expect(find.text('Workout logged'), findsOneWidget);
      final feedItems = tester
          .widgetList<ProgressActivitySection>(
            find.byType(ProgressActivitySection),
          )
          .single
          .feed;
      expect(feedItems.first.title, 'Transformation check-in');
    });
  });

  group('resilience', () {
    testWidgets('survives a 320dp phone at 2.0x text scale', (tester) async {
      await mount(
        tester,
        size: const Size(320, 900),
        textScale: 2.0,
        sessions: [
          _sessionDoc(_ago(1), id: 'a'),
          _sessionDoc(_ago(3), id: 'b'),
          _sessionDoc(_ago(6), id: 'c'),
        ],
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the shortcut row survives its widest text before stacking', (
      tester,
    ) async {
      // 1.5x is the LAST scale at which the three shortcuts are still a Row —
      // above 1.6 they stack and the reservation stops mattering. This is the
      // exact branch that overflowed by 18px on the emulator, because
      // IntrinsicHeight measured a two-line label as one line.
      await mount(
        tester,
        size: const Size(360, 2600),
        textScale: 1.5,
        sessions: [_sessionDoc(_ago(1), id: 'a'), _sessionDoc(_ago(3), id: 'b')],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Transformation'), findsOneWidget);
    });

    testWidgets('the shortcut row survives its narrowest width', (
      tester,
    ) async {
      await mount(
        tester,
        size: const Size(300, 2600),
        sessions: [_sessionDoc(_ago(1), id: 'a'), _sessionDoc(_ago(3), id: 'b')],
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a tablet width', (tester) async {
      await mount(
        tester,
        size: const Size(1024, 1300),
        sessions: [_sessionDoc(_ago(1), id: 'a'), _sessionDoc(_ago(3), id: 'b')],
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives landscape', (tester) async {
      await mount(
        tester,
        size: const Size(900, 390),
        sessions: [_sessionDoc(_ago(1), id: 'a'), _sessionDoc(_ago(3), id: 'b')],
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching range does not throw and re-renders', (
      tester,
    ) async {
      final c = await mount(
        tester,
        sessions: [
          _sessionDoc(_ago(1), id: 'a'),
          _sessionDoc(_ago(3), id: 'b'),
          _sessionDoc(_ago(40), id: 'old'),
        ],
      );
      expect(c.range.value, ProgressRange.month);
      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();
      expect(c.range.value, ProgressRange.year);
      expect(tester.takeException(), isNull);
      // The 40-day-old session is outside a month and inside a year.
      expect(c.trainingDays, 3);
    });
  });
}
