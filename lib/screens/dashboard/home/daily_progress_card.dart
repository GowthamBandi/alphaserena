import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';

/// What a metric's day looks like, so the UI never has to infer it from a
/// number that cannot carry the distinction.
///
/// The four states exist because "0.4" and "no target" and "nothing logged"
/// are three different facts and only one of them is a shortfall. Collapsing
/// them into a single percentage is how a dashboard ends up telling a member
/// they are at 0% of a goal nobody set.
enum MetricStatus {
  /// The coach set no target. Nothing to be behind on.
  noTarget,

  /// A target exists; the member has recorded nothing yet today.
  notLogged,

  /// Logged, below target.
  behind,

  /// Logged, target reached or passed.
  met,
}

/// ONE metric on the Home dashboard: what it is, where the member is, and
/// where they are going.
///
/// Deliberately free of any adherence vocabulary. Nothing here is "eaten",
/// "skipped" or "partial" — those describe compliance with a prescribed list,
/// which is a different question from "how much water have you drunk today".
class DailyMetric {
  final String label;
  final IconData icon;

  /// Today's value, or null when nothing has been recorded.
  final double? current;

  /// The coach's target, or null when none is set.
  final double? target;

  final String unit;

  /// Renders a value for display. Owned by the caller because glasses, hours,
  /// steps and grams round differently and none of them is a general rule.
  final String Function(double) format;

  const DailyMetric({
    required this.label,
    required this.icon,
    required this.unit,
    required this.format,
    this.current,
    this.target,
  });

  bool get hasTarget => target != null && target! > 0;

  MetricStatus get status {
    if (!hasTarget) return MetricStatus.noTarget;
    if (current == null) return MetricStatus.notLogged;
    return current! >= target! ? MetricStatus.met : MetricStatus.behind;
  }

  /// 0..1 for the bar. Null when there is no meaningful fraction to draw —
  /// a bar against no target would be a bar against nothing.
  double? get progress {
    if (!hasTarget || current == null) return null;
    return (current! / target!).clamp(0.0, 1.0);
  }

  /// The percentage, UNCLAMPED, so passing a target reads as the achievement
  /// it is rather than being flattened to 100%.
  int? get percent {
    if (!hasTarget || current == null) return null;
    return ((current! / target!) * 100).round();
  }

  String get currentLabel =>
      current == null ? '—' : '${format(current!)} $unit'.trim();

  String get targetLabel =>
      hasTarget ? '${format(target!)} $unit'.trim() : 'No target set';
}

/// A Home dashboard section: a titled card of [DailyMetric] rows.
///
/// Used for BOTH Lifestyle and Nutrition, so the two sections cannot drift in
/// layout, status vocabulary or the way they express "not logged". They differ
/// only in the metrics handed to them.
class DailyProgressCard extends StatelessWidget {
  final String title;
  final IconData titleIcon;
  final List<DailyMetric> metrics;

  /// Shown under the title when the card has something to say about the whole
  /// section — "3 of 4 on track", or an honest note when no target exists.
  final String? subtitle;

  /// A trailing action in the header (usually "Log"). Null hides it.
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onTap;

  const DailyProgressCard({
    super.key,
    required this.title,
    required this.titleIcon,
    required this.metrics,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.onTap,
  });

  /// "N of M on track", counting ONLY metrics that have a target.
  ///
  /// A metric with no target is not a failure and must not enter the
  /// denominator — otherwise setting fewer goals would lower the score.
  static String? onTrackSummary(List<DailyMetric> metrics) {
    final targeted = metrics.where((m) => m.hasTarget).toList();
    if (targeted.isEmpty) return null;
    final met = targeted.where((m) => m.status == MetricStatus.met).length;
    return '$met of ${targeted.length} on track';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: glassCard(p, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(titleIcon, size: 17, color: p.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.cardTitle(size: 14)
                          .copyWith(color: p.textPrimary),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: AppText.body(size: 11.5)
                            .copyWith(color: p.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: p.accent,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text(actionLabel!,
                      style: AppText.label(size: 12.5)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final m in metrics) _MetricRow(metric: m),
        ],
      ),
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: card,
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final DailyMetric metric;

  const _MetricRow({required this.metric});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final status = metric.status;
    final tint = switch (status) {
      MetricStatus.met => const Color(0xFF2EBD59),
      MetricStatus.behind => p.accent,
      _ => p.textMuted,
    };

    return Semantics(
      // One node per row: a screen reader reads "Water, 6 of 12 glasses, 50
      // percent" rather than five disconnected fragments.
      label: '${metric.label}, ${metric.currentLabel} of '
          '${metric.targetLabel}'
          '${metric.percent == null ? '' : ', ${metric.percent}%'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(metric.icon, size: 14, color: tint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    metric.label,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 13)
                        .copyWith(color: p.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                // The FIGURE yields last: it is what the member came for, so
                // it stays readable while the label truncates.
                Flexible(
                  child: Text(
                    _valueLabel(),
                    textAlign: TextAlign.end,
                    style: AppText.cardTitle(size: 13)
                        .copyWith(color: p.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _bar(p, tint),
          ],
        ),
      ),
    );
  }

  /// "6 / 12 glasses", or the bare value when there is no target to divide by,
  /// or an em dash when nothing was recorded. Three different facts, three
  /// different strings.
  String _valueLabel() {
    if (metric.status == MetricStatus.noTarget) {
      return metric.current == null ? '—' : metric.currentLabel;
    }
    final current =
        metric.current == null ? '—' : metric.format(metric.current!);
    return '$current / ${metric.targetLabel}';
  }

  Widget _bar(AppPalette p, Color tint) {
    final progress = metric.progress;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 5,
        child: Stack(
          children: [
            Container(
              color: p.isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : const Color(0xFFE8EBF0),
            ),
            if (progress != null && progress > 0)
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
