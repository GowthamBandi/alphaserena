import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/home_workout_card.dart';
import 'package:alphaserena/core/domain/workout_session.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/home/home_workout_card_widget.dart';

/// TODAY'S WORKOUT CARD, rendered pure.
///
/// (Consistency moved to `consistency_cards_widget_test.dart` when it was
/// redesigned — the two sections no longer share a test file because they no
/// longer share a shape.)
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

  // ══ TODAY'S WORKOUT ════════════════════════════════════════════════════

  group('Workout card', () {
    const ready = HomeWorkoutCard(
      mode: WorkoutCardMode.ready,
      title: 'Upper Body',
      subtitle: 'Prepared by Ravi',
      coachNote: 'Slow negatives today — three seconds down.',
      facts: [
        WorkoutFact('exercises', '6 exercises'),
        WorkoutFact('duration', '≈45 min'),
        WorkoutFact('difficulty', 'Intermediate'),
        WorkoutFact('equipment', 'Barbell · Bench'),
      ],
      cta: 'Start Workout',
    );

    testWidgets('NOT STARTED — plan name leads, one button', (tester) async {
      await tester.pumpWidget(
          host(HomeWorkoutCardWidget(card: ready, onPrimary: () {})));
      expect(find.text("TODAY'S WORKOUT"), findsOneWidget);
      expect(find.text('Upper Body'), findsOneWidget);
      expect(find.text('Prepared by Ravi'), findsOneWidget);
      expect(find.text('6 exercises'), findsOneWidget);
      expect(find.text('≈45 min'), findsOneWidget);
      expect(find.text('Intermediate'), findsOneWidget);
      expect(find.text('Barbell · Bench'), findsOneWidget);
      expect(find.textContaining('Slow negatives'), findsOneWidget);
      expect(find.text('Start Workout'), findsWidgets);
    });

    testWidgets('carries NO artwork banner and NO video', (tester) async {
      await tester.pumpWidget(
          host(HomeWorkoutCardWidget(card: ready, onPrimary: () {})));
      // Home is for execution; atmosphere lives inside the workout.
      expect(find.byType(Image), findsNothing);
      expect(find.byType(AspectRatio), findsNothing);
    });

    testWidgets('PARTIAL — percent, next exercise, next set, Resume',
        (tester) async {
      await tester.pumpWidget(host(HomeWorkoutCardWidget(
        card: const HomeWorkoutCard(
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
        ),
        onPrimary: () {},
      )));
      expect(find.text('IN PROGRESS'), findsOneWidget);
      expect(find.text('22'), findsOneWidget);
      expect(find.text('%'), findsOneWidget);
      expect(find.text('NEXT EXERCISE'), findsOneWidget);
      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('Set 2 of 4  ·  12 reps × 60 kg'), findsOneWidget);
      expect(find.text('Resume Workout'), findsWidgets);
      expect(find.text('Start Workout'), findsNothing);
    });

    testWidgets('COMPLETED — Review + Edit Log, and the four figures',
        (tester) async {
      var reviewed = false;
      var edited = false;
      await tester.pumpWidget(host(HomeWorkoutCardWidget(
        card: const HomeWorkoutCard(
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
        ),
        onPrimary: () => reviewed = true,
        onSecondary: () => edited = true,
      )));
      expect(find.text('COMPLETED'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('45m'), findsOneWidget);
      expect(find.text('12/12'), findsOneWidget);
      expect(find.text('92%'), findsOneWidget);
      expect(find.text('Start Workout'), findsNothing);

      await tester.tap(find.text('Review Workout'));
      expect(reviewed, isTrue);
      await tester.tap(find.text('Edit Workout Log'));
      expect(edited, isTrue);
    });

    testWidgets('REST — calm, no red button, quiet offer', (tester) async {
      var trained = false;
      await tester.pumpWidget(host(HomeWorkoutCardWidget(
        card: const HomeWorkoutCard(
          mode: WorkoutCardMode.rest,
          title: 'Rest day',
          subtitle: 'Recovery is part of the program.',
          secondaryCta: 'Train anyway',
        ),
        onSecondary: () => trained = true,
      )));
      expect(find.text("TODAY'S WORKOUT"), findsNothing);
      expect(find.byIcon(Icons.self_improvement_rounded), findsOneWidget);
      await tester.tap(find.text('Train anyway'));
      expect(trained, isTrue);
    });

    testWidgets('OFFLINE — Retry, and never blames the coach', (tester) async {
      var retried = false;
      await tester.pumpWidget(host(HomeWorkoutCardWidget(
        card: const HomeWorkoutCard(
          mode: WorkoutCardMode.unavailable,
          title: "Couldn't load today's session",
          subtitle: 'Your plan is safe — this will load when you reconnect.',
          cta: 'Retry',
        ),
        onPrimary: () => retried = true,
      )));
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.textContaining('Your plan is safe'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('the primary button does not render without a handler',
        (tester) async {
      await tester.pumpWidget(host(const HomeWorkoutCardWidget(card: ready)));
      expect(find.text('Start Workout'), findsNothing);
    });

    testWidgets('the spoken label carries the whole card', (tester) async {
      await tester.pumpWidget(
          host(HomeWorkoutCardWidget(card: ready, onPrimary: () {})));
      expect(find.bySemanticsLabel(RegExp('Note from your coach')),
          findsOneWidget);
    });

    testWidgets('survives a 320px phone at 1.6x text scale', (tester) async {
      await tester.pumpWidget(host(
        HomeWorkoutCardWidget(
          card: const HomeWorkoutCard(
            mode: WorkoutCardMode.inProgress,
            title: 'Full Body Strength & Conditioning',
            facts: [
              WorkoutFact('exercises', '9 exercises'),
              WorkoutFact('duration', '≈75 min'),
              WorkoutFact('difficulty', 'Advanced'),
              WorkoutFact('equipment', 'Barbell · Bench +2'),
            ],
            progressPercent: 66,
            nextUp: NextUp(
              exerciseName: 'Romanian Deadlift',
              exerciseIndex: 4,
              setNumber: 3,
              totalSets: 5,
              prescribedReps: '8-12',
              prescribedWeight: '82.5',
            ),
            cta: 'Resume Workout',
          ),
          onPrimary: () {},
        ),
        textScale: 1.6,
        size: const Size(320, 640),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the completed card survives 1.6x with four figures',
        (tester) async {
      await tester.pumpWidget(host(
        HomeWorkoutCardWidget(
          card: const HomeWorkoutCard(
            mode: WorkoutCardMode.completed,
            title: 'Full Body Strength & Conditioning',
            subtitle: 'Completed',
            progressPercent: 100,
            results: [
              WorkoutResult('Duration', '1h 15m'),
              WorkoutResult('Exercises', '9'),
              WorkoutResult('Sets', '27/27'),
              WorkoutResult('Adherence', '100%'),
            ],
            cta: 'Review Workout',
            secondaryCta: 'Edit Workout Log',
          ),
          onPrimary: () {},
          onSecondary: () {},
        ),
        textScale: 1.6,
        size: const Size(320, 640),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
