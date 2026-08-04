import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/lifestyle_history_controller.dart';
import '../../core/services/member_rollup_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/glass_card.dart';

/// THE MEMBER'S OWN LIFESTYLE HISTORY.
///
/// Water · Steps · Sleep · Supplements, each with a month calendar, streaks,
/// averages, best/toughest day, goal hit rate and a trend — the same figures
/// their coach sees, because both read the same server-derived rollups.
///
/// The member could previously see only TODAY. Their coach had a full history
/// screen per habit; the member had none, so the person doing the work could
/// not see whether it was adding up.
class LifestyleHistoryScreen extends StatefulWidget {
  const LifestyleHistoryScreen({super.key});

  @override
  State<LifestyleHistoryScreen> createState() => _LifestyleHistoryScreenState();
}

class _LifestyleHistoryScreenState extends State<LifestyleHistoryScreen> {
  late DateTime _month;

  /// True when THIS screen registered the controller, and is therefore the one
  /// responsible for disposing it. A controller injected by a test or a
  /// binding stays that owner's to manage.
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    // Registered HERE rather than in `build`, so ownership is decided once and
    // disposal has something honest to check.
    if (!Get.isRegistered<LifestyleHistoryController>()) {
      Get.put(LifestyleHistoryController());
      _ownsController = true;
    }
  }

  @override
  void dispose() {
    // LS-08. The controller was `Get.put` from `build` and deleted only on
    // SIGN-OUT, so its three monthly `coaching_rollups` listeners stayed open
    // for the rest of the session after a single visit to this screen — a
    // member who opened History once kept paying for it until they logged out.
    // `LifestyleController` has always torn its own listeners down; this one
    // simply had no owner.
    if (_ownsController) Get.delete<LifestyleHistoryController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = Get.find<LifestyleHistoryController>();

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Your history',
            style: AppText.title(size: 20).copyWith(color: p.textPrimary)),
      ),
      body: Obx(() {
        if (c.isLoading.value) return _skeleton(p);
        if (c.loadError.value) return _error(c, p);
        final h = c.historyFor(c.selected.value);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _habitTabs(c, p),
            const SizedBox(height: 16),
            if (!h.hasData)
              _empty(p, h)
            else ...[
              _stats(p, h),
              const SizedBox(height: 14),
              _bestWorst(p, h),
              const SizedBox(height: 18),
              _monthNav(p, h),
              const SizedBox(height: 10),
              _calendar(p, h),
              const SizedBox(height: 14),
              _legend(p, h),
            ],
            _windowNote(p),
          ],
        );
      }),
    );
  }

  // ── HABIT SELECTION ──────────────────────────────────────────────────────

  Widget _habitTabs(LifestyleHistoryController c, AppPalette p) => SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final kind in HabitKind.values) ...[
              _tab(c, p, kind),
              const SizedBox(width: 8),
            ],
          ],
        ),
      );

  Widget _tab(LifestyleHistoryController c, AppPalette p, HabitKind kind) {
    final selected = c.selected.value == kind;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? p.accent
            : (p.isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFF3F5F9)),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => c.select(kind),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(
                kind.label,
                style: AppText.body(size: 13).copyWith(
                  color: selected ? Colors.white : p.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── STATISTICS ───────────────────────────────────────────────────────────

  String _fmt(HabitHistory h, double v) => switch (h.kind) {
        HabitKind.water => '${(v / 1000).toStringAsFixed(1)}L',
        HabitKind.steps =>
          v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.round().toString(),
        HabitKind.sleep => '${v.toStringAsFixed(1)}h',
        HabitKind.supplements => v.round().toString(),
      };

  Widget _stats(AppPalette p, HabitHistory h) {
    final hit = h.goalHitRate;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _stat(p, '${h.currentStreak}', 'streak'),
        _stat(p, '${h.bestStreak}', 'best'),
        _stat(p, h.avg7 == null ? '—' : _fmt(h, h.avg7!), '7d avg'),
        _stat(p, h.avg30 == null ? '—' : _fmt(h, h.avg30!), '30d avg'),
        // Only when a goal exists — a hit rate against no goal is a rate
        // against nothing.
        if (hit != null) _stat(p, '${(hit * 100).round()}%', 'goal hit'),
        _stat(p, _trendLabel(h.trend), 'trend'),
      ],
    );
  }

  static String _trendLabel(int trend) => switch (trend) {
        1 => 'Up',
        -1 => 'Down',
        _ => 'Steady',
      };

  Widget _stat(AppPalette p, String value, String label) => Container(
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: p.surface.withValues(alpha: p.isDark ? 0.4 : 0.75),
          border: Border.all(color: p.border),
        ),
        child: Column(
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.title(size: 16).copyWith(color: p.textPrimary)),
            const SizedBox(height: 2),
            Text(label,
                style: AppText.body(size: 10.5).copyWith(color: p.textMuted)),
          ],
        ),
      );

  /// BEST and TOUGHEST day, over days the member actually LOGGED.
  Widget _bestWorst(AppPalette p, HabitHistory h) {
    final best = h.bestDay;
    final worst = h.worstDay;
    // One logged day is simultaneously the best and the toughest, which says
    // nothing. Wait for a comparison to exist before drawing one.
    if (best == null || worst == null || best.key == worst.key) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        _extreme(p, h, 'Best day', best, Icons.trending_up_rounded,
            const Color(0xFF2EBD59)),
        const SizedBox(width: 8),
        _extreme(p, h, 'Toughest day', worst, Icons.trending_down_rounded,
            p.textMuted),
      ],
    );
  }

  Widget _extreme(
    AppPalette p,
    HabitHistory h,
    String label,
    MapEntry<DateTime, double> day,
    IconData icon,
    Color tint,
  ) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: glassCard(p, radius: 12),
          child: Row(
            children: [
              Icon(icon, size: 15, color: tint),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: AppText.body(size: 10.5)
                            .copyWith(color: p.textMuted)),
                    const SizedBox(height: 2),
                    Text(_fmt(h, day.value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.cardTitle(size: 13.5)
                            .copyWith(color: p.textPrimary)),
                    Text(DateFormat('EEE, d MMM').format(day.key),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(size: 10.5)
                            .copyWith(color: p.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  // ── CALENDAR ─────────────────────────────────────────────────────────────

  DateTime _firstMonth(HabitHistory h) {
    if (h.dayValues.isEmpty) return _month;
    final first = h.dayValues.keys.reduce((a, b) => a.isBefore(b) ? a : b);
    return DateTime(first.year, first.month);
  }

  Widget _monthNav(AppPalette p, HabitHistory h) {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month);
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left),
          color: p.textPrimary,
          onPressed: _month.isAfter(_firstMonth(h))
              ? () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1))
              : null,
        ),
        Expanded(
          child: Text(
            DateFormat('MMMM yyyy').format(_month),
            textAlign: TextAlign.center,
            style: AppText.cardTitle(size: 15).copyWith(color: p.textPrimary),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          icon: const Icon(Icons.chevron_right),
          color: p.textPrimary,
          // A member cannot browse into a future that has not happened.
          onPressed: _month.isBefore(lastMonth)
              ? () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1))
              : null,
        ),
      ],
    );
  }

  Widget _calendar(AppPalette p, HabitHistory h) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // Monday-first, matching the rest of the app's week strips.
    final leading = (first.weekday + 6) % 7;

    return Column(
      children: [
        Row(
          children: [
            for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(d,
                      style: AppText.body(size: 10.5)
                          .copyWith(color: p.textMuted)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
            childAspectRatio: 1,
          ),
          itemCount: leading + daysInMonth,
          itemBuilder: (_, i) {
            if (i < leading) return const SizedBox.shrink();
            final day = DateTime(_month.year, _month.month, i - leading + 1);
            return _cell(p, h, day, today);
          },
        ),
      ],
    );
  }

  Widget _cell(AppPalette p, HabitHistory h, DateTime day, DateTime today) {
    final value = h.dayValues[day];
    final future = day.isAfter(today);
    // Three states, three renderings: hit · logged-below · not logged. A day
    // with no record is NEUTRAL, never coloured as a miss.
    final Color? fill = value == null
        ? null
        : (h.hasTarget && value >= h.target!
            ? p.accent.withValues(alpha: 0.75)
            : p.error.withValues(alpha: 0.35));
    return Semantics(
      label: '${DateFormat('d MMMM').format(day)}: '
          '${value == null ? 'not logged' : _fmt(h, value)}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: fill ??
              (p.isDark
                  ? Colors.white.withValues(alpha: future ? 0.02 : 0.05)
                  : const Color(0xFFF1F3F7)),
          borderRadius: BorderRadius.circular(8),
          border: day == today
              ? Border.all(color: p.accent, width: 1.4)
              : null,
        ),
        child: Center(
          child: Text(
            '${day.day}',
            style: AppText.body(size: 11).copyWith(
              color: fill != null
                  ? Colors.white
                  : (future ? p.textMuted.withValues(alpha: 0.5) : p.textMuted),
            ),
          ),
        ),
      ),
    );
  }

  Widget _legend(AppPalette p, HabitHistory h) => Wrap(
        spacing: 14,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (h.hasTarget) _chip(p, p.accent.withValues(alpha: 0.75), 'Goal hit'),
          if (h.hasTarget)
            _chip(p, p.error.withValues(alpha: 0.35), 'Below goal'),
          _chip(
            p,
            p.isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F3F7),
            'Not logged',
          ),
          if (!h.hasTarget)
            Text('No goal set for this habit',
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted)),
        ],
      );

  Widget _chip(AppPalette p, Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted)),
        ],
      );

  // ── STATES ───────────────────────────────────────────────────────────────

  /// WHAT THIS SCREEN CAN SEE.
  ///
  /// History is read from monthly rollups, and the reader subscribes to the
  /// last [MemberRollupService.defaultMonths]. The earliest reachable month is
  /// a property of the READ, not of the member — without saying so, hitting
  /// the back-stop is indistinguishable from having no earlier history.
  Widget _windowNote(AppPalette p) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 13, color: p.textMuted),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Showing the last ${MemberRollupService.defaultMonths} months '
                'of recorded history.',
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
              ),
            ),
          ],
        ),
      );

  Widget _empty(AppPalette p, HabitHistory h) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: glassCard(p, radius: 16),
        child: Column(
          children: [
            Icon(Icons.insights_rounded, size: 40, color: p.textMuted),
            const SizedBox(height: 14),
            Text('No ${h.kind.label.toLowerCase()} history yet',
                style:
                    AppText.cardTitle(size: 15).copyWith(color: p.textPrimary)),
            const SizedBox(height: 6),
            Text(
              'Days you log will appear here, with your streaks and averages.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 13).copyWith(color: p.textMuted),
            ),
          ],
        ),
      );

  Widget _error(LifestyleHistoryController c, AppPalette p) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: p.textMuted),
              const SizedBox(height: 14),
              Text("Couldn't load your history",
                  style: AppText.cardTitle(size: 15)
                      .copyWith(color: p.textPrimary)),
              const SizedBox(height: 6),
              // An error, NEVER the empty state: the empty state is a claim
              // about the member's behaviour, this is one about the network.
              Text(
                'This is a connection problem — nothing you logged is lost.',
                textAlign: TextAlign.center,
                style: AppText.body(size: 13).copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: c.retry,
                style: OutlinedButton.styleFrom(foregroundColor: p.accent),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );

  Widget _skeleton(AppPalette p) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: 4,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            height: i == 0 ? 40 : (i == 1 ? 78 : 150),
            decoration: BoxDecoration(
              color: p.isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFF1F3F7),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
}
