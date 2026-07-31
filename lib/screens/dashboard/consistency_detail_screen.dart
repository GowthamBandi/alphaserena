import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../controllers/member_controller.dart';
import '../../controllers/performance_controller.dart';
import '../../controllers/streak_controller.dart';
import '../../core/domain/consistency_pair.dart';
import '../../core/domain/consistency_story.dart';
import '../../core/domain/prescription.dart';
import '../../core/domain/today_expectation.dart' show localDayKey;
import '../../core/domain/workout_session.dart';
import '../../core/services/workout_log_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/glass_card.dart';
import 'home/consistency_cards_pair.dart'
    show kWorkoutStreakHeroTag, kNutritionStreakHeroTag, kLoggedGreen;

/// CONSISTENCY, TOLD AS A STORY.
///
/// The screen this replaces was a correct analytics dashboard: streak card,
/// today card, week card, timeline list, month grid, insights list. Six
/// sections, all true, none of them building on the one before. A member
/// finished it knowing their numbers and feeling nothing.
///
/// The rewrite is one narrative, five beats:
///
///   1. WHERE YOU STAND   the streak, given the whole first screen, plus the
///                        single most useful sentence in the product: exactly
///                        what closes the next milestone.
///   2. THIS WEEK         seven circles, every state visually distinct.
///   3. LAST 30 DAYS      the shape of the habit, tappable to the truth of any
///                        single day.
///   4. WHAT YOU'VE EARNED five milestones, each stating its window.
///   5. ONE LAST WORD     a closing line the data unlocked.
///
/// BUSINESS LOGIC IS UNTOUCHED. Every verdict comes from the certified engine
/// via [PerformanceController]; this screen counts and phrases, never judges.
class ConsistencyDetailScreen extends StatefulWidget {
  /// `workout` or `nutrition` — chooses the source set and the copy.
  final bool isWorkout;

  const ConsistencyDetailScreen({super.key, required this.isWorkout});

  @override
  State<ConsistencyDetailScreen> createState() =>
      _ConsistencyDetailScreenState();
}

class _ConsistencyDetailScreenState extends State<ConsistencyDetailScreen> {
  bool get _isWorkout => widget.isWorkout;

  String get _title =>
      _isWorkout ? 'Workout Consistency' : 'Nutrition Consistency';

  Color _tint(AppPalette p) => _isWorkout ? p.accent : kLoggedGreen;

  ConsistencyTrack get _track =>
      _isWorkout ? ConsistencyTrack.workout : ConsistencyTrack.nutrition;

  StreakController get _streaks => Get.isRegistered<StreakController>()
      ? Get.find<StreakController>()
      : Get.put(StreakController());

