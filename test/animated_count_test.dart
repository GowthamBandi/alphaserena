import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/core/widgets/serena/premium_states.dart';
import 'package:alphaserena/screens/dashboard/home/daily_metric.dart';

/// THE RULES A COUNTING NUMBER MUST OBEY.
///
/// A counter is the one animation in the app that displays FALSE VALUES on
/// purpose — every figure between where it started and where it is going. That
/// is fine while something else on screen is making the same claim (the ring
/// sweeping from empty), and it is a lie the rest of the time. These tests pin
/// which is which, because the difference is invisible in a screenshot and
/// obvious to a member.

void main() {
  Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(body: Center(child: child)),
        ),
      );

  Widget counter(
    double? value, {
    bool animateOnAppear = true,
  }) =>
      AnimatedCount(
        value: value,
        animateOnAppear: animateOnAppear,
        builder: (context, shown) =>
            Text(shown == null ? '—' : shown.round().toString()),
      );

  group('counting up', () {
    testWidgets('travels to its value instead of teleporting to it',
        (tester) async {
      await tester.pumpWidget(host(counter(1000)));

      // First frame: at the start of the tween, not at the destination.
      expect(find.text('1000'), findsNothing);

      await tester.pump(const Duration(milliseconds: 450));
      final mid = int.parse(
        (tester.widget<Text>(find.byType(Text)).data)!,
      );
      expect(mid, greaterThan(0), reason: 'it should have left zero');
      expect(mid, lessThan(1000), reason: 'it should not be there yet');

      await tester.pumpAndSettle();
      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets('settles exactly on its figure, never near it', (tester) async {
      await tester.pumpWidget(host(counter(165)));
      await tester.pumpAndSettle();
      expect(find.text('165'), findsOneWidget);
    });

    testWidgets('a later change departs from the figure on screen, '
        'not from zero', (tester) async {
      await tester.pumpWidget(host(counter(1000)));
      await tester.pumpAndSettle();

      await tester.pumpWidget(host(counter(1300)));
      await tester.pump(const Duration(milliseconds: 60));

      final shown = int.parse(
        (tester.widget<Text>(find.byType(Text)).data)!,
      );
      // The mission's own example: 1200 → 1300 must not replay from nothing.
      expect(shown, greaterThan(900),
          reason: 'logging a meal must advance the number, not restart it');
    });
  });

  group('what must never animate', () {
    testWidgets('null renders its em dash with no tween at all',
        (tester) async {
      await tester.pumpWidget(host(counter(null)));
      expect(find.text('—'), findsOneWidget);
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    });

    testWidgets('reduced motion arrives immediately', (tester) async {
      await tester.pumpWidget(host(counter(1000), reduceMotion: true));
      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets(
        'animateOnAppear:false never passes through zero on first build',
        (tester) async {
      await tester.pumpWidget(host(counter(5, animateOnAppear: false)));

      // THE STREAK RULE. A member with a 5-day streak must never be shown
      // "0" — not even for one frame, not even on the way up.
      expect(find.text('5'), findsOneWidget);
      expect(find.text('0'), findsNothing);

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('animateOnAppear:false STILL animates a real change',
        (tester) async {
      await tester.pumpWidget(host(counter(5, animateOnAppear: false)));
      await tester.pumpAndSettle();

      await tester.pumpWidget(host(counter(6, animateOnAppear: false)));
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('6'), findsNothing,
          reason: 'earning a day should be felt, not just reported');

      await tester.pumpAndSettle();
      expect(find.text('6'), findsOneWidget);
    });
  });

  group('only the numerator moves', () {
    final metric = DailyMetric(
      label: 'Calories',
      unit: 'kcal',
      format: (v) => v.round().toString(),
      current: 1000,
      target: 2000,
    );

    test('the coach target is never counted up from zero', () {
      // Mid-count the member has eaten "some of 2000" — the denominator is a
      // prescription they did not change and must not appear to.
      expect(metric.valueLabelFor(0), '0 / 2000 kcal');
      expect(metric.valueLabelFor(640), '640 / 2000 kcal');
      expect(metric.valueLabelFor(1000), '1000 / 2000 kcal');
      expect(metric.valueLabelFor(1000), metric.valueLabel);
    });

    test('status is derived from the REAL value, not the frame', () {
      final met = DailyMetric(
        label: 'Protein',
        unit: 'g',
        format: (v) => v.round().toString(),
        current: 150,
        target: 150,
      );
      // Passing through 40% must not re-render this as a shortfall.
      expect(met.status, MetricStatus.met);
      expect(met.valueLabelFor(60), '60 / 150 g');
      expect(met.status, MetricStatus.met);
    });

    test('an em dash survives an intermediate frame', () {
      final nothing = DailyMetric(
        label: 'Fiber',
        unit: 'g',
        format: (v) => v.round().toString(),
        target: 30,
      );
      expect(nothing.valueLabelFor(null), '— / 30 g');
      expect(nothing.percentFor(null), isNull);
    });
  });
}
