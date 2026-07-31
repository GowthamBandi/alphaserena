import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/consistency_pair.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/home/consistency_cards_pair.dart';

/// HOME CONSISTENCY — the redesigned pair, rendered pure.
///
/// After the redesign each card shows exactly five things. These tests pin
/// both what IS there and — more usefully — what is NOT: the progress bars,
/// the "Today" row and the "Next" row that made the previous version read as
/// analytics rather than coaching.
void main() {
  Widget host(Widget child, {double textScale = 1.0, Size? size}) =>
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
            size: size ?? const Size(390, 844),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: child,
              ),
            ),
          ),
        ),
      );

  ConsistencyCard workoutCard({
    ConsistencyCardState state = ConsistencyCardState.active,
    int streak = 5,
    bool weekUnit = false,
    String motivation = 'Keep it going.',
    TodayMark today = TodayMark.open,
    List<TodayMark>? week,
  }) => ConsistencyCard(
    track: ConsistencyTrack.workout,
    state: state,
    streak: streak,
    weekUnit: weekUnit,
    week: week ??
        const [
          TodayMark.done,
          TodayMark.done,
          TodayMark.open,
          TodayMark.future,
          TodayMark.future,
          TodayMark.future,
          TodayMark.future,
        ],
    weekDone: 2,
    weekExpected: 5,
    today: today,
    motivation: motivation,
    todayIndex: 2,
  );

  ConsistencyCard nutritionCard({
    ConsistencyCardState state = ConsistencyCardState.active,
    int streak = 12,
    String motivation = 'Done today. Nice.',
  }) => ConsistencyCard(
    track: ConsistencyTrack.nutrition,
    state: state,
    streak: streak,
    week: const [
      TodayMark.done,
      TodayMark.done,
      TodayMark.done,
      TodayMark.future,
      TodayMark.future,
      TodayMark.future,
      TodayMark.future,
    ],
    weekDone: 3,
    weekExpected: 7,
    today: TodayMark.done,
    motivation: motivation,
    todayIndex: 2,
  );

  group('what the card shows', () {
    testWidgets('two independent, separately-titled cards', (tester) async {
      await tester.pumpWidget(host(ConsistencyCardsPair(
        workout: workoutCard(),
        nutrition: nutritionCard(),
        onWorkoutTap: () {},
        onNutritionTap: () {},
      )));
      expect(find.text('Workout'), findsOneWidget);
      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Day Streak'), findsNWidgets(2));
    });

    testWidgets('streak, one line of copy, circles and the tap hint',
        (tester) async {
      await tester.pumpWidget(host(ConsistencyCardsPair(
        workout: workoutCard(),
        nutrition: nutritionCard(),
        onWorkoutTap: () {},
        onNutritionTap: () {},
      )));
      expect(find.text('Keep it going.'), findsOneWidget);
      expect(find.text('Done today. Nice.'), findsOneWidget);
      expect(find.text('Tap to view'), findsNWidgets(2));
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNWidgets(2));
    });

    testWidgets('weeks-on-plan gets its own unit', (tester) async {
      await tester.pumpWidget(host(ConsistencyCardsPair(
        workout: workoutCard(streak: 3, weekUnit: true),
        nutrition: nutritionCard(),
      )));
      expect(find.text('Weeks on plan'), findsOneWidget);
      expect(find.text('Day Streak'), findsOneWidget);
    });
  });

  group('what the card deliberately does NOT show', () {
    testWidgets('no progress bars, no Today row, no Next row', (tester) async {
      await tester.pumpWidget(host(ConsistencyCardsPair(
        workout: workoutCard(),
        nutrition: nutritionCard(),
        onWorkoutTap: () {},
      )));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Today'), findsNothing);
      expect(find.text('Next'), findsNothing);
      expect(find.textContaining('this week'), findsNothing);
      expect(find.textContaining('% today'), findsNothing);
      expect(find.textContaining('days to'), findsNothing);
    });
  });

  group('honest states', () {
    testWidgets('an unreadable track shows a dash, never a zero',
        (tester) async {
      await tester.pumpWidget(host(ConsistencyCardsPair(
        workout: workoutCard(
          state: ConsistencyCardState.unavailable,
          motivation: 'Offline — your streak is safe.',
        ),
        nutrition: nutritionCard(),
      )));
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('Offline — your streak is safe.'), findsOneWidget);
    });

    testWidgets('loading shows a skeleton and no numbers', (tester) async {
      await tester.pumpWidget(host(ConsistencyCardsPair(
        workout: workoutCard(state: ConsistencyCardState.loading),
        nutrition: nutritionCard(state: ConsistencyCardState.loading),
      )));
      expect(find.text('—'), findsNothing);
      expect(find.text('0'), findsNothing);
      expect(find.text('Tap to view'), findsNothing);
    });

    testWidgets('tracks update independently — one paused, one active',
        (tester) async {
      await tester.pumpWidget(host(ConsistencyCardsPair(
        workout: workoutCard(
          state: ConsistencyCardState.paused,
          motivation: 'Paused — your streak is safe.',
        ),
        nutrition: nutritionCard(),
      )));
      expect(find.text('Paused — your streak is safe.'), findsOneWidget);
      expect(find.text('Done today. Nice.'), findsOneWidget);
    });

    testWidgets('the flame lights only for a live streak', (tester) async {
      await tester.pumpWidget(host(ConsistencyCardsPair(
        workout: workoutCard(streak: 0),
        nutrition: nutritionCard(streak: 0),
      )));
      expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);

      await tester.pumpWidget(host(ConsistencyCardsPair(
        workout: workoutCard(streak: 5),
        nutrition: nutritionCard(streak: 12),
      )));
      expect(
          find.byIcon(Icons.local_fire_department_rounded), findsNWidgets(2));
    });

    testWidgets('the two cards are always exactly equal height',
        (tester) async {
      await tester.pumpWidget(host(ConsistencyCardsPair(
        workout: workoutCard(
          today: TodayMark.rest,
          motivation: 'Rest day. Recovery counts.',
        ),
        nutrition: nutritionCard(),
        onWorkoutTap: () {},
        onNutritionTap: () {},
      )));
      final a = tester.getSize(find.byType(AnimatedScale).at(0));
      final b = tester.getSize(find.byType(AnimatedScale).at(1));
      expect(a.height, b.height);
    });
  });

  group('interaction', () {
    testWidgets('tapping a card fires only that track', (tester) async {
      var w = 0;
      var n = 0;
      await tester.pumpWidget(host(ConsistencyCardsPair(
        workout: workoutCard(),
        nutrition: nutritionCard(),
        onWorkoutTap: () => w++,
        onNutritionTap: () => n++,
      )));
      await tester.tap(find.text('Workout'));
      await tester.pumpAndSettle();
      expect(w, 1);
      expect(n, 0);
    });

    testWidgets('a press shrinks the card, and it springs back',
        (tester) async {
      await tester.pumpWidget(host(ConsistencyCardsPair(
        workout: workoutCard(),
        nutrition: nutritionCard(),
        onWorkoutTap: () {},
      )));
      final scale = find.byType(AnimatedScale).first;
      expect(tester.widget<AnimatedScale>(scale).scale, 1.0);

      final gesture =
          await tester.startGesture(tester.getCenter(find.text('Workout')));
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.widget<AnimatedScale>(scale).scale, lessThan(1.0));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(scale).scale, 1.0);
    });

    testWidgets('each streak carries a hero tag for the detail transition',
        (tester) async {
      await tester.pumpWidget(host(ConsistencyCardsPair(
        workout: workoutCard(),
        nutrition: nutritionCard(),
        onWorkoutTap: () {},
        onNutritionTap: () {},
      )));
      final tags =
          tester.widgetList<Hero>(find.byType(Hero)).map((h) => h.tag).toSet();
      expect(tags, containsAll([
        kWorkoutStreakHeroTag,
        kNutritionStreakHeroTag,
      ]));
    });
  });

  group('accessibility', () {
    testWidgets('each card is one semantic node naming its own track',
        (tester) async {
      await tester.pumpWidget(host(ConsistencyCardsPair(
        workout: workoutCard(),
        nutrition: nutritionCard(),
        onWorkoutTap: () {},
        onNutritionTap: () {},
      )));
      expect(find.bySemanticsLabel(RegExp('Workout consistency')),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Nutrition consistency')),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Open full history')),
          findsNWidgets(2));
    });

    testWidgets('an inert card is not announced as a button', (tester) async {
      await tester.pumpWidget(host(ConsistencyCardsPair(
        workout: workoutCard(state: ConsistencyCardState.unavailable),
        nutrition: nutritionCard(state: ConsistencyCardState.unavailable),
      )));
      expect(find.bySemanticsLabel(RegExp('Open full history')), findsNothing);
      expect(find.text('Tap to view'), findsNothing);
    });

    testWidgets('survives a 320px phone at 1.6x text scale', (tester) async {
      await tester.pumpWidget(host(
        ConsistencyCardsPair(
          workout: workoutCard(
            streak: 8,
            weekUnit: true,
            motivation: 'Rest day. Recovery counts.',
          ),
          nutrition: nutritionCard(
            streak: 45,
            motivation: 'Ready when you are.',
          ),
          onWorkoutTap: () {},
          onNutritionTap: () {},
        ),
        textScale: 1.6,
        size: const Size(320, 640),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a large tablet width without stretching oddly',
        (tester) async {
      await tester.pumpWidget(host(
        ConsistencyCardsPair(
          workout: workoutCard(),
          nutrition: nutritionCard(),
          onWorkoutTap: () {},
          onNutritionTap: () {},
        ),
        size: const Size(1024, 1366),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
