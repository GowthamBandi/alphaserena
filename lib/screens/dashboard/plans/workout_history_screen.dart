import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../controllers/workout_history_controller.dart';
import '../../../core/domain/workout_history.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/lifestyle_math.dart' show dayKey;
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/serena/premium_states.dart';
import 'plan_segmented_control.dart';
import 'workout_day_log_view.dart';
import 'workout_log_editor_screen.dart';

/// WORKOUT HISTORY.
///
/// The member's own training record: a month at a time, day by day, with the
/// full logged session behind any day they trained.
///
/// ── WHY A TIMELINE AND NOT A GRID ─────────────────────────────────────────
///
/// A month grid is a good answer to "how consistent was I?" — which is exactly
/// what `ConsistencyDetailScreen` already answers, and building a second one
/// here would have been the duplication this module has spent three passes
/// removing. This screen answers a different question: "what did I actually
/// do, and when?" That is a sequence, so it is drawn as one — a horizontal
/// strip the member scrubs through, with the selected day's whole session open
/// beneath it. Two screens, two questions, no overlap.
///
/// ── THE FOUR STATES, AND WHERE EACH COMES FROM ────────────────────────────
///
/// Completed / partial / skipped come from the member's own session document
/// (`computeSessionStats` over its sets). Rest / paused / excused / missed come
/// from the coach's prescription, resolved by the production engine against the
/// version that was in force ON THAT DATE. Neither half guesses at the other's
/// job, and a day about which both are silent reads as "nothing recorded" —
/// never as rest, and never as a miss.
class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen> {
  late final WorkoutHistoryController c;
  final ScrollController _timeline = ScrollController();

  /// Fires the cold-open centring once the days actually arrive. See
  /// [initState] for why the post-frame callback alone is not enough.
  Worker? _readyWorker;

  /// One day cell plus its gap. The timeline's scroll position is derived from
  /// this rather than measured, which is what makes "today is centred" exact
  /// instead of approximately right.
  static const double _cellWidth = 54;
  static const double _cellGap = 8;
  static const double _extent = _cellWidth + _cellGap;

  static const Color _accent = PlanSegmentedControl.workoutFill;

