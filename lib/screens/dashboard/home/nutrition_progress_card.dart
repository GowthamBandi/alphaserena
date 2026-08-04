import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';
import 'daily_metric.dart';
import 'home_progress_parts.dart';

/// NUTRITION PROGRESS — one ring, four bars.
///
/// ── WHY THIS SHAPE ─────────────────────────────────────────────────────────
/// The card this replaces drew five identical labelled bars stacked in a
/// column: calories, protein, carbs, fat, fiber, each the same width, weight
/// and colour. Every number was true and nothing was legible at a glance,
/// because a member opening Home is asking ONE question — *how much have I
/// eaten today?* — and that question has one answer: calories. The four macros
/// are the follow-up, and a follow-up rendered at the same visual weight as the
/// headline is not a hierarchy, it is a list.
///
/// So: calories become a single dominant ring (the figure that answers the
/// question), and the macros sit beside it as a compact 2×2 grid an order of
/// magnitude quieter. Ratio, not decoration, is what makes this read premium.
///
/// ── WHAT IT DOES NOT DO ────────────────────────────────────────────────────
/// It computes nothing. Every value and target arrives as a [DailyMetric] from
/// the caller, which reads the existing controllers. The card's only opinions
/// are about pixels — and about the four honest states a number can be in
/// (no target · nothing logged · behind · met), which it takes verbatim from
/// [MetricStatus] so the ring and the bars cannot disagree with each other.
class NutritionProgressCard extends StatelessWidget {
  /// The ring. Calories, and only calories.
  final DailyMetric calories;

  /// The grid, in reading order: Protein · Fat / Carbs · Fiber.
  final List<DailyMetric> nutrients;

  final String subtitle;

  /// The header action — the existing "Log food" route. Null hides it.
  final VoidCallback? onLogFood;

  /// Tapping the card body (the existing route to the diet screen).
  final VoidCallback? onTap;

  /// True while today's food log is still loading — a skeleton, never a
  /// fabricated zero, because "0 kcal" is a claim about what a member ate.
  final bool loading;

  const NutritionProgressCard({
    super.key,
    required this.calories,
    required this.nutrients,
    required this.subtitle,
    this.onLogFood,
    this.onTap,
    this.loading = false,
  });

