import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/food_log_controller.dart';
import '../../../controllers/home_controller.dart';
import '../../../controllers/member_controller.dart';
import '../../../controllers/membership_controller.dart';
import '../../../controllers/streak_controller.dart';
import '../../../controllers/training_controller.dart';
import '../../../core/domain/nutrition_targets.dart';
import '../../../core/domain/today_expectation.dart';
import '../../../core/domain/workout_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';
import '../../join/join_coach_screen.dart';
import '../consistency_detail_screen.dart';
import '../membership_screen.dart';
import '../home/daily_metric.dart';
import '../home/nutrition_progress_card.dart';
import '../nutrition/add_food_screen.dart';
import '../nutrition/coach_recommended_meals.dart';
import '../nutrition/food_log_section.dart';
import '../workout_briefing_screen.dart';
import '../workout_summary_screen.dart';
import 'plan_hero_card.dart';
import 'plan_segmented_control.dart';
import 'today_workout_section.dart';

/// MY PLANS — the member's single, trustworthy answer to two questions:
///
///   1. **What has my trainer assigned me?**  → the hero card, per discipline
///   2. **What have I completed today?**      → "Today's workout" / "Today's meals"
///
/// Home answers "what should I do right now". This screen answers those two,
/// and deliberately nothing else — anything that does not serve one of them
/// does not belong here.
///
/// **No new controller, no new listener, no new backend call.** Every value is
/// read from a controller that is already registered and already live:
/// `MemberController`, `TrainingController`, `FoodLogController`,
/// `StreakController`, `HomeController`, `MembershipController`. `Get.find` is
/// preferred over `Get.put` throughout precisely so this screen cannot become a
/// second owner of a stream the dashboard already owns.
///
/// **SINGLE SOURCE OF TRUTH IS STRUCTURAL, NOT A PROMISE.** Three surfaces are
/// the *literal* widgets other screens render, fed by the same controllers:
/// `NutritionProgressCard` + `DailyMetric` (Home's), `FoodLogSection` (the Diet
/// screen's — so edit, swipe-delete, undo and realtime arrive already correct
/// and cannot drift), and `TodayWorkoutSection` (fed by the one
/// `computeSessionStats` engine). Today's workout state comes from
/// `todayWorkoutPresentation`, the SAME decision function Home uses, so the two
/// screens cannot give different answers about a rest day, an excused day or a
/// paused block — which they did before this pass.
///
/// **Fields this screen deliberately does NOT show** — plan difficulty,
/// duration, frequency, start date, plan image, plan badge, plan status —
/// because `getMyTraining` serves none of them, and it serves only ACTIVE
/// assignments so a status chip could only ever have read "Active". See
/// `MY_PLANS_FIELD_INVENTORY.md`.
class MyPlansScreen extends StatefulWidget {
  const MyPlansScreen({super.key});

  @override
  State<MyPlansScreen> createState() => _MyPlansScreenState();
}

class _MyPlansScreenState extends State<MyPlansScreen> {
  PlanTab _tab = PlanTab.workout;

  MemberController get _member => Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  TrainingController get _training => Get.isRegistered<TrainingController>()
      ? Get.find<TrainingController>()
      : Get.put(TrainingController());

  FoodLogController get _log => Get.isRegistered<FoodLogController>()
      ? Get.find<FoodLogController>()
      : Get.put(FoodLogController());

  StreakController get _streak => Get.isRegistered<StreakController>()
      ? Get.find<StreakController>()
      : Get.put(StreakController());

  MembershipController get _membership =>
      Get.isRegistered<MembershipController>()
          ? Get.find<MembershipController>()
          : Get.put(MembershipController());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final member = _member;
    final training = _training;
    final membership = _membership;
    final streak = _streak;

