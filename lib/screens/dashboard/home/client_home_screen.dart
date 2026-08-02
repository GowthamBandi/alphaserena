import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../controllers/home_controller.dart';
import '../../../controllers/food_log_controller.dart';
import '../../../controllers/performance_controller.dart';
import '../../../controllers/check_in_controller.dart';
import '../../../controllers/lifestyle_controller.dart';
import '../../../controllers/streak_controller.dart';
import '../../../core/constants/quotes.dart';
import '../../../core/domain/consistency_pair.dart';
import '../../../core/domain/home_workout_card.dart';
import '../../../core/domain/today_expectation.dart';
import '../../../core/domain/workout_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../join/join_coach_screen.dart';
import '../../onboarding/identity_setup_screen.dart';
import '../../onboarding/onboarding_flow_screen.dart';
import '../../../core/models/app_notification.dart';
import '../../../core/services/notification_center_service.dart';
import '../check_in_screen.dart';
import '../notification_visuals.dart';
import 'consistency_cards_pair.dart';
import 'home_header.dart';
import 'home_workout_card_widget.dart';
import '../consistency_detail_screen.dart';
import '../nutrition/diet_screen.dart';
import 'daily_progress_card.dart';
import '../lifestyle_history_screen.dart';
import '../lifestyle_today_screen.dart';
import '../membership_screen.dart';
import '../notification_center_screen.dart';
import '../workout_briefing_screen.dart';
import '../workout_summary_screen.dart';

/// Home Dashboard — compact organization header (identity · coach · comms),
/// then the Consistency hero, today's session, nutrition, lifestyle,
/// check-in and coach updates.
class ClientHomeScreen extends StatelessWidget {
  const ClientHomeScreen({super.key});

  /// PRESCRIPTION ENGINE (Phase 4): the performance derivations the streak
  /// cards read. Resolved lazily — TrainingController and StreakController
  /// are both registered by the time any card builds.
  PerformanceController get _perf =>
      Get.isRegistered<PerformanceController>()
          ? Get.find<PerformanceController>()
          : Get.put(PerformanceController());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final h = Get.isRegistered<HomeController>()
        ? Get.find<HomeController>()
        : Get.put(HomeController());
    final checkIn = Get.isRegistered<CheckInController>()
        ? Get.find<CheckInController>()
        : Get.put(CheckInController());
    // Safe to create eagerly: LifestyleController rebinds on `member.isLinked`
    // and is deleted in the signOut teardown, like the other member controllers.
    final lifestyle = Get.isRegistered<LifestyleController>()
        ? Get.find<LifestyleController>()
        : Get.put(LifestyleController());
    final streaks = Get.isRegistered<StreakController>()
        ? Get.find<StreakController>()
        : Get.put(StreakController());

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          if (h.isLoading) {
            return _skeletonLoader(p);
          }

          final linked = h.isLinked;
          final active = h.membershipController.isActive;
          final stage = h.stage;