  /// Brand-warm ramp, one hue per macro, in grid order. Four distinct tints
  /// let the eye return to the same bar twice without re-reading its label;
  /// they stay inside the AlphaSerena warm range (plus one green) so the card
  /// never looks like a chart library's default palette.
  static const List<Color> _macroTints = [
    Color(0xFFFF5252), // Protein — accent soft
    Color(0xFFFFCA28), // Fat — amber
    Color(0xFFFB8C00), // Carbs — gradient orange
    kMetGreen, // Fiber — logged green
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;

    final body = Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: glassCard(p, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProgressCardHeader(
            title: 'Nutrition Progress',
            subtitle: subtitle,
            icon: Icons.restaurant_rounded,
            palette: p,
            actionLabel: 'Log Food',
            actionIcon: Icons.add_rounded,
            onAction: onLogFood,
          ),
          SizedBox(height: 16 * (scale > 1.3 ? 1.2 : 1)),
          if (loading) _skeleton(p) else _content(p, scale),
        ],
      ),
    );

    if (onTap == null) return body;
    return PressableCard(onTap: onTap!, child: body);
  }

  // ── The body ─────────────────────────────────────────────────────────────

  Widget _content(AppPalette p, double scale) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Side by side is the premium reading, but it needs real width. Below
        // it — a small phone, or a member on large accessibility text — the
        // ring goes on top and the grid takes the full width, rather than
        // squeezing four ratios into 90px each.
        final stacked = constraints.maxWidth < 320 || scale > 1.35;
        final ring = _CalorieRing(
          metric: calories,
          palette: p,
          diameter: (stacked ? 132.0 : 118.0) * (scale > 1.3 ? 1.15 : 1.0),
        );
        final grid = _NutrientGrid(
          nutrients: nutrients,
          tints: _macroTints,
          palette: p,
          // Two ratios per row stop fitting long before the text stops
          // growing; one column keeps every figure readable instead.
          singleColumn: scale > 1.6 || constraints.maxWidth < 230,
        );

        if (stacked) {
          return Column(
            children: [
              Center(child: ring),
              const SizedBox(height: 18),
              grid,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ring,
            const SizedBox(width: 18),
            Expanded(child: grid),
          ],
        );
      },
    );
  }

  // ── Loading ──────────────────────────────────────────────────────────────

  Widget _skeleton(AppPalette p) {
    Widget block(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(4),
          ),
        );

    Widget cell() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            block(46, 10),
            const SizedBox(height: 7),
            block(70, 12),
            const SizedBox(height: 8),
            block(double.infinity, 6),
          ],
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 118,
          height: 118,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: p.surfaceAlt, width: 11),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            children: [
              Row(children: [
                Expanded(child: cell()),
                const SizedBox(width: 14),
                Expanded(child: cell()),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: cell()),
                const SizedBox(width: 14),
                Expanded(child: cell()),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══ THE RING ══════════════════════════════════════════════════════════════

/// Calories as one animated arc.
///
/// The sweep is the ONLY thing on this card that moves on load, which is why
/// it reads as an arrival rather than as motion for its own sake. It animates
/// from wherever it was, so logging lunch advances the arc from breakfast's
/// position instead of replaying from zero.
class _CalorieRing extends StatelessWidget {
  final DailyMetric metric;
  final AppPalette palette;
  final double diameter;

  const _CalorieRing({
    required this.metric,
    required this.palette,
    required this.diameter,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final progress = metric.progress ?? 0;
    final met = metric.status == MetricStatus.met;
    final stroke = diameter * 0.095;

    return Semantics(
      label: metric.semanticLabel,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: diameter,
            height: diameter,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => CustomPaint(
                painter: _RingPainter(
                  progress: t,
                  stroke: stroke,
                  // The bloom is a dark-mode effect: on a white card the same
                  // blur reads as a smudge rather than as light.
                  glow: p.isDark ? 6 : 2.5,
                  track: p.isDark
                      ? Colors.white.withValues(alpha: 0.07)
                      : const Color(0xFFE8EBF0),
                  // Met turns the whole ring green: the one moment the card
                  // has something to celebrate, said in the colour the rest of
                  // the app already uses for "done today".
                  colors: met
                      ? const [kMetGreen, Color(0xFF7BD97C)]
                      : const [BrandColors.accent, BrandColors.gradientOrange],
                ),
                child: child,
              ),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(stroke + 6),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'KCAL',
                          maxLines: 1,
                          style: AppText.label(size: 9.5).copyWith(
                            color: p.textMuted,
                            letterSpacing: 1.6,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          metric.current == null
                              ? '—'
                              : metric.format(metric.current!),
                          maxLines: 1,
                          style: AppText.title(size: 34).copyWith(
                            color: metric.current == null
                                ? p.textMuted
                                : p.textPrimary,
                            height: 0.95,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          // Current / target, under the ring — the sentence the number inside
          // is short for. Kept OUT of the ring so neither has to shrink.
          //
          // Pinned to the ring's own width, and scaled down rather than
          // truncated: an unconstrained label would widen this whole column
          // and shove the macro grid sideways, so a five-digit calorie goal
          // would silently re-lay-out the card.
          SizedBox(
            width: diameter,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                metric.valueLabel,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: AppText.label(size: 12).copyWith(
                  color: met ? kMetGreen : p.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double stroke;
  final Color track;
  final List<Color> colors;

  /// Blur sigma for the bloom under the arc.
  final double glow;

  const _RingPainter({
    required this.progress,
    required this.stroke,
    required this.track,
    required this.colors,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final arcRect = Rect.fromCircle(center: centre, radius: radius);

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );

    if (progress <= 0) return;

    const start = -math.pi / 2;
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      colors: [...colors, colors.first],
      stops: const [0.0, 0.75, 1.0],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(arcRect);

    // A soft bloom under the arc. It is 6px of blur, and it is the difference
    // between a progress indicator and a ring that looks lit from behind.
    canvas.drawArc(
      arcRect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow),
    );
    canvas.drawArc(
      arcRect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.stroke != stroke ||
      old.track != track ||
      old.glow != glow ||
      old.colors != colors;
}

// ═══ THE MACROS ════════════════════════════════════════════════════════════

class _NutrientGrid extends StatelessWidget {
  final List<DailyMetric> nutrients;
  final List<Color> tints;
  final AppPalette palette;
  final bool singleColumn;

  const _NutrientGrid({
    required this.nutrients,
    required this.tints,
    required this.palette,
    required this.singleColumn,
  });

  @override
  Widget build(BuildContext context) {
    final cells = [
      for (var i = 0; i < nutrients.length; i++)
        _NutrientCell(
          metric: nutrients[i],
          tint: tints[i % tints.length],
          palette: palette,
        ),
    ];

    if (singleColumn) {
      return Column(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            cells[i],
          ],
        ],
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 16));
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: cells[i]),
          const SizedBox(width: 14),
          if (i + 1 < cells.length)
            Expanded(child: cells[i + 1])
          else
            const Expanded(child: SizedBox.shrink()),
        ],
      ));
    }
    return Column(children: rows);
  }
}

class _NutrientCell extends StatelessWidget {
  final DailyMetric metric;
  final Color tint;
  final AppPalette palette;

  const _NutrientCell({
    required this.metric,
    required this.tint,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final met = metric.status == MetricStatus.met;

    return Semantics(
      // One node per macro, so a screen reader says "Protein, 65 g of 150 g,
      // 43%" instead of three disconnected fragments.
      label: metric.semanticLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 11.5)
                      .copyWith(color: p.textMuted, height: 1.1),
                ),
              ),
              if (met) ...[
                const SizedBox(width: 4),
                const Icon(Icons.check_circle_rounded,
                    size: 11, color: kMetGreen),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            metric.valueLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.cardTitle(size: 12.5)
                .copyWith(color: p.textPrimary, height: 1.15),
          ),
          const SizedBox(height: 7),
          MetricBar(progress: metric.progress, tint: tint, palette: p),
        ],
      ),
    );
  }
}
