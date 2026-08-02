import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/home/daily_progress_card.dart';

/// THE HOME DASHBOARD'S PROGRESS SECTIONS.
///
/// One widget serves both Lifestyle and Nutrition, so the two can never drift
/// in layout, status vocabulary or how they express "not logged". These pin
/// the distinctions the widget exists to preserve: a target nobody set, a day
/// nobody logged, a shortfall and an achievement are four different facts and
/// only one of them is a failure.
DailyMetric metric({
  String label = 'Water',
  double? current,
  double? target,
  String unit = 'glasses',
}) =>
    DailyMetric(
      label: label,
      icon: Icons.water_drop_outlined,
      unit: unit,
      format: (v) => v.round().toString(),
      current: current,
      target: target,
    );

void main() {
  group('status distinguishes four different facts', () {
    test('no target set is NOT a shortfall', () {
      final m = metric(current: 6);
      expect(m.status, MetricStatus.noTarget);
      expect(m.progress, isNull, reason: 'a bar against no target draws nothing');
      expect(m.percent, isNull);
      expect(m.targetLabel, 'No target set');
    });

    test('nothing logged is distinct from logging zero', () {
      final m = metric(target: 12);
      expect(m.status, MetricStatus.notLogged);
      expect(m.currentLabel, '—', reason: 'never a fabricated 0');
      expect(m.progress, isNull);
    });

    test('logged below target is behind', () {
      final m = metric(current: 6, target: 12);
      expect(m.status, MetricStatus.behind);
      expect(m.progress, 0.5);
      expect(m.percent, 50);
    });

    test('reaching the target is met', () {
      expect(metric(current: 12, target: 12).status, MetricStatus.met);
    });

    test('passing the target reads as the achievement it is', () {
      final m = metric(current: 18, target: 12);
      expect(m.status, MetricStatus.met);
      // The BAR clamps so it cannot overflow its track...
      expect(m.progress, 1.0);
      // ...but the PERCENTAGE does not, so 150% is not flattened to 100%.
      expect(m.percent, 150);
    });

    test('a zero or negative target counts as no target', () {
      // A stored 0 is "not set", not a goal of nothing.
      expect(metric(current: 5, target: 0).status, MetricStatus.noTarget);
      expect(metric(current: 5, target: -3).status, MetricStatus.noTarget);
    });
  });

  group('the on-track summary', () {
    test('counts ONLY metrics that have a target', () {
      // Otherwise setting fewer goals would lower the score.
      final summary = DailyProgressCard.onTrackSummary([
        metric(label: 'Water', current: 12, target: 12),
        metric(label: 'Steps', current: 4000, target: 8000),
        metric(label: 'Sleep', current: 7), // untargeted — not counted
      ]);
      expect(summary, '1 of 2 on track');
    });

    test('no targets at all yields no summary, not "0 of 0"', () {
      expect(
        DailyProgressCard.onTrackSummary([metric(current: 6)]),
        isNull,
      );
    });

    test('an unlogged targeted metric counts against the total', () {
      final summary = DailyProgressCard.onTrackSummary([
        metric(label: 'Water', current: 12, target: 12),
        metric(label: 'Steps', target: 8000),
      ]);
      expect(summary, '1 of 2 on track');
    });
  });

  group('rendering', () {
    Future<void> pump(
      WidgetTester tester,
      List<DailyMetric> metrics, {
      Size size = const Size(390, 1200),
      double textScale = 1.0,
      ThemeData? theme,
      String? subtitle,
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
                child: DailyProgressCard(
                  title: 'Lifestyle progress',
                  titleIcon: Icons.favorite_border,
                  metrics: metrics,
                  subtitle: subtitle,
                  actionLabel: 'Log',
                  onAction: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows current, target and the section title', (tester) async {
      await pump(tester, [
        metric(label: 'Water', current: 6, target: 12),
        metric(label: 'Steps', current: 9200, target: 8000, unit: ''),
      ], subtitle: '1 of 2 on track');
      expect(find.text('Lifestyle progress'), findsOneWidget);
      expect(find.text('1 of 2 on track'), findsOneWidget);
      expect(find.text('6 / 12 glasses'), findsOneWidget);
      expect(find.text('Water'), findsOneWidget);
    });

    testWidgets('an untargeted metric shows its value, not a fake ratio',
        (tester) async {
      await pump(tester, [metric(label: 'Sleep', current: 7, unit: 'h')]);
      expect(find.text('7 h'), findsOneWidget);
      expect(find.textContaining('/'), findsNothing);
    });

    testWidgets('an unlogged metric shows a dash against its target',
        (tester) async {
      await pump(tester, [metric(label: 'Water', target: 12)]);
      expect(find.text('— / 12 glasses'), findsOneWidget);
    });

    testWidgets('NO adherence vocabulary appears anywhere', (tester) async {
      // The central product rule of this redesign: these words describe
      // compliance with a prescribed list and cannot express how much water
      // someone drank.
      await pump(tester, [
        metric(label: 'Water', current: 6, target: 12),
        metric(label: 'Steps', current: 9200, target: 8000, unit: ''),
      ], subtitle: '1 of 2 on track');
      for (final word in [
        'eaten', 'Eaten', 'skipped', 'Skipped', 'partial', 'Partial',
        'adherence', 'Adherence',
      ]) {
        expect(find.textContaining(word), findsNothing,
            reason: '"$word" must not appear on the dashboard');
      }
    });

    testWidgets('320dp at 2.0x accessibility text does not overflow',
        (tester) async {
      await pump(
        tester,
        [
          metric(label: 'Water', current: 6, target: 12),
          metric(label: 'Steps', current: 9200, target: 8000, unit: ''),
          metric(label: 'Sleep', current: 7.5, target: 8, unit: 'h'),
          metric(label: 'Supplements', current: 2, target: 3, unit: ''),
        ],
        size: const Size(320, 2400),
        textScale: 2.0,
        subtitle: '2 of 4 on track',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('light mode and tablet render cleanly', (tester) async {
      await pump(tester, [metric(current: 6, target: 12)],
          theme: AppTheme.light);
      expect(tester.takeException(), isNull);
      await pump(tester, [metric(current: 6, target: 12)],
          size: const Size(1024, 1400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('each row is ONE semantic node', (tester) async {
      // A screen reader should say "Water, 6 glasses of 12 glasses, 50 percent"
      // rather than five disconnected fragments.
      final handle = tester.ensureSemantics();
      await pump(tester, [metric(label: 'Water', current: 6, target: 12)]);
      expect(
        find.bySemanticsLabel(RegExp('Water, 6 glasses of 12 glasses, 50%')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
