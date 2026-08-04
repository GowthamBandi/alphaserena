import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/analytics/progress_analytics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';

/// How a series should be READ, which decides its axis and its tooltip — not
/// how it should be coloured. A ratio is always 0..1 and gets a percentage
/// axis; a scalar is auto-ranged and carries its own unit.
enum SeriesKind { ratio, scalar }

/// THE ONE CHART OF THE PROGRESS MODULE.
///
/// ── WHY ONE ───────────────────────────────────────────────────────────────
///
/// The screen this replaces drew a single hand-rolled `LineChart` for weight
/// and nothing else, with three fixed x-labels regardless of range and a fixed
/// ±2 kg y-padding that flattened a 30 kg transformation while exaggerating a
/// 0.5 kg fluctuation. Every trend on the new screen — adherence, strength,
/// volume, weight, a measurement — is the same object, so a member learns to
/// read one thing and every axis obeys the same rules.
///
/// ── WHAT IT REFUSES TO DO ─────────────────────────────────────────────────
///
///  • It never interpolates. A day with no record is a GAP, not a point on a
///    line between its neighbours — `fl_chart` connects what it is given, and
///    it is only ever given days that happened.
///  • It never plots a fabricated zero. A caller passing an empty series gets
///    the empty state, not a flat line along the axis.
///  • It never implies precision it does not have. With fewer than two points
///    there is no trend, so it draws a single marker and says so.
class ProgressChart extends StatefulWidget {
  const ProgressChart({
    super.key,
    required this.series,
    required this.palette,
    required this.kind,
    this.unit = '',
    this.smooth = false,
    this.height = 190,
    this.semanticLabel,
  });

  final List<TrendPoint> series;
  final AppPalette palette;
  final SeriesKind kind;

  /// Rendered in the tooltip and the y-axis for a scalar series ("kg").
  final String unit;

  /// Overlays a trailing moving average. Only meaningful on a noisy daily
  /// series; a five-point strength chart is smoothed into meaninglessness.
  final bool smooth;

  final double height;
  final String? semanticLabel;

  @override
  State<ProgressChart> createState() => _ProgressChartState();
}

/// Axis slack above 100% and below 0% on a ratio chart, in ratio units.
///
/// Enough to clear the line width plus a dot radius; smaller than the 0.25 grid
/// interval so it never introduces a gridline of its own.
const double _ratioHeadroom = 0.06;

