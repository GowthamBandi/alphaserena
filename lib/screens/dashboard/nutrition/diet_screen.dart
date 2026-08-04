import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/food_log_controller.dart';
import '../../../controllers/training_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';
import 'add_food_screen.dart';
import 'coach_recommended_meals.dart';
import 'food_history_screen.dart';
import 'food_log_section.dart';

/// PHASE 3B — THE DIET SCREEN. The whole nutrition journey, in one place.
///
/// Two sections, in the order the member needs them:
///
///   1. COACH RECOMMENDED MEALS — what they SHOULD eat. **Read only.** A
///      recommendation is the coach's statement and the member cannot amend
///      it; it also contributes NOTHING to any total, because nobody has
///      eaten it yet.
///   2. TODAY'S FOOD LOG — what they ACTUALLY ate. The only input, and the
///      only source of nutrition totals.
///
/// PREVIOUS DAYS is reached from the app bar's history action ONLY. It used to
/// ALSO be a card at the foot of this list; two controls opening one screen is
/// a choice the member has to make and can get wrong. The same reasoning
/// removed the trailing "Add more food" button, which duplicated the FAB.
///
/// Keeping the two side by side is the point of the screen: the member can see
/// the plan and their reality together without either being mistaken for the
/// other, which is exactly what a single merged "meals" list used to do.
class DietScreen extends StatelessWidget {
  const DietScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final training = Get.isRegistered<TrainingController>()
        ? Get.find<TrainingController>()
        : Get.put(TrainingController());
    final log = Get.isRegistered<FoodLogController>()
        ? Get.find<FoodLogController>()
        : Get.put(FoodLogController());

    // The screen may have been left open across midnight.
    WidgetsBinding.instance.addPostFrameCallback((_) => log.ensureFreshDay());

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Diet',
            style: AppText.title(size: 20).copyWith(color: p.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Previous days',
            icon: Icon(Icons.history_rounded, color: p.textPrimary),
            onPressed: () => Get.to(() => const FoodHistoryScreen()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: p.accent,
        onPressed: () => Get.to(() => const AddFoodScreen()),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text('Add food',
            style: AppText.label(size: 14).copyWith(color: Colors.white)),
      ),
      body: RefreshIndicator(
        color: p.accent,
        onRefresh: () async {
          log.ensureFreshDay();
          await training.load();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _sectionHeader(p, 'Coach recommended', Icons.assignment_outlined),
            const SizedBox(height: 10),
            Obx(() => _recommendations(context, training, p)),
            const SizedBox(height: 28),
            _sectionHeader(p, "Today's food log", Icons.checklist_rounded),
            const SizedBox(height: 10),
            FoodLogSection(controller: log),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(AppPalette p, String title, IconData icon) => Row(
        children: [
          Icon(icon, size: 16, color: p.textMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: AppText.label(size: 11.5)
                  .copyWith(color: p.textMuted, letterSpacing: 0.9),
            ),
          ),
        ],
      );

  // ── SECTION 1 — COACH RECOMMENDATIONS (READ ONLY) ───────────────────────

  Widget _recommendations(
    BuildContext context,
    TrainingController training,
    AppPalette p,
  ) {
    final items = training.dietItems;
    if (items.isEmpty) return _noPlan(training, p);

    // THE SHARED WIDGET, not a layout this screen owns. My Plans renders the
    // identical section, and the coach's own words are the last thing that
    // should be phrased two ways in two places.
    return CoachRecommendedMeals(
      items: items,
      planName: (training.diet.value?['name'] ?? '').toString().trim(),
      note: (training.diet.value?['description'] ?? '').toString().trim(),
    );
  }

  Widget _noPlan(TrainingController training, AppPalette p) {
    final failed = training.error.value.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
      decoration: glassCard(p, radius: 16),
      child: Column(
        children: [
          Icon(failed ? Icons.error_outline_rounded : Icons.restaurant_rounded,
              size: 34, color: p.textMuted),
          const SizedBox(height: 12),
          Text(
            failed ? "Couldn't load your plan" : 'No diet plan yet',
            style: AppText.cardTitle(size: 14.5).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            failed
                ? 'This is a connection problem — your plan is safe.'
                // NOT a blocker: logging works without a plan, and saying so
                // is what stops a member waiting for permission to start.
                : 'Your coach is building it. You can still log what you eat — '
                    'everything below works without a plan.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
          ),
          if (failed) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: training.load,
              style: OutlinedButton.styleFrom(foregroundColor: p.accent),
              child: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }

}