  @override
  void initState() {
    super.initState();
    final existing = Get.isRegistered<WorkoutHistoryController>();
    c = existing
        ? Get.find<WorkoutHistoryController>()
        : Get.put(WorkoutHistoryController());
    // BELT AND BRACES, and honestly labelled as such.
    //
    // The nutrition twin carries the same call under a comment claiming "the
    // controller outlives this screen — `Get.put` keeps one instance for the
    // session". MEASURED ON DEVICE, that is not true of either screen: the app
    // runs GetX's default `SmartManagement.full`, and a controller `Get.put`
    // inside a pushed route is disposed when that route pops. Proven twice on
    // emulator-5554 — select the 3rd, press back, re-enter, and the panel is on
    // TODAY again, which only a rebuilt controller explains.
    //
    // So every entry to History is already a cold load and there is no stale
    // month to fix. This guard is kept anyway, and costs one no-op branch:
    // marking the controller `permanent: true` — or GetX changing its disposal
    // rule — would otherwise silently reintroduce a member's own session
    // missing from their own record, with nothing on the screen to catch it.
    if (existing) c.load();
    // CENTRE THE CURRENT DATE, ONCE THE STRIP EXISTS.
    //
    // A member opening History on the 28th should not have to drag four weeks
    // to reach the day they just trained. Post-frame because the offset depends
    // on the viewport width, which does not exist until the first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _centreSelected());
    // ⚠️ THE LINE ABOVE NEVER ONCE WORKED IN PRODUCTION.
    //
    // This screen CREATES the controller, `onInit` starts the read, and
    // `isLoading` is therefore true for the whole of the first frame — the body
    // renders the skeleton, the timeline does not exist, and the post-frame
    // callback finds no `ScrollController` to move and returns silently.
    // Nothing re-centred when the days arrived.
    //
    // And because the controller is disposed on every route pop (see above),
    // that is not a first-visit quirk: EVERY entry to History is a cold entry,
    // so the strip never centred at all. A member opening History late in the
    // month got it parked on the 1st with the panel below describing the 28th —
    // no cell highlighted anywhere on screen, the exact "my tap was ignored"
    // state `showMonth` was fixed for.
    //
    // Measured before the fix: cold offset 0.0 against a 1568 extent; the same
    // screen handed an already-loaded controller centres at 1506.0. Every test
    // in the group literally named "the timeline centres the day the member
    // came to see" asserted `selectedIndex` — the SELECTION — and not one ever
    // read the scroll offset, which is why this survived.
    _readyWorker = ever<bool>(c.isLoading, (loading) {
      if (loading || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centreSelected();
      });
    });
  }

  @override
  void dispose() {
    _readyWorker?.dispose();
    _timeline.dispose();
    super.dispose();
  }

  void _centreSelected({bool animate = false}) {
    if (!_timeline.hasClients) return;
    final viewport = _timeline.position.viewportDimension;
    final target =
        (c.selectedIndex * _extent) - (viewport / 2) + (_cellWidth / 2);
    // Clamped to the scrollable range: the 1st and the 31st cannot be centred
    // on a strip that does not extend past them, and asking for an out-of-range
    // offset makes the list rubber-band on open.
    final clamped = target.clamp(
      _timeline.position.minScrollExtent,
      _timeline.position.maxScrollExtent,
    );
    if (animate) {
      _timeline.animateTo(
        clamped,
        duration: const Duration(milliseconds: 420),
        curve: PlanSegmentedControl.travelCurve,
      );
    } else {
      _timeline.jumpTo(clamped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: p.textPrimary),
        title: Text('Workout History',
            style: AppText.title(size: 20).copyWith(color: p.textPrimary)),
      ),
      body: SafeArea(
        top: false,
        child: Obx(() {
          if (c.isLoading.value) return _skeleton(p);
          if (c.loadError.value) return _error(p);
          return RefreshIndicator(
            color: _accent,
            onRefresh: c.load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _selectors(p),
                ),
                // Reserves its slot whether visible or not, so a background
                // re-read can never push the calendar down as it arms.
                Padding(
                  padding: const EdgeInsets.only(left: 18, top: 6),
                  child: Obx(() => SyncWhisper(visible: c.isRefreshing.value)),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _monthSummary(p),
                ),
                const SizedBox(height: 16),
                // Full-bleed: a timeline that stops 18dp short of the screen
                // edge reads as a cut-off list rather than a scrollable one.
                _timelineStrip(p),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _legend(p),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _dayPanel(p),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── MONTH / YEAR ─────────────────────────────────────────────────────────

  Widget _selectors(AppPalette p) {
    final m = c.month.value;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _selectorPill(
            p,
            label: 'Month',
            value: DateFormat('MMMM').format(m),
            onTap: () => _pickMonth(p),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _selectorPill(
            p,
            label: 'Year',
            value: '${m.year}',
            onTap: () => _pickYear(p),
          ),
        ),
      ],
    );
  }

  Widget _selectorPill(
    AppPalette p, {
    required String label,
    required String value,
    required VoidCallback onTap,
  }) =>
      Semantics(
        button: true,
        label: '$label, $value',
        container: true,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: p.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFF1F3F7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label.toUpperCase(),
                            style: AppText.label(size: 9.5).copyWith(
                                color: p.textMuted, letterSpacing: 1.0)),
                        const SizedBox(height: 2),
                        Text(value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.cardTitle(size: 14.5)
                                .copyWith(color: p.textPrimary)),
                      ],
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, size: 18, color: p.textMuted),
                ],
              ),
            ),
          ),
        ),
      );

  Future<void> _pickMonth(AppPalette p) async {
    final year = c.month.value.year;
    await _sheet(
      p,
      title: 'Month',
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (var i = 1; i <= 12; i++)
            _option(
              p,
              label: DateFormat('MMM').format(DateTime(year, i)),
              selected: c.month.value.month == i,
              // A month that has not happened yet is OFFERED AND DISABLED
              // rather than hidden: a grid that reflows from 12 cells to 8 when
              // the member switches to the current year is a grid they have to
              // re-read.
              enabled: !c.isFutureMonth(year, i),
              onTap: () {
                c.showMonth(year, i);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
    _afterMonthChange();
  }

  Future<void> _pickYear(AppPalette p) async {
    final years = c.years;
    await _sheet(
      p,
      title: 'Year',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final y in years)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: _option(
                  p,
                  label: '$y',
                  selected: c.month.value.year == y,
                  enabled: true,
                  onTap: () {
                    // Switching year keeps the month where possible, and falls
                    // back to the latest month that has actually happened —
                    // landing a member on a future month of the current year
                    // would show them an empty calendar and no way to tell why.
                    var month = c.month.value.month;
                    while (month > 1 && c.isFutureMonth(y, month)) {
                      month--;
                    }
                    c.showMonth(y, month);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ),
        ],
      ),
    );
    _afterMonthChange();
  }

  void _afterMonthChange() {
    if (!mounted) return;
    // The strip is rebuilt for the new month; centring must wait for that
    // frame or it would scroll the OLD month's extents.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _centreSelected(animate: true));
  }

  Future<void> _sheet(
    AppPalette p, {
    required String title,
    required Widget child,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: p.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: p.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(title,
                      style: AppText.title(size: 18)
                          .copyWith(color: p.textPrimary)),
                  const SizedBox(height: 14),
                  child,
                ],
              ),
            ),
          ),
        ),
      );

  Widget _option(
    AppPalette p, {
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) =>
      Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        inMutuallyExclusiveGroup: true,
        label: label,
        container: true,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: enabled ? onTap : null,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: selected
                    ? _accent.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: selected ? _accent : p.border),
              ),
              child: Text(
                label,
                style: AppText.label(size: 13).copyWith(
                  color: !enabled
                      ? p.textMuted.withValues(alpha: 0.45)
                      : selected
                          ? _accent
                          : p.textPrimary,
                ),
              ),
            ),
          ),
        ),
      );

  // ── MONTH SUMMARY ────────────────────────────────────────────────────────

  Widget _monthSummary(AppPalette p) {
    final sessions = c.monthSessionCount;
    final volume = c.monthVolumeKg;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: glassCard(p, radius: 16),
      child: Wrap(
        spacing: 26,
        runSpacing: 12,
        children: [
          _summaryStat(p, 'Sessions', '$sessions'),
          // Only once something was logged: "0 sets" beside "0 sessions" is
          // the same fact twice, and the second one reads as a judgement.
          if (sessions > 0)
            _summaryStat(p, 'Sets completed', '${c.monthCompletedSets}'),
          if (volume != null)
            _summaryStat(p, 'Volume', '${volume.round()} kg'),
        ],
      ),
    );
  }

  Widget _summaryStat(AppPalette p, String label, String value) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.body(size: 11).copyWith(color: p.textMuted)),
          const SizedBox(height: 2),
          Text(value,
              style: AppText.title(size: 21).copyWith(color: p.textPrimary)),
        ],
      );

  // ── THE TIMELINE ─────────────────────────────────────────────────────────

  /// THE STRIP GROWS WITH THE TEXT, RATHER THAN CLIPPING IT.
  ///
  /// The height was a flat `92`, while the two glyphs inside it — the weekday
  /// initial and the day number — scale with the member's accessibility text
  /// setting. At 2.0x that Column wanted 95dp and got 90, so every one of the
  /// ~30 cells painted an overflow stripe across the screen's ONLY navigation
  /// surface. Clamping the scaler would have "fixed" it by shrinking type for
  /// exactly the members who asked for larger type.
  ///
  /// So the height is derived from the same two styles the cell renders, and
  /// floored at the original 92 — the 1.0x design is untouched, and the strip
  /// can only ever grow. The multiplier is Poppins' own line box, deliberately
  /// generous: this returns a MINIMUM, and over-reserving costs a few dp of a
  /// horizontal strip while under-reserving costs a clipped calendar.
  double _stripHeight(BuildContext context) {
    final ts = MediaQuery.textScalerOf(context);
    final glyphs = ts.scale(10.5) * 1.5 + ts.scale(16) * 1.5;
    // The gaps (4 + 6), the state mark (9) and the 1dp border top and bottom
    // are fixed — they do not scale with text and must not be multiplied.
    const fixed = 4 + 6 + 9 + 2;
    return math.max(92, glyphs + fixed);
  }

  Widget _timelineStrip(AppPalette p) {
    final days = c.days;
    final selectedKey = dayKey(c.selectedDay.value);
    final todayKey = dayKey(DateTime.now());
    return SizedBox(
      height: _stripHeight(context),
      child: ListView.builder(
        controller: _timeline,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: days.length,
        itemExtent: _extent,
        itemBuilder: (_, i) {
          final day = days[i];
          return _dayCell(
            p,
            day,
            isSelected: dayKey(day.date) == selectedKey,
            isToday: dayKey(day.date) == todayKey,
          );
        },
      ),
    );
  }

  Widget _dayCell(
    AppPalette p,
    WorkoutHistoryDay day, {
    required bool isSelected,
    required bool isToday,
  }) {
    final visual = _visualFor(p, day.state);
    final future = day.state == WorkoutDayState.future;

    return Padding(
      padding: const EdgeInsets.only(right: _cellGap),
      child: Semantics(
        button: !future,
        selected: isSelected,
        label: '${DateFormat('EEEE d MMMM').format(day.date)}, '
            '${visual.semantics}',
        container: true,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            // A future day cannot be selected: there is nothing behind it and
            // nothing to say about it, and a cell that highlights but shows an
            // empty panel is worse than one that does not respond.
            onTap: future ? null : () => c.select(day.date),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: _cellWidth,
              decoration: BoxDecoration(
                color: isSelected
                    ? visual.fill.withValues(alpha: p.isDark ? 0.20 : 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? visual.fill
                      : isToday
                          ? p.border
                          : Colors.transparent,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    // One letter, uppercased — a three-letter weekday does not
                    // fit a 54dp cell at any accessibility text size.
                    DateFormat('E').format(day.date).substring(0, 1),
                    style: AppText.body(size: 10.5).copyWith(
                      color: future
                          ? p.textMuted.withValues(alpha: 0.4)
                          : p.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${day.date.day}',
                    style: AppText.cardTitle(size: 16).copyWith(
                      color: future
                          ? p.textMuted.withValues(alpha: 0.4)
                          : isSelected
                              ? p.textPrimary
                              : p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _stateMark(p, day.state, visual),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The state, as a SHAPE as well as a colour.
  ///
  /// Colour alone fails every member with a colour-vision deficiency, and this
  /// strip is the entire navigational surface of the screen. Completed is a
  /// filled dot, partial is a half-filled ring, skipped is a bar, rest is a
  /// hollow ring, missed is a hairline dot, and nothing-recorded is nothing.
  Widget _stateMark(AppPalette p, WorkoutDayState state, _DayVisual visual) {
    switch (state) {
      case WorkoutDayState.completed:
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: visual.fill, shape: BoxShape.circle),
        );
      case WorkoutDayState.partial:
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: visual.fill, width: 2.5),
          ),
        );
      case WorkoutDayState.skipped:
        return Container(
          width: 10,
          height: 3,
          decoration: BoxDecoration(
            color: visual.fill,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      case WorkoutDayState.missed:
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: visual.fill, width: 1),
          ),
        );
      case WorkoutDayState.rest:
      case WorkoutDayState.paused:
      case WorkoutDayState.excused:
        return Icon(visual.icon, size: 11, color: visual.fill);
      case WorkoutDayState.today:
      case WorkoutDayState.future:
      case WorkoutDayState.unknown:
        // Deliberately EMPTY. A dot here would be a claim, and about these
        // days the app has nothing to claim.
        return const SizedBox(height: 9);
    }
  }

  _DayVisual _visualFor(AppPalette p, WorkoutDayState state) =>
      switch (state) {
        WorkoutDayState.completed => (
            fill: const Color(0xFF2EBD59),
            icon: Icons.check_rounded,
            label: 'Completed',
            semantics: 'workout completed',
          ),
        WorkoutDayState.partial => (
            fill: _accent,
            icon: Icons.timelapse_rounded,
            label: 'Partial',
            semantics: 'workout partly completed',
          ),
        WorkoutDayState.skipped => (
            fill: const Color(0xFFE0A106),
            icon: Icons.remove_rounded,
            label: 'Skipped',
            semantics: 'workout skipped',
          ),
        WorkoutDayState.missed => (
            fill: p.textMuted,
            icon: Icons.close_rounded,
            label: 'Missed',
            semantics: 'training day missed',
          ),
        WorkoutDayState.rest => (
            fill: p.textMuted,
            icon: Icons.bedtime_outlined,
            label: 'Rest',
            semantics: 'rest day',
          ),
        WorkoutDayState.paused => (
            fill: p.textMuted,
            icon: Icons.pause_rounded,
            label: 'Paused',
            semantics: 'coaching paused',
          ),
        WorkoutDayState.excused => (
            fill: p.textMuted,
            icon: Icons.event_available_outlined,
            label: 'Excused',
            semantics: 'excused by your coach',
          ),
        WorkoutDayState.today => (
            fill: p.accent,
            icon: Icons.today_rounded,
            label: 'Today',
            semantics: 'today, nothing logged yet',
          ),
        WorkoutDayState.future => (
            fill: p.textMuted,
            icon: Icons.circle_outlined,
            label: 'Upcoming',
            semantics: 'upcoming',
          ),
        WorkoutDayState.unknown => (
            fill: p.textMuted,
            icon: Icons.remove_rounded,
            label: 'Nothing recorded',
            semantics: 'nothing recorded',
          ),
      };

  /// Only the states actually PRESENT this month.
  ///
  /// A fixed legend of nine keys under a month containing two of them is
  /// noise — and, worse, it implies the other seven are somewhere on screen to
  /// be found.
  Widget _legend(AppPalette p) {
    final present = <WorkoutDayState>{
      for (final d in c.days)
        if (d.state != WorkoutDayState.future &&
            d.state != WorkoutDayState.unknown)
          d.state,
    };
    if (present.isEmpty) return const SizedBox.shrink();
    const order = [
      WorkoutDayState.completed,
      WorkoutDayState.partial,
      WorkoutDayState.skipped,
      WorkoutDayState.missed,
      WorkoutDayState.rest,
      WorkoutDayState.paused,
      WorkoutDayState.excused,
      WorkoutDayState.today,
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final state in order)
          if (present.contains(state))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _stateMark(p, state, _visualFor(p, state)),
                const SizedBox(width: 6),
                Text(_visualFor(p, state).label,
                    style:
                        AppText.body(size: 11).copyWith(color: p.textMuted)),
              ],
            ),
      ],
    );
  }

  // ── THE SELECTED DAY ─────────────────────────────────────────────────────

  Widget _dayPanel(AppPalette p) {
    final day = c.selected;
    if (day == null) return const SizedBox.shrink();
    final log = day.log;

    return StateSwap(
      stateKey: dayKey(day.date),
      child: Column(
        key: ValueKey(dayKey(day.date)),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(DateFormat('EEEE, d MMMM').format(day.date).toUpperCase(),
              style: AppText.label(size: 11)
                  .copyWith(color: p.textMuted, letterSpacing: 1.0)),
          const SizedBox(height: 10),
          if (log != null)
            WorkoutDayLogView(
              log: log,
              today: DateTime.now(),
              // TODAY IS EDITABLE, THE PAST IS NOT — the same rule the food
              // log applies, and for the same reason: corrections belong to
              // the day they were made on, and a history list built for review
              // invites accidental rewrites of days a coach has already read.
              onEdit: dayKey(day.date) == dayKey(DateTime.now())
                  ? () => _openEditor(log)
                  : null,
            )
          else
            _noLog(p, day),
        ],
      ),
    );
  }

  Future<void> _openEditor(WorkoutDayLog log) async {
    await Get.to(() => WorkoutLogEditorScreen(
          sessionId: log.sessionId,
          initial: log,
        ));
    // Re-read on return: the editor writes straight to Firestore, so the copy
    // this screen is holding is stale the moment a set is corrected.
    await c.load();
  }

  /// A day with no session. Says WHY, from the coach's own prescription, and
  /// says nothing when the prescription cannot answer either.
  Widget _noLog(AppPalette p, WorkoutHistoryDay day) {
    final (title, body) = switch (day.state) {
      WorkoutDayState.rest => (
          'Rest day',
          'Your coach prescribed no training on this day. Recovery is part of '
              'the plan, not a gap in it.',
        ),
      WorkoutDayState.paused => (
          'Coaching paused',
          'Your coaching was paused on this day, so nothing was expected.',
        ),
      WorkoutDayState.excused => (
          'Excused by your coach',
          'Your coach cancelled this day after the fact — it counts against '
              'nothing.',
        ),
      WorkoutDayState.missed => (
          'No session logged',
          'Your coach had asked for a session on this day and none was '
              'recorded.',
        ),
      WorkoutDayState.today => (
          'Nothing logged yet today',
          "Today's session will appear here as soon as you log your first set.",
        ),
      WorkoutDayState.future => (
          'Still to come',
          'This day has not happened yet.',
        ),
      _ => (
          'Nothing recorded',
          // THE HONEST DEFAULT. Most members on most days have no coach-authored
          // prescription at all, so the app genuinely does not know whether this
          // was a rest day or a missed one — and it says exactly that rather
          // than picking the flattering answer or the accusatory one.
          c.hasPrescription
              ? 'No session was logged on this day.'
              : 'No session was logged on this day, and your coach has not set '
                  'a training schedule — so nothing was expected either.',
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
      decoration: glassCard(p, radius: 16),
      child: Column(
        children: [
          Icon(_visualFor(p, day.state).icon, size: 26, color: p.textMuted),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style:
                  AppText.cardTitle(size: 15).copyWith(color: p.textPrimary)),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: AppText.body(size: 12.5).copyWith(color: p.textMuted)),
        ],
      ),
    );
  }

  // ── STATES ───────────────────────────────────────────────────────────────

  /// THE SKELETON MIRRORS THE REAL LAYOUT, DOWN TO THE PADDING.
  ///
  /// It did not. The loaded screen pads `(0, 4, 0, 32)` and lets the timeline
  /// run full-bleed; the skeleton padded `(18, 8, 18, 28)` uniformly and drew
  /// the timeline inset with a hardcoded 92. So the moment the data arrived
  /// the whole page slid up 4dp and the timeline visibly grew 36dp wider —
  /// a placeholder that promises one layout and hands over another, which is
  /// the specific cheapness a skeleton exists to avoid.
  ///
  /// Every gap, every radius and the strip height now come from the same
  /// values the loaded screen uses, including [_stripHeight], so the swap is
  /// a dissolve rather than a reflow at ANY accessibility text size.
  Widget _skeleton(AppPalette p) => ListView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: SerenaSkeleton(height: 58, radius: 14),
          ),
          // 6 (whisper padding) + 18 (SyncWhisper.height, reserved whether it
          // is showing or not) + 8 — the loaded layout's gap, to the pixel. A
          // flat 14 here made the whole page jump 18dp the moment the days
          // arrived, which is the reflow this skeleton exists to avoid.
          const SizedBox(height: 6 + SyncWhisper.height + 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: SerenaSkeleton(height: 80, radius: 16),
          ),
          const SizedBox(height: 16),
          // Full-bleed, exactly like the strip it stands in for.
          SerenaSkeleton(height: _stripHeight(context), radius: 14),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: SerenaSkeleton(height: 22, radius: 8),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: SerenaSkeleton(height: 180, radius: 16),
          ),
        ],
      );

  Widget _error(AppPalette p) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: SerenaEmptyState(
            glyph: '\u{1F4E1}',
            title: "Couldn't load your history",
            // NEVER the empty state. "You have never trained" is a claim about
            // the member; this is a claim about the network.
            body: 'This is a connection problem — every session you logged is '
                'still saved.',
            actionLabel: 'Try again',
            onAction: c.load,
            boxed: false,
          ),
        ),
      );
}

/// How one day state is drawn and announced. A record type rather than a class:
/// it has no behaviour, and every field is read at the point of use.
typedef _DayVisual = ({
  Color fill,
  IconData icon,
  String label,
  String semantics,
});
