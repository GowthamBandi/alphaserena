// ═══════════════════════════════════════════════════════════════════════════
// THE TIME AXIS MUST LABEL EXACTLY TWO DATES — THE TWO ENDS
// ═══════════════════════════════════════════════════════════════════════════
//
// `progress_chart.dart` states this as its contract:
//
//     // Exactly two dated anchors — the ends. Intermediate ticks on a
//     // time axis whose points are irregular label positions that no
//     // record sits on, which is worse than not labelling them.
//     interval: (maxX - minX).abs().clamp(1.0, double.infinity),
//
// It does not hold, and the emulator showed it: a two-point Nutrition series
// rendered "3 Aug · 3 Aug · 4 Aug" — the same day labelled twice, and a middle
// tick sitting on no record at all.
//
// ── WHY, PROVEN FROM fl_chart 1.2.0's OWN SOURCE ───────────────────────────
//
// `AxisChartHelper.iterateThroughAxis` does NOT anchor its tick sequence to
// `minX`. It anchors to the axis BASELINE — `LineChartData.baselineX`, which
// defaults to **0, the Unix epoch** — via
// `Utils.getBestInitialIntervalValue(min, max, interval, baseline: 0)`:
//
//     final diff = baseline - min;        // = -minX, a huge negative number
//     final mod  = diff % interval;       // Dart % → [0, interval)
//     if ((max - min).abs() <= mod) return min;
//     if (mod == 0) return min;
//     return min + mod;                   // ← an INTERIOR tick
//
// With `interval == maxX - minX`, `mod` is the offset of the member's first
// data point from an epoch-aligned grid — an arbitrary instant strictly inside
// the span. So `initialValue` lands in the middle of the chart. Then, because
// `minIncluded` and `maxIncluded` both default to true, the iterator ALSO
// yields `min` and `max` around it:
//
//     if (minIncluded && !firstPositionOverlapsWithMin) yield min;   // label 1
//     while (axisSeek <= end + epsilon) yield axisSeek;              // label 2
//     if (maxIncluded && !lastPositionOverlapsWithMax) yield max;    // label 3
//
// THREE labels, for every series whose start is not exactly interval-aligned
// with the epoch — which is essentially every series a member will ever have.
// Whether the middle one happens to read the same as an end is luck; on the
// device it did, which is what made the defect visible as a duplicate.
//
// So this is an AXIS INTERVAL / BASELINE interaction. It is NOT a formatter
// bug (the formatter is asked for a third value and answers correctly), NOT a
// timezone bug, NOT floating-point rounding, and NOT duplicate source data —
// the series genuinely has two points, which the first test below pins.

import 'package:alphaserena/core/analytics/progress_analytics.dart';
import 'package:alphaserena/core/theme/app_colors.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/progress/progress_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The exact series the emulator rendered as "3 Aug · 3 Aug · 4 Aug":
/// two nutrition-adherence days, consecutive.
final _twoDays = <TrendPoint>[
  TrendPoint(DateTime(2026, 8, 3, 9, 17), 0.70),
  TrendPoint(DateTime(2026, 8, 4, 9, 17), 0.41),
];

Future<void> _pumpChart(
  WidgetTester tester,
  List<TrendPoint> series, {
  SeriesKind kind = SeriesKind.ratio,
  String unit = '',
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(390, 700);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ProgressChart(
              series: series,
              palette: context.palette,
              kind: kind,
              unit: unit,
            ),
          ),
        ),
      ),
    ),
  );
  // Past the draw-in animation, so the axis is in its settled state.
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
}

/// Every date-shaped label the chart rendered ("3 Aug", "12 Sep", …).
List<String> _dateLabels(WidgetTester tester) {
  final re = RegExp(r'^\d{1,2} [A-Z][a-z]{2}$');
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where(re.hasMatch)
      .toList();
}

void main() {
  testWidgets('the series really does have exactly two points', (tester) async {
    // Rules out "duplicate source data" as the explanation before the axis is
    // accused of anything.
    expect(_twoDays.length, 2);
    expect(_twoDays[0].date.day, 3);
    expect(_twoDays[1].date.day, 4);
  });

  testWidgets('a two-point series labels exactly its two ends', (tester) async {
    await _pumpChart(tester, _twoDays);
    final labels = _dateLabels(tester);
    expect(
      labels,
      ['3 Aug', '4 Aug'],
      reason:
          'The time axis rendered $labels. The chart promises "exactly two '
          'dated anchors — the ends", but fl_chart anchors its ticks to '
          'baselineX (the Unix epoch), not to minX, so it emits an interior '
          'tick AND both ends. On the emulator this read "3 Aug · 3 Aug · '
          '4 Aug" — the same day labelled twice, and a tick on no record.',
    );
  });

  testWidgets('no date is ever labelled twice', (tester) async {
    await _pumpChart(tester, _twoDays);
    final labels = _dateLabels(tester);
    expect(
      labels.toSet().length,
      labels.length,
      reason: 'A duplicated axis label reads as a rendering fault: $labels',
    );
  });

  testWidgets('a long daily series still labels only its two ends', (
    tester,
  ) async {
    final long = <TrendPoint>[
      for (var i = 30; i >= 0; i--)
        TrendPoint(
          DateTime(2026, 8, 4, 7, 41).subtract(Duration(days: i)),
          0.5 + (i % 7) / 20,
        ),
    ];
    await _pumpChart(tester, long);
    expect(_dateLabels(tester), ['5 Jul', '4 Aug']);
  });

  testWidgets('a scalar (weight) series obeys the same rule', (tester) async {
    final weight = <TrendPoint>[
      TrendPoint(DateTime(2026, 6, 1, 8), 84.2),
      TrendPoint(DateTime(2026, 7, 1, 8), 82.6),
      TrendPoint(DateTime(2026, 8, 1, 8), 81.1),
    ];
    await _pumpChart(tester, weight, kind: SeriesKind.scalar, unit: 'kg');
    expect(_dateLabels(tester), ['1 Jun', '1 Aug']);
  });

  testWidgets('two points on the SAME day still render one label each end', (
    tester,
  ) async {
    // A degenerate span: minX and maxX differ by hours, not days. The clamp in
    // the interval guards against a zero span; this pins that the label count
    // does not change shape when it engages.
    final sameDay = <TrendPoint>[
      TrendPoint(DateTime(2026, 8, 4, 6), 0.4),
      TrendPoint(DateTime(2026, 8, 4, 21), 0.8),
    ];
    await _pumpChart(tester, sameDay);
    final labels = _dateLabels(tester);
    expect(labels.length, lessThanOrEqualTo(2), reason: 'rendered $labels');
    expect(labels.toSet().length, labels.length, reason: 'rendered $labels');
  });
}
