import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/check_in_controller.dart';
import '../../../controllers/member_controller.dart';
import '../../../controllers/progress_analytics_controller.dart';
import '../../../controllers/progress_controller.dart';
import '../../../core/analytics/progress_analytics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/progress_ring.dart';
import '../../../core/widgets/serena/premium_states.dart';
import '../../join/join_coach_screen.dart';
import '../weekly_report/weekly_report_screen.dart';
import '../consistency_detail_screen.dart';
import '../lifestyle_history_screen.dart';
import '../nutrition/nutrition_history_screen.dart';
import '../plans/workout_history_screen.dart';
import 'member_schedule_screen.dart';
import 'progress_sections.dart';
import 'progress_ui.dart';
import 'transformation_screen.dart';

/// THE PROGRESS INTELLIGENCE CENTRE.
///
/// ══════════════════════════════════════════════════════════════════════════
/// THE ONE QUESTION
/// ══════════════════════════════════════════════════════════════════════════
///
/// This screen answers **"how am I improving over time?"** and nothing else.
/// Home answers "what about today?". My Plans answers "what did my coach
/// assign?". Those are different questions and this screen deliberately
/// declines to re-answer either — no today ring, no plan list, no logging
/// action except the ones that belong to a long-range record.
///
/// ══════════════════════════════════════════════════════════════════════════
/// WHAT IT REPLACES, AND WHY
/// ══════════════════════════════════════════════════════════════════════════
///
/// The previous Progress screen was three tabs. "Overview" was a weight line
/// chart. "Transformation" was the only real feature. "Strength" was a
/// placeholder that told the member, in as many words, that strength trends
/// were "next". Meanwhile every other progress-shaped surface this app already
/// owned — streaks, achievements, adherence, a 5-week calendar, workout
/// history, nutrition history, lifestyle history — lived on four OTHER screens
/// reachable from Home, My Plans, Diet and Lifestyle, and NONE of them was
/// reachable from Progress. Progress was where progress was not.
///
/// So this is a consolidation, not a greenfield build:
///   • the ANALYSIS comes from `core/analytics/progress_analytics.dart`, the
///     file twinned with the coach app and hash-pinned against it, so a member
///     and their coach can never quote different numbers;
///   • the TRANSFORMATION module moved to its own route, code intact;
///   • the HISTORY surfaces became first-class destinations instead of being
///     scattered across four unrelated screens.
///
/// ══════════════════════════════════════════════════════════════════════════
/// THE RULES IT KEEPS
/// ══════════════════════════════════════════════════════════════════════════
///
///  • NOTHING IS FABRICATED. A metric with no data is absent, never 0%. A
///    dimension below the sample gate states that it is still building.
///  • EVERY FIGURE STATES ITS WINDOW. "Best streak" says how far back it could
///    see, because a record this app cannot observe is not one it may claim.
///  • ONE FAILING SOURCE DOES NOT BLANK THE SCREEN. It shows a banner naming
///    what is missing, so a short view is never mistaken for a complete one.
///  • WEIGHT IS NEVER JUDGED. No collection in this platform stores a goal
///    weight, so movement is reported factually and never coloured good or bad.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  ProgressAnalyticsController get _c =>
      Get.isRegistered<ProgressAnalyticsController>()
      ? Get.find<ProgressAnalyticsController>()
      : Get.put(ProgressAnalyticsController());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // LAZY LOAD, VIA TICKERMODE.
    //
    // The dashboard renders four tabs inside an `IndexedStack`, which BUILDS
    // every child at mount. Loading here in `initState` would make every member
    // pay five reads for a screen they may never open. `IndexedStack` disables
    // `TickerMode` for the children it is not showing, so this is the
    // framework's own "am I the visible tab" signal — no dashboard change, no
    // custom visibility plumbing.
    if (TickerMode.valuesOf(context).enabled) _c.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final member = Get.find<MemberController>();
    final transformation = Get.isRegistered<ProgressController>()
        ? Get.find<ProgressController>()
        : null;
    final c = _c;

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          // Touch every observable this build depends on BEFORE any early
          // return. An Obx that short-circuits without reading an Rx stays
          // subscribed to nothing and silently stops updating — a defect this
          // codebase has shipped before in a memoized getter.
          final linked = member.isLinked.value;
          final memberLoading = member.isLoading.value;
          c.revision.value;
          final loading = c.isLoading;
          final partial = c.hasPartialFailure;
          final failed = c.failedSources;
          final range = c.range.value;

          return RefreshIndicator(
            color: p.accent,
            onRefresh: () async {
              await member.claim();
              transformation?.retry();
              await c.retry();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 34),
              children: [
                _header(p, range, c),
                const SizedBox(height: 16),
                _shortcuts(context, p),
                const SizedBox(height: 20),

                if (!linked) ...[
                  _unlinked(p),
                ] else if (memberLoading || loading) ...[
                  ..._skeleton(),
                ] else if (c.isEmpty) ...[
                  _firstRun(p),
                ] else ...[
                  if (partial) ...[
                    ProgressPartialBanner(
                      sources: failed,
                      onRetry: () => c.retry(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── 1 · OVERALL PROGRESS ─────────────────────────────────
                  _overview(context, p, c),
                  const SizedBox(height: 22),

                  // ── 2 · ANALYTICS ────────────────────────────────────────
                  ProgressSectionHeader(
                    title: 'Analytics',
                    subtitle: 'Every trend your records can support',
                  ),
                  const SizedBox(height: 10),
                  ProgressAnalyticsSection(controller: c),
                  const SizedBox(height: 22),

                  // ── 3 · INSIGHTS ─────────────────────────────────────────
                  const ProgressSectionHeader(
                    title: 'Insights',
                    subtitle: 'Only what your own data proves',
                  ),
                  const SizedBox(height: 10),
                  ProgressInsightsSection(insights: c.insights),
                  const SizedBox(height: 22),

                  // ── 4 · HISTORY ──────────────────────────────────────────
                  const ProgressSectionHeader(
                    title: 'History',
                    subtitle: 'Day by day, in full detail',
                  ),
                  const SizedBox(height: 10),
                  _history(context, p),
                  const SizedBox(height: 22),

                  // ── 5 · ACHIEVEMENTS ─────────────────────────────────────
                  const ProgressSectionHeader(
                    title: 'Achievements',
                    subtitle: 'Earned, never awarded',
                  ),
                  const SizedBox(height: 10),
                  ProgressAchievementsSection(
                    controller: c,
                    transformationCount: transformation?.completed.length ?? 0,
                  ),
                  const SizedBox(height: 22),

                  // ── 6 · RECENT ACTIVITY ──────────────────────────────────
                  const ProgressSectionHeader(
                    title: 'Recent activity',
                    subtitle: 'What you recorded, and when',
                  ),
                  const SizedBox(height: 10),
                  ProgressActivitySection(
                    controller: c,
                    transformation: transformation,
                  ),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header(
    AppPalette p,
    ProgressRange range,
    ProgressAnalyticsController c,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Progress',
        style: AppText.title(size: 26).copyWith(color: p.textPrimary),
      ),
      const SizedBox(height: 3),
      Text(
        'How you are improving over time.',
        style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
      ),
      const SizedBox(height: 14),
      ProgressRangeBar(value: range, onChanged: c.setRange),
    ],
  );

  // ── Shortcut row ──────────────────────────────────────────────────────────

  Widget _shortcuts(BuildContext context, AppPalette p) {
    final checkIn = Get.isRegistered<CheckInController>()
        ? Get.find<CheckInController>()
        : null;
    // A "Due" pip is a real claim about a real field — `clients.nextCheckInAt`,
    // written by the coach. Absent cadence shows no pip rather than a nag.
    final due = checkIn?.isDue ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context).scale(1);
        // Three across is right until the labels stop fitting. At large
        // accessibility scales they stack, because a shortcut whose label is
        // ellipsised is a shortcut to somewhere unknown.
        final stack = constraints.maxWidth < 300 || scaler >= 1.6;
        final tiles = [
          _ShortcutTile(
            icon: Icons.photo_camera_rounded,
            label: 'Transformation',
            caption: 'Photos & measurements',
            onTap: () => Get.to(() => const TransformationScreen()),
          ),
          _ShortcutTile(
            icon: Icons.assignment_turned_in_rounded,
            label: 'Weekly check-in',
            caption: due ? 'Due now' : 'Send your coach an update',
            highlight: due,
            onTap: () => Get.to(() => const WeeklyReportScreen()),
          ),
          _ShortcutTile(
            icon: Icons.event_available_rounded,
            label: 'Schedule',
            caption: 'Your week & reviews',
            onTap: () => Get.to(() => const MemberScheduleScreen()),
          ),
        ];
        if (stack) {
          return Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                tiles[i],
                if (i != tiles.length - 1) const SizedBox(height: 9),
              ],
            ],
          );
        }
        // A RESERVED HEIGHT, not `IntrinsicHeight`.
        //
        // 🔴 THE DEVICE FOUND THIS AND NO HOST TEST COULD HAVE.
        // The first version wrapped the row in `IntrinsicHeight` to make the
        // three cards equal. `IntrinsicHeight` asks each child for its
        // intrinsic height, and `Text` computes ITS intrinsic height at
        // UNBOUNDED width — i.e. as a single line. In a 113dp-wide tile
        // "Transformation" and "Send your coach an update" both wrap to two
        // lines, so the measured height was short and the real content
        // overflowed the bottom by 18px on the emulator.
        //
        // Reserving the height instead makes the three tiles equal BY
        // CONSTRUCTION rather than by measurement, and the tile caps its own
        // text at the reserved number of lines, so the row cannot overflow at
        // any scale it is used at. Above 1.6x the tiles stack and take their
        // natural heights, where none of this applies.
        final rowHeight = _ShortcutTile.reservedHeight(scaler);
        return SizedBox(
          height: rowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                Expanded(child: tiles[i]),
                if (i != tiles.length - 1) const SizedBox(width: 9),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Overall progress ──────────────────────────────────────────────────────

  Widget _overview(
    BuildContext context,
    AppPalette p,
    ProgressAnalyticsController c,
  ) {
    final score = c.score;
    final dims = c.dimensions;
    final verdict = c.verdict;
    final direction = c.direction;

    return ProgressCard(
      accent: true,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final scaler = MediaQuery.textScalerOf(context).scale(1);
              final narrow = constraints.maxWidth < 300 || scaler >= 1.5;
              final ring = _scoreRing(p, score, verdict);
              final copy = _verdictCopy(p, verdict, direction, c);
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: ring),
                    const SizedBox(height: 16),
                    copy,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ring,
                  const SizedBox(width: 18),
                  Expanded(child: copy),
                ],
              );
            },
          ),
          if (dims.isNotEmpty) ...[
            const SizedBox(height: 18),
            Divider(height: 1, color: p.border.withValues(alpha: .8)),
            const SizedBox(height: 14),
            for (var i = 0; i < dims.length; i++) ...[
              _dimensionRow(context, p, dims[i]),
              if (i != dims.length - 1) const SizedBox(height: 11),
            ],
          ],
          const SizedBox(height: 16),
          Divider(height: 1, color: p.border.withValues(alpha: .8)),
          const SizedBox(height: 14),
          _statBand(context, p, c),
        ],
      ),
    );
  }

  Widget _scoreRing(AppPalette p, double? score, ProgressVerdict verdict) {
    // NO SCORE MEANS NO RING FILL — not a ring at zero. A 0% arc under a member
    // who simply has not logged enough yet is a grade they did not earn.
    final tint = switch (verdict) {
      ProgressVerdict.building => p.textMuted,
      ProgressVerdict.slipping || ProgressVerdict.behind => kProgressAmber,
      ProgressVerdict.steady => p.accent,
      ProgressVerdict.improving || ProgressVerdict.excellent => kProgressGreen,
    };
    return ProgressRing(
      value: score ?? 0,
      palette: p,
      colors: [tint, tint],
      diameter: 108,
      semanticLabel: score == null
          ? 'Progress score not available yet'
          : 'Progress score ${(score * 100).round()} percent',
      child: score == null
          ? Icon(Icons.hourglass_empty_rounded, color: p.textMuted, size: 26)
          : AnimatedCount(
              value: score * 100,
              // The ring sweeps from empty, so the number counting up with it
              // is the two halves of one object agreeing. A standalone figure
              // would be displaying false readings on the way.
              animateOnAppear: true,
              builder: (context, shown) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(shown ?? 0).round()}%',
                    style: AppText.title(size: 26).copyWith(color: tint),
                  ),
                  Text(
                    'overall',
                    style: AppText.body(size: 10.5).copyWith(
                      color: p.textMuted,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _verdictCopy(
    AppPalette p,
    ProgressVerdict verdict,
    ProgressDirection direction,
    ProgressAnalyticsController c,
  ) {
    final (title, body) = switch (verdict) {
      ProgressVerdict.building => (
        'Still building your picture',
        'A few more logged days and this becomes a real read on your training, '
            'not a guess.',
      ),
      ProgressVerdict.slipping => (
        'Momentum is slipping',
        'Something has dropped off compared with earlier in the '
            '${c.range.value.phrase}. The insights below name which part.',
      ),
      ProgressVerdict.behind => (
        'Below your targets',
        'You are under the ${(AnalyticsPolicy.onTrackPct * 100).round()}% '
            'on-track mark across the ${c.range.value.phrase}.',
      ),
      ProgressVerdict.steady => (
        'Holding steady',
        'Consistent across the ${c.range.value.phrase}, with no drop-off.',
      ),
      ProgressVerdict.improving => (
        'Trending up',
        'Your recent half of the ${c.range.value.phrase} is measurably better '
            'than the half before it.',
      ),
      ProgressVerdict.excellent => (
        'Everything is clicking',
        'On target and recently active. This is what a good block looks like.',
      ),
    };

    final momentum = c.momentumOf;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppText.title(size: 19).copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: 5),
        Text(
          body,
          style: AppText.body(
            size: 12.5,
          ).copyWith(color: p.textMuted, height: 1.4),
        ),
        if (momentum != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                directionIcon(momentum.direction),
                size: 15,
                color: directionColor(p, momentum.direction),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Active ${momentum.recentDays} of the last '
                  '${momentum.halfWindow} days',
                  style: AppText.body(size: 11.5).copyWith(
                    color: p.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _dimensionRow(BuildContext context, AppPalette p, ScoredDimension d) {
    // LOW CONFIDENCE STILL SHOWS THE DIMENSION, but says so instead of
    // headlining a number three days cannot support.
    final trusted = d.confidence == ProgressConfidence.ok;
    return Semantics(
      container: true,
      label:
          '${d.label}: ${(d.value * 100).round()} percent, '
          '${directionWord(d.direction)}, ${d.sample} days recorded'
          '${trusted ? '' : ', still building'}',
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Flexible, because "Workout quality" at 2.0x text scale
                    // is wider than the column it sits in and a bare Text in
                    // a Row cannot shrink — it overflowed by 241px on a 320dp
                    // phone. The label ellipsises; the direction arrow beside
                    // it never gets pushed off the edge.
                    Flexible(
                      child: Text(
                        d.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(
                          size: 13,
                        ).copyWith(color: p.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Icon(
                      directionIcon(d.direction),
                      size: 14,
                      color: directionColor(p, d.direction),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: d.value.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 640),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 5,
                      backgroundColor: p.surfaceAlt,
                      valueColor: AlwaysStoppedAnimation(
                        trusted ? p.accent : p.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // The value column scales with the text, or a percentage at 2.0x
          // does not fit the box reserved for it at 1.0x.
          SizedBox(
            width: 62 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(d.value * 100).round()}%',
                    maxLines: 1,
                    style: AppText.label(size: 14).copyWith(
                      color: trusted ? p.textPrimary : p.textMuted,
                    ),
                  ),
                ),
                Text(
                  trusted ? '${d.sample} days' : 'building',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 10).copyWith(color: p.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBand(
    BuildContext context,
    AppPalette p,
    ProgressAnalyticsController c,
  ) {
    final freq = c.weeklyFrequency;
    final stats = <Widget>[
      ProgressStat(
        value: '${c.trainingDays}',
        label: 'Training days',
        caption: c.range.value.phrase,
      ),
      ProgressStat(
        value: freq == 0 ? '—' : freq.toStringAsFixed(1),
        label: 'Per week',
        caption: 'observed',
      ),
      ProgressStat(
        value: '${c.currentStreak}',
        label: 'Day streak',
        caption: c.currentStreak == 0 ? 'not running' : 'running',
        valueColor: c.currentStreak > 0 ? kProgressGreen : null,
        icon: c.currentStreak > 0 ? Icons.local_fire_department_rounded : null,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context).scale(1);
        // Three unbreakable numbers cannot share a 320dp row at 2.0x. Below
        // that threshold they wrap rather than truncate.
        if (constraints.maxWidth < 280 || scaler >= 1.6) {
          return Wrap(
            spacing: 24,
            runSpacing: 14,
            children: stats,
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in stats) Expanded(child: s),
          ],
        );
      },
    );
  }

  // ── History shortcuts ─────────────────────────────────────────────────────

  Widget _history(BuildContext context, AppPalette p) => Column(
    children: [
      _HistoryRow(
        icon: Icons.fitness_center_rounded,
        label: 'Workout history',
        caption: 'Every session, set by set',
        onTap: () => Get.to(() => const WorkoutHistoryScreen()),
      ),
      const SizedBox(height: 9),
      _HistoryRow(
        icon: Icons.restaurant_rounded,
        label: 'Nutrition history',
        caption: 'What you ate, day by day',
        onTap: () => Get.to(() => const NutritionHistoryScreen()),
      ),
      const SizedBox(height: 9),
      _HistoryRow(
        icon: Icons.spa_rounded,
        label: 'Lifestyle history',
        caption: 'Water, steps, sleep, supplements',
        onTap: () => Get.to(() => const LifestyleHistoryScreen()),
      ),
      const SizedBox(height: 9),
      _HistoryRow(
        icon: Icons.calendar_month_rounded,
        label: 'Consistency',
        caption: 'Streaks and your training calendar',
        onTap: () =>
            Get.to(() => const ConsistencyDetailScreen(isWorkout: true)),
      ),
    ],
  );

  // ── States ────────────────────────────────────────────────────────────────

  List<Widget> _skeleton() => const [
    SerenaSkeleton(height: 250),
    SizedBox(height: 22),
    SerenaSkeleton(height: 300),
    SizedBox(height: 22),
    SerenaSkeleton(height: 160),
  ];

  Widget _firstRun(AppPalette p) => const ProgressCard(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: SerenaEmptyState(
      glyph: '📈',
      title: 'Your progress starts with one record',
      body:
          'Log a workout, your food, or a transformation check-in. This screen '
          'turns those records into trends — and never shows a number your own '
          'data cannot support.',
      boxed: false,
    ),
  );

  Widget _unlinked(AppPalette p) => ProgressCard(
    child: Column(
      children: [
        Icon(Icons.link_off_rounded, color: p.accent, size: 40),
        const SizedBox(height: 12),
        Text(
          'Connect to a coach',
          style: AppText.title(size: 17).copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'Progress tracks your training against what your coach prescribes. '
          'Link a membership to start the record.',
          textAlign: TextAlign.center,
          style: AppText.body(size: 12).copyWith(color: p.textMuted),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Find a Coach',
          icon: Icons.search,
          onPressed: () => Get.to(() => const JoinCoachScreen()),
        ),
      ],
    ),
  );
}

/// One tile of the premium shortcut row.
class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;
  final bool highlight;

  // 11.5, not 12.5: at 12.5 the single longest label — "Transformation", which
  // has no space to break at — did not fit the third of a 390dp row this tile
  // gets, so Flutter broke it MID-WORD and the shortcut read "Transformatio /
  // n" on a real device. A hard line cap cannot prevent that; only making the
  // word fit can. `reservedHeight` derives from this same constant, so the row
  // reservation follows automatically.
  static const double _labelSize = 11.5;
  static const double _captionSize = 10.5;
  static const double _lineFactor = 1.32;
  static const int _labelLines = 2;
  static const int _captionLines = 2;

  /// The height the row reserves for every tile, at a given text scale.
  ///
  /// Derived from the SAME constants the tile lays out with, so the reservation
  /// and the content can never disagree — which is precisely how the
  /// `IntrinsicHeight` version came to be 18px short on a real device.
  static double reservedHeight(double scaler) {
    const chrome = 13.0 + 13.0 + 19.0 + 10.0 + 3.0; // padding, icon, gaps
    final text =
        (_labelSize * _labelLines + _captionSize * _captionLines) *
        _lineFactor *
        scaler;
    return chrome + text;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      container: true,
      button: true,
      label: '$label. $caption',
      excludeSemantics: true,
      child: ProgressCard(
        accent: highlight,
        padding: const EdgeInsets.fromLTRB(12, 13, 12, 13),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: highlight ? kProgressAmber : p.accent,
                ),
                if (highlight) ...[
                  const Spacer(),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: kProgressAmber,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            // Flexible + a hard line cap. The reservation above is the
            // CONTRACT; these two make the tile keep it whatever the label
            // turns out to be, so a longer word in a future release
            // ellipsises instead of overflowing a row it cannot resize.
            Flexible(
              child: Text(
                label,
                maxLines: _labelLines,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(size: _labelSize).copyWith(
                  color: p.textPrimary,
                  height: _lineFactor,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Flexible(
              child: Text(
                caption,
                maxLines: _captionLines,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: _captionSize).copyWith(
                  color: p.textMuted,
                  height: _lineFactor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the history shortcut list.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      container: true,
      button: true,
      label: '$label. $caption',
      excludeSemantics: true,
      child: ProgressCard(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: p.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: p.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppText.body(
                      size: 13,
                    ).copyWith(color: p.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    style: AppText.body(size: 11).copyWith(color: p.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
