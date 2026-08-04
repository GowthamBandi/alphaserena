import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../controllers/food_log_controller.dart';
import '../../../core/domain/food_portion_math.dart';
import '../../../core/models/member_food.dart';
import '../../../core/models/nutrition_day_model.dart';
import '../../../core/services/nutrition_day_service.dart' show DietSaveResult;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/serena/premium_states.dart';
import 'add_food_screen.dart';

import 'food_quantity_sheet.dart';

/// PHASE 3B — TODAY'S FOOD LOG, as a section of the Diet screen.
///
/// Extracted from the standalone Food Log screen when the Diet screen became
/// the single home of the nutrition journey. It is a SECTION, not a screen,
/// precisely so there is exactly one surface showing today's log: two would be
/// two owners of the same question, and the member would have to work out
/// which one is current.
///
/// Owns the whole mutation surface — add, edit, soft delete, undo — because
/// those belong beside the rows they change.
class FoodLogSection extends StatelessWidget {
  final FoodLogController controller;

  /// Whether to render the "Logged today" totals card above the meals.
  ///
  /// True on the Diet screen, where it is the only statement of the day's
  /// totals. FALSE on My Plans, where `NutritionProgressCard` sits directly
  /// above this section and states the same four macros *against the coach's
  /// targets* — so the totals card would repeat all five figures a few hundred
  /// pixels lower with strictly less information. The meals themselves are the
  /// reason this section is on that screen.
  final bool showTotals;

