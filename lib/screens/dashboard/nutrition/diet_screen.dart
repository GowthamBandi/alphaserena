import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/food_log_controller.dart';
import '../../../controllers/training_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/serena/premium_states.dart';
import 'add_food_screen.dart';
import 'coach_recommended_meals.dart';
import 'nutrition_history_screen.dart';
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
  /// Whether to offer the history action.
  ///
  /// False when Nutrition History itself opened this screen ("Edit Food Log"
  /// on today). Otherwise the member can push History → Diet → History → Diet
  /// without limit, stacking duplicate routes behind a back button that then
  /// has to be tapped four times to leave. The workout twin never had this to
  /// solve: its editor is a dedicated screen with no history of its own.
  final bool showHistoryAction;

  const DietScreen({super.key, this.showHistoryAction = true});

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
          if (showHistoryAction)
            IconButton(
            tooltip: 'Previous days',
            icon: Icon(Icons.history_rounded, color: p.textPrimary),
            // ONE HISTORY, AND IT IS THE CALENDAR.
            //
            // This opened `FoodHistoryScreen`, a reverse-chronological list.
            // The member's other half of My Plans answers "what did I do
            // before?" with a month calendar, and answering the same question
            // two different ways in one tab is two interaction models to
            // learn for one idea.
            onPressed: () => Get.to(() => const NutritionHistoryScreen()),
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
            Row(
              children: [
                Expanded(
                  child: _sectionHeader(
                      p, 'Coach recommended', Icons.assignment_outlined),
                ),
                // The plan is re-pulled by this screen's pull-to-refresh. Say
                // so where the plan is, rather than leaving a silent second of
                // nothing happening.
                Obx(() => SyncWhisper(visible: training.isRefreshing)),
              ],
            ),
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
    // A FIRST LOAD IS NOT AN ANSWER. Opening Diet from Home before the plan
    // has ever resolved rendered "No diet plan yet — your coach is building
    // it", which is a statement about the COACH, made before anything had
    // been asked of the server. It then flipped to the real plan a moment
    // later. Telling a member their coach has done nothing, and being wrong,
    // is the worst version of an empty state.
    if (items.isEmpty && training.isFirstLoad) {
      return const SerenaSkeleton(height: 132, radius: 16);
    }
    if (items.isEmpty) {
      return StateSwap(stateKey: 'no-plan', child: _noPlan(training, p));
    }

    // THE SHARED WIDGET, not a layout this screen owns. My Plans renders the
    // identical section, and the coach's own words are the last thing that
    // should be phrased two ways in two places.
    return StateSwap(
      stateKey: 'plan',
      child: CoachRecommendedMeals(
        items: items,
        planName: (training.diet.value?['name'] ?? '').toString().trim(),
        note: (training.diet.value?['description'] ?? '').toString().trim(),
      ),
    );
  }

  Widget _noPlan(TrainingController training, AppPalette p) {
    final failed = training.error.value.isNotEmpty;
    if (failed) {
      return SerenaEmptyState(
        glyph: '📡',
        title: "Couldn't load your plan",
        body: 'This is a connection problem — your plan is safe and will be '
            'here when you reconnect.',
        actionLabel: 'Try again',
        onAction: training.load,
      );
    }
    return const SerenaEmptyState(
      glyph: '🥗',
      title: 'No diet assigned yet',
      // NOT a blocker, and the second sentence is why this state has no
      // button: logging works without a plan, so the member is not waiting on
      // anyone to start. An action here would imply they were.
      body: "Your coach hasn't assigned a nutrition plan yet — it will appear "
          'here automatically when they do. You can still log everything you '
          'eat below.',
    );
  }
}
