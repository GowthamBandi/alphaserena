import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/home/daily_metric.dart';
import 'package:alphaserena/screens/dashboard/home/lifestyle_progress_card.dart';

/// HOME → LIFESTYLE PROGRESS, rendered pure.
///
/// The rules this pins are the ones a "premium" redesign is most likely to
/// quietly break: a supplements tile that appears when nothing was prescribed,
/// a "0%" printed against a target nobody set, a grid that leaves a hole when
/// there are three tiles instead of four, and a second affordance competing
/// with the card's single destination.
DailyMetric metric({
  required String label,
  double? current,
  double? target,
  String unit = '',
  String Function(double)? format,
}) =>
    DailyMetric(
      label: label,
      unit: unit,
      format: format ?? (v) => v.round().toString(),
      current: current,
      target: target,
    );

LifestyleTile water({double? current = 6, double? target = 12}) => LifestyleTile(
      metric: metric(
          label: 'Water', current: current, target: target, unit: 'glasses'),
      icon: Icons.water_drop_rounded,
      tint: const Color(0xFF29B6F6),
    );

LifestyleTile steps({double? current = 6500, double? target = 10000}) =>
    LifestyleTile(
      metric: metric(label: 'Steps', current: current, target: target),
      icon: Icons.directions_walk_rounded,
      tint: const Color(0xFFFB8C00),
    );

LifestyleTile sleep({double? current = 7.5, double? target = 8}) =>
    LifestyleTile(
      metric: metric(
        label: 'Sleep',
        current: current,
        target: target,
        format: (v) {
          final total = (v * 60).round();
          final h = total ~/ 60;
          final m = total % 60;
          return m == 0 ? '${h}h' : '${h}h ${m}m';
        },
      ),
      icon: Icons.bedtime_rounded,
      tint: const Color(0xFF7C83FF),
    );

LifestyleTile supplements({int taken = 2, int of = 3}) => LifestyleTile(
      metric: metric(
          label: 'Supplements',
          current: taken.toDouble(),
          target: of.toDouble()),
      icon: Icons.medication_rounded,
      tint: const Color(0xFF2EBD59),
      valueText: '$taken / $of',
      showGoal: false,
    );

