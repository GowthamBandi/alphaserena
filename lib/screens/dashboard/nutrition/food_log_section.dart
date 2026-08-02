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
import 'add_food_screen.dart';
import 'food_history_screen.dart' show entryAmountLabel;
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

  const FoodLogSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      if (controller.isLoading.value) return _skeleton(p);
      if (controller.loadError.value) return _error(p);

      final byMeal = controller.entriesByMeal;
      if (byMeal.isEmpty) return _empty(context, p);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _totals(p),
          const SizedBox(height: 16),
          for (final slot in [...kMealSlots, kOtherMealSlot])
            if (byMeal[slot] != null && byMeal[slot]!.isNotEmpty)
              _mealBlock(context, p, slot, byMeal[slot]!),
          _addMoreButton(context, p, label: 'Add more food'),
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
            Text('${controller.loggedCalories.round()}',
                style: AppText.display(size: 34)
                    .copyWith(color: const Color(0xFF2EBD59))),
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
          Text('${grams.toStringAsFixed(grams < 10 ? 1 : 0)} g',
              style:
                  AppText.cardTitle(size: 15).copyWith(color: p.textPrimary)),
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

  Widget _addMoreButton(
    BuildContext context,
    AppPalette p, {
    required String label,
  }) =>
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => Get.to(() => const AddFoodScreen()),
          style: OutlinedButton.styleFrom(
            foregroundColor: p.accent,
            side: BorderSide(color: p.accent.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(label, style: AppText.label(size: 14)),
        ),
      );

  Widget _empty(BuildContext context, AppPalette p) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: glassCard(p, radius: 18),
        child: Column(
          children: [
            Icon(Icons.restaurant_menu_rounded, size: 38, color: p.textMuted),
            const SizedBox(height: 12),
            Text('Nothing logged yet today',
                style:
                    AppText.cardTitle(size: 15).copyWith(color: p.textPrimary)),
            const SizedBox(height: 6),
            Text(
              'Log what you ACTUALLY ate. Your coach sees this next to the plan '
              'they built for you.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 13).copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 16),
            _addMoreButton(context, p, label: 'Add your first food'),
          ],
        ),
      );

  Widget _error(AppPalette p) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: glassCard(p, radius: 18),
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded, size: 36, color: p.textMuted),
            const SizedBox(height: 12),
            Text("Couldn't load today's food",
                style:
                    AppText.cardTitle(size: 15).copyWith(color: p.textPrimary)),
            const SizedBox(height: 6),
            // An error, NEVER the empty state: the empty state is a claim
            // about the member's behaviour, this is a claim about the network.
            Text(
              'This is a connection problem, not an empty day — anything you '
              'logged is still there.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 13).copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: controller.retry,
              style: OutlinedButton.styleFrom(foregroundColor: p.accent),
              child: const Text('Try again'),
            ),
          ],
        ),
      );

  Widget _skeleton(AppPalette p) => Column(
        children: [
          for (final h in [150.0, 70.0, 70.0])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                height: h,
                decoration: BoxDecoration(
                  color: p.isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFF1F3F7),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
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
