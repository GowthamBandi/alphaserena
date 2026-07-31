import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/workout_session.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/workout_rest_overlay.dart';

/// WORKOUT EXPERIENCE Phase 2 — the guided surfaces, rendered pure.
///
/// The rest overlay is the piece with real behaviour worth pinning: it must
/// count against the WALL CLOCK (so a locked phone loses nothing), pause,
/// extend, and survive both a tiny screen and a large accessibility text
/// scale.
void main() {
  Widget host(Widget child, {double textScale = 1.0}) => MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: child),
        ),
      );

  group('rest overlay', () {
    testWidgets('shows the remaining time and the three controls',
        (tester) async {
      await tester.pumpWidget(host(const RestOverlay(
        seconds: 90,
        nextSetNumber: 2,
        accent: Color(0xFFE10600),
      )));
      expect(find.text('Next: Set 2'), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('30s'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('the countdown follows the WALL CLOCK, not tick counts',
        (tester) async {
      await tester.pumpWidget(host(const RestOverlay(
        seconds: 90,
        nextSetNumber: 2,
        accent: Color(0xFFE10600),
      )));
      // Advancing only the widget-test clock fires the ticker without moving
      // real time. A tick-counting timer would jump to 1:25 here; a
      // wall-clock one must not — which is exactly why a locked phone or a
      // backgrounded app no longer loses (or gains) rest time.
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('1:30'), findsOneWidget);
    });

    testWidgets('pause freezes the countdown and offers Resume',
        (tester) async {
      await tester.pumpWidget(host(const RestOverlay(
        seconds: 45,
        nextSetNumber: 3,
        accent: Color(0xFFE10600),
      )));
      expect(find.text('45'), findsOneWidget);
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('paused'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('45'), findsOneWidget); // frozen at the paused value
    });

    testWidgets('+30s extends the remaining time', (tester) async {
      await tester.pumpWidget(host(const RestOverlay(
        seconds: 30,
        nextSetNumber: 2,
        accent: Color(0xFFE10600),
      )));
      await tester.tap(find.text('Pause')); // freeze so the read is stable
      await tester.pump();
      await tester.tap(find.text('30s'));
      await tester.pump();
      expect(find.text('1:00'), findsOneWidget);
    });

    testWidgets('survives a small screen at 1.6x text scale', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(
        const RestOverlay(
          seconds: 75,
          nextSetNumber: 2,
          accent: Color(0xFFE10600),
          reminder:
              'Sip some water — hydration holds your performance up and this '
              'is a deliberately long reminder to stress the layout.',
        ),
        textScale: 1.6,
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('reminders rotate but never impersonate the coach',
        (tester) async {
      final a = restReminderFor(1);
      final b = restReminderFor(2);
      expect(a, isNot(b));
      expect(kRestReminders.every((r) => !r.contains('coach')), isTrue);
    });
  });

  group('session stats power the summary honestly', () {
    test('a fully completed session reads complete', () {
      final stats = computeSessionStats([
        ExerciseLog(
          name: 'Bench',
          exerciseId: 'e1',
          sets: [
            SetLog(
              pReps: '10',
              pWeight: '40',
              pRest: '90',
              actualReps: '10',
              actualWeight: '40',
              state: SetLogState.completed,
            ),
          ],
        ),
      ]);
      expect(stats.completedSets, stats.totalSets);
      expect(stats.skippedSets, 0);
      expect(stats.targetHitPct, 1.0);
      expect(stats.volumeKg, 400);
    });
  });
}
