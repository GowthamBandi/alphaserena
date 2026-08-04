import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../controllers/food_log_controller.dart';
import '../../../controllers/nutrition_history_controller.dart';
import '../../../core/domain/nutrition_history.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/serena/premium_states.dart';
import '../plans/plan_segmented_control.dart';
import 'diet_screen.dart';
import 'nutrition_day_log_view.dart';

/// NUTRITION HISTORY — the member's own food record, on a calendar.
///
/// The deliberate twin of `WorkoutHistoryScreen`. Same anatomy, same gestures,
/// same rules — month and year selectors, a horizontal day timeline centred on
/// the selected date, a legend of only the states actually present, and a
/// panel below showing the chosen day in full. A member who has learned one
/// of these two screens has learned both, which is the entire point of
/// building it this way rather than inventing a second interaction model for
/// the other half of the same tab.
///
/// The differences are all differences of SUBJECT, and each is deliberate:
///
///   • **The accent is the Diet green**, not the workout red — the same two
///     colours the segmented control above it uses to name the two halves of
///     My Plans. A history screen in the wrong colour would read as the wrong
///     tab's history.
///   • **Five states, not nine.** A workout day can be rest, paused or excused
///     because a coach PRESCRIBES training. Nobody prescribes a rest day from
///     eating, so those states have no meaning here and are not invented.
///   • **`partial` comes from the day's OWN frozen adherence**, never from
///     today's target — see `nutrition_history.dart`, which is where that rule
///     lives and is tested.
class NutritionHistoryScreen extends StatefulWidget {
  const NutritionHistoryScreen({super.key});

  @override
  State<NutritionHistoryScreen> createState() => _NutritionHistoryScreenState();
}

class _NutritionHistoryScreenState extends State<NutritionHistoryScreen> {
  late final NutritionHistoryController c;

  /// Fires the cold-open centring once the days actually arrive. See
  /// [initState] for why the post-frame callback alone is not enough.
  Worker? _readyWorker;
  final ScrollController _timeline = ScrollController();

  /// One day cell plus its gap. The scroll position is DERIVED from this
  /// rather than measured, which is what makes "the current day is centred"
  /// exact instead of approximately right.
  static const double _cellWidth = 54;
  static const double _cellGap = 8;
  static const double _extent = _cellWidth + _cellGap;

  static const Color _accent = PlanSegmentedControl.dietFill;
  static const Color _logged = Color(0xFF2EBD59);
  static const Color _partial = Color(0xFFE0A106);