  const FoodLogSection({
    super.key,
    required this.controller,
    this.showTotals = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      if (controller.isLoading.value) {
        return StateSwap(stateKey: 'skeleton', child: _skeleton(p));
      }
      if (controller.loadError.value) {
        return StateSwap(stateKey: 'error', child: _error(p));
      }

      final byMeal = controller.entriesByMeal;
      if (byMeal.isEmpty) {
        return StateSwap(stateKey: 'empty', child: _empty(context, p));
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTotals) ...[
            _totals(p),
            const SizedBox(height: 16),
          ] else if (controller.hasQueuedWrites.value)
            // The totals card normally carries the "Syncing" indicator. Hiding
            // the card must not hide the fact that writes are still queued —
            // that is the member's assurance their food is safe offline.
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_queue_rounded, size: 14, color: p.textMuted),
                  const SizedBox(width: 4),
                  Text('Syncing',
                      style:
                          AppText.body(size: 11).copyWith(color: p.textMuted)),
                ],
              ),
            ),
          for (final slot in [...kMealSlots, kOtherMealSlot])
            if (byMeal[slot] != null && byMeal[slot]!.isNotEmpty)
              _mealBlock(context, p, slot, byMeal[slot]!),
          // No trailing "Add more food" button: the screen's FAB already says
          // "+ Add food" and every meal header carries its own "+". A third
          // control for the same action is the one a member has to think about.
        ],
      );
    });
  }

  // ── TOTALS ───────────────────────────────────────────────────────────────

  Widget _totals(AppPalette p) => Container(
        padding: const EdgeInsets.all(18),
        decoration: glassCard(p, radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Logged today',
                      style: AppText.cardTitle(size: 14)
                          .copyWith(color: p.textPrimary)),
                ),
                if (controller.hasQueuedWrites.value)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_queue_rounded,
                          size: 14, color: p.textMuted),
                      const SizedBox(width: 4),
                      // NOT an error: the entries are in the local cache and
                      // Firestore replays them on reconnect.
                      Text('Syncing',
                          style: AppText.body(size: 11)
                              .copyWith(color: p.textMuted)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // This is the number the member came here to change. It is the
            // one figure in the app that moves BECAUSE of something they just
            // did, so it is the last one that should arrive by teleporting.
            AnimatedCount(
              value: controller.loggedCalories,
              builder: (context, shown) => Text(
                '${(shown ?? 0).round()}',
                style: AppText.display(size: 34).copyWith(
                  color: const Color(0xFF2EBD59),
                  fontFeatures: kTabularFigures,
                ),
              ),
            ),
            Text(
              'kcal from ${controller.entryCount} '
              '${controller.entryCount == 1 ? 'item' : 'items'}',
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _macro(p, 'Protein', controller.loggedProtein),
                _macro(p, 'Carbs', controller.loggedCarbs),
                _macro(p, 'Fat', controller.loggedFat),
                _macro(p, 'Fiber', controller.loggedFiber),
              ],
            ),
          ],
        ),
      );

  Widget _macro(AppPalette p, String label, double grams) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.body(size: 11).copyWith(color: p.textMuted)),
          const SizedBox(height: 2),
          AnimatedCount(
            value: grams,
            builder: (context, shown) {
              final g = shown ?? 0;
              // The decimal place is chosen from the REAL total, not the
              // frame: deriving it from `g` would flip "9.4" to "10" and back
              // mid-count, which reads as the number stuttering.
              return Text(
                '${g.toStringAsFixed(grams < 10 ? 1 : 0)} g',
                style: AppText.cardTitle(size: 15).copyWith(
                  color: p.textPrimary,
                  fontFeatures: kTabularFigures,
                ),
              );
            },
          ),
        ],
      );

  // ── MEALS ────────────────────────────────────────────────────────────────

  Widget _mealBlock(
    BuildContext context,
    AppPalette p,
    String slot,
    List<FoodEntry> entries,
  ) {
    final totals = controller.totalsForMeal(slot);
    final startedAt = mealStartedAt(entries);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The meal name, its figures and the add control STACK rather than
          // share one row. At 2.0x accessibility text the single-row version
          // overflowed by up to 138px — a meal heading is exactly the place a
          // member with large type needs the layout to yield.
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
                          .copyWith(color: p.textMuted, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 10,
                      children: [
                        Text('${(totals['calories'] ?? 0).round()} kcal',
                            style: AppText.body(size: 11)
                                .copyWith(color: p.textMuted)),
                        if (startedAt != null)
                          // DERIVED from the earliest entry in the meal, never
                          // stored: a stored copy could disagree with the
                          // entries it summarises.
                          Text(
                            DateFormat('h:mm a').format(
                              DateTime.fromMillisecondsSinceEpoch(startedAt),
                            ),
                            style: AppText.body(size: 11)
                                .copyWith(color: p.textMuted),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Add to ${kMealLabels[slot] ?? 'meal'}',
                icon: Icon(Icons.add_rounded, size: 20, color: p.accent),
                onPressed: () =>
                    Get.to(() => AddFoodScreen(initialMealSlot: slot)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final e in entries) _entryRow(context, p, e),
        ],
      ),
    );
  }

  Widget _entryRow(BuildContext context, AppPalette p, FoodEntry e) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Dismissible(
          key: ValueKey(e.entryId),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 18),
            decoration: BoxDecoration(
              color: p.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.delete_outline_rounded, color: p.error),
          ),
          onDismissed: (_) => _remove(context, e),
          child: Semantics(
            button: true,
            label: '${e.foodName}, ${entryAmountLabel(e)}, '
                '${e.consumed.calories.round()} calories. Tap to edit.',
            excludeSemantics: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _edit(context, e),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: glassCard(p, radius: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              // The SNAPSHOTTED label: a food renamed or
                              // removed from the library since does not turn
                              // this row into an id.
                              e.foodName.isEmpty ? 'Food' : e.foodName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.cardTitle(size: 14)
                                  .copyWith(color: p.textPrimary),
                            ),
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  entryAmountLabel(e),
                                  style: AppText.body(size: 12)
                                      .copyWith(color: p.textMuted),
                                ),
                                _sourceChip(p, e),
                              ],
                            ),
                            if (e.note != null) ...[
                              const SizedBox(height: 4),
                              Text(e.note!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.body(size: 11.5)
                                      .copyWith(color: p.textMuted)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text('${e.consumed.calories.round()} kcal',
                            textAlign: TextAlign.end,
                            style: AppText.cardTitle(size: 14)
                                .copyWith(color: p.textPrimary)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  /// WHERE the food came from. `foodTier` names the library; `source` names how
  /// it reached the day. Both are stored, and the member sees the one that
  /// answers "is this my coach's food?".
  Widget _sourceChip(AppPalette p, FoodEntry e) {
    final isOrg = e.foodTier == FoodTier.org;
    final color = isOrg ? p.accent : const Color(0xFF3B82F6);
    final label = switch (e.source) {
      FoodEntrySource.plan => 'From plan',
      _ => isOrg ? "Coach's" : 'Library',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label,
          style: AppText.body(size: 10)
              .copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }

  // ── MUTATIONS ────────────────────────────────────────────────────────────

  Future<void> _remove(BuildContext context, FoodEntry e) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await controller.removeEntry(e);
    if (result == DietSaveResult.failed) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Could not remove ${e.foodName}.'),
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }
    // SOFT delete, so Undo restores the SAME entry — not a re-creation under a
    // new id with a new timestamp, which would reorder the member's meal.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${e.foodName} removed'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => controller.restoreEntry(e),
        ),
      ));
  }

  Future<void> _edit(BuildContext context, FoodEntry e) async {
    // Rebuild the per-100 basis from the FROZEN snapshot and the STORED mass —
    // never by re-reading the food, which may have been re-costed since.
    final grams = gramsOfEntry(e);
    if (grams <= 0) return;
    final knowsMass = e.grams != null && e.grams! > 0;
    final isGrams = e.unit == 'g';
    final factor = kFoodBaseGrams / grams;
    final per100 = {
      'calories': e.consumed.calories * factor,
      'protein': e.consumed.protein * factor,
      'carbs': e.consumed.carbs * factor,
      'fat': e.consumed.fat * factor,
      'fiber': e.consumed.fiber * factor,
      'sugar': e.consumed.sugar * factor,
      'saturatedFat': e.consumed.saturatedFat * factor,
    };
    final food = MemberFood(
      foodId: e.foodId ?? '',
      name: e.foodName.isEmpty ? 'Food' : e.foodName,
      tier: e.foodTier == FoodTier.org
          ? MemberFoodTier.org
          : MemberFoodTier.global,
      per100: per100,
      portions: [
        if (!isGrams && e.quantity != null && e.quantity! > 0)
          FoodPortionOption(label: e.unit, grams: grams / e.quantity!),
      ],
      // A legacy entry carries no recorded mass; the sheet then declines to
      // state one rather than showing a figure derived from an assumption.
      massKnown: knowsMass || isGrams,
    );

    if (!context.mounted) return;
    final result = await showModalBottomSheet<FoodQuantityResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FoodQuantitySheet(
        food: food,
        mealSlot: e.mealSlot,
        isEdit: true,
        initialNote: e.note,
        initialSelection: isGrams
            ? PortionSelection.grams(grams)
            : PortionSelection(
                mode: PortionMode.portion,
                quantity: e.quantity ?? 1,
                portionLabel: e.unit,
                gramsPerPortion: grams / (e.quantity ?? 1),
              ),
      ),
    );
    if (result == null) return;
    await controller.editEntry(
      entry: e,
      per100: per100,
      selection: result.selection,
      mealSlot: result.mealSlot,
    );
  }

  // ── STATES ───────────────────────────────────────────────────────────────

  /// TODAY HAS NOT STARTED — not "no data".
  ///
  /// The distinction the copy has to carry: nothing is missing, nothing has
  /// failed, and the member is one tap from the whole feature working. So it
  /// names what the screen will DO for them once they start, rather than
  /// reporting the absence of rows.
  Widget _empty(BuildContext context, AppPalette p) => SerenaEmptyState(
        glyph: '\u{1F37D}\u{FE0F}',
        title: "Today's nutrition hasn't started",
        body: "Log your first meal and we'll track calories, protein, carbs "
            'and fats through your day — and your coach sees it next to the '
            'plan they built for you.',
        actionLabel: 'Log First Meal',
        onAction: () => Get.to(() => const AddFoodScreen()),
      );

  Widget _error(AppPalette p) => SerenaEmptyState(
        glyph: '\u{1F4E1}',
        title: "Couldn't load today's food",
        // An error, NEVER the empty state: the empty state is a claim about
        // the member's behaviour, this is a claim about the network.
        body: 'This is a connection problem, not an empty day — anything you '
            'logged is still there.',
        actionLabel: 'Try again',
        onAction: controller.retry,
      );

  Widget _skeleton(AppPalette p) => Column(
        children: [
          for (final h in [150.0, 70.0, 70.0])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SerenaSkeleton(height: h, radius: 16),
            ),
        ],
      );
}

/// Total grams an entry represents.
///
/// The STORED mass when the entry has one, then the direct value for a
/// grams-unit entry. A LEGACY portion entry (logged before `grams` existed) has
/// neither, so it falls back to a 100 g basis purely as a scaling pivot — the
/// reparameterization is exact, so re-scaling the count stays correct, and the
/// caller passes `massKnown: false` so no figure derived from that pivot is
/// ever shown or written back.
double gramsOfEntry(FoodEntry e) {
  if (e.grams != null && e.grams! > 0) return e.grams!;
  if (e.quantity == null || e.quantity! <= 0) return 0;
  if (e.unit == 'g') return e.quantity!;
  return kFoodBaseGrams;
}
