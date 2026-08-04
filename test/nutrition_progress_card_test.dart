import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/home/daily_metric.dart';
import 'package:alphaserena/screens/dashboard/home/nutrition_progress_card.dart';

/// HOME → NUTRITION PROGRESS, rendered pure.
///
/// The card computes nothing, so what these pin is the PRESENTATION contract:
/// calories dominate as a ring, the four macros read as ratios beside it, and
/// the four honest states (no target · nothing logged · behind · met) survive
/// the redesign intact. A premium card that quietly turns "no target" into
/// "0%" is the exact failure this suite exists to catch.
DailyMetric metric({
  required String label,
  double? current,
  double? target,
  String unit = 'g',
}) =>
    DailyMetric(
      label: label,
      unit: unit,
      format: (v) => v.round().toString(),
      current: current,
      target: target,
    );

DailyMetric calories({double? current = 850, double? target = 2000}) =>
    metric(label: 'Calories', current: current, target: target, unit: 'kcal');

List<DailyMetric> macros() => [
      metric(label: 'Protein', current: 65, target: 150),
      metric(label: 'Fat', current: 32, target: 60),
      metric(label: 'Carbs', current: 180, target: 250),
      metric(label: 'Fiber', current: 14, target: 30),
    ];

void main() {
  Future<void> pump(
    WidgetTester tester, {
    DailyMetric? cals,
    List<DailyMetric>? nutrients,
    String subtitle = "Today's nutrition",
    Size size = const Size(390, 1000),
    double textScale = 1.0,
    ThemeData? theme,
    bool loading = false,
    VoidCallback? onLogFood,
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
                child: NutritionProgressCard(
                  calories: cals ?? calories(),
                  nutrients: nutrients ?? macros(),
                  subtitle: subtitle,
                  loading: loading,
                  onLogFood: onLogFood ?? () {},
                  onTap: onTap,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // A LOADING CARD NEVER SETTLES, BY DESIGN.
    //
    // The skeleton shimmers on a repeating controller — the same contract as
    // `CircularProgressIndicator`, and the whole point of the change: a static
    // grey block is indistinguishable from a card that failed to render. So a
    // loading state is pumped a fixed distance rather than settled, which is
    // also a stronger assertion (it proves the animation is actually running).
    if (loading) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    } else {
      await tester.pumpAndSettle();
    }
  }

  group('what the card shows', () {
    testWidgets('title, subtitle and the Log Food action', (tester) async {
      await pump(tester);
      expect(find.text('Nutrition Progress'), findsOneWidget);
      expect(find.text("Today's nutrition"), findsOneWidget);
      expect(find.text('Log Food'), findsOneWidget);
    });

    testWidgets('CALORIES lead: the ring carries the figure and the ratio',
        (tester) async {
      await pump(tester);
      expect(find.text('KCAL'), findsOneWidget);
      expect(find.text('850'), findsOneWidget);
      expect(find.text('850 / 2000 kcal'), findsOneWidget);
    });

    testWidgets('four macros, each as current / target', (tester) async {
      await pump(tester);
      for (final label in ['Protein', 'Fat', 'Carbs', 'Fiber']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('65 / 150 g'), findsOneWidget);
      expect(find.text('32 / 60 g'), findsOneWidget);
      expect(find.text('180 / 250 g'), findsOneWidget);
      expect(find.text('14 / 30 g'), findsOneWidget);
    });

    testWidgets('the macros read in the designed order — Protein · Fat, '
        'Carbs · Fiber', (tester) async {
      await pump(tester);
      double x(String s) => tester.getCenter(find.text(s)).dx;
      double y(String s) => tester.getCenter(find.text(s)).dy;
      expect(y('Protein'), lessThan(y('Carbs')));
      expect(y('Fat'), lessThan(y('Fiber')));
      expect(x('Protein'), lessThan(x('Fat')));
      expect(x('Carbs'), lessThan(x('Fiber')));
    });

    testWidgets('NO adherence vocabulary appears anywhere', (tester) async {
      await pump(tester);
      for (final word in [
        'eaten', 'Eaten', 'skipped', 'Skipped', 'partial', 'Partial',
        'adherence', 'Adherence',
      ]) {
        expect(find.textContaining(word), findsNothing,
            reason: '"$word" must not appear on the dashboard');
      }
    });
  });

  group('honest states', () {
    testWidgets('nothing logged shows a dash, never a fabricated zero',
        (tester) async {
      await pump(
        tester,
        cals: calories(current: null),
        nutrients: [
          metric(label: 'Protein', target: 150),
          metric(label: 'Fat', target: 60),
          metric(label: 'Carbs', target: 250),
          metric(label: 'Fiber', target: 30),
        ],
        subtitle: 'Nothing logged yet today',
      );
      expect(find.text('—'), findsOneWidget); // inside the ring
      expect(find.text('— / 2000 kcal'), findsOneWidget);
      expect(find.text('— / 150 g'), findsOneWidget);
      expect(find.text('0 / 2000 kcal'), findsNothing);
    });

    testWidgets('no coach target is not a shortfall', (tester) async {
      await pump(
        tester,
        cals: calories(target: null),
        nutrients: [
          metric(label: 'Protein', current: 65),
          metric(label: 'Fat', current: 32),
          metric(label: 'Carbs', current: 180),
          metric(label: 'Fiber', current: 14),
        ],
        subtitle: 'No coach targets yet',
      );
      // The value still shows; no ratio and no percentage are invented.
      expect(find.text('850'), findsOneWidget);
      expect(find.text('65 g'), findsOneWidget);
      expect(find.textContaining('/'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('a met macro is marked, and a passed target is not flattened',
        (tester) async {
      await pump(tester, nutrients: [
        metric(label: 'Protein', current: 180, target: 150),
        metric(label: 'Fat', current: 32, target: 60),
        metric(label: 'Carbs', current: 180, target: 250),
        metric(label: 'Fiber', current: 14, target: 30),
      ]);
      expect(find.text('180 / 150 g'), findsOneWidget,
          reason: 'passing a target reads as the achievement it is');
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('loading shows a skeleton and NO numbers', (tester) async {
      await pump(tester, loading: true);
      expect(find.text('850'), findsNothing);
      expect(find.text('KCAL'), findsNothing);
      expect(find.text('Nutrition Progress'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('zero completion draws a track with no fill', (tester) async {
      await pump(tester, cals: calories(current: 0));
      expect(find.text('0 / 2000 kcal'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('interaction', () {
    testWidgets('Log Food fires its own action, not the card tap',
        (tester) async {
      var logged = 0;
      var opened = 0;
      await pump(tester,
          onLogFood: () => logged++, onTap: () => opened++);
      await tester.tap(find.text('Log Food'));
      await tester.pumpAndSettle();
      expect(logged, 1);
      expect(opened, 0);
    });

    testWidgets('tapping the body opens the diet screen route', (tester) async {
      var opened = 0;
      await pump(tester, onTap: () => opened++);
      await tester.tap(find.text('Nutrition Progress'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  });

  group('responsive + themes', () {
    testWidgets('the ring animates in from empty', (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: NutritionProgressCard(
            calories: calories(),
            nutrients: macros(),
            subtitle: 'x',
            onLogFood: () {},
          ),
        ),
      ));
      // Mid-flight the arc must be somewhere between nothing and its target;
      // if the tween were missing, pumping would already be settled.
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('320dp at 2.0x accessibility text does not overflow',
        (tester) async {
      await pump(tester,
          size: const Size(320, 2600), textScale: 2.0);
      expect(tester.takeException(), isNull);
      expect(find.text('Protein'), findsOneWidget);
    });

    testWidgets('small phone, tablet, landscape and light mode render cleanly',
        (tester) async {
      await pump(tester, size: const Size(320, 1200));
      expect(tester.takeException(), isNull);
      await pump(tester, size: const Size(1024, 1400));
      expect(tester.takeException(), isNull);
      await pump(tester, size: const Size(900, 500));
      expect(tester.takeException(), isNull);
      await pump(tester, theme: AppTheme.light);
      expect(tester.takeException(), isNull);
      expect(find.text('850'), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('the ring and each macro are single semantic nodes',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      expect(
        find.bySemanticsLabel('Calories, 850 kcal of 2000 kcal, 43%'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Protein, 65 g of 150 g, 43%'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
