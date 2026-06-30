import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

import '../../controllers/member_controller.dart';
import '../../controllers/training_controller.dart';
import '../../controllers/dashboard_controller.dart';
import '../../controllers/membership_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/brand.dart';
import '../join/join_coach_screen.dart';
import 'membership_screen.dart';
import 'client_workout_screen.dart';
import 'client_diet_screen.dart';

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
    final dashCtrl = Get.isRegistered<DashboardController>()
        ? Get.find<DashboardController>()
        : Get.put(DashboardController());

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
                  _activePlans(training, p),
                  const SizedBox(height: 16),
                  _todaysNutrition(training, dashCtrl, p),
                  const SizedBox(height: 16),
                  _sectionTitle("Today's Meals", p),
                  const SizedBox(height: 12),
                  _meals(dashCtrl, p),
                  const SizedBox(height: 12),
                  _logFoodButton(context, dashCtrl, p),
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.gymName.isNotEmpty
                                ? member.gymName
                                : 'Alpha Arena',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: p.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(Icons.verified, color: p.accent, size: 12),
                      ],
                    ),
                    Text(
                      'Your Transformation Partner',
                      style: GoogleFonts.poppins(
                        color: p.textMuted,
                        fontSize: 9.5,
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
                            'Your Trainer',
                            style: GoogleFonts.poppins(
                              color: p.accent,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            member.trainerName.isNotEmpty
                                ? member.trainerName
                                : 'Your Coach',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: p.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Performance Coach',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: p.textMuted,
                              fontSize: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    ClipOval(
                      child: Image.asset(
                        'assets/images/trainer.png',
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 38,
                          height: 38,
                          color: p.surfaceAlt,
                          alignment: Alignment.center,
                          child: Text(
                            member.trainerName.isNotEmpty
                                ? member.trainerName[0].toUpperCase()
                                : 'C',
                            style: AppText.title(
                              size: 14,
                            ).copyWith(color: p.accent),
                          ),
                        ),
                      ),
                    ),
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
    DashboardController dashCtrl,
    AppPalette p,
  ) {
    final caloriesGoal = _sum(training.dietItems, 'calories');
    final finalGoal = caloriesGoal > 0 ? caloriesGoal : 2000.0;
    final caloriesConsumed = dashCtrl.dailyCalories.value;
    final caloriesLeft = (finalGoal - caloriesConsumed).clamp(0.0, finalGoal);
    final nutritionPercent = (caloriesConsumed / finalGoal).clamp(0.0, 1.0);

    // Sum assigned targets
    final targetProtein = _sum(training.dietItems, 'protein');
    final targetCarbs = _sum(training.dietItems, 'carbs');
    final targetFat = _sum(training.dietItems, 'fat');
    final targetFiber = _sum(training.dietItems, 'fiber');

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
                      '${caloriesLeft.round()}',
                      style: GoogleFonts.poppins(
                        color: p.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'kcal left',
                      style: GoogleFonts.poppins(
                        color: p.textMuted,
                        fontSize: 9,
                      ),
                    ),
                    Text(
                      '/ ${finalGoal.round()} kcal',
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
                        dashCtrl.carbs.value,
                        targetCarbs,
                        const Color(0xFF2EBD59),
                        Icons.grain,
                        p,
                      ),
                    ),
                    Expanded(
                      child: _macroV(
                        'Protein',
                        dashCtrl.protein.value,
                        targetProtein,
                        const Color(0xFF3B82F6),
                        Icons.egg_alt,
                        p,
                      ),
                    ),
                    Expanded(
                      child: _macroV(
                        'Fats',
                        dashCtrl.fats.value,
                        targetFat,
                        const Color(0xFFF59E0B),
                        Icons.water_drop,
                        p,
                      ),
                    ),
                    Expanded(
                      child: _macroV(
                        'Fiber',
                        dashCtrl.fiber.value,
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

  Widget _meals(DashboardController dashCtrl, AppPalette p) {
    final allLoggedMeals = <Map<String, dynamic>>[];
    dashCtrl.meals.forEach((type, list) {
      for (final mealItem in list) {
        allLoggedMeals.add({
          'type': type,
          'name': mealItem['name'],
          'calories': mealItem['calories'],
        });
      }
    });

    if (allLoggedMeals.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.border),
        ),
        child: Text(
          'No meals logged today yet.',
          style: AppText.body(size: 13).copyWith(color: p.textMuted),
        ),
      );
    }

    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: allLoggedMeals.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final m = allLoggedMeals[i];
          final calories = m['calories'] as double? ?? 0.0;
          return Container(
            width: 150,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  m['type']?.toString() ?? 'Meal',
                  style: GoogleFonts.poppins(color: p.textMuted, fontSize: 10),
                ),
                const SizedBox(height: 4),
                Text(
                  m['name']?.toString() ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: p.textPrimary,
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${calories.round()} kcal',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF2EBD59),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _logFoodButton(
    BuildContext context,
    DashboardController dashCtrl,
    AppPalette p,
  ) {
    return GestureDetector(
      onTap: () => _showLogFoodBottomSheet(context, dashCtrl, p),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Log Your Food',
              style: GoogleFonts.poppins(
                color: p.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: p.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 14),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogFoodBottomSheet(
    BuildContext context,
    DashboardController dashCtrl,
    AppPalette p,
  ) {
    final nameCtrl = TextEditingController();
    final calCtrl = TextEditingController();
    final protCtrl = TextEditingController();
    final carbCtrl = TextEditingController();
    final fatCtrl = TextEditingController();
    String selectedMeal = 'Breakfast';

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Log Food Item',
                style: AppText.title(size: 18).copyWith(color: p.textPrimary),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedMeal,
                dropdownColor: p.surface,
                decoration: InputDecoration(
                  labelText: 'Meal Type',
                  labelStyle: TextStyle(color: p.textMuted),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: p.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: p.accent),
                  ),
                ),
                style: TextStyle(color: p.textPrimary),
                items: ['Breakfast', 'Lunch', 'Dinner', 'Evening Snack']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) selectedMeal = v;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                style: TextStyle(color: p.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Food Name',
                  labelStyle: TextStyle(color: p.textMuted),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: p.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: p.accent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: calCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: p.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Calories (kcal)',
                        labelStyle: TextStyle(color: p.textMuted),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: p.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: p.accent),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: protCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: p.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Protein (g)',
                        labelStyle: TextStyle(color: p.textMuted),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: p.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: p.accent),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: carbCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: p.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Carbs (g)',
                        labelStyle: TextStyle(color: p.textMuted),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: p.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: p.accent),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: fatCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: p.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Fats (g)',
                        labelStyle: TextStyle(color: p.textMuted),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: p.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: p.accent),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: p.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final cal = double.tryParse(calCtrl.text) ?? 0.0;
                    final prot = double.tryParse(protCtrl.text) ?? 0.0;
                    final carb = double.tryParse(carbCtrl.text) ?? 0.0;
                    final fat = double.tryParse(fatCtrl.text) ?? 0.0;
                    if (name.isEmpty || cal <= 0) {
                      Get.snackbar(
                        'Input Error',
                        'Please enter a food name and calorie count.',
                      );
                      return;
                    }
                    dashCtrl.addMeal(
                      selectedMeal,
                      name: name,
                      calories: cal,
                      proteinVal: prot,
                      carbsVal: carb,
                      fatsVal: fat,
                      fiberVal: 0.0,
                    );
                    Get.back();
                    Get.snackbar('Success', '$name logged to $selectedMeal');
                  },
                  child: Text(
                    'Log Item',
                    style: AppText.label(
                      size: 14,
                    ).copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  Widget _workoutOverview(TrainingController training, AppPalette p) {
    final hasWorkout = training.workout.value != null;
    final workoutName =
        training.workout.value?['name']?.toString() ?? 'Rest Day';
    final count = training.workoutItems.length;

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
                errorBuilder: (_, __, ___) => Container(
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
