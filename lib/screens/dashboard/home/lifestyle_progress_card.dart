import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/serena/premium_states.dart';
import 'daily_metric.dart';
import 'home_progress_parts.dart';

/// ONE lifestyle target, ready to render.
///
/// Carries the [DailyMetric] verbatim — every number, target, ratio and status
/// still comes from the controller — plus the two things a tile needs that a
/// metric has no opinion about: how it looks, and how its value reads as a
/// sentence ("7h 30m" is not something a generic formatter should invent).
class LifestyleTile {
  final DailyMetric metric;
  final IconData icon;
  final Color tint;

  /// The dominant figure. Defaults to the metric's own label ("6 glasses").
  final String? valueText;

  /// The line under it. Defaults to "Goal 12 glasses" / "No target set".
  final String? goalText;

  /// False drops the goal line entirely — supplements are already "2 / 3", and
  /// a "Goal 3" beneath that would be the same fact twice.
  final bool showGoal;

  const LifestyleTile({
    required this.metric,
    required this.icon,
    required this.tint,
    this.valueText,
    this.goalText,
    this.showGoal = true,
  });

  String get label => metric.label;

  String get value => valueFor(metric.current);

  /// [value] at an intermediate figure — see [DailyMetric.valueLabelFor].
  ///
  /// A caller-supplied [valueText] is a fixed phrase ("2 of 3 taken"), not a
  /// rendering of this metric's number, so it is returned unchanged: counting
  /// a string nobody derived from [shown] would be animation theatre.
  String valueFor(double? shown) =>
      valueText ?? metric.currentLabelFor(shown);

  String? get goal => !showGoal
      ? null
      : (goalText ??
          (metric.hasTarget ? 'Goal ${metric.targetLabel}' : 'No target set'));

  String get semanticLabel =>
      '$label, $value${goal == null ? '' : ', $goal'}'
      '${metric.percent == null ? '' : ', ${metric.percent}% complete'}';
}

/// LIFESTYLE PROGRESS — four targets, one glance, one tap.
///
/// ── WHY THIS SHAPE ─────────────────────────────────────────────────────────
/// The card this replaces was a VERTICAL LIST: four full-width rows, each a
/// label, a ratio and a bar, stacked. It cost a third of the viewport to say
/// four short things, and because every row was the same width and weight, a
/// member had to read all four to learn anything — a list makes you scan,
/// where a dashboard lets you glance.
///
/// Four compact tiles in a 2×2 grid answer the same question in half the
/// height, and the completion percentage does the work the eye was doing:
/// "80%" is legible from across a room; a bar two-thirds full is not.
///
/// ── WHAT IT DOES NOT DO ────────────────────────────────────────────────────
/// It computes nothing. Water is still glasses derived from drink events,
/// steps still null-when-unlogged, sleep still hours from the same
/// derivation — the card receives [DailyMetric]s and draws them. It also does
/// not decide whether a supplements tile exists: a member whose coach
/// prescribed no stack is simply handed three tiles, and the grid rebalances
/// so the third spans the full width rather than leaving a hole.
class LifestyleProgressCard extends StatelessWidget {
  /// Water · Steps / Sleep · Supplements, in that order. Three is a legitimate
  /// list (no prescribed supplements) and lays out just as deliberately.
  final List<LifestyleTile> tiles;

  final String subtitle;

  /// The WHOLE card opens the existing Today screen. There is no second
  /// affordance and no header action: one card, one destination.
  final VoidCallback? onTap;

  /// True while the day's events are still loading — a skeleton, never zeros.
  final bool loading;

