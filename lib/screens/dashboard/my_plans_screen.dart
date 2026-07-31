import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

import '../../controllers/member_controller.dart';
import '../../core/domain/member_identity.dart';
import '../../controllers/training_controller.dart';
import '../../controllers/diet_log_controller.dart';
import '../../controllers/membership_controller.dart';
import '../../core/domain/nutrition_targets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/brand.dart';
import '../join/join_coach_screen.dart';
import 'membership_screen.dart';
import 'client_workout_screen.dart';
import 'client_diet_screen.dart';

/// The coach's REAL photo, or their initials, or a neutral glyph — never the
/// stock portrait this card used to show under the heading "Your Trainer".
/// Same rule as Profile and Home: `resolveCoachPhoto` exists so callers "render
/// initials, never a stranger's face".
Widget _coachAvatar(MemberController member, AppPalette p) {
  final photo = member.trainerPhotoUrl;
  final initials = initialsOf(member.trainerName);

  Widget fallback() => Container(
    color: p.surfaceAlt,
    alignment: Alignment.center,
    child: initials.isNotEmpty
        ? Text(initials, style: AppText.title(size: 14).copyWith(color: p.accent))
        : Icon(Icons.person_outline, color: p.textMuted, size: 18),
  );

  return ClipOval(
    child: SizedBox(
      width: 38,
      height: 38,
      child: photo.isEmpty
          ? fallback()
          : CachedNetworkImage(
              imageUrl: photo,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(color: p.surfaceAlt),
              errorWidget: (_, _, _) => fallback(),
            ),
    ),
  );
}

/// My Plans — partner, active plans, today's nutrition + meals, workout overview.
class MyPlansScreen extends StatefulWidget {
  const MyPlansScreen({super.key});

  @override
  State<MyPlansScreen> createState() => _MyPlansScreenState();
}

class _MyPlansScreenState extends State<MyPlansScreen> {
  int _tabIndex = 0; // 0 = Current Plans, 1 = Previous Plans