class _ProgressChartState extends State<ProgressChart>
    with SingleTickerProviderStateMixin {
  /// EAGER, not `late final`.
  ///
  /// A `late final` animation controller initialises on first ACCESS, and
  /// `dispose()` can be that first access when a build path returns early —
  /// which then runs `createTicker` against an already-deactivated State and
  /// throws "Looking up a deactivated widget's ancestor is unsafe". That exact
  /// defect shipped three times in the sibling app, intermittently, because a
  /// healthy session always painted first and never saw it.
  AnimationController? _draw;

  @override
  void initState() {
    super.initState();
    _draw = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant ProgressChart old) {
    super.didUpdateWidget(old);
    // Re-draw when the SHAPE of the data changes (a new range, a new metric),
    // not when a single value ticks — replaying a 620 ms sweep because one
    // point moved reads as a glitch, not as feedback.
    if (old.series.length != widget.series.length ||
        old.unit != widget.unit ||
        old.kind != widget.kind) {
      _draw?.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _draw?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final pts = widget.series;

    if (pts.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'Nothing recorded in this range.',
            style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
          ),
        ),
      );
    }

    if (pts.length == 1) {
      // ONE POINT IS NOT A TREND. Drawing a line through it — or padding the
      // axis to imply a second — would state a direction nothing supports.
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _format(pts.single.value),
                style: AppText.title(size: 26).copyWith(color: p.accent),
              ),
              const SizedBox(height: 6),
              Text(
                'on ${DateFormat('d MMM').format(pts.single.date)}',
                style: AppText.body(size: 12).copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 10),
              Text(
                'One more record unlocks the trend.',
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      label: widget.semanticLabel ?? _autoSemantics(pts),
      // The chart itself is decorative once the label above states the trend;
      // exposing every fl_chart internal to a screen reader is noise.
      excludeSemantics: true,
      child: SizedBox(
        height: widget.height,
        child: AnimatedBuilder(
          animation: _draw!,
          builder: (context, _) => LineChart(
            _data(p, pts, _draw!.value),
            duration: Duration.zero, // the draw-in is ours, not fl_chart's
          ),
        ),
      ),
    );
  }

  /// One epoch-millisecond axis position → its calendar-day label.
  static String _dayLabel(double x) => DateFormat(
    'd MMM',
  ).format(DateTime.fromMillisecondsSinceEpoch(x.toInt()));

  String _format(double v) => switch (widget.kind) {
    SeriesKind.ratio => '${(v * 100).round()}%',
    SeriesKind.scalar => widget.unit.isEmpty
        ? _trim(v)
        : '${_trim(v)} ${widget.unit}',
  };

  /// Drops a trailing `.0` so "80 kg" does not read as "80.0 kg", but keeps one
  /// decimal where it carries meaning (82.4 kg).
  static String _trim(double v) {
    final s = v.abs() >= 1000 ? v.round().toString() : v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  String _autoSemantics(List<TrendPoint> pts) {
    final first = _format(pts.first.value);
    final last = _format(pts.last.value);
    final from = DateFormat('d MMMM').format(pts.first.date);
    final to = DateFormat('d MMMM').format(pts.last.date);
    return 'Trend from $first on $from to $last on $to, '
        '${pts.length} records.';
  }

  LineChartData _data(AppPalette p, List<TrendPoint> pts, double t) {
    final spots = [
      for (final e in pts)
        FlSpot(e.date.millisecondsSinceEpoch.toDouble(), e.value),
    ];

    // The draw-in reveals points left to right rather than growing them from
    // the axis: a value that animates UP from zero displays every number below
    // itself on the way, which on a weight chart is a series of false readings.
    final shown = (spots.length * t).ceil().clamp(2, spots.length);
    final visible = spots.sublist(0, shown);

    final values = pts.map((e) => e.value).toList();
    var minY = values.reduce((a, b) => a < b ? a : b);
    var maxY = values.reduce((a, b) => a > b ? a : b);

    if (widget.kind == SeriesKind.ratio) {
      // A percentage axis is always the whole scale. Auto-ranging 78%–82% to
      // fill the card turns normal consistency into a dramatic mountain.
      //
      // The band is 0..1 but the AXIS is given a hair of headroom at each end,
      // because a line is drawn with width and its markers with a radius: a
      // member at 100% — the single most likely value on an adherence chart, and
      // exactly what a perfect-adherence member sees — had their line and every
      // dot drawn ON the plot boundary, where fl_chart clips them. The result
      // read as a broken chart at precisely the moment it should have been the
      // most rewarding. The headroom is deliberately smaller than the 0.25 grid
      // interval, so the gridlines and their labels still land on 0/25/50/75/100.
      minY = -_ratioHeadroom;
      maxY = 1 + _ratioHeadroom;
    } else {
      // Pad by a fraction of the ACTUAL spread, never a fixed constant. A fixed
      // ±2 kg flattened a real transformation and magnified scale noise.
      final spread = maxY - minY;
      final pad = spread == 0 ? (maxY.abs() * 0.05 + 1) : spread * 0.18;
      minY -= pad;
      maxY += pad;
      if (minY < 0 && values.every((v) => v >= 0)) minY = 0;
    }

    final minX = spots.first.x;
    final maxX = spots.last.x;

    final bars = <LineChartBarData>[
      LineChartBarData(
        spots: visible,
        isCurved: true,
        // Low tension: enough to feel considered, not enough to invent a
        // shape between two points that the data does not have.
        curveSmoothness: 0.22,
        preventCurveOverShooting: true,
        color: p.accent,
        barWidth: 2.6,
        dotData: FlDotData(
          // Dots on a dense daily series become a smear; on a sparse one they
          // are the evidence that each point is a real record.
          show: visible.length <= 14,
          getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
            radius: 3,
            color: p.accent,
            strokeWidth: 2,
            strokeColor: p.surface,
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              p.accent.withValues(alpha: .22),
              p.accent.withValues(alpha: .01),
            ],
          ),
        ),
      ),
    ];

    if (widget.smooth && pts.length >= 5) {
      final avg = movingAverage(values, 7);
      bars.add(
        LineChartBarData(
          spots: [
            for (var i = 0; i < shown; i++) FlSpot(spots[i].x, avg[i]),
          ],
          isCurved: true,
          curveSmoothness: 0.3,
          color: p.textMuted.withValues(alpha: .55),
          barWidth: 1.4,
          dashArray: const [5, 4],
          dotData: const FlDotData(show: false),
        ),
      );
    }

    return LineChartData(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: widget.kind == SeriesKind.ratio
            ? 0.25
            : ((maxY - minY) / 3).abs().clamp(0.0001, double.infinity),
        getDrawingHorizontalLine: (_) => FlLine(
          color: p.border.withValues(alpha: .55),
          strokeWidth: 1,
          dashArray: const [4, 5],
        ),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: bars,
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        getTouchedSpotIndicator: (bar, indexes) => [
          for (final _ in indexes)
            TouchedSpotIndicatorData(
              FlLine(color: p.accent.withValues(alpha: .45), strokeWidth: 1),
              FlDotData(
                getDotPainter: (s, _, _, _) => FlDotCirclePainter(
                  radius: 4.5,
                  color: p.accent,
                  strokeWidth: 2.5,
                  strokeColor: p.surface,
                ),
              ),
            ),
        ],
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => p.textPrimary.withValues(alpha: .92),
          tooltipBorderRadius: BorderRadius.circular(10),
          tooltipPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 7,
          ),
          getTooltipItems: (spots) => [
            for (final s in spots)
              // Only the raw series is interrogable. A tooltip on the smoothed
              // overlay would quote an average as though it were a record.
              if (s.barIndex == 0)
                LineTooltipItem(
                  _format(s.y),
                  AppText.label(size: 12.5).copyWith(color: p.background),
                  children: [
                    TextSpan(
                      text:
                          '\n${DateFormat('EEE d MMM').format(DateTime.fromMillisecondsSinceEpoch(s.x.toInt()))}',
                      style: AppText.body(
                        size: 10.5,
                      ).copyWith(color: p.background.withValues(alpha: .75)),
                    ),
                  ],
                )
              else
                null,
          ],
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: widget.kind == SeriesKind.ratio
                ? 0.25
                : ((maxY - minY) / 3).abs().clamp(0.0001, double.infinity),
            getTitlesWidget: (value, meta) {
              // fl_chart offers a label at each edge; drawing them collides
              // with the plot border and looks like a rendering fault.
              if (value <= meta.min || value >= meta.max) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  widget.kind == SeriesKind.ratio
                      ? '${(value * 100).round()}%'
                      : _trim(value),
                  textAlign: TextAlign.right,
                  style: AppText.body(size: 10).copyWith(color: p.textMuted),
                ),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            // Exactly two dated anchors — the ends. Intermediate ticks on a
            // time axis whose points are irregular label positions that no
            // record sits on, which is worse than not labelling them.
            //
            // 🔴 THE INTERVAL ALONE DOES NOT ACHIEVE THAT, and for a long time
            // it silently did not. `AxisChartHelper.iterateThroughAxis` anchors
            // its tick sequence to the axis BASELINE — `baselineX`, which
            // defaults to **0, the Unix epoch** — not to `minX`:
            //
            //     final mod = (baseline - min) % interval;   // → [0, interval)
            //     return min + mod;                          // an INTERIOR tick
            //
            // and then, because `minIncluded`/`maxIncluded` both default to
            // true, it emits `min` and `max` AROUND that. Three labels, for
            // every series whose start is not exactly interval-aligned with the
            // epoch — which is every series a member will ever have. Observed on
            // the emulator as "3 Aug · 3 Aug · 4 Aug", and reproduced as
            // "1 Jun · 14 Jun · 1 Aug" on a weight chart, where the middle
            // label named a date on which nothing was measured.
            //
            // So the ends are selected HERE, where the promise can actually be
            // kept regardless of what the tick generator offers.
            interval: (maxX - minX).abs().clamp(1.0, double.infinity),
            getTitlesWidget: (value, meta) {
              // A tolerance, not equality: these are epoch milliseconds carried
              // through double arithmetic.
              final span = (maxX - minX).abs();
              final tol = span == 0 ? 1.0 : span / 10000;
              final isStart = (value - minX).abs() <= tol;
              final isEnd = (value - maxX).abs() <= tol;
              if (!isStart && !isEnd) return const SizedBox.shrink();
              // When both ends fall on ONE calendar day the axis has one date
              // to state, not the same date twice.
              final startLabel = _dayLabel(minX);
              final endLabel = _dayLabel(maxX);
              if (isEnd && !isStart && endLabel == startLabel) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  isStart ? startLabel : endLabel,
                  style: AppText.body(size: 10).copyWith(color: p.textMuted),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
