import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:alphaserena/core/domain/consistency_pair.dart';
import 'package:alphaserena/core/domain/home_workout_card.dart';
import 'package:alphaserena/core/domain/workout_session.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/home/consistency_cards_pair.dart';
import 'package:alphaserena/screens/dashboard/home/home_workout_card_widget.dart';

/// PIXEL LOCK for the two refined Home surfaces, light and dark.
///
/// These replace the goldens of the consistency tiles this redesign removed.
/// They exist because the failure mode of a "premium" card is not a crash —
/// it is a quiet drift in spacing, weight and rhythm that no assertion
/// catches and every member sees.
///
/// Regenerate with:
///   flutter test --update-goldens test/home_cards_golden_test.dart
void main() {
  // `AppText` builds every style through google_fonts, which resolves its
  // faces over the network and is not bundled as an asset here. A golden that
  // awaits (as `matchesGoldenFile` does) gives that fetch time to fail, so the
  // suite must both stop it trying and ignore the resulting complaint. The
  // cards render with the fallback face — deterministically, which is all a
  // pixel lock needs. The filter is narrow on purpose: any OTHER error still
  // fails the test.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget host(Widget child, {required bool dark}) => MaterialApp(
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: MediaQuery(
      data: const MediaQueryData(size: Size(390, 844)),
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: RepaintBoundary(child: child),
          ),
        ),
      ),
    ),
  );

  Future<void> pump(WidgetTester tester, Widget child,
      {required bool dark}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(host(child, dark: dark));
    // pump(), NOT pumpAndSettle(): google_fonts resolves its faces over the
    // network and the app does not bundle them as assets, so settling would
    // await a fetch that fails on CI. One frame renders the card with the
    // fallback face — deterministically, which is what a pixel lock needs.
    await tester.pump();
  }

  const ConsistencyCard workout = ConsistencyCard(
    track: ConsistencyTrack.workout,
    state: ConsistencyCardState.active,
    streak: 5,
    week: [
      TodayMark.done,
      TodayMark.done,
      TodayMark.open,
      TodayMark.unknown,
      TodayMark.unknown,
      TodayMark.unknown,
      TodayMark.unknown,
    ],
    weekDone: 2,
    weekExpected: 5,
    today: TodayMark.open,
    motivation: 'Keep it going.',
    todayIndex: 2,
  );

  const nutrition = ConsistencyCard(
    track: ConsistencyTrack.nutrition,
    state: ConsistencyCardState.active,
    streak: 12,
    week: [
      TodayMark.done,
      TodayMark.done,
      TodayMark.done,
      TodayMark.unknown,
      TodayMark.unknown,
      TodayMark.unknown,
      TodayMark.unknown,
    ],
    weekDone: 3,
    weekExpected: 7,
    today: TodayMark.done,
    motivation: 'Done today. Nice.',
    todayIndex: 2,
  );

  // `AppText` routes every style through google_fonts, which is not bundled
  // as an asset here. The first widget that asks for a face raises one error;
  // google_fonts then records the failure and never retries. `matchesGoldenFile`
  // awaits, which is long enough for that first error to land INSIDE a golden
  // test and fail it — so this test absorbs it up front, deliberately, and
  // every golden below then renders with the fallback face deterministically.
  // (The suite's other goldens pass for the same reason by accident: thirty
  // earlier tests happen to run before them.)
  testWidgets('warm up font resolution', (tester) async {
    await tester.pumpWidget(
      host(ConsistencyCardsPair(
            workout: workout,
            nutrition: nutrition,
            onWorkoutTap: () {},
            onNutritionTap: () {}),
          dark: true),
    );
    await tester.pump();
    tester.takeException();
  });

  group('Consistency pair', () {
    testWidgets('dark', (tester) async {
      await pump(
        tester,
        ConsistencyCardsPair(
            workout: workout,
            nutrition: nutrition,
            onWorkoutTap: () {},
            onNutritionTap: () {}),
        dark: true,
      );
      await expectLater(
        find.byType(ConsistencyCardsPair),
        matchesGoldenFile('goldens/consistency_pair_dark.png'),
      );
    });

    testWidgets('light', (tester) async {
      await pump(
        tester,
        ConsistencyCardsPair(
            workout: workout,
            nutrition: nutrition,
            onWorkoutTap: () {},
            onNutritionTap: () {}),
        dark: false,
      );
      await expectLater(
        find.byType(ConsistencyCardsPair),
        matchesGoldenFile('goldens/consistency_pair_light.png'),
      );
    });

    testWidgets('rest day beside an active track — equal height', (tester) async {
      await pump(
        tester,
        ConsistencyCardsPair(
          onWorkoutTap: () {},
          onNutritionTap: () {},
          workout: const ConsistencyCard(
            track: ConsistencyTrack.workout,
            state: ConsistencyCardState.active,
            streak: 3,
            week: [
              TodayMark.done,
              TodayMark.done,
              TodayMark.rest,
              TodayMark.unknown,
              TodayMark.unknown,
              TodayMark.unknown,
              TodayMark.unknown,
            ],
            weekDone: 2,
            weekExpected: 4,
            today: TodayMark.rest,
            motivation: 'Rest day. Recovery counts.',
            todayIndex: 2,
          ),
          nutrition: nutrition,
        ),
        dark: true,
      );
      await expectLater(
        find.byType(ConsistencyCardsPair),
        matchesGoldenFile('goldens/consistency_pair_rest.png'),
      );
    });

    testWidgets('loading', (tester) async {
      await pump(
        tester,
        ConsistencyCardsPair(
          onWorkoutTap: () {},
          onNutritionTap: () {},
          workout: const ConsistencyCard(
            track: ConsistencyTrack.workout,
            state: ConsistencyCardState.loading,
          ),
          nutrition: const ConsistencyCard(
            track: ConsistencyTrack.nutrition,
            state: ConsistencyCardState.loading,
          ),
        ),
        dark: true,
      );
      await expectLater(
        find.byType(ConsistencyCardsPair),
        matchesGoldenFile('goldens/consistency_pair_loading.png'),
      );
    });
  });

  group("Today's workout card", () {
    const ready = HomeWorkoutCard(
      mode: WorkoutCardMode.ready,
      title: 'Upper Body',
      subtitle: 'Prepared by Ravi',
      coachNote: 'Slow negatives today — three seconds down on every rep.',
      facts: [
        WorkoutFact('exercises', '6 exercises'),
        WorkoutFact('duration', '≈45 min'),
        WorkoutFact('difficulty', 'Intermediate'),
        WorkoutFact('equipment', 'Barbell · Bench'),
      ],
      cta: 'Start Workout',
    );

    const inProgress = HomeWorkoutCard(
      mode: WorkoutCardMode.inProgress,
      title: 'Upper Body',
      progressPercent: 22,
      nextUp: NextUp(
        exerciseName: 'Bench Press',
        exerciseIndex: 1,
        setNumber: 2,
        totalSets: 4,
        prescribedReps: '12',
        prescribedWeight: '60',
      ),
      cta: 'Resume Workout',
    );

    const completed = HomeWorkoutCard(
      mode: WorkoutCardMode.completed,
      title: 'Upper Body',
      subtitle: 'Completed',
      progressPercent: 100,
      results: [
        WorkoutResult('Duration', '45m'),
        WorkoutResult('Exercises', '4'),
        WorkoutResult('Sets', '12/12'),
        WorkoutResult('Adherence', '92%'),
      ],
      cta: 'Review Workout',
      secondaryCta: 'Edit Workout Log',
    );

    testWidgets('not started — dark', (tester) async {
      await pump(
        tester,
        HomeWorkoutCardWidget(card: ready, onPrimary: () {}),
        dark: true,
      );
      await expectLater(
        find.byType(HomeWorkoutCardWidget),
        matchesGoldenFile('goldens/workout_card_ready_dark.png'),
      );
    });

    testWidgets('not started — light', (tester) async {
      await pump(
        tester,
        HomeWorkoutCardWidget(card: ready, onPrimary: () {}),
        dark: false,
      );
      await expectLater(
        find.byType(HomeWorkoutCardWidget),
        matchesGoldenFile('goldens/workout_card_ready_light.png'),
      );
    });

    testWidgets('in progress — dark', (tester) async {
      await pump(
        tester,
        HomeWorkoutCardWidget(card: inProgress, onPrimary: () {}),
        dark: true,
      );
      await expectLater(
        find.byType(HomeWorkoutCardWidget),
        matchesGoldenFile('goldens/workout_card_progress_dark.png'),
      );
    });

    testWidgets('completed — dark', (tester) async {
      await pump(
        tester,
        HomeWorkoutCardWidget(
          card: completed,
          onPrimary: () {},
          onSecondary: () {},
        ),
        dark: true,
      );
      await expectLater(
        find.byType(HomeWorkoutCardWidget),
        matchesGoldenFile('goldens/workout_card_completed_dark.png'),
      );
    });

    testWidgets('rest day — dark', (tester) async {
      await pump(
        tester,
        HomeWorkoutCardWidget(
          card: const HomeWorkoutCard(
            mode: WorkoutCardMode.rest,
            title: 'Rest day',
            subtitle: 'Prescribed by Ravi. Recovery is part of the program — '
                'today counts by resting.',
            secondaryCta: 'Train anyway',
          ),
          onSecondary: () {},
        ),
        dark: true,
      );
      await expectLater(
        find.byType(HomeWorkoutCardWidget),
        matchesGoldenFile('goldens/workout_card_rest_dark.png'),
      );
    });
  });
}