  double _sum(List<Map<String, dynamic>> items, String key) {
    double t = 0;
    for (final i in items) {
      final v = i[key];
      if (v is num) t += v.toDouble();
      if (v is String) t += double.tryParse(v) ?? 0;
    }
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final member = Get.isRegistered<MemberController>()
        ? Get.find<MemberController>()
        : Get.put(MemberController());
    final training = Get.isRegistered<TrainingController>()
        ? Get.find<TrainingController>()
        : Get.put(TrainingController());
    final membership = Get.isRegistered<MembershipController>()
        ? Get.find<MembershipController>()
        : Get.put(MembershipController());
    final dietLog = Get.isRegistered<DietLogController>()
        ? Get.find<DietLogController>()
        : Get.put(DietLogController());

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          final linked = member.isLinked.value;
          final active = membership.isActive;
          final loading =
              member.isLoading.value ||
              training.isLoading.value ||
              membership.isLoading.value;

          if (loading) {
            return _skeletonLoader(p);
          }

          return RefreshIndicator(
            onRefresh: () async {
              await member.claim();
              await training.load();
            },
            color: p.accent,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              children: [
                _header(p),
                const SizedBox(height: 18),
                _tabs(p),
                const SizedBox(height: 16),

                if (_tabIndex == 1) ...[
                  // Previous Plans Tab
                  const SizedBox(height: 40),
                  _emptyPlans(
                    p,
                    'No Previous Plans',
                    'Your past archived programs will show up here once updated by your coach.',
                  ),
                ] else if (!linked) ...[
                  // Unlinked state blocker
                  _unlinkedCard(p),
                ] else if (!active) ...[
                  // Inactive subscription blocker
                  _inactiveMembershipCard(p),
                ] else ...[
                  // Active Plans
                  _partnerCard(member, p),
                  const SizedBox(height: 20),
                  _sectionTitle('Active Plans', p),
                  const SizedBox(height: 12),
                  if (training.error.value.isNotEmpty &&
                      training.workout.value == null &&
                      training.diet.value == null)
                    _trainingErrorBanner(training, p)
                  else
                    _activePlans(training, p),
                  const SizedBox(height: 16),
                  _todaysNutrition(training, dietLog, p),
                  const SizedBox(height: 16),
                  _sectionTitle("Today's Meals", p),
                  const SizedBox(height: 12),
                  _mealsSummary(dietLog, p),
                  const SizedBox(height: 20),
                  _workoutOverview(training, p),
                  const SizedBox(height: 20),
                  _planDetails(member, training, p),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _sectionTitle(String t, AppPalette p) => Text(
    t,
    style: GoogleFonts.poppins(
      color: p.textPrimary,
      fontSize: 16,
      fontWeight: FontWeight.w700,
    ),
  );

  // Distinct from "Pending Assignment": the load FAILED — offer a Retry.
  Widget _trainingErrorBanner(TrainingController training, AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: p.textMuted, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Couldn't load your plans. Check your connection.",
              style: GoogleFonts.poppins(color: p.textMuted, fontSize: 12.5),
            ),
          ),
          TextButton(
            onPressed: () => training.load(),
            child: Text(
              'Retry',
              style: GoogleFonts.poppins(
                color: p.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(AppPalette p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Plans',
                style: GoogleFonts.poppins(
                  color: p.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Your personalized plans, crafted for your goals.',
                style: GoogleFonts.poppins(color: p.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        _iconBtn(Icons.calendar_today_outlined, p),
      ],
    );
  }

  Widget _iconBtn(IconData icon, AppPalette p) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: p.surface,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: p.border),
    ),
    child: Icon(icon, color: p.textPrimary, size: 18),
  );

  Widget _tabs(AppPalette p) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _tabIndex = 0),
                child: Column(
                  children: [
                    Text(
                      'Current Plans',
                      style: GoogleFonts.poppins(
                        color: _tabIndex == 0 ? p.accent : p.textMuted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 2,
                      color: _tabIndex == 0 ? p.accent : Colors.transparent,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _tabIndex = 1),
                child: Column(
                  children: [
                    Text(
                      'Previous Plans',
                      style: GoogleFonts.poppins(
                        color: _tabIndex == 1 ? p.accent : p.textMuted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 2,
                      color: _tabIndex == 1 ? p.accent : Colors.transparent,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _unlinkedCard(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          Icon(Icons.link_off_rounded, color: p.accent, size: 40),
          const SizedBox(height: 14),
          Text(
            'Connect to a Coach',
            style: AppText.title(size: 16).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'No coach linked yet. Find a coach or enter a handle to unlock your custom diet and training programs.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 18),
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

  Widget _inactiveMembershipCard(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          Icon(Icons.lock_outline_rounded, color: p.accent, size: 40),
          const SizedBox(height: 14),
          Text(
            'Plans Locked',
            style: AppText.title(size: 16).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Subscribe to your coach\'s subscription plan to unlock workout calendars, diet logs, and message boards.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 18),
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

  Widget _emptyPlans(AppPalette p, String title, String sub) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          Icon(Icons.folder_open_outlined, color: p.textMuted, size: 44),
          const SizedBox(height: 12),
          Text(
            title,
            style: AppText.title(size: 16).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _partnerCard(MemberController member, AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: p.isDark
              ? [const Color(0xFF1A0E0E), const Color(0xFF141414)]
              : [const Color(0xFFFFF2F2), const Color(0xFFFFFFFF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: p.isDark ? const Color(0xFF2A1414) : const Color(0xFFFFECEC),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: p.surfaceAlt,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: const AlphaAMark(size: 26),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Same identity rules as Profile and Home. This card was the
                    // third copy of the same fossil: 'Alpha Arena', 'Your Coach',
                    // 'Performance Coach' and the stock trainer portrait — plus
                    // an UNCONDITIONAL verified badge, which is precisely the
                    // defect HomeHeader records fixing ("it was previously drawn
                    // unconditionally, which claimed a verification no document
                    // backed").
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            // Identical unknown-state wording to Home and
                            // Profile — see the note on the Profile card.
                            member.orgName.isNotEmpty
                                ? member.orgName
                                : 'Your Organization',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: member.orgName.isNotEmpty
                                  ? p.textPrimary
                                  : p.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Only when the platform actually verified them.
                        if (member.orgVerified.value) ...[
                          const SizedBox(width: 3),
                          Icon(Icons.verified, color: p.accent, size: 12),
                        ],
                      ],
                    ),
                    Text(
                      'Your coaching organization',
                      style: GoogleFonts.poppins(
                        color: p.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your coach',
                            style: GoogleFonts.poppins(
                              color: p.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            member.trainerName.isNotEmpty
                                ? member.trainerName
                                : 'Not assigned yet',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: member.trainerName.isNotEmpty
                                  ? p.textPrimary
                                  : p.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          // 'Performance Coach' removed — no coach job title is
                          // stored anywhere in the platform.
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    _coachAvatar(member, p),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: p.border, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              _planStat(
                Icons.calendar_today_outlined,
                'Plan Type',
                member.goal.isNotEmpty ? member.goal : 'General Fitness',
                p,
              ),
              _planStat(Icons.refresh, 'Next Check-in', 'Weekly', p),
              _planStat(Icons.flag_outlined, 'Duration', 'Ongoing', p),
            ],
          ),
        ],
      ),
    );
  }

  Widget _planStat(IconData icon, String label, String value, AppPalette p) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: p.accent, size: 14),
            const SizedBox(height: 5),
            Text(
              label,
              style: GoogleFonts.poppins(color: p.textMuted, fontSize: 8.5),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: p.textPrimary,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _activePlans(TrainingController training, AppPalette p) {
    final hasWorkout = training.workout.value != null;
    final hasDiet = training.diet.value != null;
    final dietName = training.diet.value?['name']?.toString() ?? 'No Diet';
    final workoutName =
        training.workout.value?['name']?.toString() ?? 'No Workout';

    return Row(
      children: [
        _planCard(
          Icons.restaurant_menu,
          const Color(0xFF2EBD59),
          'Nutrition Plan',
          hasDiet ? dietName : 'Pending Assignment',
          () => Get.to(() => ClientDietScreen()),
          p,
        ),
        const SizedBox(width: 12),
        _planCard(
          Icons.fitness_center,
          p.accent,
          'Workout Plan',
          hasWorkout ? workoutName : 'Pending Assignment',
          () => Get.to(() => ClientWorkoutScreen()),
          p,
        ),
      ],
    );
  }

  Widget _planCard(
    IconData icon,
    Color color,
    String title,
    String sub,
    VoidCallback onTap,
    AppPalette p,
  ) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.border),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.poppins(
                            color: p.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            color: p.textMuted,
                            fontSize: 9,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _todaysNutrition(
    TrainingController training,
    DietLogController diet,
    AppPalette p,
  ) {
    // One canonical rule (`core/domain/nutrition_targets.dart`) — the coach's
    // `clients.dietTargets` goal when set, else the assigned plan's sum. The
    // previous `caloriesGoal > 0 ? caloriesGoal : 2000.0` invented a 2000 kcal
    // goal out of nothing and burned the ring down against it.
    NutritionTarget target(String targetKey, String itemKey) =>
        resolveNutritionTarget(
          diet: training.diet.value,
          targetKey: targetKey,
          itemKey: itemKey,
          items: training.dietItems,
        );

    final calories = target('targetCalories', 'calories');
    final caloriesConsumed = diet.consumedCalories;
    // Only a real coach goal supports "remaining"; otherwise the ring reports
    // logging progress and the centre reads "kcal eaten".
    final hasGoal = calories.isCoachGoal;
    final caloriesGoal = calories.value;
    final caloriesLeft = hasGoal
        ? (caloriesGoal - caloriesConsumed).clamp(0.0, caloriesGoal)
        : 0.0;
    final nutritionPercent = hasGoal
        ? (caloriesConsumed / caloriesGoal).clamp(0.0, 1.0)
        : (diet.totalFoods > 0
              ? (diet.loggedCount / diet.totalFoods).clamp(0.0, 1.0)
              : 0.0);

    final targetProtein = target('targetProtein', 'protein').value;
    final targetCarbs = target('targetCarbs', 'carbs').value;
    final targetFat = target('targetFat', 'fat').value;
    final targetFiber = target('targetFiber', 'fiber').value;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant, color: Color(0xFF2EBD59), size: 18),
              const SizedBox(width: 8),
              Text(
                "Today's Nutrition",
                style: GoogleFonts.poppins(
                  color: p.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Get.to(() => ClientDietScreen()),
                child: Row(
                  children: [
                    Text(
                      'View Full Plan',
                      style: GoogleFonts.poppins(
                        color: p.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(Icons.chevron_right, color: p.accent, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircularPercentIndicator(
                radius: 48,
                lineWidth: 8,
                percent: nutritionPercent,
                backgroundColor: p.isDark
                    ? const Color(0xFF262626)
                    : const Color(0xFFE0E0E0),
                linearGradient: LinearGradient(
                  colors: [p.accent, const Color(0xFF2EBD59)],
                ),
                circularStrokeCap: CircularStrokeCap.round,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasGoal
                          ? '${caloriesLeft.round()}'
                          : '${caloriesConsumed.round()}',
                      style: GoogleFonts.poppins(
                        color: p.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      hasGoal ? 'kcal left' : 'kcal eaten',
                      style: GoogleFonts.poppins(
                        color: p.textMuted,
                        fontSize: 9,
                      ),
                    ),
                    // The denominator is only shown when it is a real goal —
                    // "/ 1750 kcal" beside a prescription sum reads as a target
                    // the coach never set.
                    if (hasGoal)
                      Text(
                        '/ ${caloriesGoal.round()} kcal',
                        style: GoogleFonts.poppins(
                          color: p.textMuted,
                          fontSize: 7.5,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _macroV(
                        'Carbs',
                        diet.consumedCarbs,
                        targetCarbs,
                        const Color(0xFF2EBD59),
                        Icons.grain,
                        p,
                      ),
                    ),
                    Expanded(
                      child: _macroV(
                        'Protein',
                        diet.consumedProtein,
                        targetProtein,
                        const Color(0xFF3B82F6),
                        Icons.egg_alt,
                        p,
                      ),
                    ),
                    Expanded(
                      child: _macroV(
                        'Fats',
                        diet.consumedFat,
                        targetFat,
                        const Color(0xFFF59E0B),
                        Icons.water_drop,
                        p,
                      ),
                    ),
                    Expanded(
                      child: _macroV(
                        'Fiber',
                        diet.consumedFiber,
                        targetFiber,
                        const Color(0xFF9B5DE5),
                        Icons.spa,
                        p,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macroV(
    String name,
    double current,
    double goal,
    Color color,
    IconData icon,
    AppPalette p,
  ) {
    final finalGoal = goal > 0
        ? goal
        : (name == 'Carbs'
              ? 300.0
              : name == 'Protein'
              ? 150.0
              : name == 'Fats'
              ? 70.0
              : 35.0);
    final pct = (current / finalGoal).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 13),
          ),
          const SizedBox(height: 5),
          Text(
            name,
            style: GoogleFonts.poppins(color: p.textMuted, fontSize: 9),
          ),
          Text(
            '${current.round()}/${finalGoal.round()}g',
            style: GoogleFonts.poppins(
              color: p.textPrimary,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: p.isDark
                  ? const Color(0xFF262626)
                  : const Color(0xFFE0E0E0),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  // Real adherence summary for the My Plans nutrition tab — the daily marking
  // itself lives in ClientDietScreen (writes client_diet_logs). Replaces the old
  // free-form, in-memory "add a food" mock that never persisted.
  Widget _mealsSummary(DietLogController diet, AppPalette p) {
    return Obx(() {
      final total = diet.totalFoods;
      final logged = diet.loggedCount;
      final pct = (diet.adherence * 100).round();
      final hasPlan = total > 0;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.restaurant_menu, color: p.accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasPlan
                        ? '$logged of $total foods logged · $pct% adherence'
                        : 'No nutrition plan assigned yet',
                    style: GoogleFonts.poppins(
                      color: p.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (hasPlan) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: p.accent,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Get.to(() => ClientDietScreen()),
                  icon: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    logged > 0 ? 'Update Meal Log' : 'Log Your Meals',
                    style: AppText.label(
                      size: 14,
                    ).copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  /// Rest day of a weekly schedule: the schedule's name, today's rest, the
  /// next mapped day, and the week at a glance — every line a served fact.
  Widget _weeklyRestCard(
    TrainingController training,
    AppPalette p, {
    bool unavailable = false,
  }) {
    final weekly = training.weeklyOverview;
    final next = training.nextTrainingDay;
    final days = ((weekly?['days'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.fitness_center, color: p.accent, size: 16),
            const SizedBox(width: 8),
            Text(
              'Workout Plan Overview',
              style: GoogleFonts.poppins(
                color: p.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (weekly?['name'] ?? 'Weekly schedule').toString(),
                style: GoogleFonts.poppins(
                  color: p.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                unavailable
                    ? "Today's workout is unavailable — its plan was removed. "
                          'Ask your coach.'
                    : next == null
                    ? 'Rest day today.'
                    : 'Rest day today — next: ${next['planName']} '
                          'on ${next['day']}.',
                style: GoogleFonts.poppins(
                  color: unavailable ? p.error : p.textMuted,
                  fontSize: 12,
                ),
              ),
              if (days.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final d in days)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(
                            d['day'].toString().length >= 3
                                ? d['day'].toString().substring(0, 3)
                                : d['day'].toString(),
                            style: GoogleFonts.poppins(
                              color: d['isToday'] == true
                                  ? p.accent
                                  : p.textMuted,
                              fontSize: 11.5,
                              fontWeight: d['isToday'] == true
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            (d['planName'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: p.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _workoutOverview(TrainingController training, AppPalette p) {
    final hasWorkout = training.workout.value != null;
    final workoutName =
        training.workout.value?['name']?.toString() ?? 'Rest Day';
    final count = training.workoutItems.length;

    // WEEKLY PRESCRIPTION — an authored rest day of a weekly schedule. The
    // track exists but today asks for nothing: rendering the normal card would
    // show a workout with 0 exercises, which reads as broken. Say REST, name
    // the next training day, and show the week — all served facts.
    if (hasWorkout && training.isWeeklyRestDay) {
      return _weeklyRestCard(training, p);
    }
    // A weekly day whose day-plan was archived/removed serves no items with
    // `dayPlanUnavailable` — a coach-side fault the member must not misread as
    // their own rest day OR as a broken 0-exercise workout.
    if (hasWorkout && training.workout.value?['dayPlanUnavailable'] == true) {
      return _weeklyRestCard(training, p, unavailable: true);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.fitness_center, color: p.accent, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Workout Plan Overview',
                  style: GoogleFonts.poppins(
                    color: p.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: () => Get.to(() => ClientWorkoutScreen()),
              child: Row(
                children: [
                  Text(
                    'View Full Plan',
                    style: GoogleFonts.poppins(
                      color: p.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(Icons.chevron_right, color: p.accent, size: 16),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              Image.asset(
                'assets/images/ex1.png',
                width: double.infinity,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: double.infinity,
                  height: 120,
                  color: p.surfaceAlt,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.black.withValues(alpha: 0.35),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: p.accent,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            hasWorkout ? 'Active Workout Plan' : 'Rest Day',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      workoutName,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      hasWorkout
                          ? '$count Exercises Assigned'
                          : 'Rest, recover, and grow.',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => Get.to(() => ClientWorkoutScreen()),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.calendar_month_outlined,
                  color: p.textPrimary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'View Workout Calendar',
                  style: GoogleFonts.poppins(
                    color: p.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _planDetails(
    MemberController member,
    TrainingController training,
    AppPalette p,
  ) {
    final caloriesGoal = _sum(training.dietItems, 'calories');
    final finalGoal = caloriesGoal > 0 ? caloriesGoal : 2000.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Plan Details', p),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              _detail(
                Icons.flag_outlined,
                'Plan Type',
                member.goal.isNotEmpty ? member.goal : 'General',
                p,
              ),
              _detail(Icons.schedule, 'Duration', 'Ongoing', p),
              _detail(
                Icons.local_fire_department,
                'Daily Calories',
                '${finalGoal.round()} kcal',
                p,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detail(IconData icon, String label, String value, AppPalette p) =>
      Expanded(
        child: Column(
          children: [
            Icon(icon, color: p.accent, size: 16),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: p.textMuted, fontSize: 8.5),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: p.textPrimary,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _skeletonLoader(AppPalette p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 24,
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 200,
                  height: 12,
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: p.surfaceAlt,
                borderRadius: BorderRadius.circular(11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          height: 40,
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          height: 80,
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          height: 150,
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ],
    );
  }
}
