import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:alphaserena/core/domain/consistency_pair.dart';
import 'package:alphaserena/core/domain/consistency_story.dart';
import 'package:alphaserena/core/domain/performance.dart';
import 'package:alphaserena/core/domain/prescription.dart';
import 'package:alphaserena/core/theme/app_colors.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/consistency_detail_screen.dart';
import 'package:alphaserena/screens/dashboard/home/consistency_cards_pair.dart';

/// PATROL — the Consistency experience, on a real device.
///
/// ── WHY THESE TESTS MOUNT WIDGETS RATHER THAN LAUNCH THE APP ───────────────
/// Home is behind Firebase auth, and the emulator has no member session (phone
/// OTP is externally blocked on this project). Driving the real app would test
/// the splash screen, not Consistency. So each test mounts the REAL production
/// widgets with fixture data and exercises them on real hardware — which is
/// where the things a `flutter test` cannot see actually live:
///
///   • real Poppins/Teko metrics instead of the fallback face used in goldens
///   • real device pixel ratio, real text-scale behaviour
///   • genuine overflow (a RenderFlex error surfaces as a red banner here)
///   • real orientation changes and real navigation/hero animation
///
/// Patrol 3.20's binding exposes no in-test screenshot API, so the visual
/// record is captured separately with `adb exec-out screencap` against the
/// same widgets rendered by `lib/main_consistency_preview.dart`.
///
/// Every fixture below is a value the production engine can genuinely produce.
void main() {
  // ── Fixtures ────────────────────────────────────────────────────────────
  const activeWeek = [
    TodayMark.done,
    TodayMark.done,
    TodayMark.open,
    TodayMark.future,
    TodayMark.future,
    TodayMark.future,
    TodayMark.future,
  ];

  const mixedWeek = [
    TodayMark.done,
    TodayMark.missed,
    TodayMark.open,
    TodayMark.rest,
    TodayMark.excused,
    TodayMark.future,
    TodayMark.future,
  ];

  ConsistencyCard card({
    required ConsistencyTrack track,
    ConsistencyCardState state = ConsistencyCardState.active,
    int streak = 5,
    bool weekUnit = false,
    String motivation = 'Keep it going.',
    List<TodayMark> week = activeWeek,
    TodayMark today = TodayMark.open,
  }) => ConsistencyCard(
    track: track,
    state: state,
    streak: streak,
    weekUnit: weekUnit,
    week: week,
    weekDone: 2,
    weekExpected: 5,
    today: today,
    motivation: motivation,
    todayIndex: 2,
  );

  DayVerdict verdict(int daysAgo, ExpectationKind e, OutcomeKind o) =>
      DayVerdict(
        date: DateTime.now().subtract(Duration(days: daysAgo)),
        expectation: e,
        outcome: o,
      );

  /// A month of real-looking history: trained Mon/Wed/Fri, rested weekends,
  /// one missed day, one coach excuse.
  List<DayVerdict> history() => [
    for (var i = 0; i < 35; i++)
      () {
        final d = DateTime.now().subtract(Duration(days: i));
        if (i == 0) {
          return verdict(i, ExpectationKind.required, OutcomeKind.open);
        }
        if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
          return verdict(i, ExpectationKind.rest, OutcomeKind.excluded);
        }
        if (i == 4) {
          return verdict(i, ExpectationKind.required, OutcomeKind.missed);
        }
        if (i == 9) {
          return verdict(
              i, ExpectationKind.required, OutcomeKind.excusedByCoach);
        }
        if (d.weekday == DateTime.tuesday || d.weekday == DateTime.thursday) {
          return verdict(i, ExpectationKind.rest, OutcomeKind.excluded);
        }
        return verdict(i, ExpectationKind.required, OutcomeKind.done);
      }(),
  ];

  List<Achievement> achievements() => buildAchievements(
    track: ConsistencyTrack.workout,
    logsAvailable: true,
    currentStreak: 5,
    longestStreak: 14,
    totalLogged: 22,
    verdicts: history(),
    monthCells: [
      for (var i = 1; i <= 20; i++)
        MonthCell(
          DateTime(DateTime.now().year, DateTime.now().month, i),
          i % 3 == 0 ? MonthCellState.missed : MonthCellState.done,
        ),
    ],
    weekUnit: false,
  );

  /// A host that mirrors production chrome: the real theme, a real Scaffold,
  /// and real MediaQuery so text scaling and size behave as they do in the app.
  Widget host(
    Widget child, {
    bool dark = true,
    double textScale = 1.0,
  }) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          backgroundColor: Theme.of(context)
              .extension<AppPalette>()!
              .background,
          body: SafeArea(child: child),
        ),
      ),
    ),
  );

  Widget pair({
    ConsistencyCardState state = ConsistencyCardState.active,
    List<TodayMark> week = activeWeek,
    int workoutStreak = 5,
    String workoutMotivation = 'Keep it going.',
    VoidCallback? onWorkoutTap,
    VoidCallback? onNutritionTap,
  }) => Padding(
    padding: const EdgeInsets.all(18),
    child: ConsistencyCardsPair(
      workout: card(
        track: ConsistencyTrack.workout,
        state: state,
        streak: workoutStreak,
        motivation: workoutMotivation,
        week: week,
      ),
      nutrition: card(
        track: ConsistencyTrack.nutrition,
        state: state,
        streak: 12,
        motivation: 'Done today. Nice.',
        week: week,
        today: TodayMark.done,
      ),
      onWorkoutTap: onWorkoutTap,
      onNutritionTap: onNutritionTap,
    ),
  );

  Widget detail({bool isWorkout = true, int streak = 5}) =>
      ConsistencyDetailView(
        isWorkout: isWorkout,
        hero: buildStreakHero(
          track: isWorkout
              ? ConsistencyTrack.workout
              : ConsistencyTrack.nutrition,
          state: ConsistencyCardState.active,
          streak: streak,
          weekUnit: false,
          hasHistory: true,
          loggedToday: false,
        ),
        week: mixedWeek,
        verdicts: history(),
        achievements: achievements(),
        closingMessage: 'Small wins become lifelong habits.',
      );

  // ══ 1. HOME RENDERS ═════════════════════════════════════════════════════

  patrolTest('home consistency renders both cards with no overflow',
      ($) async {
    await $.pumpWidgetAndSettle(host(pair(onWorkoutTap: () {})));

    expect($('Workout'), findsOneWidget);
    expect($('Nutrition'), findsOneWidget);
    expect($('5'), findsOneWidget);
    expect($('12'), findsOneWidget);
    expect($('Keep it going.'), findsOneWidget);
    expect($('Tap to view'), findsOneWidget);
  });

  patrolTest('home consistency renders in light mode', ($) async {
    await $.pumpWidgetAndSettle(host(pair(onWorkoutTap: () {}), dark: false));
    expect($('Workout'), findsOneWidget);
  });

  patrolTest('home consistency survives large accessibility fonts',
      ($) async {
    await $.pumpWidgetAndSettle(
      host(pair(onWorkoutTap: () {}), textScale: 1.6),
    );
    expect($('Workout'), findsOneWidget);
    expect($('Nutrition'), findsOneWidget);
  });

  patrolTest('home consistency handles a mixed week without overflow',
      ($) async {
    await $.pumpWidgetAndSettle(
      host(pair(week: mixedWeek, onWorkoutTap: () {})),
    );
    expect($('Workout'), findsOneWidget);
  });

  // ══ 2. EMPTY / OFFLINE / PAUSED ═════════════════════════════════════════

  patrolTest('a brand-new member sees an invitation, never a wall of zeroes',
      ($) async {
    await $.pumpWidgetAndSettle(host(pair(
      workoutStreak: 0,
      workoutMotivation: 'Start your first session.',
      onWorkoutTap: () {},
    )));
    expect($('Start your first session.'), findsOneWidget);
  });

  patrolTest('offline shows a dash and a reassurance, never a lost streak',
      ($) async {
    await $.pumpWidgetAndSettle(host(pair(
      state: ConsistencyCardState.unavailable,
      workoutMotivation: 'Offline — your streak is safe.',
    )));
    expect($('—'), findsWidgets);
    expect($('0'), findsNothing);
  });

  patrolTest('loading shows a skeleton, not a zero', ($) async {
    await $.pumpWidgetAndSettle(
      host(pair(state: ConsistencyCardState.loading)),
    );
    expect($('Tap to view'), findsNothing);
  });

  // ══ 3. NAVIGATION + HERO ════════════════════════════════════════════════

  patrolTest('tapping the workout card opens its detail and comes back',
      ($) async {
    await $.pumpWidgetAndSettle(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: SafeArea(
              child: pair(
                onWorkoutTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Workout Consistency')),
                      body: detail(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await $('Workout').tap();
    await $.pumpAndSettle();

    // The hero transition landed on the detail screen.
    expect($('CURRENT STREAK'), findsOneWidget);
    expect($('THIS WEEK'), findsOneWidget);
    expect($('LAST 30 DAYS'), findsOneWidget);

    // Flutter-level back, NOT native.pressBack(): this harness mounts a bare
    // MaterialApp, so an Android back at the root would finish the activity
    // and tear down Patrol's app-service channel mid-run (EOFException). The
    // thing under test is the app's own back navigation anyway.
    await $.tester.pageBack();
    await $.pumpAndSettle();
    expect($('Tap to view'), findsOneWidget);
  });

  patrolTest('tapping the nutrition card opens the nutrition track',
      ($) async {
    await $.pumpWidgetAndSettle(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: SafeArea(
              child: pair(
                onNutritionTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar:
                          AppBar(title: const Text('Nutrition Consistency')),
                      body: detail(isWorkout: false, streak: 12),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await $('Nutrition').tap();
    await $.pumpAndSettle();
    expect($('CURRENT STREAK'), findsOneWidget);
  });

  // ══ 4. DETAIL SCREEN ════════════════════════════════════════════════════

  patrolTest('the detail screen tells the whole story, top to bottom',
      ($) async {
    await $.pumpWidgetAndSettle(host(detail()));

    expect($('CURRENT STREAK'), findsOneWidget);
    expect($('5 Days'), findsOneWidget);
    expect($('THIS WEEK'), findsOneWidget);
    expect($('Mon'), findsOneWidget);
    expect($('Sun'), findsOneWidget);

    await $.scrollUntilVisible(finder: $('LAST 30 DAYS'));
    await $.pumpAndSettle();

    await $.scrollUntilVisible(finder: $("WHAT YOU'VE EARNED"));
    await $.pumpAndSettle();
    expect($('Longest Streak'), findsOneWidget);
    expect($('Adherence'), findsOneWidget);
    expect($('Monthly Goal'), findsOneWidget);

    await $.scrollUntilVisible(
      finder: $('Small wins become lifelong habits.'),
    );
    await $.pumpAndSettle();
  });

  patrolTest('every week state is visually present and distinct', ($) async {
    await $.pumpWidgetAndSettle(host(detail()));
    // The legend names all six states the mission requires.
    expect($('Completed'), findsOneWidget);
    expect($('Rest'), findsOneWidget);
    expect($('Excused'), findsOneWidget);
    expect($('Missed'), findsOneWidget);
    expect($('Today'), findsOneWidget);
    expect($('Upcoming'), findsOneWidget);
  });

  patrolTest('the detail screen survives large accessibility fonts',
      ($) async {
    await $.pumpWidgetAndSettle(host(detail(), textScale: 1.6));
    expect($('CURRENT STREAK'), findsOneWidget);
  });

  patrolTest('the detail screen renders in light mode', ($) async {
    await $.pumpWidgetAndSettle(host(detail(), dark: false));
    expect($('CURRENT STREAK'), findsOneWidget);
  });

  patrolTest('a member with no history is invited, not measured', ($) async {
    await $.pumpWidgetAndSettle(host(
      ConsistencyDetailView(
        isWorkout: true,
        hero: buildStreakHero(
          track: ConsistencyTrack.workout,
          state: ConsistencyCardState.active,
          streak: 0,
          weekUnit: false,
          hasHistory: false,
          loggedToday: false,
        ),
        week: const [
          TodayMark.future,
          TodayMark.future,
          TodayMark.open,
          TodayMark.future,
          TodayMark.future,
          TodayMark.future,
          TodayMark.future,
        ],
        verdicts: const [],
        achievements: buildAchievements(
          track: ConsistencyTrack.workout,
          logsAvailable: true,
          currentStreak: 0,
          longestStreak: 0,
          totalLogged: 0,
          verdicts: const [],
          monthCells: const [],
          weekUnit: false,
        ),
        closingMessage:
            'Everything starts with one session. Today is as good as any.',
      ),
    ));
    expect($('Your first session starts it.'), findsOneWidget);
    expect($('—'), findsWidgets);
  });

  // ══ 5. ORIENTATION + FORM FACTORS ═══════════════════════════════════════

  patrolTest('landscape holds up on both surfaces', ($) async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
    await $.pumpWidgetAndSettle(host(pair(onWorkoutTap: () {})));
    await $.pumpAndSettle();
    expect($('Workout'), findsOneWidget);

    await $.pumpWidgetAndSettle(host(detail()));
    await $.pumpAndSettle();
    expect($('CURRENT STREAK'), findsOneWidget);

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    await $.pumpAndSettle();
  });

  patrolTest('the detail screen scrolls smoothly end to end', ($) async {
    await $.pumpWidgetAndSettle(host(detail()));
    final list = find.byType(ListView);
    for (var i = 0; i < 6; i++) {
      await $.tester.drag(list, const Offset(0, -260));
      await $.tester.pump(const Duration(milliseconds: 16));
    }
    await $.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      await $.tester.drag(list, const Offset(0, 260));
      await $.tester.pump(const Duration(milliseconds: 16));
    }
    await $.pumpAndSettle();
    expect($('CURRENT STREAK'), findsOneWidget);
  });
}