  @override
  void initState() {
    super.initState();
    final existing = Get.isRegistered<NutritionHistoryController>();
    c = existing
        ? Get.find<NutritionHistoryController>()
        : Get.put(NutritionHistoryController());
    // ⚠️ THIS COMMENT USED TO SAY "THE CONTROLLER OUTLIVES THIS SCREEN —
    // `Get.put` keeps one instance for the session". MEASURED ON DEVICE, it
    // does not. The app runs GetX's default `SmartManagement.full`, and a
    // controller `Get.put` inside a pushed route is disposed when that route
    // pops. Proven on emulator-5554 against the workout twin, which is built
    // the same way: select a past day, press back, re-enter, and the panel is
    // on TODAY again — only a rebuilt controller explains that.
    //
    // So every entry here is already a cold load, and the stale month this call
    // was written to prevent cannot currently occur. It is KEPT as belt and
    // braces at the cost of one no-op branch: marking the controller
    // `permanent: true` — or GetX changing its disposal rule — would otherwise
    // silently bring back a member's own lunch missing from their own record.
    // The re-read is QUIET (see `isRefreshing`), so days already on screen stay
    // on screen while it runs.
    if (existing) c.refreshVisibleMonth();
    // CENTRE THE CURRENT DATE, ONCE THE STRIP EXISTS.
    //
    // A member opening History on the 28th should not have to drag four weeks
    // to reach the day they just logged. Post-frame because the offset depends
    // on the viewport width, which does not exist until the first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _centreSelected());
    // ⚠️ THE LINE ABOVE NEVER ONCE WORKED IN PRODUCTION.
    //
    // This screen CREATES the controller, `onInit` starts the read, and
    // `isLoading` is therefore true for the whole of the first frame — the body
    // renders the skeleton, the timeline does not exist, and the post-frame
    // callback finds no `ScrollController` to move and returns silently.
    // Nothing re-centred when the days arrived. And since the controller is
    // disposed on every route pop (see above), EVERY entry is a cold entry, so
    // the strip never centred at all: a member opening History late in the
    // month got it parked on the 1st with the panel below describing the 28th.
    //
    // Measured before the fix: cold offset 0.0 against a 1568 extent.
    // `isRefreshing`, not `isLoading`, carries the re-read above — so this
    // fires exactly once, on the first load, and never yanks the strip out
    // from under a member who has scrolled it themselves.
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

  void _afterMonthChange() {
    if (!mounted) return;
    // The strip is rebuilt for the new month; centring must wait for that
    // frame or it would scroll against the OLD month's extents.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _centreSelected(animate: true));
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
        title: Text('Nutrition History',
            style: AppText.title(size: 20).copyWith(color: p.textPrimary)),
      ),
      body: SafeArea(
        top: false,
        child: Obx(() {
          if (c.isLoading.value) return _skeleton(p);
          return RefreshIndicator(
            color: _accent,
            onRefresh: () => c.load(force: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _selectors(p),
                ),
                // ── A FAILED MONTH MUST NOT TRAP THE MEMBER ──────────────
                //
                // The error used to replace the WHOLE body, selectors and
                // all — so a member who landed on a month that failed to load
                // had exactly two options: retry the same failing month, or
                // leave the screen. The one thing they actually wanted, "show
                // me a different month", was the thing the error state had
                // removed.
                //
                // The selectors stay. Only the CONTENT below them becomes the
                // apology, and changing month re-reads and recovers.
                if (c.loadError.value) ...[
                  const SizedBox(height: 28),
                  _error(p),
                ] else ...[
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
            _sheetOption(
              p,
              label: DateFormat('MMM').format(DateTime(year, i, 1)),
              selected: c.month.value.month == i,
              // OFFERED DISABLED, NEVER HIDDEN. Hiding them reflows a 12-cell
              // grid to however many months have happened — a grid the member
              // has to re-read every time they change year.
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
    await _sheet(
      p,
      title: 'Year',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final y in c.years)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: _sheetOption(
                  p,
                  label: '$y',
                  selected: c.month.value.year == y,
                  enabled: true,
                  onTap: () {
                    // Switching year keeps the month where possible, and falls
                    // back to the latest month that has actually happened —
                    // landing a member on a future month of the current year
                    // would show an empty calendar and no way to tell why.
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

  Widget _sheetOption(
    AppPalette p, {
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? _accent.withValues(alpha: 0.16) : null,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected ? _accent : p.border,
              ),
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
      );

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
                      style: AppText.title(size: 17)
                          .copyWith(color: p.textPrimary)),
                  const SizedBox(height: 14),
                  child,
                ],
              ),
            ),
          ),
        ),
      );

  // ── MONTH SUMMARY ────────────────────────────────────────────────────────

  Widget _monthSummary(AppPalette p) {
    final s = c.monthSummary;
    final avg = s.averageCalories;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: glassCard(p, radius: 16),
      child: Wrap(
        spacing: 26,
        runSpacing: 12,
        children: [
          _summaryStat(p, 'Days logged', '${s.daysLogged}'),
          // Only once something was logged: "0 items" beside "0 days" is the
          // same fact twice, and the second one reads as a judgement.
          if (s.daysLogged > 0) ...[
            _summaryStat(p, 'Items', '${s.entryCount}'),
            // Averaged over the days that HAVE food, never over the month —
            // dividing by 31 would report a member who logged a perfect week
            // as eating 400 kcal a day.
            if (avg != null)
              _summaryStat(p, 'Avg / day', '${avg.round()} kcal'),
          ],
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
  /// Derived from the same two styles the cell renders and floored at the
  /// original 92, so the 1.0x design is untouched and the strip can only ever
  /// grow. The workout twin shipped with a flat 92 and clipped every cell at
  /// 2.0x accessibility text; this one is built from that lesson rather than
  /// waiting to repeat it.
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
    final selectedKey = nutritionDayKey(c.selectedDay.value);
    final todayKey = nutritionDayKey(c.today);
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
            isSelected: nutritionDayKey(day.date) == selectedKey,
            isToday: nutritionDayKey(day.date) == todayKey,
          );
        },
      ),
    );
  }

