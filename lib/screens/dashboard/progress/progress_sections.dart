import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../controllers/progress_analytics_controller.dart';
import '../../../controllers/progress_controller.dart';
import '../../../core/analytics/progress_analytics.dart';
import '../../../core/models/check_in_submission_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import 'progress_chart.dart';
import 'progress_ui.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ANALYTICS — one chart, many metrics, a real range
// ═══════════════════════════════════════════════════════════════════════════

/// A metric the analytics section can plot. Built ONLY when its source has
/// data; a metric with nothing behind it never becomes a chip, so the picker
/// can never offer a member a chart that turns out to be empty.
class _Metric {
  final String id;
  final String label;
  final List<TrendPoint> series;
  final SeriesKind kind;
  final String unit;
  final bool smooth;

  /// The one-line reading of this metric, stated under the chart.
  final String caption;

  const _Metric({
    required this.id,
    required this.label,
    required this.series,
    required this.kind,
    required this.caption,
    this.unit = '',
    this.smooth = false,
  });
}

class ProgressAnalyticsSection extends StatefulWidget {
  const ProgressAnalyticsSection({super.key, required this.controller});

  final ProgressAnalyticsController controller;

  @override
  State<ProgressAnalyticsSection> createState() =>
      _ProgressAnalyticsSectionState();
}