  const LifestyleProgressCard({
    super.key,
    required this.tiles,
    required this.subtitle,
    this.onTap,
    this.loading = false,
  });

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
            title: 'Lifestyle Progress',
            subtitle: subtitle,
            icon: Icons.favorite_rounded,
            palette: p,
            showChevron: onTap != null,
          ),
          SizedBox(height: 14 * (scale > 1.3 ? 1.2 : 1)),
          if (loading)
            _skeleton(p)
          else if (tiles.isEmpty)
            _empty(p)
          else
            _grid(p, scale),
        ],
      ),
    );

    if (onTap == null) return body;
    return PressableCard(
      onTap: onTap!,
      semanticLabel: "Lifestyle progress. Open today's tracker",
      child: body,
    );
  }

  // ── The grid ─────────────────────────────────────────────────────────────

  Widget _grid(AppPalette p, double scale) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two tiles per row need real width; below it a single column keeps
        // every figure at full size rather than shrinking the one thing the
        // member came to read.
        final singleColumn = scale > 1.45 || constraints.maxWidth < 280;
        final cells = [
          for (final t in tiles) _Tile(tile: t, palette: p),
        ];

        if (singleColumn) {
          return Column(
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                cells[i],
              ],
            ],
          );
        }

        final rows = <Widget>[];
        for (var i = 0; i < cells.length; i += 2) {
          if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
          // An ODD tile takes the full width. Not a half tile beside a hole:
          // a member with no prescribed supplements should see a card that
          // looks designed for three, not one missing its fourth.
          if (i + 1 >= cells.length) {
            rows.add(cells[i]);
            break;
          }
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cells[i]),
                  const SizedBox(width: 12),
                  Expanded(child: cells[i + 1]),
                ],
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }

  // ── States ───────────────────────────────────────────────────────────────

  Widget _empty(AppPalette p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(Icons.self_improvement_rounded, size: 18, color: p.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nothing to track yet — your coach has not set any daily '
                'targets.',
                style: AppText.body(size: 12).copyWith(color: p.textSecondary),
              ),
            ),
          ],
        ),
      );

  Widget _skeleton(AppPalette p) {
    Widget block(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(4),
          ),
        );

    Widget cell() => Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
          decoration: glassCardSoft(p, radius: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                block(26, 26),
                const SizedBox(width: 8),
                block(40, 10),
              ]),
              const SizedBox(height: 12),
              block(58, 14),
              const SizedBox(height: 7),
              block(44, 9),
              const SizedBox(height: 11),
              block(double.infinity, 5),
            ],
          ),
        );

    return Column(
      children: [
        for (var r = 0; r < 2; r++) ...[
          if (r > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cell()),
                const SizedBox(width: 12),
                Expanded(child: cell()),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One tile: icon · label · percentage / value · goal / bar.
///
/// The percentage sits top-right in the tile's own tint — far enough from the
/// value that the two never read as one number, close enough to the label that
/// it is obviously about THIS metric.
class _Tile extends StatelessWidget {
  final LifestyleTile tile;
  final AppPalette palette;

  const _Tile({required this.tile, required this.palette});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final m = tile.metric;
    final met = m.status == MetricStatus.met;
    final percent = m.percent;
    final logged = m.current != null;

    return Semantics(
      label: tile.semanticLabel,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
        decoration: glassCardSoft(p, radius: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: tile.tint.withValues(alpha: p.isDark ? 0.18 : 0.13),
                  ),
                  child: Icon(tile.icon, size: 14, color: tile.tint),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tile.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 11.5)
                        .copyWith(color: p.textMuted, height: 1.1),
                  ),
                ),
                // Only a real ratio earns a percentage. No target, or nothing
                // logged, prints nothing — never "0%", which is a claim about
                // the member rather than about the data.
                if (percent != null) ...[
                  const SizedBox(width: 4),
                  AnimatedCount(
                    value: m.current,
                    builder: (context, shown) => Text(
                      '${m.percentFor(shown) ?? percent}%',
                      maxLines: 1,
                      style: AppText.label(size: 11.5).copyWith(
                        color: met ? kMetGreen : tile.tint,
                        height: 1.1,
                        fontFeatures: kTabularFigures,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 11),
            AnimatedCount(
              value: m.current,
              builder: (context, shown) => Text(
                tile.valueFor(shown),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.cardTitle(size: 15).copyWith(
                  color: logged ? p.textPrimary : p.textMuted,
                  height: 1.1,
                  fontFeatures: kTabularFigures,
                ),
              ),
            ),
            if (tile.goal != null) ...[
              const SizedBox(height: 3),
              Text(
                tile.goal!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 10.5)
                    .copyWith(color: p.textMuted, height: 1.15),
              ),
            ],
            const SizedBox(height: 11),
            MetricBar(
              progress: m.progress,
              tint: met ? kMetGreen : tile.tint,
              palette: p,
              height: 5,
            ),
          ],
        ),
      ),
    );
  }
}