  Widget _dayCell(
    AppPalette p,
    NutritionHistoryDay day, {
    required bool isSelected,
    required bool isToday,
  }) {
    final visual = _visualFor(p, day.state);
    final future = day.state == NutritionDayState.future;

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
  /// strip is the entire navigational surface of the screen. Logged is a
  /// filled dot, partial is a half-filled ring, today is a hollow ring, and an
  /// empty or future day is nothing at all — because nothing is what happened.
  Widget _stateMark(AppPalette p, NutritionDayState state, _DayVisual visual) {
    switch (state) {
      case NutritionDayState.logged:
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: visual.fill, shape: BoxShape.circle),
        );
      case NutritionDayState.partial:
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: visual.fill, width: 2),
          ),
        );
      case NutritionDayState.today:
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: visual.fill, width: 1.4),
          ),
        );
      case NutritionDayState.empty:
      case NutritionDayState.future:
        return const SizedBox(height: 9);
    }
  }

  _DayVisual _visualFor(AppPalette p, NutritionDayState state) =>
      switch (state) {
        NutritionDayState.logged => (
            fill: _logged,
            label: 'Logged',
            semantics: 'food logged',
          ),
        NutritionDayState.partial => (
            fill: _partial,
            label: 'Partial',
            semantics: 'logged, under target',
          ),
        NutritionDayState.empty => (
            fill: p.textMuted,
            label: 'Nothing logged',
            semantics: 'nothing logged',
          ),
        NutritionDayState.today => (
            fill: _accent,
            label: 'Today',
            semantics: 'today, nothing logged yet',
          ),
        NutritionDayState.future => (
            fill: p.textMuted,
            label: 'Upcoming',
            semantics: 'upcoming',
          ),
      };

  /// Only the states actually PRESENT this month.
  ///
  /// A fixed legend of five keys under a month containing two of them is
  /// noise — and, worse, it implies the other three are somewhere on screen to
  /// be found.
  Widget _legend(AppPalette p) {
    final present = <NutritionDayState>{
      for (final d in c.days)
        if (d.state != NutritionDayState.future &&
            d.state != NutritionDayState.empty)
          d.state,
    };
    if (present.isEmpty) return const SizedBox.shrink();
    const order = [
      NutritionDayState.logged,
      NutritionDayState.partial,
      NutritionDayState.today,
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final s in order)
          if (present.contains(s)) _legendKey(p, s),
      ],
    );
  }

  Widget _legendKey(AppPalette p, NutritionDayState state) {
    final v = _visualFor(p, state);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stateMark(p, state, v),
        const SizedBox(width: 6),
        Text(v.label,
            style: AppText.body(size: 11.5).copyWith(color: p.textMuted)),
      ],
    );
  }

  // ── THE DAY ──────────────────────────────────────────────────────────────

  Widget _dayPanel(AppPalette p) {
    final day = c.selected;
    if (day == null) return const SizedBox.shrink();
    final log = day.log;
    final isToday = nutritionDayKey(day.date) == nutritionDayKey(c.today);

    return StateSwap(
      stateKey: nutritionDayKey(day.date),
      child: Column(
        key: ValueKey(nutritionDayKey(day.date)),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(DateFormat('EEEE, d MMMM').format(day.date).toUpperCase(),
              style: AppText.label(size: 11)
                  .copyWith(color: p.textMuted, letterSpacing: 1.0)),
          const SizedBox(height: 10),
          if (log != null && log.hasEntries)
            NutritionDayLogView(
              log: log,
              // TODAY IS EDITABLE, THE PAST IS NOT — the same rule Workout
              // History applies, for the same reason: corrections belong to
              // the day they were made on, and a record built for review
              // invites accidental rewrites of days a coach has already read.
              onEdit: isToday ? _openFoodLog : null,
            )
          else
            _noLog(p, day, isToday),
        ],
      ),
    );
  }

  Future<void> _openFoodLog() async {
    // No history action on the Diet screen we push — this IS the history.
    await Get.to(() => const DietScreen(showHistoryAction: false));
    // Re-read on return: the Food Log writes straight to Firestore, so the
    // copy this screen is holding is stale the moment an entry is corrected.
    await c.load(force: true);
    // Today's totals may have changed, and Home reads the same controller.
    if (Get.isRegistered<FoodLogController>()) {
      Get.find<FoodLogController>().ensureFreshDay();
    }
  }

  /// A DAY WITH NOTHING ON IT — the premium empty state.
  ///
  /// Never a blank list, and never one message for three different days. A
  /// past day with nothing logged, today before the first meal, and a day that
  /// has not happened are three different facts about a member, and flattening
  /// them into "No data" would describe the DATABASE rather than describing
  /// them. Only the day that can still be acted on gets an action.
  Widget _noLog(AppPalette p, NutritionHistoryDay day, bool isToday) {
    final (glyph, title, body, action) = switch (day.state) {
      NutritionDayState.today => (
          '\u{1F374}',
          'Nothing logged yet today',
          "Today's meals will appear here as soon as you log your first food.",
          'Log Food',
        ),
      NutritionDayState.future => (
          '\u{1F4C5}',
          'Still to come',
          'This day has not happened yet.',
          null,
        ),
      _ => (
          '\u{1F37D}',
          'No food logged',
          'Nothing was recorded on this day. Days you did log are marked on '
              'the timeline above.',
          null,
        ),
    };

    return SerenaEmptyState(
      glyph: glyph,
      title: title,
      body: body,
      actionLabel: action,
      // The action exists ONLY for today. Offering "Log Food" on a day three
      // weeks ago would either write to the wrong day or do nothing, and both
      // are worse than no button.
      onAction: action != null && isToday ? _openFoodLog : null,
    );
  }

  // ── STATES ───────────────────────────────────────────────────────────────

  /// Mirrors the loaded layout exactly — same padding, same gaps, same
  /// full-bleed strip at the same text-scale-aware height — so the swap to
  /// real content is a dissolve rather than a reflow.
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
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: SerenaEmptyState(
            glyph: '\u{1F4E1}',
            title: "Couldn't load your history",
            // NEVER the empty state. "You have never logged food" is a claim
            // about the member; this is a claim about the network.
            body: 'This is a connection problem — every meal you logged is '
                'still saved.',
            actionLabel: 'Try again',
            onAction: () => c.load(force: true),
            boxed: false,
          ),
        ),
      );
}

/// How one day state is drawn and announced. A record type rather than a class:
/// it has no behaviour, and every field is read at the point of use.
typedef _DayVisual = ({
  Color fill,
  String label,
  String semantics,
});