class _ProgressAnalyticsSectionState extends State<ProgressAnalyticsSection> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = widget.controller;

    return Obx(() {
      c.revision.value; // rebuild on any source change
      final metrics = _metricsOf(c);

      if (metrics.isEmpty) {
        return const ProgressCard(
          child: ProgressUnavailable(
            title: 'No trends yet',
            reason:
                'Trends appear once there is something to compare. Log a '
                'workout, your food, or a check-in and this fills in.',
          ),
        );
      }

      // A selection that no longer exists (the range narrowed past its data)
      // must fall back rather than render an empty chart under a live chip.
      final active = metrics.firstWhere(
        (m) => m.id == _selected,
        orElse: () => metrics.first,
      );

      return ProgressCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: metrics.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final m = metrics[i];
                  final on = m.id == active.id;
                  return Semantics(
                    container: true,
                    button: true,
                    selected: on,
                    label: m.label,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selected = m.id);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: on
                              ? p.accent.withValues(alpha: .13)
                              : p.surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: on
                                ? p.accent.withValues(alpha: .45)
                                : p.border,
                          ),
                        ),
                        child: Text(
                          m.label,
                          style: AppText.label(size: 12).copyWith(
                            color: on ? p.accent : p.textMuted,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            // The chart is KEYED on the metric so switching rebuilds its
            // animation controller from scratch. Without the key, fl_chart
            // tweens between two unrelated series and a percentage line
            // visibly melts into a kilogram line.
            ProgressChart(
              key: ValueKey('${active.id}_${c.range.value.name}'),
              series: active.series,
              palette: p,
              kind: active.kind,
              unit: active.unit,
              smooth: active.smooth,
            ),
            const SizedBox(height: 10),
            Text(
              active.caption,
              style: AppText.body(
                size: 12,
              ).copyWith(color: p.textMuted, height: 1.4),
            ),
            if (active.id == 'strength' && c.strengthOptions.length > 1) ...[
              const SizedBox(height: 12),
              _exercisePicker(context, p, c),
            ],
          ],
        ),
      );
    });
  }

  Widget _exercisePicker(
    BuildContext context,
    AppPalette p,
    ProgressAnalyticsController c,
  ) {
    final current = c.strengthExercise;
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: c.strengthOptions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, i) {
          final o = c.strengthOptions[i];
          final on = o.key == current?.key;
          return Semantics(
            container: true,
            button: true,
            selected: on,
            label: '${o.name}, ${o.sessions} sessions',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                c.selectedExercise.value = o.key;
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? p.textPrimary.withValues(alpha: .07) : null,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: on ? p.textMuted : p.border),
                ),
                child: Text(
                  o.name.isEmpty ? 'Unnamed' : o.name,
                  style: AppText.body(size: 11.5).copyWith(
                    color: on ? p.textPrimary : p.textMuted,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Builds the metric list. EVERY entry is gated on real data.
  List<_Metric> _metricsOf(ProgressAnalyticsController c) {
    final out = <_Metric>[];
    final phrase = c.range.value.phrase;

    void ratio(String id, String label, List<TrendPoint> series) {
      if (series.length < 2) return;
      final s = seriesDirection(series);
      final avg =
          series.map((e) => e.value).reduce((a, b) => a + b) / series.length;
      out.add(
        _Metric(
          id: id,
          label: label,
          series: series,
          kind: SeriesKind.ratio,
          smooth: series.length >= 10,
          caption:
              'Averaging ${(avg * 100).round()}% over the $phrase · '
              '${directionWord(s)} · ${series.length} days recorded.',
        ),
      );
    }

    ratio('workout', 'Workout quality', c.workoutSeries);
    ratio('nutrition', 'Nutrition', c.nutritionSeries);
    ratio('lifestyle', 'Lifestyle', c.lifestyleSeries);

    final weight = c.weightSeries;
    if (weight.length >= 2) {
      final net = netChange(weight)!;
      out.add(
        _Metric(
          id: 'weight',
          label: 'Weight',
          series: weight,
          kind: SeriesKind.scalar,
          unit: 'kg',
          // The FULL history, not the window: a transformation is not a 30-day
          // story and clipping it understates the member's actual work.
          caption:
              net.abs() < AnalyticsPolicy.weightFlatBandKg
              ? 'Holding steady across ${weight.length} check-ins.'
              : '${net > 0 ? 'Up' : 'Down'} ${net.abs().toStringAsFixed(1)} kg '
                    'across ${weight.length} check-ins, '
                    '${DateFormat('d MMM').format(weight.first.date)} to '
                    '${DateFormat('d MMM').format(weight.last.date)}.',
        ),
      );
    }

    final strength = c.strengthTrend;
    final ex = c.strengthExercise;
    if (strength.length >= 2 && ex != null) {
      final net = netChange(strength)!;
      out.add(
        _Metric(
          id: 'strength',
          label: 'Strength',
          series: strength,
          kind: SeriesKind.scalar,
          unit: 'kg',
          caption:
              '${ex.name} · heaviest working set per session · '
              '${net == 0 ? 'unchanged' : '${net > 0 ? 'up' : 'down'} '
                        '${net.abs().toStringAsFixed(1)} kg'} '
              'over ${strength.length} sessions.',
        ),
      );
    }

    final volume = c.volumeTrend;
    if (volume.length >= 2) {
      out.add(
        _Metric(
          id: 'volume',
          label: 'Volume',
          series: volume,
          kind: SeriesKind.scalar,
          unit: 'kg·reps',
          caption:
              'Weight moved per session over the $phrase. '
              'Only completed sets with a logged weight and reps count.',
        ),
      );
    }

    for (final key in c.measurementKeys) {
      final series = c.measurementFor(key);
      if (series.length < 2) continue;
      final net = netChange(series)!;
      out.add(
        _Metric(
          id: 'm_$key',
          label: _measurementLabel(key),
          series: series,
          kind: SeriesKind.scalar,
          unit: 'cm',
          caption:
              '${net == 0 ? 'Unchanged' : '${net > 0 ? 'Up' : 'Down'} '
                        '${net.abs().toStringAsFixed(1)} cm'} '
              'across ${series.length} measurements.',
        ),
      );
    }

    return out;
  }

  /// Reuses the same vocabulary the Transformation surface renders, so one
  /// measurement is never called two things in one app.
  static String _measurementLabel(String key) => switch (key) {
    'leftArm' => 'Left arm',
    'rightArm' => 'Right arm',
    'leftThigh' => 'Left thigh',
    'rightThigh' => 'Right thigh',
    'leftCalf' => 'Left calf',
    'rightCalf' => 'Right calf',
    _ => key.isEmpty ? key : key[0].toUpperCase() + key.substring(1),
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// INSIGHTS
// ═══════════════════════════════════════════════════════════════════════════

class ProgressInsightsSection extends StatelessWidget {
  const ProgressInsightsSection({super.key, required this.insights});

  final List<ProgressInsight> insights;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (insights.isEmpty) {
      return const ProgressCard(
        child: ProgressUnavailable(
          title: 'No insights yet',
          reason:
              'Insights are statements this app can prove from your own '
              'records. When there is something true to say, it appears here.',
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < insights.length; i++) ...[
          _row(p, insights[i]),
          if (i != insights.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }

  Widget _row(AppPalette p, ProgressInsight insight) {
    final tint = switch (insight.tone) {
      InsightTone.positive => kProgressGreen,
      InsightTone.caution => kProgressAmber,
      InsightTone.neutral => p.textSecondary,
    };
    final icon = switch (insight.kind) {
      InsightKind.training => Icons.fitness_center_rounded,
      InsightKind.nutrition => Icons.restaurant_rounded,
      InsightKind.lifestyle => Icons.spa_rounded,
      InsightKind.body => Icons.monitor_weight_outlined,
      InsightKind.streak => Icons.local_fire_department_rounded,
      InsightKind.record => Icons.emoji_events_rounded,
    };
    return ProgressCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Semantics(
        container: true,
        label: '${insight.headline} ${insight.basis}',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    insight.headline,
                    style: AppText.body(
                      size: 13,
                    ).copyWith(color: p.textPrimary, height: 1.35),
                  ),
                  const SizedBox(height: 4),
                  // THE BASIS IS NOT DECORATION. An insight that cannot show
                  // its work is an opinion, and this product does not offer
                  // opinions about a member's body.
                  Text(
                    insight.basis,
                    style: AppText.body(size: 11).copyWith(color: p.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ACHIEVEMENTS
// ═══════════════════════════════════════════════════════════════════════════

class ProgressAchievement {
  final String glyph;
  final String value;
  final String label;

  /// The window or source this figure is true FOR. Never omitted: a "longest
  /// streak" that silently means "longest we happened to load" is a claim the
  /// app cannot support.
  final String basis;

  const ProgressAchievement({
    required this.glyph,
    required this.value,
    required this.label,
    required this.basis,
  });
}

class ProgressAchievementsSection extends StatelessWidget {
  const ProgressAchievementsSection({
    super.key,
    required this.controller,
    required this.transformationCount,
  });

  final ProgressAnalyticsController controller;
  final int transformationCount;

  /// Built ONLY from records that exist. There is no badge ladder, no locked
  /// tier and no "80% to your next award" — this platform stores no goal, so a
  /// target would be invented, and a locked badge is a promise the backend
  /// cannot keep.
  List<ProgressAchievement> get achievements {
    final c = controller;
    final out = <ProgressAchievement>[];
    final historyDays = c.loadedHistoryDays;

    if (c.sessions.isNotEmpty) {
      out.add(
        ProgressAchievement(
          glyph: '🏋️',
          value: '${c.sessions.length}',
          // A NOUN, not a sentence. "Workout logged" was both grammatically
          // odd beside its own count and a literal duplicate of the Recent
          // Activity row, so one screen said the same three words about two
          // different facts.
          label: c.sessions.length == 1 ? 'Workout' : 'Workouts',
          basis: 'All time',
        ),
      );
    }

    if (c.bestStreak >= 1) {
      out.add(
        ProgressAchievement(
          glyph: '🔥',
          // The unit belongs to the VALUE, not the label. The label was a
          // ternary whose two branches were byte-identical — a pluralisation
          // that never pluralised, which is a defect that reads as one.
          value: '${c.bestStreak} ${c.bestStreak == 1 ? 'day' : 'days'}',
          label: 'Best streak',
          basis: historyDays > 0
              ? 'Longest in $historyDays days'
              : 'Longest run recorded',
        ),
      );
    }

    final bests = c.bests;
    if (bests.isNotEmpty) {
      final b = bests.first;
      out.add(
        ProgressAchievement(
          glyph: '🥇',
          value: '${b.weight.toStringAsFixed(b.weight % 1 == 0 ? 0 : 1)} kg',
          label: b.exercise.isEmpty ? 'Heaviest set' : b.exercise,
          basis: 'Heaviest set · ${DateFormat('d MMM yyyy').format(b.at)}',
        ),
      );
    }

    if (c.volume > 0) {
      out.add(
        ProgressAchievement(
          glyph: '⚡',
          value: _compact(c.volume),
          label: 'kg·reps moved',
          basis: 'Over the ${c.range.value.phrase}',
        ),
      );
    }

    if (transformationCount > 0) {
      out.add(
        ProgressAchievement(
          glyph: '📸',
          value: '$transformationCount',
          label: transformationCount == 1 ? 'Check-in' : 'Check-ins',
          basis: 'Transformation history',
        ),
      );
    }

    if (c.exerciseVariety > 0) {
      out.add(
        ProgressAchievement(
          glyph: '🎯',
          value: '${c.exerciseVariety}',
          label: 'Exercises trained',
          basis: 'Over the ${c.range.value.phrase}',
        ),
      );
    }

    return out;
  }

  static String _compact(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = achievements;
    if (items.isEmpty) {
      return const ProgressCard(
        child: ProgressUnavailable(
          title: 'Nothing earned yet',
          reason:
              'Milestones come from what you record. Your first logged '
              'workout starts the board.',
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context).scale(1);
        // Two across normally; ONE across when the text scale would force a
        // number to truncate. A truncated achievement is worse than a taller
        // list.
        final columns = (constraints.maxWidth >= 340 && scaler < 1.45) ? 2 : 1;
        final width =
            (constraints.maxWidth - ((columns - 1) * 10)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final a in items)
              SizedBox(width: width, child: _tile(p, a)),
          ],
        );
      },
    );
  }

  Widget _tile(AppPalette p, ProgressAchievement a) => ProgressCard(
    padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
    child: Semantics(
      container: true,
      label: '${a.value} ${a.label}. ${a.basis}.',
      excludeSemantics: true,
      child: Row(
        children: [
          Text(a.glyph, style: const TextStyle(fontSize: 21)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    a.value,
                    maxLines: 1,
                    style: AppText.title(
                      size: 18,
                    ).copyWith(color: p.textPrimary),
                  ),
                ),
                Text(
                  a.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  a.basis,
                  maxLines: 2,
                  style: AppText.body(size: 10).copyWith(color: p.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// RECENT ACTIVITY
// ═══════════════════════════════════════════════════════════════════════════

class ProgressActivity {
  final DateTime at;
  final IconData icon;
  final String title;
  final String detail;
  const ProgressActivity(this.at, this.icon, this.title, this.detail);
}

class ProgressActivitySection extends StatelessWidget {
  const ProgressActivitySection({
    super.key,
    required this.controller,
    required this.transformation,
    this.limit = 6,
  });

  final ProgressAnalyticsController controller;
  final ProgressController? transformation;
  final int limit;

  /// A merged, newest-first feed of what the member actually recorded.
  ///
  /// Built from the sources ALREADY loaded for the analytics above — it opens
  /// no stream of its own. Nothing is inferred: a row exists because a document
  /// exists.
  List<ProgressActivity> get feed {
    final out = <ProgressActivity>[];

    for (final s in controller.sessions) {
      final sets = [for (final e in s.entries) ...e.sets];
      final done = sets.where((x) => x.completed).length;
      out.add(
        ProgressActivity(
          s.date,
          Icons.fitness_center_rounded,
          'Workout logged',
          '${s.entries.length} ${s.entries.length == 1 ? 'exercise' : 'exercises'}'
              '${done == 0 ? '' : ' · $done ${done == 1 ? 'set' : 'sets'} completed'}',
        ),
      );
    }

    for (final e in transformation?.completed ?? const []) {
      final bits = <String>[
        if (e.weightKg != null) '${e.weightKg!.toStringAsFixed(1)} kg',
        if (e.measurements.isNotEmpty)
          '${e.measurements.length} measurements',
        if (e.photos.isNotEmpty) '${e.photos.length} photos',
      ];
      out.add(
        ProgressActivity(
          e.recordedAt,
          Icons.photo_camera_rounded,
          'Transformation check-in',
          bits.isEmpty ? 'Recorded' : bits.join(' · '),
        ),
      );
    }

    for (final c in controller.checkIns) {
      final at = c.submittedAt;
      if (at == null) continue;
      out.add(
        ProgressActivity(
          at,
          Icons.assignment_turned_in_rounded,
          c.status == CheckInSubmissionStatus.reviewed
              ? 'Check-in reviewed by your coach'
              : 'Weekly check-in sent',
          c.status == CheckInSubmissionStatus.reviewed && c.coachResponse.isNotEmpty
              ? c.coachResponse
              : '${c.ratings.length} ${c.ratings.length == 1 ? 'rating' : 'ratings'}'
                    '${c.weightKg == null ? '' : ' · ${c.weightKg!.toStringAsFixed(1)} kg'}',
        ),
      );
    }

    out.sort((a, b) => b.at.compareTo(a.at));
    return out.take(limit).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = feed;
    if (items.isEmpty) {
      return const ProgressCard(
        child: ProgressUnavailable(
          title: 'No activity yet',
          reason:
              'Everything you log — a workout, a check-in, a photo — shows up '
              'here as it happens.',
        ),
      );
    }
    return ProgressCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _row(p, items[i]),
            if (i != items.length - 1)
              Divider(height: 1, color: p.border.withValues(alpha: .7)),
          ],
        ],
      ),
    );
  }

  Widget _row(AppPalette p, ProgressActivity a) => Semantics(
    container: true,
    label: '${a.title}. ${a.detail}. ${_relative(a.at)}.',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(a.icon, size: 17, color: p.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: AppText.body(size: 12.5).copyWith(
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  a.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 11).copyWith(color: p.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _relative(a.at),
            style: AppText.body(size: 10.5).copyWith(color: p.textMuted),
          ),
        ],
      ),
    ),
  );

  /// Relative where it helps, absolute where it does not. "43 days ago" is a
  /// number a member has to do arithmetic on; a date is not.
  static String _relative(DateTime at) {
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(at.year, at.month, at.day)).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return '${days}d ago';
    if (days < 28) return '${(days / 7).floor()}w ago';
    return DateFormat('d MMM').format(at);
  }
}