          return RefreshIndicator(
            onRefresh: h.refreshAll,
            color: p.accent,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              children: [
                // One compact header: org identity + coach + comms (linked)
                // or the AlphaSerena brand row (not linked yet).
                if (linked) HomeHeader(controller: h) else const BrandHeader(),
                const SizedBox(height: 16),

                // Expiry banner if expiring in <= 7 days
                if (linked && active && h.showExpiryBanner) _expiryBanner(h, p),

                if (!linked) ...[_unlinkedCard(p), const SizedBox(height: 18)],

                // If not linked or not active, display blockers and skip the private content
                if (!linked) ...[
                  const SizedBox(height: 12),
                  // Render a motivational quote since we don't have plans to show
                  _quote(p),
                ] else if (!active) ...[
                  _inactiveMembershipCard(h, p),
                  const SizedBox(height: 18),
                  _quote(p),
                ] else if (h.trainingController.error.value.isNotEmpty &&
                    !h.hasPlan) ...[
                  // A load FAILURE must not read as a lifecycle stage ("coach is
                  // preparing your plan") — show a distinct error + Retry.
                  _trainingErrorCard(h, p),
                  const SizedBox(height: 18),
                  _quote(p),
                ] else if (stage != ClientStage.ready) ...[
                  // Active member, but the coaching lifecycle isn't ready yet —
                  // guide them through onboarding → coach → plan instead of
                  // showing empty/placeholder plan content.
                  _gettingStartedCard(h, stage, p),
                  const SizedBox(height: 18),
                  _quote(p),
                ] else ...[
                  // HOME REFINEMENT hierarchy — MOTIVATE → GUIDE → LOG.
                  //
                  //   MOTIVATE  the Consistency hero, directly under the coach
                  //             header. The first thing a member should feel
                  //             is that they are someone who trains. A streak,
                  //             their own week at a glance, and one forward
                  //             sentence — before a single task is mentioned.
                  //   GUIDE     today's session, as one premium card that owns
                  //             the ENTIRE workout question: what today is
                  //             (including rest / excused / paused), what it
                  //             contains, how far in they are, and the exact
                  //             set to resume at.
                  //   LOG       nutrition → lifestyle → check-in. Ordered by
                  //             action frequency: food is logged 3–6× a day,
                  //             lifestyle 1–3×, the check-in weekly.
                  //
                  // REMOVED — the "Today's Plan" hero. It restated, as a list
                  // of rows, what the four sections below already say in full:
                  // workout status, nutrition progress, lifestyle targets and
                  // the check-in. One fact, two renderings, is the class of
                  // contradiction this screen exists to prevent — and the
                  // duplicate cost the member a full card of vertical space
                  // before they reached anything actionable. Every state it
                  // owned has been re-homed to the section that owns the fact:
                  // workout day-states → the session card; a DUE check-in →
                  // its own card (whose suppression is lifted below).
                  //
                  // ALSO REMOVED — the standalone greeting row (a line that
                  // said nothing the header doesn't) and the three-row
                  // exercise preview (the briefing is one tap away and shows
                  // the full list; the preview was a second, shorter copy).
                  if (h.trainingController.error.value.isNotEmpty &&
                      h.hasPlan) ...[
                    // A stale plan shown silently is a quiet lie — say it.
                    _staleSyncBanner(h, p),
                    const SizedBox(height: 12),
                  ],
                  _consistencyCards(h, streaks, p),
                  const SizedBox(height: 18),
                  _workoutCard(h, streaks, p),
                  const SizedBox(height: 18),
                  _nutritionProgress(h, p),
                  const SizedBox(height: 18),
                  _lifestyleProgress(lifestyle, p),
                  const SizedBox(height: 18),
                  ..._checkInWidgets(checkIn, p),
                  const _CoachUpdatesSection(),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── HOME REFINEMENT: motivate, then guide ───────────────────────────────

  /// CONSISTENCY — two cards, two tracks, built independently.
  ///
  /// Each card is fed by the Prescription Engine for ITS OWN track, so one can
  /// be a prescribed rest day while the other is mid-progress, and one can be
  /// unreadable while the other is live. Nothing is shared but the rules.
  Widget _consistencyCards(
    HomeController h,
    StreakController s,
    AppPalette p,
  ) {
    final perf = _perf;
    final loading = s.isLoading.value;
    final now = DateTime.now();

    final workout = buildConsistencyCard(
      track: ConsistencyTrack.workout,
      loading: loading,
      // The ONE input that outranks everything: a day-key set that could not
      // be read must never become a streak of zero.
      logsAvailable: perf.workoutLogsAvailable,
      history: perf.workoutHistory,
      logged: perf.workoutDays,
      week: perf.weekOf(isWorkout: true),
      // WEEKS-ON-PLAN wherever a schedule exists: a member training 4x/week
      // could never push a day-streak past 2, so a day count punished the
      // very compliance it claimed to measure.
      streak: perf.workoutHistory.hasPrescription
          ? perf.weeklyStreakOf(isWorkout: true)
          : (s.workoutStreak ?? 0),
      weekUnit: perf.workoutHistory.hasPrescription,
      today: now,
    );

    final nutrition = buildConsistencyCard(
      track: ConsistencyTrack.nutrition,
      loading: loading,
      logsAvailable: perf.dietLogsAvailable,
      history: perf.dietHistory,
      logged: perf.dietDays,
      week: perf.weekOf(isWorkout: false),
      // Eating is genuinely daily, so the diet streak stays in DAYS even with
      // a prescription — weeks-on-plan is the workout's unit, not this one.
      streak: perf.dietHistory.hasPrescription
          ? perf.dailyStreakOf(isWorkout: false)
          : (s.dietStreak ?? 0),
      weekUnit: false,
      today: now,
    );

    bool inert(ConsistencyCard c) =>
        c.state == ConsistencyCardState.loading ||
        c.state == ConsistencyCardState.unavailable;

    return ConsistencyCardsPair(
      workout: workout,
      nutrition: nutrition,
      // Offered only once there is something to open; an unavailable card
      // stays inert rather than promising a page that would be just as empty.
      onWorkoutTap: inert(workout)
          ? null
          : () => Get.to(() => const ConsistencyDetailScreen(isWorkout: true)),
      onNutritionTap: inert(nutrition)
          ? null
          : () => Get.to(() => const ConsistencyDetailScreen(isWorkout: false)),
    );
  }

  /// TODAY'S WORKOUT — the single owner of the workout question on Home.
  Widget _workoutCard(HomeController h, StreakController s, AppPalette p) {
    final items = h.trainingController.workoutItems;
    final exercises = exercisesFromServedItems(items);
    final stats = s.todayWorkoutStats;

    final card = buildHomeWorkoutCard(
      loading: h.trainingController.isLoading.value,
      loadFailed: h.trainingController.error.value.isNotEmpty,
      hasCachedPlan: h.hasPlan,
      presentation: _workoutPresentation(h, s),
      planName: h.workoutName,
      coachLabel: h.hasCoachName ? h.coachName : 'Your coach',
      // The coach's word for TODAY, verbatim - the prescription note the
      // server resolved. '' when they wrote none; never a generated line.
      coachNote: h.trainingController.workoutExpectation?.note ?? '',
      facts: workoutFacts(
        exerciseCount: items.length,
        // The ONE estimate on the card, and it always wears its "~".
        estimatedMinutes: estimatedMinutes(exercises),
        difficulty:
            distinctLabels(items.map((e) => (e['difficulty'] ?? '').toString())),
        equipment:
            distinctLabels(items.map((e) => (e['equipment'] ?? '').toString())),
      ),
      todayStats: stats,
      nextUp: s.todayNextUp,
      durationSeconds: s.todayDurationSeconds,
    );

    void openSession() => Get.to(() => const WorkoutBriefingScreen());

    // A finished session reviews rather than restarts: the summary is the
    // same screen the member saw on finishing, rebuilt from the SAME stats.
    void review() {
      if (stats == null) return;
      Get.to(() => WorkoutSummaryScreen(
            sessionId: s.todaySessionId,
            planName: h.workoutName,
            stats: stats,
            durationSeconds: s.todayDurationSeconds,
          ));
    }

    return HomeWorkoutCardWidget(
      card: card,
      onPrimary: switch (card.mode) {
        WorkoutCardMode.unavailable => h.trainingController.load,
        WorkoutCardMode.completed ||
        WorkoutCardMode.closed =>
          stats == null ? null : review,
        _ => card.cta.isEmpty ? null : openSession,
      },
      // 'Edit Workout Log' reopens the session itself, which is where a set is
      // corrected; 'Train anyway' opens the briefing.
      onSecondary: card.secondaryCta.isEmpty ? null : openSession,
    );
  }


  /// Shown when the last sync failed but a previously-loaded plan is still on
  /// screen. Rendering stale content silently was a quiet lie; one calm line
  /// fixes it without an alarm.
  Widget _staleSyncBanner(HomeController h, AppPalette p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: p.surfaceAlt.withValues(alpha: 0.5),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 14, color: p.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline — showing your last synced plan.',
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
          ),
          TextButton(
            onPressed: h.trainingController.load,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              'Retry',
              style: AppText.label(size: 12).copyWith(color: p.accent),
            ),
          ),
        ],
      ),
    );
  }

  /// The Phase-3 presentation for today's workout — computed once per build
  /// pass and shared by the hero and the content section, so the two can
  /// never tell different stories.
  TodayWorkoutPresentation _workoutPresentation(
    HomeController h,
    StreakController s,
  ) => todayWorkoutPresentation(
    expectation: h.trainingController.workoutExpectation,
    hasPlan: h.workoutPreviewItems.isNotEmpty,
    doneToday: s.workoutToday,
    doneThisWeek: sessionsThisWeek(s.workoutDays.value, DateTime.now()),
    coachName: _coachLabel(),
  );


  Widget _trainingErrorCard(HomeController h, AppPalette p) {
    return Container(
      decoration: glassCard(p),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, color: p.accent, size: 34),
          const SizedBox(height: 10),
          Text(
            "Couldn't load your plan",
            style: AppText.cardTitle(size: 15).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Check your connection and try again.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => h.trainingController.load(),
              style: ElevatedButton.styleFrom(backgroundColor: p.accent),
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
              label: Text(
                'Retry',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Weekly check-in — cadence-driven, never a permanent Home fixture:
  /// • open submission awaiting review → "waiting for coach review" state
  /// • due (repository `nextCheckInAt` reached) → prominent warning card
  /// • scheduled but not due → HIDDEN (reappears on the coach's cadence)
  /// • no cadence configured → slim invite (the only entry to free-form
  ///   check-ins, which the backend explicitly supports)
  /// Returns [] or [card, gap] so the layout has no orphan spacing.
  List<Widget> _checkInWidgets(CheckInController c, AppPalette p) {
    const amber = Color(0xFFF59E0B);
    const green = Color(0xFF2EBD59);
    final open = c.open.value;

    if (open != null) {
      return [
        _tappableCard(
          p,
          onTap: () => Get.to(() => const CheckInScreen()),
          semanticLabel:
              'Weekly check-in submitted, waiting for review. Tap to edit',
          child: Row(
            children: [
              const Icon(Icons.hourglass_top_rounded, color: green),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weekly check-in',
                      style: AppText.cardTitle(
                        size: 14,
                      ).copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Waiting for ${_coachLabel()} to review — tap to edit',
                      style: AppText.body(
                        size: 12,
                      ).copyWith(color: p.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusChip('Submitted ✓', green),
            ],
          ),
        ),
        const SizedBox(height: 18),
      ];
    }

    final due = c.isDue;
    final scheduled = c.nextCheckInAt != null;
    if (scheduled && !due) return const []; // reappears when the date arrives
    // RE-HOMED (Home Refinement): a DUE check-in used to be suppressed here
    // because the Today's Plan hero carried it as an agenda row. Removing
    // that hero would have made a due check-in silently INVISIBLE — the
    // member would simply never be asked. The card below owns the state
    // again, in amber, exactly as it did before the hero existed.

    return [
      _tappableCard(
        p,
        onTap: () => Get.to(() => const CheckInScreen()),
        semanticLabel: due
            ? 'Weekly check-in due today. Tap to start'
            : 'Weekly check-in. Tap to start',
        decoration: due
            ? glassCard(p).copyWith(
                border: Border.all(
                  color: amber.withValues(alpha: 0.55),
                  width: 1.2,
                ),
              )
            : glassCard(p),
        child: Row(
          children: [
            Icon(
              Icons.assignment_turned_in_outlined,
              color: due ? amber : p.accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Weekly check-in',
                    style: AppText.cardTitle(
                      size: 14,
                    ).copyWith(color: p.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    due
                        ? 'Due now — tell your coach how the week went'
                        : 'Rate your week, weight & notes for your coach',
                    style: AppText.body(
                      size: 12,
                    ).copyWith(color: due ? amber : p.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            due
                ? _statusChip('Due today', amber)
                : Icon(Icons.chevron_right, color: p.textMuted),
          ],
        ),
      ),
      const SizedBox(height: 18),
    ];
  }

  /// The coach's short label for inline copy ("your coach" when unnamed).
  String _coachLabel() {
    final h = Get.find<HomeController>();
    return h.hasCoachName ? h.coachName : 'your coach';
  }

  /// Live lifestyle summary for TODAY — real logged values only (repository
  /// data via [LifestyleController]); an honest "nothing logged yet" line
  /// otherwise. Tap always opens the full logger.
  // ── HOME DASHBOARD: TWO PROGRESS SECTIONS ───────────────────────────────
  //
  // Home is a DASHBOARD, not a logger. Each section answers one question —
  // "where am I today against what my coach set" — and every row carries the
  // same four facts: current, target, progress, status.
  //
  // Neither section uses adherence vocabulary. "Eaten", "partial" and
  // "skipped" describe compliance with a prescribed LIST; they cannot express
  // how much water someone drank, and they are not how nutrition is measured
  // any more. The old lifestyle card was a single line of run-together text
  // ("Water 8/12 · 9.2k steps · Sleep 7h") with no target for steps or sleep
  // and no progress at all; the old nutrition card was a calorie ring whose
  // centre read "kcal left" beside four macro tiles in a different visual
  // language. One shape now serves both.

  /// LIFESTYLE PROGRESS — water, steps, sleep, supplements.
  ///
  /// Every value is DERIVED from the member's recorded events, never read
  /// from the legacy projection document: gating a line on that mirror meant a
  /// member's water only appeared once a best-effort bridge write had
  /// round-tripped, and never at all if it failed.
  Widget _lifestyleProgress(LifestyleController c, AppPalette p) {
    final t = c.targets;
    final supplements = c.supplementChecklist;
    final takenCount = supplements.where((s) => s.taken).length;

    final metrics = <DailyMetric>[
      DailyMetric(
        label: 'Water',
        icon: Icons.water_drop_outlined,
        unit: 'glasses',
        format: (v) => v.round().toString(),
        // Glasses, because that is the unit the member logs in. Null when
        // nothing is recorded — zero glasses drunk and no record of drinking
        // are different claims.
        current: c.waterMl > 0 ? c.waterGlasses.toDouble() : null,
        target: t.waterTargetMl == null ? null : c.waterTargetGlasses.toDouble(),
      ),
      DailyMetric(
        label: 'Steps',
        icon: Icons.directions_walk_rounded,
        unit: '',
        format: (v) => v >= 1000
            ? '${(v / 1000).toStringAsFixed(1)}k'
            : v.round().toString(),
        current: c.steps?.toDouble(),
        target: t.stepsTarget?.toDouble(),
      ),
      DailyMetric(
        label: 'Sleep',
        icon: Icons.bedtime_outlined,
        unit: 'h',
        format: (v) =>
            v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1),
        current: c.sleepHours,
        target: t.sleepHoursTarget,
      ),
      // Only when the coach actually prescribed a stack: a supplement row with
      // nothing prescribed would invite a member to wonder what they missed.
      if (supplements.isNotEmpty)
        DailyMetric(
          label: 'Supplements',
          icon: Icons.medication_outlined,
          unit: '',
          format: (v) => v.round().toString(),
          current: takenCount.toDouble(),
          target: supplements.length.toDouble(),
        ),
    ];

    final hasAnyTarget = metrics.any((m) => m.hasTarget);
    return DailyProgressCard(
      title: 'Lifestyle progress',
      titleIcon: Icons.favorite_border,
      metrics: metrics,
      subtitle: hasAnyTarget
          ? DailyProgressCard.onTrackSummary(metrics)
          // Honest lifecycle: without targets the member can still track, and
          // saying so beats implying a coach-driven tracker that is not set up.
          : 'No coach targets yet — you can still track your day',
      // "History" rather than a second "Log": the card body already taps
      // through to the logger, so the header action is the affordance the
      // member had NO route to before — their own streaks and averages.
      actionLabel: 'History',
      onAction: () => Get.to(() => const LifestyleHistoryScreen()),
      onTap: () => Get.to(() => const LifestyleTodayScreen()),
    );
  }

  /// NUTRITION PROGRESS — today's consumed against today's target.
  ///
  /// Consumed comes from the FOOD LOG and nothing else. It is not derived from
  /// the diet plan, from recommendations, or from eaten/partial/skipped marks:
  /// a recommendation nobody ate is not nutrition, and the marks stopped being
  /// written when coach recommendations became read-only.
  Widget _nutritionProgress(HomeController h, AppPalette p) {
    final log = Get.isRegistered<FoodLogController>()
        ? Get.find<FoodLogController>()
        : Get.put(FoodLogController());

    String grams(double v) =>
        v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

    // Null when nothing is logged, so "no food recorded" never renders as
    // "ate zero" — the same distinction every other metric on this screen
    // makes.
    double? logged(double v) => log.entryCount == 0 ? null : v;

    final metrics = <DailyMetric>[
      DailyMetric(
        label: 'Calories',
        icon: Icons.local_fire_department_outlined,
        unit: 'kcal',
        format: (v) => v.round().toString(),
        current: logged(log.loggedCalories),
        target: h.hasCoachCalorieGoal ? h.targetCalories : null,
      ),
      DailyMetric(
        label: 'Protein',
        icon: Icons.egg_alt_outlined,
        unit: 'g',
        format: grams,
        current: logged(log.loggedProtein),
        target: h.proteinTarget.isCoachGoal ? h.targetProtein : null,
      ),
      DailyMetric(
        label: 'Carbs',
        icon: Icons.grain_rounded,
        unit: 'g',
        format: grams,
        current: logged(log.loggedCarbs),
        target: h.carbsTarget.isCoachGoal ? h.targetCarbs : null,
      ),
      DailyMetric(
        label: 'Fat',
        icon: Icons.water_drop_rounded,
        unit: 'g',
        format: grams,
        current: logged(log.loggedFat),
        target: h.fatTarget.isCoachGoal ? h.targetFat : null,
      ),
      DailyMetric(
        label: 'Fiber',
        icon: Icons.spa_outlined,
        unit: 'g',
        format: grams,
        current: logged(log.loggedFiber),
        target: h.fiberTarget.isCoachGoal ? h.targetFiber : null,
      ),
    ];

    final summary = DailyProgressCard.onTrackSummary(metrics);
    return DailyProgressCard(
      title: 'Nutrition progress',
      titleIcon: Icons.restaurant_outlined,
      metrics: metrics,
      subtitle: summary ??
          (log.entryCount == 0
              ? 'Nothing logged yet today'
              : 'No coach targets yet'),
      actionLabel: 'Log food',
      onAction: () => Get.to(() => const DietScreen()),
      onTap: () => Get.to(() => const DietScreen()),
    );
  }

  Widget _expiryBanner(HomeController h, AppPalette p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: p.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: p.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              h.membershipExpiryText,
              style: AppText.body(
                size: 12,
              ).copyWith(color: p.error, fontWeight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: () => Get.to(() => MembershipScreen()),
            child: Text(
              'Renew',
              style: AppText.label(
                size: 12,
              ).copyWith(color: p.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unlinkedCard(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: glassCard(p, radius: 16),
      child: Column(
        children: [
          Icon(Icons.link_off_rounded, color: p.accent, size: 36),
          const SizedBox(height: 12),
          Text(
            'Connect to a Coach',
            style: AppText.title(size: 16).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'No coach linked yet. Find a coach or enter a handle to unlock your workout and nutrition plans.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () => Get.to(() => const JoinCoachScreen()),
            child: Text('Find a Coach', style: AppText.label(size: 13)),
          ),
        ],
      ),
    );
  }

  Widget _inactiveMembershipCard(HomeController h, AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: glassCard(p, radius: 16),
      child: Column(
        children: [
          Icon(Icons.lock_outline_rounded, color: p.accent, size: 36),
          const SizedBox(height: 12),
          Text(
            'Membership Inactive',
            style: AppText.title(size: 16).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Subscribe to a plan to unlock your daily training routines, diet charts, and chat with your trainer.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () => Get.to(() => MembershipScreen()),
            child: Text(
              'View Membership Plans',
              style: AppText.label(size: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ── Coaching lifecycle: Getting Started tracker ─────────────────────
  Widget _gettingStartedCard(
    HomeController h,
    ClientStage stage,
    AppPalette p,
  ) {
    final String title;
    final String message;
    final bool showCta;
    switch (stage) {
      case ClientStage.identity:
        title = 'Set up your profile';
        message =
            'Tell us a little about yourself — your coach builds everything around who you are.';
        showCta = true;
        break;
      case ClientStage.onboarding:
        title = 'Complete your onboarding';
        message =
            'Answer a few questions from ${h.coachName} so your plan is built around you.';
        showCta = true;
        break;
      case ClientStage.awaitingTrainer:
        title = 'Coach being assigned';
        message =
            '${h.gymName} is assigning your coach. You\'ll be ready to train shortly.';
        showCta = false;
        break;
      case ClientStage.preparingPlan:
        title = 'Your plan is on the way';
        message = h.hasCoachName
            ? 'Coach ${h.coachName} is preparing your workout & diet plan. Hang tight!'
            : 'Your coach is preparing your workout & diet plan. Hang tight!';
        showCta = false;
        break;
      case ClientStage.ready:
        title = '';
        message = '';
        showCta = false;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: glassCard(p, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rocket_launch_rounded, color: p.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'Getting Started',
                style: GoogleFonts.poppins(
                  color: p.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _stepTracker(stage, p),
          const SizedBox(height: 20),
          Text(
            title,
            style: AppText.title(size: 18).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: AppText.body(
              size: 12.5,
            ).copyWith(color: p.textMuted, height: 1.4),
          ),
          if (showCta) ...[
            const SizedBox(height: 16),
            GradientButton(
              label: stage == ClientStage.identity
                  ? 'Set Up Profile'
                  : 'Complete Onboarding',
              showChevron: true,
              // Branch OUTSIDE the closure: a ternary inside one closure types
              // it as `() => StatefulWidget`, which GetX turns into the same
              // anonymous route name as the dashboard's own ternary push — and
              // preventDuplicates then silently drops the navigation entirely.
              onPressed: () => stage == ClientStage.identity
                  ? Get.to(() => const IdentitySetupScreen())
                  : Get.to(() => const OnboardingFlowScreen()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepTracker(ClientStage stage, AppPalette p) {
    const labels = ['Profile', 'Onboarding', 'Coach', 'Plan'];
    final children = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      final done = stage.index > i;
      final active = stage.index == i;
      children.add(_stepNode(labels[i], i + 1, done, active, p));
      if (i < labels.length - 1) {
        children.add(
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.only(bottom: 18),
              color: stage.index > i ? p.accent : p.border,
            ),
          ),
        );
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _stepNode(String label, int n, bool done, bool active, AppPalette p) {
    final Color ring = done || active ? p.accent : p.border;
    final Color fill = done
        ? p.accent
        : (active ? p.accent.withValues(alpha: 0.14) : p.surface);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: 1.6),
          ),
          child: done
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
              : Text(
                  '$n',
                  style: GoogleFonts.poppins(
                    color: active ? p.accent : p.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: done || active ? p.textPrimary : p.textMuted,
            fontSize: 10.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _tappableCard(
    AppPalette p, {
    required VoidCallback onTap,
    required Widget child,
    double radius = 16,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    BoxDecoration? decoration,
    String? semanticLabel,
  }) {
    final card = Material(
      color: Colors.transparent,
      child: Ink(
        decoration: decoration ?? glassCard(p, radius: radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (semanticLabel == null) return card;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: card,
    );
  }

  /// Small tinted status chip ("Due today", "Submitted ✓").
  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _quote(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: p.isDark
              ? [const Color(0xFF1A0E0E), const Color(0xFF141414)]
              : [const Color(0xFFFFF5F5), const Color(0xFFFFFFFF)],
        ),
        border: Border.all(
          color: p.isDark ? const Color(0xFF2A1414) : const Color(0xFFFFECEC),
        ),
      ),
      child: Row(
        children: [
          Text(
            '"',
            style: TextStyle(
              color: p.accent,
              fontSize: 40,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Quotes.daily(),
                  style: GoogleFonts.poppins(
                    color: p.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '— Alpha Serena',
                  style: GoogleFonts.poppins(color: p.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Whether today's session is genuinely part-done, per the ONE completion

  Widget _skeletonLoader(AppPalette p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        // Mirrors the real header: org row, divider, coach row — so the
        // transition out of the skeleton doesn't shift the layout.
        Container(
          decoration: glassCard(p),
          padding: const EdgeInsets.fromLTRB(12, 11, 11, 11),
          child: Column(
            children: [
              Row(
                children: [
                  _skeletonBox(width: 48, height: 48, radius: 14, p: p),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skeletonBox(width: 132, height: 15, radius: 4, p: p),
                      const SizedBox(height: 6),
                      _skeletonBox(width: 104, height: 10, radius: 3, p: p),
                    ],
                  ),
                  const Spacer(),
                  _skeletonBox(width: 44, height: 44, radius: 13, p: p),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Divider(height: 1, thickness: 1, color: p.border),
              ),
              Row(
                children: [
                  const SizedBox(width: 6),
                  _skeletonBox(width: 36, height: 36, radius: 18, p: p),
                  const SizedBox(width: 18),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skeletonBox(width: 44, height: 9, radius: 3, p: p),
                      const SizedBox(height: 5),
                      _skeletonBox(width: 108, height: 13, radius: 4, p: p),
                    ],
                  ),
                  const Spacer(),
                  _skeletonBox(width: 92, height: 30, radius: 11, p: p),
                ],
              ),
            ],
          ),
        ),
        // Shaped like the REAL order below it — hero, session card, nutrition,
        // lifestyle — so the screen settles instead of jumping when the data
        // lands. A skeleton that doesn't match its content is a worse first
        // impression than no skeleton at all.
        const SizedBox(height: 16),
        _skeletonBox(width: double.infinity, height: 158, radius: 20, p: p),
        const SizedBox(height: 18),
        _skeletonBox(width: double.infinity, height: 320, radius: 20, p: p),
        const SizedBox(height: 18),
        _skeletonBox(width: double.infinity, height: 230, radius: 16, p: p),
        const SizedBox(height: 18),
        _skeletonBox(width: double.infinity, height: 110, radius: 16, p: p),
      ],
    );
  }

  Widget _skeletonBox({
    required double width,
    required double height,
    required double radius,
    required AppPalette p,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// H2 Coach Updates — the latest meaningful events from the coaching side
/// (plan assigned, check-in reviewed, membership changes…), straight from the
/// member's notification items (Cloud-Function-written; repository-backed by
/// definition). Hidden entirely when there are none — never a generic quote.
/// Stateful so the Firestore stream is created once (same rationale as the
/// bell).
class _CoachUpdatesSection extends StatefulWidget {
  const _CoachUpdatesSection();

  @override
  State<_CoachUpdatesSection> createState() => _CoachUpdatesSectionState();
}

class _CoachUpdatesSectionState extends State<_CoachUpdatesSection> {
  late final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final Stream<List<AppNotification>>? _stream = _uid.isEmpty
      ? null
      : NotificationCenterService().watchItems(_uid, limit: 10);

  @override
  Widget build(BuildContext context) {
    final stream = _stream;
    if (stream == null) return const SizedBox.shrink();
    final p = context.palette;
    return StreamBuilder<List<AppNotification>>(
      stream: stream,
      builder: (context, snap) {
        final items = (snap.data ?? const <AppNotification>[]).take(3).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign_outlined, color: p.accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Coach Updates',
                  style: GoogleFonts.poppins(
                    color: p.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Semantics(
                  button: true,
                  label: 'View all coach updates',
                  excludeSemantics: true,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          Get.to(() => const NotificationCenterScreen()),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        child: Text(
                          'View all',
                          style: GoogleFonts.poppins(
                            color: p.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...items.map((n) => _row(n, p)),
          ],
        );
      },
    );
  }

  /// Compact relative age ("now", "5m", "3h", "4d", then a short date) so the
  /// feed reads as a timeline without a verbose timestamp per row.
  static String _relTime(DateTime? t) {
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat('d MMM').format(t);
  }

  Widget _row(AppNotification n, AppPalette p) {
    final v = notificationVisual(n.category);
    final age = _relTime(n.createdAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        label:
            '${n.isUnread ? 'Unread. ' : ''}${n.title}. '
            '${n.body.isNotEmpty ? '${n.body}. ' : ''}'
            '${age.isNotEmpty ? '$age ago' : ''}',
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: glassCardSoft(p, radius: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Get.to(() => const NotificationCenterScreen()),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: v.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(v.icon, color: v.color, size: 17),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: p.textPrimary,
                              fontSize: 12,
                              fontWeight: n.isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          if (n.body.isNotEmpty)
                            Text(
                              n.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                color: p.textMuted,
                                fontSize: 10.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (age.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        age,
                        style: GoogleFonts.poppins(
                          color: p.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                    if (n.isUnread)
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          color: p.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
