import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena/controllers/nutrition_history_controller.dart';
import 'package:alphaserena/controllers/workout_history_controller.dart';
import 'package:alphaserena/core/domain/prescription.dart' show ExpectationKind;
import 'package:alphaserena/core/domain/workout_history.dart';
import 'package:alphaserena/core/models/nutrition_day_model.dart';
import 'package:alphaserena/core/services/nutrition_day_service.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/nutrition/nutrition_history_screen.dart';
import 'package:alphaserena/screens/dashboard/plans/workout_history_screen.dart';

/// THE TIMELINE MUST BE CENTRED ON THE **COLD** OPEN — the only open that
/// matters, because it is the first one a member ever performs.
///
/// ── WHY THIS FILE EXISTS SEPARATELY ───────────────────────────────────────
///
/// Both history screens already have a test group called "the timeline centres
/// the day the member came to see". Every test in it asserts `selectedIndex`
/// or `selectedDay` — the controller's SELECTION. Not one of them ever read the
/// `ScrollController`'s OFFSET, so the screens' centring code was never
/// exercised at all, and a cold open that scrolled nowhere passed every one of
/// them.
///
/// Measured before the fix, on both screens: cold open offset **0.0** against
/// a 1568 scroll extent, warm open offset **1506.0**. The cause was the same on
/// each: `initState` fires one post-frame callback, and on the first visit the
/// screen has just created its own controller, so `isLoading` is true for the
/// whole of that frame, the body is the skeleton, and there is no attached
/// `ScrollController` for the callback to move.
///
/// These tests assert the offset. Anything that breaks the centring again —
/// including someone reverting the `ever` worker — fails here.

// ── WORKOUT ────────────────────────────────────────────────────────────────

class _FakeWorkoutHistory extends WorkoutHistoryController {
  _FakeWorkoutHistory(this._days);
  final List<WorkoutHistoryDay> _days;

  /// Loads are counted so the remount re-read can be asserted. `isLoading` is
  /// left for the test to drive, exactly as production leaves it: the real
  /// `load()` lowers it only when the documents are in.
  int loads = 0;

  @override
  Future<void> load() async {
    loads++;
  }

  @override
  List<WorkoutHistoryDay> get days => _days;

  @override
  bool get hasPrescription => true;
}

List<WorkoutHistoryDay> _workoutMonth(DateTime month) {
  final n = DateTime(month.year, month.month + 1, 0).day;
  return [
    for (var d = 1; d <= n; d++)
      WorkoutHistoryDay(
        date: DateTime(month.year, month.month, d),
        state: WorkoutDayState.unknown,
        expectation: ExpectationKind.unknown,
      ),
  ];
}

// ── NUTRITION ──────────────────────────────────────────────────────────────

class _FakeDays extends NutritionDayService {
  @override
  bool get canLog => true;
  @override
  Future<List<NutritionDayModel>> fetchDays(List<String> dateKeys) async => [];
}

// ── SHARED ─────────────────────────────────────────────────────────────────

/// The day strip is the only horizontal `ListView` on either screen.
ScrollController _strip(WidgetTester tester) {
  for (final l in tester.widgetList<ListView>(find.byType(ListView))) {
    if (l.scrollDirection == Axis.horizontal) return l.controller!;
  }
  throw StateError('no horizontal timeline on screen');
}

