import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/core/widgets/premium_video_player.dart';
import 'package:alphaserena/screens/dashboard/workout_player_screen.dart';

/// THE PLAYER'S HONESTY STATES.
///
/// The decoder itself needs a platform channel and cannot run here, but the
/// two states that MATTER most to a member are reachable without one — "your
/// coach attached no video" and "a video exists and will not load" — and they
/// are precisely the two the old screen got wrong (it showed a spinner
/// forever). Those are pinned here, along with the exercise screen's rule
/// that no field is ever rendered from a placeholder.
void main() {
  Widget host(Widget child, {double textScale = 1.0}) => MaterialApp(
    theme: AppTheme.dark,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  group('PremiumVideoPlayer — absence vs failure', () {
    testWidgets('no video attached is a calm absence, not an error',
        (tester) async {
      await tester.pumpWidget(host(const PremiumVideoPlayer(videoUrl: '')));
      expect(find.text('No demo video'), findsOneWidget);
      expect(find.textContaining("hasn't attached"), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a whitespace url is still "no video", not a failure',
        (tester) async {
      await tester.pumpWidget(host(const PremiumVideoPlayer(videoUrl: '   ')));
      expect(find.text('No demo video'), findsOneWidget);
    });

    testWidgets('an unplayable url fails LOUDLY instead of spinning forever',
        (tester) async {
      await tester.pumpWidget(
          host(const PremiumVideoPlayer(videoUrl: 'not-a-real-url')));
      await tester.pump();
      expect(find.text("Video couldn't load"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // The one thing the old screen did: an endless promise.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('the failure state offers a reachable Retry', (tester) async {
      await tester.pumpWidget(
          host(const PremiumVideoPlayer(videoUrl: 'not-a-real-url')));
      await tester.pump();
      expect(
        find.bySemanticsLabel(RegExp('Retry loading the video')),
        findsOneWidget,
      );
    });

    testWidgets('the empty state survives 1.6x text scale', (tester) async {
      await tester.pumpWidget(
          host(const PremiumVideoPlayer(videoUrl: ''), textScale: 1.6));
      expect(tester.takeException(), isNull);
    });
  });

  group('WorkoutPlayerScreen — nothing is rendered from a placeholder', () {
    // A real phone is tall and narrow; the default 800×600 test surface is
    // neither, and it would leave the chip row unbuilt below the fold.
    setUp(() {
      final view = TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .first;
      view.physicalSize = const Size(1080, 2400);
      view.devicePixelRatio = 3.0;
    });
    tearDown(() {
      final view = TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .first;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    testWidgets('a fully curated exercise shows every real field',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: const WorkoutPlayerScreen(exercise: {
          'name': 'Bench Press',
          'sets': 4,
          'reps': '8-12',
          'weight': '60',
          'muscleGroup': 'Chest',
          'equipment': 'Barbell',
          'difficulty': 'Intermediate',
          'instructions': 'Retract the shoulder blades and control the descent.',
          'videoUrl': '',
        }),
      ));
      expect(find.text('Bench Press'), findsWidgets);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('8-12'), findsOneWidget);
      expect(find.text('Chest'), findsOneWidget);
      expect(find.text('Barbell'), findsOneWidget);
      expect(find.text('Intermediate'), findsOneWidget);
      expect(find.text('HOW TO'), findsOneWidget);
      expect(find.textContaining('Retract the shoulder'), findsOneWidget);
    });

    testWidgets('a bare exercise renders NO empty labels', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: const WorkoutPlayerScreen(exercise: {'name': 'Mobility Flow'}),
      ));
      // Absent data produces no heading — "—" beside a label would claim the
      // coach left something blank.
      expect(find.text('HOW TO'), findsNothing);
      expect(find.text('SETS'), findsNothing);
      expect(find.text('WEIGHT'), findsNothing);
      expect(find.text('No demo video'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a zero prescription is treated as missing, never as "0 sets"',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: const WorkoutPlayerScreen(exercise: {
          'name': 'Plank',
          'sets': 0,
          'reps': '60s',
          'weight': '0',
        }),
      ));
      expect(find.text('SETS'), findsNothing);
      expect(find.text('WEIGHT'), findsNothing);
      expect(find.text('REPS'), findsOneWidget);
      expect(find.text('60s'), findsOneWidget);
    });

    testWidgets('a video duration chip needs a video to exist', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: const WorkoutPlayerScreen(exercise: {
          'name': 'Squat',
          'videoDurationSeconds': 95,
          'videoUrl': '', // no video → no duration claim
        }),
      ));
      expect(find.text('1:35'), findsNothing);
    });

    testWidgets('an unnamed exercise still has an honest title', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: const WorkoutPlayerScreen(exercise: {}),
      ));
      expect(find.text('Exercise'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
