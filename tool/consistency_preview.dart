// DEV TOOL — not shipped, not referenced by the app.
//
// Renders every Consistency state on a real device so the visual record in
// ALPHASERENA_CONSISTENCY_UX_CERTIFICATION.md is a photograph of the real
// widgets with the real fonts, not a golden rendered with a fallback face.
//
// Run:  flutter run -t tool/consistency_preview.dart -d emulator-5554
// Then: adb exec-out screencap -p > shot.png   (swipe to advance)
import 'package:flutter/material.dart';

import 'package:alphaserena/core/domain/consistency_pair.dart';
import 'package:alphaserena/core/domain/consistency_story.dart';
import 'package:alphaserena/core/domain/performance.dart';
import 'package:alphaserena/core/domain/prescription.dart';
import 'package:alphaserena/core/theme/app_colors.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/consistency_detail_screen.dart';
import 'package:alphaserena/screens/dashboard/home/consistency_cards_pair.dart';

void main() => runApp(const _Preview());

const _activeWeek = [
  TodayMark.done,
  TodayMark.done,
  TodayMark.open,
  TodayMark.future,
  TodayMark.future,
  TodayMark.future,
  TodayMark.future,
];

const _mixedWeek = [
  TodayMark.done,
  TodayMark.missed,
  TodayMark.open,
  TodayMark.rest,
  TodayMark.excused,
  TodayMark.future,
  TodayMark.future,
];

ConsistencyCard _card({
  required ConsistencyTrack track,
  ConsistencyCardState state = ConsistencyCardState.active,
  int streak = 5,
  bool weekUnit = false,
  String motivation = 'Keep it going.',
  List<TodayMark> week = _activeWeek,
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

DayVerdict _v(int daysAgo, ExpectationKind e, OutcomeKind o) => DayVerdict(
  date: DateTime.now().subtract(Duration(days: daysAgo)),
  expectation: e,
  outcome: o,
);

List<DayVerdict> _history() => [
  for (var i = 0; i < 35; i++)
    () {
      final d = DateTime.now().subtract(Duration(days: i));
      if (i == 0) return _v(i, ExpectationKind.required, OutcomeKind.open);
      if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
        return _v(i, ExpectationKind.rest, OutcomeKind.excluded);
      }
      if (i == 4) return _v(i, ExpectationKind.required, OutcomeKind.missed);
      if (i == 9) {
        return _v(i, ExpectationKind.required, OutcomeKind.excusedByCoach);
      }
      if (d.weekday == DateTime.tuesday || d.weekday == DateTime.thursday) {
        return _v(i, ExpectationKind.rest, OutcomeKind.excluded);
      }
      return _v(i, ExpectationKind.required, OutcomeKind.done);
    }(),
];

Widget _detail({bool isWorkout = true, int streak = 5}) =>
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
      week: _mixedWeek,
      verdicts: _history(),
      achievements: buildAchievements(
        track: isWorkout
            ? ConsistencyTrack.workout
            : ConsistencyTrack.nutrition,
        logsAvailable: true,
        currentStreak: streak,
        longestStreak: 14,
        totalLogged: 22,
        verdicts: _history(),
        monthCells: [
          for (var i = 1; i <= 20; i++)
            MonthCell(
              DateTime(DateTime.now().year, DateTime.now().month, i),
              i % 3 == 0 ? MonthCellState.missed : MonthCellState.done,
            ),
        ],
        weekUnit: false,
      ),
      closingMessage: 'Small wins become lifelong habits.',
    );

class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final pages = <({String name, bool dark, double scale, Widget child})>[
      (
        name: 'home-active-dark',
        dark: true,
        scale: 1,
        child: _pair(streak: 5, motivation: 'Keep it going.'),
      ),
      (
        name: 'home-mixed-week',
        dark: true,
        scale: 1,
        child: _pair(
          streak: 5,
          motivation: 'Rest day. Recovery counts.',
          week: _mixedWeek,
        ),
      ),
      (
        name: 'home-empty',
        dark: true,
        scale: 1,
        child: _pair(streak: 0, motivation: 'Start your first session.'),
      ),
      (
        name: 'home-offline',
        dark: true,
        scale: 1,
        child: _pair(
          state: ConsistencyCardState.unavailable,
          motivation: 'Offline — your streak is safe.',
        ),
      ),
      (
        name: 'home-loading',
        dark: true,
        scale: 1,
        child: _pair(state: ConsistencyCardState.loading),
      ),
      (
        name: 'home-light',
        dark: false,
        scale: 1,
        child: _pair(streak: 5, motivation: 'Keep it going.'),
      ),
      (
        name: 'home-large-text',
        dark: true,
        scale: 1.6,
        child: _pair(streak: 5, motivation: 'Keep it going.'),
      ),
      (name: 'detail-dark', dark: true, scale: 1, child: _detail()),
      (name: 'detail-light', dark: false, scale: 1, child: _detail()),
      (
        name: 'detail-nutrition',
        dark: true,
        scale: 1,
        child: _detail(isWorkout: false, streak: 12),
      ),
    ];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: PageView(
        children: [
          for (final p in pages)
            Theme(
              data: p.dark ? AppTheme.dark : AppTheme.light,
              child: Builder(
                builder: (context) {
                  final pal = Theme.of(context).extension<AppPalette>()!;
                  return MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(p.scale)),
                    child: Scaffold(
                      backgroundColor: pal.background,
                      body: SafeArea(child: p.child),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _pair({
    ConsistencyCardState state = ConsistencyCardState.active,
    int streak = 5,
    String motivation = 'Keep it going.',
    List<TodayMark> week = _activeWeek,
  }) => Padding(
    padding: const EdgeInsets.all(18),
    child: ConsistencyCardsPair(
      workout: _card(
        track: ConsistencyTrack.workout,
        state: state,
        streak: streak,
        motivation: motivation,
        week: week,
        today: week == _mixedWeek ? TodayMark.open : TodayMark.open,
      ),
      nutrition: _card(
        track: ConsistencyTrack.nutrition,
        state: state,
        streak: state == ConsistencyCardState.active ? 12 : 0,
        motivation: state == ConsistencyCardState.active
            ? 'Done today. Nice.'
            : motivation,
        week: week,
        today: TodayMark.done,
      ),
      onWorkoutTap: state == ConsistencyCardState.active ? () {} : null,
      onNutritionTap: state == ConsistencyCardState.active ? () {} : null,
    ),
  );
}