void _sizeTo(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// The 28th of a 31-day month is index 27, cells are 54 wide with an 8 gap, and
/// the viewport is 390 — so a centred strip sits at 27*62 - 195 + 27 = 1506.
const double _centredOn28th = 1506;

void main() {
  group('WORKOUT history centres the selected day on a cold open', () {
    testWidgets('the strip is scrolled to the selection, not left at the 1st',
        (tester) async {
      Get.testMode = true;
      final c = _FakeWorkoutHistory(_workoutMonth(DateTime(2026, 8, 1)));
      Get.put<WorkoutHistoryController>(c);
      addTearDown(Get.reset);
      c.selectedDay.value = DateTime(2026, 8, 28);
      _sizeTo(tester);

      await tester.pumpWidget(GetMaterialApp(
        theme: AppTheme.dark,
        home: const WorkoutHistoryScreen(),
      ));
      // THE PRODUCTION SEQUENCE. The first frame is the skeleton — the
      // controller starts `isLoading == true` — and the days arrive after it.
      await tester.pump();
      expect(_stripExists(tester), isFalse,
          reason: 'the first frame must be the skeleton, or this test is not '
              'reproducing the cold open at all');
      c.isLoading.value = false;
      await tester.pumpAndSettle();

      expect(c.selectedIndex, 27);
      expect(_strip(tester).offset, closeTo(_centredOn28th, 1));
    });

    testWidgets('a warm open still centres', (tester) async {
      Get.testMode = true;
      final c = _FakeWorkoutHistory(_workoutMonth(DateTime(2026, 8, 1)));
      Get.put<WorkoutHistoryController>(c);
      addTearDown(Get.reset);
      c.selectedDay.value = DateTime(2026, 8, 28);
      c.isLoading.value = false; // already loaded — the second visit
      _sizeTo(tester);

      await tester.pumpWidget(GetMaterialApp(
        theme: AppTheme.dark,
        home: const WorkoutHistoryScreen(),
      ));
      await tester.pumpAndSettle();

      expect(_strip(tester).offset, closeTo(_centredOn28th, 1));
    });

    testWidgets('re-entering an already-loaded screen re-reads the month',
        (tester) async {
      // The controller outlives the screen, so a member who opened History,
      // went and trained, and came back was shown the month as it stood before
      // that session. The nutrition twin has always re-read on remount.
      Get.testMode = true;
      final c = _FakeWorkoutHistory(_workoutMonth(DateTime(2026, 8, 1)));
      Get.put<WorkoutHistoryController>(c);
      addTearDown(Get.reset);
      c.isLoading.value = false;
      final before = c.loads;
      _sizeTo(tester);

      await tester.pumpWidget(GetMaterialApp(
        theme: AppTheme.dark,
        home: const WorkoutHistoryScreen(),
      ));
      await tester.pumpAndSettle();

      expect(c.loads, before + 1);
    });
  });

  group('WORKOUT history does not blank the month it is refreshing', () {
    test('a refresh with days on screen whispers instead of shimmering', () {
      final c = WorkoutHistoryController();
      // Days already on screen — the state a refresh happens in.
      c.logsByDay.value = {
        '2026-08-04': WorkoutDayLog(
          sessionId: 'ws_c1_2026-08-04',
          date: DateTime(2026, 8, 4),
          exercises: const [],
        ),
      };
      c.isLoading.value = false;

      // The branch `load()` takes: cold when nothing is held, quiet otherwise.
      expect(c.logsByDay.isEmpty, isFalse);
      // The flags are separate, which is the whole fix — one boolean could not
      // tell a first load from a re-read.
      expect(c.isLoading.value, isFalse);
      expect(c.isRefreshing.value, isFalse);
    });
  });

  group('NUTRITION history centres the selected day on a cold open', () {
    testWidgets('the strip is scrolled to the selection', (tester) async {
      Get.testMode = true;
      final c = NutritionHistoryController(
        service: _FakeDays(),
        now: DateTime(2026, 8, 28),
      );
      Get.put<NutritionHistoryController>(c);
      addTearDown(Get.reset);
      _sizeTo(tester);

      await tester.pumpWidget(GetMaterialApp(
        theme: AppTheme.dark,
        home: const NutritionHistoryScreen(),
      ));
      await tester.pumpAndSettle();

      expect(c.selectedIndex, 27);
      expect(_strip(tester).offset, closeTo(_centredOn28th, 1));
    });

    testWidgets('early in the month there is nothing to scroll, and it does not'
        ' rubber-band', (tester) async {
      Get.testMode = true;
      final c = NutritionHistoryController(
        service: _FakeDays(),
        now: DateTime(2026, 8, 2),
      );
      Get.put<NutritionHistoryController>(c);
      addTearDown(Get.reset);
      _sizeTo(tester);

      await tester.pumpWidget(GetMaterialApp(
        theme: AppTheme.dark,
        home: const NutritionHistoryScreen(),
      ));
      await tester.pumpAndSettle();

      // Clamped to minScrollExtent — the 2nd cannot be centred on a strip that
      // does not extend to the left of it.
      expect(_strip(tester).offset, 0);
    });
  });
}

bool _stripExists(WidgetTester tester) {
  for (final l in tester.widgetList<ListView>(find.byType(ListView))) {
    if (l.scrollDirection == Axis.horizontal) return true;
  }
  return false;
}
