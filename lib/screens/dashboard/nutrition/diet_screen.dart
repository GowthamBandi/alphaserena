import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/food_log_controller.dart';
import '../../../controllers/training_controller.dart';
import '../../../core/models/nutrition_day_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';
import 'add_food_screen.dart';
import 'food_history_screen.dart';
import 'food_log_section.dart';

/// PHASE 3B — THE DIET SCREEN. The whole nutrition journey, in one place.
///
/// Three sections, in the order the member needs them:
///
///   1. COACH RECOMMENDED MEALS — what they SHOULD eat. **Read only.** A
///      recommendation is the coach's statement and the member cannot amend
///      it; it also contributes NOTHING to any total, because nobody has
///      eaten it yet.
///   2. TODAY'S FOOD LOG — what they ACTUALLY ate. The only input, and the
///      only source of nutrition totals.
///   3. PREVIOUS DAYS — the same log, historically, read-only.
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
            const SizedBox(height: 28),
            _previousDays(p),
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

    // Grouped by the CANONICAL slug, so the coach's free-text meal labels
    // ("Mid-morning", legacy "Snacks") land in the same buckets the food log
    // uses. Without this the two halves of this screen would file the same
    // meal under two different headings.
    final byMeal = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      byMeal
          .putIfAbsent(canonicalMealSlot(item['meal']), () => [])
          .add(item);
    }

    final planName = (training.diet.value?['name'] ?? '').toString().trim();
    final note = (training.diet.value?['description'] ?? '').toString().trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (planName.isNotEmpty || note.isNotEmpty)
          _planHeader(p, planName, note),
        for (final slot in [...kMealSlots, kOtherMealSlot])
          if (byMeal[slot] != null && byMeal[slot]!.isNotEmpty)
            _recommendedMeal(context, p, slot, byMeal[slot]!),
      ],
    );
  }

  Widget _planHeader(AppPalette p, String planName, String note) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: glassCard(p, radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (planName.isNotEmpty)
              Text(planName,
                  style: AppText.cardTitle(size: 15)
                      .copyWith(color: p.textPrimary)),
            if (note.isNotEmpty) ...[
              if (planName.isNotEmpty) const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote_rounded,
                      size: 15, color: p.textMuted),
                  const SizedBox(width: 7),
                  // The coach's note. It is PLAN-level — the data model has no
                  // per-meal note, and inventing one would attribute words to
                  // a coach who never wrote them.
                  Expanded(
                    child: Text(note,
                        style: AppText.body(size: 12.5)
                            .copyWith(color: p.textSecondary)),
                  ),
                ],
              ),
            ],
          ],
        ),
      );

  Widget _recommendedMeal(
    BuildContext context,
    AppPalette p,
    String slot,
    List<Map<String, dynamic>> foods,
  ) {
    double sum(String key) {
      var t = 0.0;
      for (final f in foods) {
        final v = f[key];
        if (v is num) t += v.toDouble();
        if (v is String) t += double.tryParse(v) ?? 0;
      }
      return t;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: glassCard(p, radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stacked for the same reason as the log's meal header: at large
            // text scales the name, the figure and the action cannot share a
            // row without one of them being clipped.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (kMealLabels[slot] ?? 'Other').toUpperCase(),
                        style: AppText.label(size: 11)
                            .copyWith(color: p.textPrimary, letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 2),
                      Text('${sum('calories').round()} kcal',
                          style: AppText.body(size: 11)
                              .copyWith(color: p.textMuted)),
                    ],
                  ),
                ),
                // The bridge from recommendation to log. It does NOT mark the
                // recommendation — it opens Add Food on this meal, so what
                // gets recorded is still a thing the member says they ate.
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: p.accent,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () =>
                      Get.to(() => AddFoodScreen(initialMealSlot: slot)),
                  child: Text('Log', style: AppText.label(size: 12.5)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final f in foods) _recommendedFood(p, f),
          ],
        ),
      ),
    );
  }

  Widget _recommendedFood(AppPalette p, Map<String, dynamic> f) {
    final name = (f['name'] ?? 'Food').toString();
    // The coach's own words for the amount, shown verbatim. Where a portion
    // was authored it is preferred, because that is what the coach chose;
    // grams are the fallback the builder stores alongside it.
    final quantity = (f['quantity'] ?? '').toString().trim();
    final grams = f['grams'];
    final amount = quantity.isNotEmpty
        ? quantity
        : (grams is num && grams > 0 ? '${grams.round()} g' : '');
    final kcal = f['calories'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: p.textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: AppText.body(size: 13.5)
                        .copyWith(color: p.textPrimary)),
                if (amount.isNotEmpty)
                  Text(amount,
                      style: AppText.body(size: 11.5)
                          .copyWith(color: p.textMuted)),
              ],
            ),
          ),
          if (kcal is num && kcal > 0)
            Flexible(
              child: Text('${kcal.round()} kcal',
                  textAlign: TextAlign.end,
                  style: AppText.body(size: 12).copyWith(color: p.textMuted)),
            ),
        ],
      ),
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

  // ── SECTION 3 — PREVIOUS DAYS ────────────────────────────────────────────

  Widget _previousDays(AppPalette p) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Get.to(() => const FoodHistoryScreen()),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: glassCard(p, radius: 16),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 20, color: p.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Previous days',
                          style: AppText.cardTitle(size: 14)
                              .copyWith(color: p.textPrimary)),
                      const SizedBox(height: 2),
                      Text('Everything you have logged before today',
                          style: AppText.body(size: 12)
                              .copyWith(color: p.textMuted)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: p.textMuted),
              ],
            ),
          ),
        ),
      );
}