void main() {
  Future<void> pump(
    WidgetTester tester, {
    List<LifestyleTile>? tiles,
    String subtitle = "Today's targets",
    Size size = const Size(390, 1000),
    double textScale = 1.0,
    ThemeData? theme,
    bool loading = false,
    VoidCallback? onTap,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: LifestyleProgressCard(
                  tiles: tiles ??
                      [water(), steps(), sleep(), supplements()],
                  subtitle: subtitle,
                  loading: loading,
                  onTap: onTap ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('what the card shows', () {
    testWidgets('title, subtitle and four tiles', (tester) async {
      await pump(tester);
      expect(find.text('Lifestyle Progress'), findsOneWidget);
      expect(find.text("Today's targets"), findsOneWidget);
      for (final label in ['Water', 'Steps', 'Sleep', 'Supplements']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('each tile carries value, goal and completion', (tester) async {
      await pump(tester);
      expect(find.text('6 glasses'), findsOneWidget);
      expect(find.text('Goal 12 glasses'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);

      expect(find.text('6500'), findsOneWidget);
      expect(find.text('Goal 10000'), findsOneWidget);
      expect(find.text('65%'), findsOneWidget);

      expect(find.text('7h 30m'), findsOneWidget);
      expect(find.text('Goal 8h'), findsOneWidget);
      expect(find.text('94%'), findsOneWidget);

      // Supplements are already a ratio — no redundant goal line under it.
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('67%'), findsOneWidget);
      expect(find.text('Goal 3'), findsNothing);
    });

    testWidgets('a 2×2 grid, not a vertical list', (tester) async {
      await pump(tester);
      Offset at(String s) => tester.getCenter(find.text(s));
      expect(at('Water').dy, closeTo(at('Steps').dy, 1));
      expect(at('Sleep').dy, closeTo(at('Supplements').dy, 1));
      expect(at('Water').dx, lessThan(at('Steps').dx));
      expect(at('Water').dy, lessThan(at('Sleep').dy));
    });

    testWidgets('there is NO History button — one card, one destination',
        (tester) async {
      await pump(tester);
      expect(find.text('History'), findsNothing);
      expect(find.text('Log'), findsNothing);
    });

    testWidgets('NO adherence vocabulary appears anywhere', (tester) async {
      await pump(tester);
      for (final word in [
        'eaten', 'Eaten', 'skipped', 'Skipped', 'partial', 'Partial',
        'adherence', 'Adherence',
      ]) {
        expect(find.textContaining(word), findsNothing);
      }
    });
  });

  group('supplements exist only when the coach prescribed a stack', () {
    testWidgets('no stack → no tile, and no hole where it was',
        (tester) async {
      await pump(tester, tiles: [water(), steps(), sleep()]);
      expect(find.text('Supplements'), findsNothing);
      // The odd tile takes the FULL width rather than sitting beside a gap.
      final sleepTileWidth = tester.getSize(find.ancestor(
        of: find.text('Sleep'),
        matching: find.byType(Container),
      ).first);
      final waterTileWidth = tester.getSize(find.ancestor(
        of: find.text('Water'),
        matching: find.byType(Container),
      ).first);
      expect(sleepTileWidth.width, greaterThan(waterTileWidth.width * 1.5));
    });

    testWidgets('a full stack renders the fourth tile', (tester) async {
      await pump(tester, tiles: [water(), steps(), sleep(), supplements()]);
      expect(find.text('Supplements'), findsOneWidget);
    });
  });

  group('honest states', () {
    testWidgets('nothing logged shows a dash and NO percentage',
        (tester) async {
      await pump(tester, tiles: [
        water(current: null),
        steps(current: null),
      ]);
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('Goal 12 glasses'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing,
          reason: '0% is a claim about the member, not about the data');
    });

    testWidgets('no coach target is not a shortfall', (tester) async {
      await pump(
        tester,
        tiles: [water(target: null), steps(target: null)],
        subtitle: 'No coach targets yet — you can still track your day',
      );
      expect(find.text('6 glasses'), findsOneWidget);
      expect(find.text('No target set'), findsNWidgets(2));
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('No coach targets yet'), findsOneWidget);
    });

    testWidgets('passing a target is not flattened to 100%', (tester) async {
      await pump(tester, tiles: [steps(current: 16000, target: 8000)]);
      expect(find.text('200%'), findsOneWidget);
    });

    testWidgets('full completion is marked in the done-today green',
        (tester) async {
      await pump(tester, tiles: [water(current: 12, target: 12)]);
      final pct = tester.widget<Text>(find.text('100%'));
      expect(pct.style!.color, const Color(0xFF2EBD59));
    });

    testWidgets('loading shows a skeleton and NO numbers', (tester) async {
      await pump(tester, loading: true);
      expect(find.text('Water'), findsNothing);
      expect(find.text('6 glasses'), findsNothing);
      expect(find.text('Lifestyle Progress'), findsOneWidget);
    });

    testWidgets('an empty tile list says so rather than drawing an empty grid',
        (tester) async {
      await pump(tester, tiles: []);
      expect(find.textContaining('Nothing to track yet'), findsOneWidget);
    });
  });

  group('interaction', () {
    testWidgets('tapping ANYWHERE opens the Today screen', (tester) async {
      var opened = 0;
      await pump(tester, onTap: () => opened++);
      await tester.tap(find.text('Lifestyle Progress'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      await tester.tap(find.text('7h 30m'));
      await tester.pumpAndSettle();
      expect(opened, 2, reason: 'a tile is not a dead zone');
    });

    testWidgets('a press shrinks the card, and it springs back',
        (tester) async {
      await pump(tester);
      double scale() => tester
          .widget<AnimatedScale>(find.byType(AnimatedScale).first)
          .scale;
      expect(scale(), 1);
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('Water')));
      await tester.pump(const Duration(milliseconds: 60));
      expect(scale(), lessThan(1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scale(), 1);
    });
  });

  group('responsive + themes', () {
    testWidgets('320dp at 2.0x accessibility text does not overflow',
        (tester) async {
      await pump(tester, size: const Size(320, 3000), textScale: 2.0);
      expect(tester.takeException(), isNull);
      expect(find.text('Water'), findsOneWidget);
    });

    testWidgets('small phone, tablet, landscape and light mode render cleanly',
        (tester) async {
      await pump(tester, size: const Size(320, 1400));
      expect(tester.takeException(), isNull);
      await pump(tester, size: const Size(1024, 1400));
      expect(tester.takeException(), isNull);
      await pump(tester, size: const Size(900, 500));
      expect(tester.takeException(), isNull);
      await pump(tester, theme: AppTheme.light);
      expect(tester.takeException(), isNull);
      expect(find.text('6 glasses'), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('each tile reads as ONE sentence, not five fragments',
        (tester) async {
      // The whole card is a single tap target, so the platform merges it into
      // one button node — which is the right behaviour for a card with one
      // destination. What matters is that the merged announcement still
      // carries each tile as a complete sentence ("Water, 6 glasses, Goal 12
      // glasses, 50% complete") rather than a stream of loose numbers.
      final handle = tester.ensureSemantics();
      await pump(tester);
      for (final sentence in [
        'Water, 6 glasses, Goal 12 glasses, 50% complete',
        'Steps, 6500, Goal 10000, 65% complete',
        'Sleep, 7h 30m, Goal 8h, 94% complete',
        'Supplements, 2 / 3, 67% complete',
      ]) {
        expect(find.bySemanticsLabel(RegExp(RegExp.escape(sentence))),
            findsOneWidget,
            reason: sentence);
      }
      handle.dispose();
    });

    testWidgets('the card announces itself as a button, and its destination',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      expect(
        find.bySemanticsLabel(RegExp("Lifestyle progress. Open today's")),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a tile never announces a percentage it does not have',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, tiles: [water(current: null), water(target: null)]);
      expect(find.bySemanticsLabel(RegExp('% complete')), findsNothing);
      handle.dispose();
    });
  });
}
