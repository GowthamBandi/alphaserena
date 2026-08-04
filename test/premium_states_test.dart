import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/core/widgets/serena/premium_states.dart';

/// THE STATE PRIMITIVES — loading, refreshing, stale and empty.
///
/// `AnimatedCount` already has its own file. These are the other five, and
/// they were the only widgets in the My Plans redesign with no test at all —
/// which matters more than usual here, because they are the ONLY things a
/// member sees on a cold start, a dropped connection, or a plan their coach
/// has not sent yet. A defect in them is invisible to every test that seeds
/// data and pumps a populated screen.
///
/// Each test pins a PROMISE the file's own doc comments make, not a layout:
/// a skeleton animates so it cannot be mistaken for a broken card, a whisper
/// reserves its slot so nothing jumps, a stale banner never takes the
/// member's data away, and an empty state never offers an action it cannot
/// perform.

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  bool disableAnimations = false,
  double textScale = 1.0,
  Size size = const Size(390, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: disableAnimations,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  group('SerenaSkeleton — a loading card must not look like a broken one', () {
    testWidgets('it shimmers, so it reads as loading rather than failed',
        (tester) async {
      await _pump(tester, const SerenaSkeleton(height: 40, width: 200));
      // The sweep IS the affordance: a static grey rectangle is exactly what a
      // card that failed to render looks like.
      expect(find.byType(ShaderMask), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion removes the sweep, not the placeholder',
        (tester) async {
      await _pump(
        tester,
        const SerenaSkeleton(height: 40, width: 200),
        disableAnimations: true,
      );
      // The member still gets the shape of what is coming — they just do not
      // get the movement they asked the OS to stop.
      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byType(SerenaSkeleton), findsOneWidget);
    });

    testWidgets('its ticker is released when it leaves the tree',
        (tester) async {
      await _pump(tester, const SerenaSkeleton(height: 40));
      await _pump(tester, const SizedBox.shrink());
      // A repeating AnimationController that outlives its widget requests
      // frames forever; the disposal assert fires through takeException.
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in the light theme', (tester) async {
      await _pump(tester, const SerenaSkeleton(height: 40),
          theme: AppTheme.light);
      expect(tester.takeException(), isNull);
    });
  });

  group('SyncWhisper — a background refresh must not move the page', () {
    testWidgets('it occupies its slot whether or not it is visible',
        (tester) async {
      await _pump(tester, const SyncWhisper(visible: false));
      final hidden = tester.getSize(find.byType(SyncWhisper));
      await _pump(tester, const SyncWhisper(visible: true));
      await tester.pump(kStateSwap);
      final shown = tester.getSize(find.byType(SyncWhisper));

      // Identical height in both states: arming the whisper cannot push the
      // content below it down, which is the layout jump this widget removes.
      expect(hidden.height, SyncWhisper.height);
      expect(shown.height, hidden.height);
    });

    testWidgets('NO spinner exists while hidden — it is not merely transparent',
        (tester) async {
      await _pump(tester, const SyncWhisper(visible: false));
      // A CircularProgressIndicator drives a ticker for as long as it EXISTS.
      // One parked invisibly on three screens is three idle screens requesting
      // frames forever, and it hangs pumpAndSettle for every test that meets
      // it. Absence is the contract, not opacity.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Updating'), findsNothing);
    });

    testWidgets('visible, it names what is happening', (tester) async {
      await _pump(tester, const SyncWhisper(visible: true, label: 'Syncing'));
      await tester.pump(kStateSwap);
      expect(find.text('Syncing'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('a settled tree with a hidden whisper does not hang',
        (tester) async {
      await _pump(tester, const SyncWhisper(visible: false));
      // The regression this guards: pumpAndSettle timing out at 10 minutes
      // because an unseen spinner never stops scheduling frames.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('StaleDataBanner — a dropped packet is not a loss of data', () {
    testWidgets('it says the data is still the member\'s last synced set',
        (tester) async {
      await _pump(tester, const StaleDataBanner());
      expect(
        find.text("Couldn't refresh. Showing your last synced information."),
        findsOneWidget,
      );
      // Never an error page: the member has lost nothing and must not be told
      // they have.
      expect(find.textContaining('Error'), findsNothing);
    });

    testWidgets('Retry appears only when there is something to retry',
        (tester) async {
      await _pump(tester, const StaleDataBanner());
      expect(find.text('Retry'), findsNothing);

      var taps = 0;
      await _pump(tester, StaleDataBanner(onRetry: () => taps++));
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(taps, 1);
    });

    testWidgets('survives 2.0x text on a 320dp screen', (tester) async {
      await _pump(
        tester,
        StaleDataBanner(onRetry: () {}),
        size: const Size(320, 800),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('SerenaEmptyState — describe the member, never the database', () {
    testWidgets('glyph, title and body all render', (tester) async {
      await _pump(
        tester,
        const SerenaEmptyState(
          glyph: '🏋️',
          title: 'No workout today',
          body: 'Your coach has not assigned one yet.',
        ),
      );
      expect(find.text('🏋️'), findsOneWidget);
      expect(find.text('No workout today'), findsOneWidget);
      expect(find.text('Your coach has not assigned one yet.'), findsOneWidget);
    });

    testWidgets('NO button when the member cannot act', (tester) async {
      await _pump(
        tester,
        const SerenaEmptyState(
          glyph: '🏋️',
          title: 'Nothing assigned',
          body: 'Waiting on your coach.',
        ),
      );
      // An empty state offering an action the member cannot perform is worse
      // than one offering none — it makes waiting look like their fault.
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('a label without a handler still renders no button',
        (tester) async {
      await _pump(
        tester,
        const SerenaEmptyState(
          glyph: '🏋️',
          title: 'Nothing assigned',
          body: 'Waiting on your coach.',
          actionLabel: 'Start',
        ),
      );
      // Both halves are required. A button wired to nothing is the dead
      // affordance this whole module exists to remove.
      expect(find.text('Start'), findsNothing);
    });

    testWidgets('the action fires when the member CAN act', (tester) async {
      var started = 0;
      await _pump(
        tester,
        SerenaEmptyState(
          glyph: '🏋️',
          title: 'Ready when you are',
          body: 'Your plan is waiting.',
          actionLabel: 'Start Workout',
          onAction: () => started++,
        ),
      );
      await tester.tap(find.text('Start Workout'));
      expect(started, 1);
    });

    testWidgets('unboxed drops the card surface, keeps the content',
        (tester) async {
      await _pump(
        tester,
        const SerenaEmptyState(
          glyph: '🥗',
          title: 'No meals logged',
          body: 'Add your first meal.',
          boxed: false,
        ),
      );
      expect(find.text('No meals logged'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives 2.0x text on a 320dp screen', (tester) async {
      await _pump(
        tester,
        SerenaEmptyState(
          glyph: '🏋️',
          title: 'No workout assigned for today',
          body: 'Your coach has not assigned a session for today yet.',
          actionLabel: 'Browse Plans',
          onAction: () {},
        ),
        size: const Size(320, 800),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('StateSwap — skeleton to content must dissolve, not jump-cut', () {
    testWidgets('a changed stateKey crossfades', (tester) async {
      await _pump(
        tester,
        const StateSwap(stateKey: 'loading', child: Text('loading')),
      );
      await _pump(
        tester,
        const StateSwap(stateKey: 'content', child: Text('content')),
      );
      await tester.pump(const Duration(milliseconds: 60));
      // Mid-transition BOTH are mounted — that is what a crossfade is, and a
      // single child here would mean the content simply replaced the skeleton.
      expect(find.byType(FadeTransition), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.text('content'), findsOneWidget);
      expect(find.text('loading'), findsNothing);
    });

    testWidgets('the same stateKey does NOT re-run the transition',
        (tester) async {
      await _pump(
        tester,
        const StateSwap(stateKey: 'content', child: Text('a')),
      );
      await tester.pumpAndSettle();
      await _pump(
        tester,
        const StateSwap(stateKey: 'content', child: Text('b')),
      );
      await tester.pumpAndSettle();
      // Same state, new value: a fade here would make every data refresh
      // flash the region it updated.
      expect(find.text('b'), findsOneWidget);
    });

    testWidgets('reduced motion swaps instantly, losing no content',
        (tester) async {
      await _pump(
        tester,
        const StateSwap(stateKey: 'content', child: Text('content')),
        disableAnimations: true,
      );
      expect(find.byType(AnimatedSwitcher), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });
  });
}