  PerformanceController get _perf => Get.isRegistered<PerformanceController>()
      ? Get.find<PerformanceController>()
      : Get.put(PerformanceController());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: p.textPrimary),
        title: Text(
          _title,
          style: AppText.cardTitle(size: 15).copyWith(color: p.textPrimary),
        ),
        actions: [_trackSwitch(p)],
      ),
      body: Obx(() {
        final perf = _perf;
        final s = _streaks;
        final loading = s.isLoading.value;
        final available =
            _isWorkout ? perf.workoutLogsAvailable : perf.dietLogsAvailable;
        final logged = perf.loggedOf(isWorkout: _isWorkout);
        final history = perf.historyOf(isWorkout: _isWorkout);

        final state = loading
            ? ConsistencyCardState.loading
            : !available
                ? ConsistencyCardState.unavailable
                : perf.weekOf(isWorkout: _isWorkout).paused
                    ? ConsistencyCardState.paused
                    : perf.weekOf(isWorkout: _isWorkout).unknown
                        ? ConsistencyCardState.unscheduled
                        : ConsistencyCardState.active;

        if (state == ConsistencyCardState.loading) return _loading(p);

        final weekUnit = _isWorkout && history.hasPrescription;
        final streak = _isWorkout
            ? (history.hasPrescription
                ? perf.weeklyStreakOf(isWorkout: true)
                : (s.workoutStreak ?? 0))
            : (history.hasPrescription
                ? perf.dailyStreakOf(isWorkout: false)
                : (s.dietStreak ?? 0));

        final hero = buildStreakHero(
          track: _track,
          state: state,
          streak: streak,
          weekUnit: weekUnit,
          hasHistory: logged.isNotEmpty,
          loggedToday: logged.contains(localDayKey(DateTime.now())),
        );

        final rail = buildWeekRail(
          history,
          logged: logged,
          today: DateTime.now(),
        );
        final verdicts = perf.timelineOf(isWorkout: _isWorkout, days: 35);
        final month = perf.monthOf(isWorkout: _isWorkout);
        final thisWeek = perf.weekOf(isWorkout: _isWorkout);

        return ConsistencyDetailView(
          isWorkout: _isWorkout,
          hero: hero,
          week: rail,
          verdicts: verdicts,
          achievements: buildAchievements(
            track: _track,
            logsAvailable: available,
            currentStreak: streak,
            longestStreak: _isWorkout ? s.workoutBest : s.dietBest,
            totalLogged: logged.length,
            verdicts: verdicts,
            monthCells: month,
            weekUnit: weekUnit,
          ),
          closingMessage: motivationMessage(
            track: _track,
            state: state,
            streak: streak,
            hasHistory: logged.isNotEmpty,
            thisWeek: thisWeek,
            lastWeekDone: _lastWeekDone(logged),
            adherence: adherenceOf(verdicts),
          ),
          onTapDay: (v) => _openDay(context, p, v),
        );
      }),
    );
  }

  /// Days logged in the PREVIOUS calendar week — the comparison the closing
  /// line uses. Counting logged days is not a verdict, so it needs no engine.
  int _lastWeekDone(Set<String> logged) {
    final t = DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    var n = 0;
    for (var i = 1; i <= 7; i++) {
      if (logged.contains(localDayKey(thisMonday.subtract(Duration(days: i))))) {
        n++;
      }
    }
    return n;
  }

  // ══ CHROME ═══════════════════════════════════════════════════════════════

  /// Switches tracks IN PLACE — one destination, two tracks. Home carries a
  /// card per track, so without this the nutrition screen would have no way in
  /// at all once a member arrived on the workout one.
  Widget _trackSwitch(AppPalette p) {
    final label = _isWorkout ? 'Nutrition' : 'Workout';
    return Semantics(
      button: true,
      label: 'Show $label consistency instead',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Material(
          color: p.surfaceAlt.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            // `off` rather than `to`: the two tracks are peers, so the back
            // stack must never grow a chain of alternating pages.
            onTap: () => Get.off(
              () => ConsistencyDetailScreen(isWorkout: !_isWorkout),
              preventDuplicates: false,
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isWorkout
                        ? Icons.restaurant_rounded
                        : Icons.fitness_center_rounded,
                    size: 13,
                    color: _isWorkout ? kLoggedGreen : p.accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: AppText.label(size: 11.5)
                        .copyWith(color: p.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the day sheet. The session lookup is LAZY — one deterministic doc
  /// read, only when a member actually asks about a day, using the same
  /// service and the same `computeSessionStats` every other surface uses.
  void _openDay(BuildContext context, AppPalette p, DayVerdict v) {
    HapticFeedback.selectionClick();
    final e = _perf.expectationDetailOf(v.date, isWorkout: _isWorkout);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DaySheet(
        verdict: v,
        expectation: e,
        palette: p,
        tint: _tint(p),
        isWorkout: _isWorkout,
      ),
    );
  }

  Widget _loading(AppPalette p) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
    children: [
      _skel(p, double.infinity, 250, 24),
      const SizedBox(height: 34),
      _skel(p, 92, 12, 4),
      const SizedBox(height: 14),
      _skel(p, double.infinity, 58, 12),
      const SizedBox(height: 34),
      _skel(p, 110, 12, 4),
      const SizedBox(height: 14),
      _skel(p, double.infinity, 190, 16),
      const SizedBox(height: 34),
      _skel(p, 140, 12, 4),
      const SizedBox(height: 14),
      for (var i = 0; i < 3; i++) ...[
        _skel(p, double.infinity, 64, 15),
        const SizedBox(height: 9),
      ],
    ],
  );

  Widget _skel(AppPalette p, double w, double h, double r) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: p.surfaceAlt,
      borderRadius: BorderRadius.circular(r),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// ONE DAY, AS A CIRCLE
// ═══════════════════════════════════════════════════════════════════════════

/// The single rendering of a day's state, shared by the week row, the legend
/// and the heat map — so the three can never drift into different vocabularies
/// for the same fact.
///
/// State is carried by FILL, BORDER and GLYPH together. Colour alone would
/// fail a colour-blind member and disappear entirely in greyscale.
class _DayCircle extends StatelessWidget {
  final TodayMark mark;
  final AppPalette palette;
  final Color tint;
  final bool isToday;
  final double size;

  const _DayCircle({
    required this.mark,
    required this.palette,
    required this.tint,
    required this.isToday,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final (Color fill, Color border, IconData? glyph, Color glyphColor) =
        switch (mark) {
      TodayMark.done => (tint, tint, Icons.check_rounded, Colors.white),
      TodayMark.rest => (
        p.textMuted.withValues(alpha: 0.13),
        p.textMuted.withValues(alpha: 0.3),
        Icons.remove_rounded,
        p.textMuted,
      ),
      TodayMark.excused => (
        kLoggedGreen.withValues(alpha: 0.14),
        kLoggedGreen.withValues(alpha: 0.45),
        Icons.shield_outlined,
        kLoggedGreen,
      ),
      TodayMark.paused => (
        p.textMuted.withValues(alpha: 0.10),
        p.textMuted.withValues(alpha: 0.28),
        Icons.pause_rounded,
        p.textMuted,
      ),
      // A miss is STATED, never shouted: an outlined circle in the muted tone.
      // The member already knows; an alarm colour would only add shame to a
      // fact, and shame is what makes people stop opening the app.
      TodayMark.missed => (
        Colors.transparent,
        p.textMuted.withValues(alpha: 0.5),
        Icons.close_rounded,
        p.textMuted,
      ),
      TodayMark.open => (
        tint.withValues(alpha: 0.10),
        tint,
        null,
        tint,
      ),
      TodayMark.future => (
        Colors.transparent,
        p.textMuted.withValues(alpha: 0.18),
        null,
        p.textMuted,
      ),
      TodayMark.unknown => (
        p.textMuted.withValues(alpha: 0.05),
        p.textMuted.withValues(alpha: 0.14),
        null,
        p.textMuted,
      ),
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(
          color: border,
          width: isToday ? 2 : 1.3,
        ),
      ),
      alignment: Alignment.center,
      child: glyph != null && size >= 20
          ? Icon(glyph, size: size * 0.46, color: glyphColor)
          : (mark == TodayMark.open && size >= 20
              ? Container(
                  width: size * 0.24,
                  height: size * 0.24,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: tint),
                )
              : null),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// THE HEAT MAP
// ═══════════════════════════════════════════════════════════════════════════

/// Five weeks, Monday-aligned, every cell tappable.
///
/// Alignment matters more than it looks: a grid that simply runs 30 cells from
/// today backwards puts Tuesday in a different column every month, and the
/// member loses the one pattern this view exists to reveal — *which days do I
/// actually train*. Monday-aligned columns make that legible at a glance.
class _HeatMap extends StatelessWidget {
  final List<DayVerdict> verdicts;
  final AppPalette palette;
  final Color tint;
  final void Function(DayVerdict)? onTapDay;

  const _HeatMap({
    required this.verdicts,
    required this.palette,
    required this.tint,
    required this.onTapDay,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final t = DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final start = thisMonday.subtract(const Duration(days: 28)); // 5 weeks

    final byKey = <String, DayVerdict>{
      for (final v in verdicts) localDayKey(v.date): v,
    };

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              SizedBox(
                width: 34,
                child: Text(
                  d,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: p.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var week = 0; week < 5; week++) ...[
          if (week > 0) const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var day = 0; day < 7; day++)
                _cell(p, start.add(Duration(days: week * 7 + day)), today,
                    byKey),
            ],
          ),
        ],
      ],
    );
  }

  Widget _cell(
    AppPalette p,
    DateTime date,
    DateTime today,
    Map<String, DayVerdict> byKey,
  ) {
    final v = byKey[localDayKey(date)];
    final future = date.isAfter(today);
    final mark = future
        ? TodayMark.future
        : v == null
            ? TodayMark.unknown
            : _markOf(v, today);
    final tappable = !future && v != null && onTapDay != null;

    return Semantics(
      button: tappable,
      label: '${DateFormat('EEEE d MMMM').format(date)}, '
          '${ConsistencyDetailView.markLabel(mark)}',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: tappable ? () => onTapDay!(v) : null,
          // 34px visual inside a 40px tap target clears the minimum comfortably
          // — the old grid used 26px cells, which is below every guideline and
          // genuinely hard to hit while holding a phone one-handed.
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: _DayCircle(
                mark: mark,
                palette: p,
                tint: tint,
                isToday: date == today,
                size: 34,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static TodayMark _markOf(DayVerdict v, DateTime today) {
    if (v.isHit) return TodayMark.done;
    if (v.isMiss) return TodayMark.missed;
    final d = DateTime(v.date.year, v.date.month, v.date.day);
    return switch (v.outcome) {
      OutcomeKind.excusedByCoach => TodayMark.excused,
      OutcomeKind.open => d == today ? TodayMark.open : TodayMark.unknown,
      _ => switch (v.expectation) {
        ExpectationKind.rest => TodayMark.rest,
        ExpectationKind.paused => TodayMark.paused,
        _ => TodayMark.unknown,
      },
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// THE DAY SHEET
// ═══════════════════════════════════════════════════════════════════════════

/// One day, fully described.
///
/// Stateful because the session facts are fetched LAZILY — a member who never
/// taps a day never pays for the read, and the 30-day grid never fires 30 of
/// them. The read is the SAME deterministic document id and the SAME
/// `computeSessionStats` every other surface uses.
class _DaySheet extends StatefulWidget {
  final DayVerdict verdict;
  final Expectation expectation;
  final AppPalette palette;
  final Color tint;
  final bool isWorkout;

  const _DaySheet({
    required this.verdict,
    required this.expectation,
    required this.palette,
    required this.tint,
    required this.isWorkout,
  });

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  SessionStats? _stats;
  int? _durationSeconds;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Only a COMPLETED workout day has a session worth fetching. Nutrition
    // days have no session document, and a missed day has nothing to show.
    if (widget.isWorkout && widget.verdict.isHit) _load();
  }

  Future<void> _load() async {
    final member = Get.isRegistered<MemberController>()
        ? Get.find<MemberController>()
        : null;
    final clientId = member?.clientId ?? '';
    if (clientId.isEmpty) return;
    setState(() => _loading = true);
    try {
      final id = workoutSessionIdFor(clientId, widget.verdict.date);
      final doc = await WorkoutLogService().fetchSession(id);
      if (!mounted) return;
      if (doc == null) {
        setState(() => _loading = false);
        return;
      }
      final logs = exercisesFromEntries(doc['entries']);
      final d = doc['durationSeconds'];
      setState(() {
        _stats = logs.isEmpty ? null : computeSessionStats(logs);
        _durationSeconds = d is num && d > 0 ? d.toInt() : null;
        _loading = false;
      });
    } catch (_) {
      // A failed lookup states LESS, never something invented.
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final v = widget.verdict;
    final e = widget.expectation;
    final reason = reasonLabelFor(e.reason);
    final facts =
        dayFactsFrom(stats: _stats, durationSeconds: _durationSeconds);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _DayCircle(
                  mark: _HeatMap._markOf(v, DateTime.now()),
                  palette: p,
                  tint: widget.tint,
                  isToday: false,
                  size: 40,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('EEEE, d MMMM').format(v.date),
                        style: AppText.cardTitle(size: 15)
                            .copyWith(color: p.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        outcomeLabelFor(v),
                        style: AppText.body(size: 12.5)
                            .copyWith(color: p.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_loading)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: p.textMuted),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Loading this session…',
                      style: AppText.body(size: 12)
                          .copyWith(color: p.textMuted),
                    ),
                  ],
                ),
              )
            else if (facts.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: glassCardSoft(p, radius: 14),
                child: Row(
                  children: [
                    for (var i = 0; i < facts.length; i++) ...[
                      if (i > 0)
                        Container(width: 1, height: 26, color: p.border),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              facts[i].value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.title(size: 19)
                                  .copyWith(color: p.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              facts[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                color: p.textMuted,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            _row(p, 'Coach asked', expectationLabelFor(e.kind)),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 10),
              _row(p, 'Reason', reason),
            ],
            if (e.note.isNotEmpty) ...[
              const SizedBox(height: 10),
              // The coach's own words for that day, verbatim.
              _row(p, 'Coach note', e.note),
            ],
            const SizedBox(height: 10),
            _row(
              p,
              'Counts',
              v.isHit
                  ? 'Yes — completed'
                  : v.isMiss
                      ? 'As a missed day'
                      : 'Not counted either way',
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(AppPalette p, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 96,
        child: Text(
          label,
          style: AppText.label(size: 11.5).copyWith(color: p.textMuted),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: AppText.body(size: 12.5).copyWith(color: p.textPrimary),
        ),
      ),
    ],
  );
}

/// THE DETAIL SCREEN'S BODY, as a pure widget.
///
/// Extracted from the screen so every state — a 60-day streak, a paused
/// track, an empty first-week member, a month full of misses — can be rendered
/// on a real device and in a golden without Firebase, an account, or a network.
/// The screen above resolves the data; this decides nothing.
class ConsistencyDetailView extends StatelessWidget {
  final bool isWorkout;
  final StreakHero hero;
  final List<TodayMark> week;
  final List<DayVerdict> verdicts;
  final List<Achievement> achievements;
  final String closingMessage;

  /// Null → the heat map renders but no day opens. Keeps the view pure.
  final void Function(DayVerdict)? onTapDay;

  const ConsistencyDetailView({
    super.key,
    required this.isWorkout,
    required this.hero,
    required this.week,
    required this.verdicts,
    required this.achievements,
    required this.closingMessage,
    this.onTapDay,
  });

  Color _tint(AppPalette p) => isWorkout ? p.accent : kLoggedGreen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        _hero(p, hero),
        const SizedBox(height: 34),
        _section(p, 'THIS WEEK'),
        const SizedBox(height: 14),
        _weekCircles(p, week),
        const SizedBox(height: 16),
        _weekLegend(p),
        const SizedBox(height: 34),
        _section(p, 'LAST 30 DAYS'),
        const SizedBox(height: 14),
        _HeatMap(
          verdicts: verdicts,
          palette: p,
          tint: _tint(p),
          onTapDay: onTapDay,
        ),
        const SizedBox(height: 34),
        _section(p, "WHAT YOU'VE EARNED"),
        const SizedBox(height: 14),
        _achievements(p, achievements),
        const SizedBox(height: 30),
        _closing(p, closingMessage),
      ],
    );
  }

  Widget _section(AppPalette p, String text) => Text(
    text,
    style: GoogleFonts.poppins(
      color: p.textMuted,
      fontSize: 10.5,
      letterSpacing: 1.6,
      fontWeight: FontWeight.w700,
    ),
  );

  // ══ 1. WHERE YOU STAND ═══════════════════════════════════════════════════

  /// The streak, given the whole first screen.
  ///
  /// A big number alone is a scoreboard. What makes it coaching is the line
  /// underneath: "One more workout to reach 3 days" converts an abstract
  /// figure into a single, obviously-achievable next action — which is the
  /// entire mechanism behind the goal-gradient effect.
  Widget _hero(AppPalette p, StreakHero h) {
    final tint = _tint(p);
    return Semantics(
      label: h.semanticLabel,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 26),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: h.lit
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tint.withValues(alpha: p.isDark ? 0.22 : 0.13),
                    tint.withValues(alpha: p.isDark ? 0.05 : 0.03),
                  ],
                )
              : null,
          color: h.lit ? null : p.surface,
          border: Border.all(
            color: h.lit
                ? tint.withValues(alpha: 0.34)
                : p.border,
          ),
        ),
        child: Column(
          children: [
            if (h.lit)
              Icon(Icons.local_fire_department_rounded, size: 34, color: tint)
            else
              Icon(Icons.trending_up_rounded, size: 30, color: p.textMuted),
            const SizedBox(height: 12),
            Text(
              h.label.toUpperCase(),
              style: GoogleFonts.poppins(
                color: p.textMuted,
                fontSize: 10.5,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Hero(
              tag: isWorkout
                  ? kWorkoutStreakHeroTag
                  : kNutritionStreakHeroTag,
              flightShuttleBuilder: (_, _, _, _, _) => Material(
                color: Colors.transparent,
                child: Text(
                  '${h.streak}',
                  style: AppText.title(size: 48)
                      .copyWith(color: tint, height: 0.9),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: Text(
                  h.value,
                  textAlign: TextAlign.center,
                  style: AppText.title(size: 52).copyWith(
                    color: h.lit ? p.textPrimary : p.textMuted,
                    height: 0.95,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              h.encouragement,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: p.textPrimary,
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (h.nextStep.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                h.nextStep,
                textAlign: TextAlign.center,
                style: AppText.body(size: 13)
                    .copyWith(color: p.textMuted, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ══ 2. THIS WEEK ═════════════════════════════════════════════════════════

  static const List<String> _dayLetters = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// Seven circles, every engine state visually distinct — by SHAPE as well as
  /// colour, so the row survives greyscale and any colour vision.
  Widget _weekCircles(AppPalette p, List<TodayMark> rail) {
    final todayIndex = DateTime.now().weekday - 1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          Semantics(
            label: '${_dayLetters[i]}: ${markLabel(rail[i])}',
            excludeSemantics: true,
            child: Column(
              children: [
                Text(
                  _dayLetters[i],
                  style: GoogleFonts.poppins(
                    color: i == todayIndex ? p.textPrimary : p.textMuted,
                    fontSize: 11,
                    height: 1.2,
                    fontWeight:
                        i == todayIndex ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 9),
                _DayCircle(
                  mark: rail[i],
                  palette: p,
                  tint: _tint(p),
                  isToday: i == todayIndex,
                  size: 34,
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String markLabel(TodayMark m) => switch (m) {
    TodayMark.done => 'completed',
    TodayMark.missed => 'missed',
    TodayMark.rest => 'scheduled rest',
    TodayMark.excused => 'excused by coach',
    TodayMark.paused => 'coaching paused',
    TodayMark.open => 'today, still open',
    TodayMark.future => 'upcoming',
    TodayMark.unknown => 'not scheduled',
  };

  Widget _weekLegend(AppPalette p) => Wrap(
    spacing: 14,
    runSpacing: 8,
    children: [
      _legendItem(p, TodayMark.done, 'Completed'),
      _legendItem(p, TodayMark.rest, 'Rest'),
      _legendItem(p, TodayMark.excused, 'Excused'),
      _legendItem(p, TodayMark.missed, 'Missed'),
      _legendItem(p, TodayMark.open, 'Today'),
      _legendItem(p, TodayMark.future, 'Upcoming'),
    ],
  );

  Widget _legendItem(AppPalette p, TodayMark m, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _DayCircle(
        mark: m,
        palette: p,
        tint: _tint(p),
        isToday: m == TodayMark.open,
        size: 14,
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: GoogleFonts.poppins(
          color: p.textMuted,
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );

  // ══ 4. WHAT YOU'VE EARNED ════════════════════════════════════════════════

  Widget _achievements(AppPalette p, List<Achievement> items) => Column(
    children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(height: 9),
        _achievementTile(p, items[i]),
      ],
    ],
  );

  Widget _achievementTile(AppPalette p, Achievement a) {
    final tint = _tint(p);
    return Semantics(
      label: a.isEmpty
          ? '${a.title}: not yet'
          : '${a.title}: ${a.value}, ${a.basis}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 16, 13),
        decoration: glassCardSoft(p, radius: 15),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (a.isEmpty ? p.textMuted : tint)
                    .withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(a.glyph, style: const TextStyle(fontSize: 17)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title,
                    style: GoogleFonts.poppins(
                      color: p.textPrimary,
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    // The window is ALWAYS stated. A "longest streak" this app
                    // can only see 60 days of is not an all-time record.
                    a.basis,
                    style: AppText.body(size: 10.5)
                        .copyWith(color: p.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              a.value,
              style: AppText.title(size: 21).copyWith(
                color: a.isEmpty ? p.textMuted : p.textPrimary,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══ 5. ONE LAST WORD ═════════════════════════════════════════════════════

  Widget _closing(AppPalette p, String message) {
    if (message.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _tint(p).withValues(alpha: 0.07),
        border: Border.all(color: _tint(p).withValues(alpha: 0.2)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          color: p.textPrimary,
          fontSize: 13.5,
          height: 1.45,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

}