    // This screen lives in the dashboard's IndexedStack, so it stays mounted
    // for the whole session. A member who leaves the app on this tab across
    // midnight would otherwise read yesterday's food log and yesterday's
    // session under a "today" heading. The dashboard re-anchors on RESUME;
    // this covers the phone that was never backgrounded.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _log.ensureFreshDay();
      streak.ensureFreshDay();
      training.ensureFreshDay();
    });

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          final loading = member.isLoading.value ||
              training.isLoading.value ||
              membership.isLoading.value;
          // A REFRESH MUST NOT BLANK THE SCREEN.
          //
          // The plan is now re-pulled on app resume, on entering this tab and
          // on a coach's plan-change push — and every one of those flips
          // `isLoading`, which was rendering the SKELETON straight over content
          // the member already had. A background refresh that greys out a plan
          // you are reading is worse than no refresh at all; it looks like the
          // data was lost.
          //
          // So: the skeleton is for a COLD load only — nothing held yet.
          // Otherwise the content stays put and a slim bar says what is
          // happening, which is the whole difference between "updating" and
          // "broken".
          final hasContent =
              training.workout.value != null || training.diet.value != null;
          final coldLoad = loading && !hasContent;
          final refreshing = loading && hasContent;

          return RefreshIndicator(
            color: p.accent,
            onRefresh: () async {
              await member.claim();
              await training.load();
              await streak.load();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: [
                _header(p),
                const SizedBox(height: 18),
                PlanSegmentedControl(
                  value: _tab,
                  onChanged: (t) => setState(() => _tab = t),
                ),
                // Height-stable: an 18px gap when idle, the same 18px plus the
                // bar when refreshing, so nothing under it jumps.
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: refreshing
                      ? _refreshingBar(p)
                      : const SizedBox(width: double.infinity, height: 18),
                ),
                if (coldLoad)
                  _skeleton(p)
                else if (!member.isLinked.value)
                  _blocker(
                    p,
                    icon: Icons.link_off_rounded,
                    title: 'No coach linked yet',
                    body: 'Once you join a coach, the plans they build for you '
                        'appear here.',
                    actionLabel: 'Find a coach',
                    onAction: () => Get.to(() => const JoinCoachScreen()),
                  )
                else if (!membership.isActive)
                  _blocker(
                    p,
                    icon: Icons.lock_outline_rounded,
                    title: 'Membership inactive',
                    body: 'Renew your membership to see the plans your coach '
                        'assigned.',
                    actionLabel: 'Renew membership',
                    onAction: () => Get.to(() => MembershipScreen()),
                  )
                else
                  // AnimatedSwitcher rather than an IndexedStack: only the
                  // visible tab is built, so switching does not keep the other
                  // discipline's widget tree (and its Obx subscriptions) alive.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.03),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_tab),
                      child: _tab == PlanTab.workout
                          ? _workoutTab(p, member, training, streak)
                          : _dietTab(p, member, training),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────────

  Widget _header(AppPalette p) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Plans',
                    style: AppText.title(size: 24)
                        .copyWith(color: p.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  'Assigned by your coach · logged by you.',
                  style: AppText.body(size: 12).copyWith(color: p.textMuted),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: _tab == PlanTab.workout
                ? 'Workout history'
                : 'Nutrition history',
            container: true,
            child: Material(
              color: p.surface,
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: _openHistory,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: p.border),
                  ),
                  child: Icon(Icons.calendar_today_outlined,
                      color: p.textPrimary, size: 18),
                ),
              ),
            ),
          ),
        ],
      );

  /// The history calendar for the tab the member is looking at.
  ///
  /// This button was DEAD on the original screen (a bare `Container` with no
  /// gesture detector), and after the first rebuild it raised a snackbar
  /// telling the member to go and find the feature on Home. It now opens the
  /// same consistency calendar Home's cards open — the real destination.
  void _openHistory() => Get.to(
        () => ConsistencyDetailScreen(isWorkout: _tab == PlanTab.workout),
      );

  // ── WORKOUT TAB ───────────────────────────────────────────────────────────

  Widget _workoutTab(
    AppPalette p,
    MemberController member,
    TrainingController training,
    StreakController streak,
  ) {
    // A load FAILURE with nothing cached must never read as "your coach hasn't
    // assigned anything": the coach removed nothing, the network did.
    if (training.error.value.isNotEmpty && training.workout.value == null) {
      return _errorCard(p, training);
    }
    final workout = training.workout.value;
    final items = training.workoutItems;

    if (workout == null) {
      return _blocker(
        p,
        icon: Icons.fitness_center_rounded,
        title: 'No workout plan right now',
        body: 'Your coach will assign one soon. Nothing is wrong — plans can '
            'also be paused between blocks.',
      );
    }

    // THE SAME DECISION FUNCTION HOME USES. Before this, My Plans knew only
    // `restDay` and rendered "Start Workout · 3 exercises" on days Home was
    // correctly showing "Today is excused" or "Coaching paused" — two screens
    // reading one served expectation and giving the member opposite answers.
    final presentation = todayWorkoutPresentation(
      expectation: training.workoutExpectation,
      hasPlan: items.isNotEmpty,
      doneToday: streak.workoutToday,
      doneThisWeek: sessionsThisWeek(streak.workoutDays.value, DateTime.now()),
      coachName: _coachName(member, training),
    );

    final stats = streak.todayWorkoutStats;
    final exercises = streak.todayExercises;
    final finished = stats != null && stats.isFullyResolved;
    final started = stats != null && stats.completedSets > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PlanHeroCard(
          tab: PlanTab.workout,
          planName: (workout['name'] ?? 'Workout Plan').toString(),
          coachName: _coachName(member, training),
          orgName: member.gymName,
          todayLine: _workoutTodayLine(presentation, training, items, stats),
          facts: _workoutFacts(training, items),
          ctaLabel: _workoutCtaLabel(presentation, stats),
          ctaIcon: finished
              ? Icons.fact_check_outlined
              : started
                  ? Icons.play_arrow_rounded
                  : Icons.play_arrow_rounded,
          // A completed session is a statement, not a button — the card stops
          // inviting a tap once there is nothing left to do.
          completedToday: stats != null && stats.isComplete,
          onCta: _workoutCta(presentation, training, stats, streak),
        ),
        // The coach's word for today, verbatim, when the prescription carries
        // one. Never a generated line.
        if (presentation.body.isNotEmpty &&
            !presentation.showContent) ...[
          const SizedBox(height: 12),
          _quietCard(p, presentation.body),
        ],
        // THE COACH'S PLAN-LEVEL NOTE, which `buildWorkout` has served since
        // Workout Plans V1 and which NOTHING in this app rendered.
        //
        // The backend's own comment calls it "the one field a coach wrote that
        // disappeared entirely between the two apps" — it was restored on the
        // wire and then dropped again on this tab, while the Diet tab showed
        // its equivalent. Asymmetry, not a decision.
        if (_workoutNote(training).isNotEmpty) ...[
          const SizedBox(height: 12),
          _coachNote(p, _workoutNote(training)),
        ],
        if (presentation.disclosure.isNotEmpty) ...[
          const SizedBox(height: 10),
          _disclosure(p, presentation.disclosure),
        ],
        const SizedBox(height: 18),
        // WHAT THE MEMBER ACTUALLY DID — the half of this screen's job that did
        // not exist before. It REPLACES the flat prescription list once a
        // session exists, because it already states every prescribed set
        // alongside the result: showing both would be the same facts twice.
        if (exercises != null && exercises.isNotEmpty && stats != null) ...[
          _sectionTitle(p, "Today's workout"),
          const SizedBox(height: 10),
          TodayWorkoutSection(
            exercises: exercises,
            stats: stats,
            durationSeconds: streak.todayDurationSeconds,
            nextUp: streak.todayNextUp,
            // The library facts the coach curated — muscle group, equipment —
            // live on the SERVED item, not on the session log. Passing them
            // keeps them visible once the session view replaces the plain
            // prescription list.
            items: items,
          ),
        ] else ...[
          _sectionTitle(p, "Today's exercises"),
          const SizedBox(height: 10),
          if (items.isEmpty)
            _quietCard(p, _emptyItemsReason(training))
          else
            for (final e in items) _exerciseRow(p, e),
        ],
      ],
    );
  }

  /// Why there are no exercises today, distinguishing the three real causes.
  ///
  /// `dayPlanUnavailable` is served by `buildWorkout` when the coach's mapped
  /// day-plan was deleted, and until now NOTHING in this app read it — the
  /// member saw "this plan has no exercises yet" for a plan that had plenty,
  /// on a day whose plan had gone missing.
  String _emptyItemsReason(TrainingController training) {
    if (training.workout.value?['dayPlanUnavailable'] == true) {
      return "Today's session isn't available right now — your coach is "
          'updating this day of the plan.';
    }
    if (training.isWeeklyRestDay) {
      return 'Nothing scheduled today. Your next session is already planned.';
    }
    return 'This plan has no exercises yet.';
  }

  /// One line about TODAY. Prefers what the member has DONE over what is
  /// scheduled — once they have started, "3 of 9 sets done" is the fact that
  /// matters, not "3 exercises today".
  String? _workoutTodayLine(
    TodayWorkoutPresentation presentation,
    TrainingController training,
    List<Map<String, dynamic>> items,
    SessionStats? stats,
  ) {
    if (stats != null && stats.totalSets > 0) {
      if (stats.isComplete) return 'Workout complete · every set done';
      if (stats.isFullyResolved) {
        return '${stats.completedSets} of ${stats.totalSets} sets done · '
            '${stats.skippedSets} skipped';
      }
      if (stats.completedSets > 0) {
        return '${stats.completedSets} of ${stats.totalSets} sets done';
      }
    }
    if (presentation.title.isNotEmpty) return presentation.title;
    if (training.isWeeklyRestDay) {
      final next = training.nextTrainingDay;
      final name = (next?['planName'] ?? '').toString();
      return name.isNotEmpty
          ? 'Rest day · next: $name on ${next!['day']}'
          : 'Rest day — recovery is part of the plan';
    }
    if (items.isEmpty) return null;
    return '${items.length} '
        '${items.length == 1 ? 'exercise' : 'exercises'} today';
  }

  String _workoutCtaLabel(
    TodayWorkoutPresentation presentation,
    SessionStats? stats,
  ) {
    if (stats != null && stats.isComplete) return 'Workout complete';
    if (stats != null && stats.isFullyResolved) return 'Review Workout';
    if (stats != null && stats.completedSets > 0) return 'Resume Workout';
    if (!presentation.showContent) {
      // Rest / excused / paused / dormant. "Train anyway" is an OFFER; the
      // states that offer nothing get a disabled, honest label.
      return presentation.trainAnyway ? 'Train anyway' : 'Nothing scheduled';
    }
    return presentation.cta.isEmpty ? 'Start Workout' : presentation.cta;
  }

  /// The real destination, at last.
  ///
  /// The previous build raised `Get.snackbar('Start Workout', 'Open it from
  /// Home → Start Workout.')` — the primary action of this screen's primary tab
  /// was a sign pointing at another screen. Verified dead on device before this
  /// change.
  VoidCallback? _workoutCta(
    TodayWorkoutPresentation presentation,
    TrainingController training,
    SessionStats? stats,
    StreakController streak,
  ) {
    if (stats != null && stats.isComplete) return null; // a statement, not a CTA
    if (stats != null && stats.isFullyResolved) {
      return () => Get.to(() => WorkoutSummaryScreen(
            sessionId: streak.todaySessionId,
            planName: (training.workout.value?['name'] ?? 'Workout').toString(),
            stats: stats,
            durationSeconds: streak.todayDurationSeconds,
          ));
    }
    // Resume, start, or "train anyway" all land on the briefing — the same
    // entry point Home uses, so there is one way into a session.
    if (stats != null && stats.completedSets > 0) {
      return () => Get.to(() => const WorkoutBriefingScreen());
    }
    if (!presentation.showContent && !presentation.trainAnyway) {
      return null;
    }
    return () => Get.to(() => const WorkoutBriefingScreen());
  }

  /// BACKED FACTS ONLY. Every one of these is read from the served payload; a
  /// fact whose source is absent is simply not added, so the row never appears
  /// rather than appearing empty or invented.
  List<PlanFact> _workoutFacts(
    TrainingController training,
    List<Map<String, dynamic>> items,
  ) {
    final facts = <PlanFact>[];
    if (items.isNotEmpty) {
      facts.add((
        icon: Icons.format_list_numbered_rounded,
        label: 'Exercises',
        value: '${items.length}',
      ));
      final sets = items.fold<int>(
        0,
        (a, e) => a + ((e['sets'] is num) ? (e['sets'] as num).toInt() : 0),
      );
      if (sets > 0) {
        facts.add((
          icon: Icons.repeat_rounded,
          label: 'Sets',
          value: '$sets',
        ));
      }
      // Distinct muscle groups actually present on the served items.
      final groups = <String>{
        for (final e in items)
          if ((e['muscleGroup'] ?? '').toString().trim().isNotEmpty)
            e['muscleGroup'].toString().trim(),
      };
      if (groups.isNotEmpty) {
        facts.add((
          icon: Icons.accessibility_new_rounded,
          label: 'Focus',
          value: groups.take(2).join(', '),
        ));
      }
    }
    // Only real when the coach authored a weekly schedule. Absent for every
    // single-plan member, which is why it is conditional rather than a row
    // that reads "—".
    final weekly = training.weeklyOverview;
    final days = (weekly?['days'] as List?)?.length ?? 0;
    if (days > 0) {
      facts.add((
        icon: Icons.calendar_view_week_rounded,
        label: 'Days/week',
        value: '$days',
      ));
    }
    return facts;
  }

  Widget _exerciseRow(AppPalette p, Map<String, dynamic> e) {
    final name = (e['name'] ?? 'Exercise').toString();
    final muscle = (e['muscleGroup'] ?? '').toString().trim();
    final equipment = (e['equipment'] ?? '').toString().trim();
    final sets = e['sets'] is num ? (e['sets'] as num).toInt() : 0;
    final reps = (e['reps'] ?? '').toString().trim();
    final thumb = (e['thumbnailUrl'] ?? '').toString().trim();
    final meta = [
      if (sets > 0) '$sets ${sets == 1 ? 'set' : 'sets'}',
      if (reps.isNotEmpty) '$reps reps',
      if (equipment.isNotEmpty) equipment,
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: glassCard(p, radius: 14),
        child: Row(
          children: [
            // A real thumbnail when the coach set one; otherwise an ICON, not
            // a grey rectangle pretending to be a photo that failed to load.
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 48,
                height: 48,
                child: thumb.isEmpty
                    ? Container(
                        color: p.isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : const Color(0xFFF1F3F7),
                        child: Icon(Icons.fitness_center_rounded,
                            size: 20, color: p.textMuted),
                      )
                    : Image.network(
                        thumb,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: p.isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : const Color(0xFFF1F3F7),
                          child: Icon(Icons.fitness_center_rounded,
                              size: 20, color: p.textMuted),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.cardTitle(size: 14)
                        .copyWith(color: p.textPrimary),
                  ),
                  if (muscle.isNotEmpty || meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      [if (muscle.isNotEmpty) muscle, if (meta.isNotEmpty) meta]
                          .join('  ·  '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppText.body(size: 11.5).copyWith(color: p.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── DIET TAB ──────────────────────────────────────────────────────────────

  Widget _dietTab(
    AppPalette p,
    MemberController member,
    TrainingController training,
  ) {
    final home = Get.isRegistered<HomeController>()
        ? Get.find<HomeController>()
        : null;
    final log = _log;

    NutritionTarget target(String key, String item) => resolveNutritionTarget(
          servedTargets: training.servedTargets.value,
          diet: training.diet.value,
          targetKey: key,
          itemKey: item,
          items: training.dietItems,
        );

    final calories = target('targetCalories', 'calories');
    final diet = training.diet.value;
    // SYMMETRY WITH THE WORKOUT TAB, which this branch was missing: a failed
    // load rendered as "No diet plan right now — your coach will assign one",
    // telling the member their coach had done nothing when the truth was a
    // network error. The Diet screen already drew this distinction; this tab
    // did not.
    final loadFailed = training.error.value.isNotEmpty && diet == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loadFailed)
          _errorCard(p, training)
        else if (diet == null)
          _blocker(
            p,
            icon: Icons.restaurant_rounded,
            title: 'No diet plan right now',
            body: 'You can still log everything you eat — the log below works '
                'without a plan.',
          )
        else
          PlanHeroCard(
            tab: PlanTab.diet,
            planName: (diet['name'] ?? 'Diet Plan').toString(),
            coachName: _coachName(member, training),
            orgName: member.gymName,
            todayLine: log.entryCount == 0
                ? 'Nothing logged yet today'
                : '${log.entryCount} '
                    '${log.entryCount == 1 ? 'item' : 'items'} logged '
                    '· ${log.loggedCalories.round()} kcal',
            facts: _dietFacts(training),
            // ADD FOOD, not "Open Diet".
            //
            // The whole log now lives on this tab — totals, meals, edit, delete,
            // undo — so a button labelled "Open Diet" led to a screen showing
            // the member the same thing again. Logging a food is the one action
            // this tab cannot perform inline, so it is the one the CTA does.
            ctaLabel: 'Add Food',
            ctaIcon: Icons.add_rounded,
            onCta: () => Get.to(() => const AddFoodScreen()),
          ),
        // WHAT THE COACH TOLD THE MEMBER TO EAT.
        //
        // This tab's whole first job is "what has my trainer assigned me?", and
        // it used to answer that with two number chips — `Plan items 2 ·
        // Meals 1` — while the actual prescribed foods lived on a screen the
        // member had to go and find. The literal `CoachRecommendedMeals` the
        // Diet screen renders, so the coach's words cannot be phrased two ways.
        if (training.dietItems.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionTitle(p, "Your coach's plan"),
          const SizedBox(height: 10),
          CoachRecommendedMeals(
            items: training.dietItems,
            // The hero card already names the plan; only the note is added
            // here, and only when the coach wrote one.
            note: _dietNote(training),
            // The tab's own green, not the brand red — see the parameter's doc.
            accent: PlanSegmentedControl.fillFor(PlanTab.diet),
            // WHAT THE MEMBER STILL NEEDS. The prescribed foods they have
            // already logged today are marked, so the coach's plan stops being
            // a static reference and starts answering the member's question.
            // A factual `foodId` match — never an amount-based adherence claim.
            loggedFoodIds: {
              for (final e in log.liveEntries)
                if ((e.foodId ?? '').isNotEmpty) e.foodId!,
            },
          ),
        ] else if (_dietNote(training).isNotEmpty) ...[
          const SizedBox(height: 12),
          _quietCard(p, _dietNote(training)),
        ],
        const SizedBox(height: 18),
        _sectionTitle(p, "Today's nutrition"),
        const SizedBox(height: 10),
        // THE SAME WIDGET HOME RENDERS, fed by the SAME controller and the SAME
        // canonical target rule. Not a copy — the literal `NutritionProgressCard`.
        // This is what makes "exactly the same values as Home" structural
        // rather than a promise.
        _nutritionCard(p, home, log, calories, target),
        const SizedBox(height: 22),
        _sectionTitle(p, "Today's meals"),
        const SizedBox(height: 10),
        // THE LITERAL DIET-SCREEN SECTION. Reusing the widget rather than
        // rebuilding a meal list here is what gives this tab correct swipe-to-
        // delete, undo, the edit sheet, the queued-write indicator, the honest
        // error state and live updates on day one — and what makes it
        // impossible for the two surfaces to drift apart later.
        // `showTotals: false` — the nutrition card above already states every
        // total, against the coach's targets. Repeating them here was a
        // duplication this rebuild introduced and caught on device.
        FoodLogSection(controller: log, showTotals: false),
      ],
    );
  }

  String _workoutNote(TrainingController training) =>
      (training.workout.value?['description'] ?? '').toString().trim();

  /// The coach speaking, marked as a quotation so it never reads as app copy.
  Widget _coachNote(AppPalette p, String note) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: glassCard(p, radius: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.format_quote_rounded, size: 15, color: p.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                note,
                style:
                    AppText.body(size: 12.5).copyWith(color: p.textSecondary),
              ),
            ),
          ],
        ),
      );

  String _dietNote(TrainingController training) =>
      (training.diet.value?['description'] ?? '').toString().trim();

  /// The plan's own facts.
  ///
  /// The five macro-target chips that used to sit here were DELETED: the
  /// nutrition card immediately below states every one of those targets
  /// *alongside what the member has actually eaten*, so the chips restated five
  /// numbers with strictly less information, a few hundred pixels above them.
  /// That is the duplication this pass exists to remove.
  List<PlanFact> _dietFacts(TrainingController training) {
    final facts = <PlanFact>[];
    final items = training.dietItems.length;
    if (items > 0) {
      facts.add((
        icon: Icons.list_alt_rounded,
        label: 'Plan items',
        value: '$items',
      ));
      final meals = <String>{
        for (final i in training.dietItems)
          if ((i['meal'] ?? '').toString().trim().isNotEmpty)
            i['meal'].toString().trim().toLowerCase(),
      };
      if (meals.isNotEmpty) {
        facts.add((
          icon: Icons.restaurant_menu_rounded,
          label: 'Meals',
          value: '${meals.length}',
        ));
      }
    }
    return facts;
  }

  Widget _nutritionCard(
    AppPalette p,
    HomeController? home,
    FoodLogController log,
    NutritionTarget calories,
    NutritionTarget Function(String, String) target,
  ) {
    String grams(double v) =>
        v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

    // Null when nothing is logged, so "no food recorded" never renders as
    // "ate zero" — identical to Home's rule, deliberately.
    double? logged(double v) => log.entryCount == 0 ? null : v;

    DailyMetric macro(
      String label,
      String key,
      String item,
      double current,
    ) {
      final t = target(key, item);
      return DailyMetric(
        label: label,
        unit: 'g',
        format: grams,
        current: logged(current),
        target: t.isCoachGoal ? t.value : null,
      );
    }

    return NutritionProgressCard(
      calories: DailyMetric(
        label: 'Calories',
        unit: 'kcal',
        format: (v) => v.round().toString(),
        current: logged(log.loggedCalories),
        target: calories.isCoachGoal ? calories.value : null,
      ),
      nutrients: [
        macro('Protein', 'targetProtein', 'protein', log.loggedProtein),
        macro('Fat', 'targetFat', 'fat', log.loggedFat),
        macro('Carbs', 'targetCarbs', 'carbs', log.loggedCarbs),
        macro('Fiber', 'targetFiber', 'fiber', log.loggedFiber),
      ],
      loading: log.isLoading.value,
      subtitle: nutritionCardSubtitle(
        loadError: log.loadError.value,
        hasAnyTarget: calories.isCoachGoal,
        entryCount: log.entryCount,
      ),
      // NO "Log Food" pill and NO tap-through here. On Home that pill is the
      // only route to logging and earns its place; on THIS tab the hero card's
      // "Add Food" CTA sits directly above it and the full log sits directly
      // below it, so a third control to the same place is the one the member
      // has to think about.
    );
  }

  // ── SHARED PIECES ─────────────────────────────────────────────────────────

  String _coachName(MemberController member, TrainingController training) {
    final live = (training.coach.value?['name'] ?? '').toString().trim();
    return live.isNotEmpty ? live : member.trainerName;
  }

  /// "Checking for updates" — quiet, non-blocking, and honest about the fact
  /// that this screen talks to a backend.
  Widget _refreshingBar(AppPalette p) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                valueColor: AlwaysStoppedAnimation(p.textMuted),
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'Checking for updates from your coach',
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
          ],
        ),
      );

  Widget _sectionTitle(AppPalette p, String t) => Text(
        t.toUpperCase(),
        style: AppText.label(size: 11.5)
            .copyWith(color: p.textMuted, letterSpacing: 0.9),
      );

  Widget _disclosure(AppPalette p, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 13, color: p.textMuted),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted)),
          ),
        ],
      );

  Widget _quietCard(AppPalette p, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: glassCard(p, radius: 14),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
        ),
      );

  Widget _blocker(
    AppPalette p, {
    required IconData icon,
    required String title,
    required String body,
    // A blocker that names a remedy must OFFER it.
    //
    // "Renew your membership to see the plans your coach assigned" with no
    // renew button, and "once you join a coach…" with no way to join, are the
    // two dead ends left on this screen: the member is told exactly what to do
    // and given nothing to do it with.
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
        decoration: glassCard(p, radius: 18),
        child: Column(
          children: [
            Icon(icon, size: 38, color: p.textMuted),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: AppText.cardTitle(size: 15.5)
                    .copyWith(color: p.textPrimary)),
            const SizedBox(height: 7),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: onAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PlanSegmentedControl.fillFor(_tab),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: Text(actionLabel,
                      style: AppText.label(size: 14)
                          .copyWith(color: Colors.white)),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _errorCard(AppPalette p, TrainingController training) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
        decoration: glassCard(p, radius: 18),
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded, size: 34, color: p.textMuted),
            const SizedBox(height: 12),
            Text("Couldn't load your plans",
                style: AppText.cardTitle(size: 15)
                    .copyWith(color: p.textPrimary)),
            const SizedBox(height: 6),
            Text(
              'This is a connection problem — your plans are safe.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: training.load,
              style: OutlinedButton.styleFrom(foregroundColor: p.accent),
              child: const Text('Try again'),
            ),
          ],
        ),
      );

  Widget _skeleton(AppPalette p) => Column(
        children: [
          for (final h in [220.0, 90.0, 90.0, 200.0])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                height: h,
                decoration: BoxDecoration(
                  color: p.isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFF1F3F7),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
        ],
      );
}
