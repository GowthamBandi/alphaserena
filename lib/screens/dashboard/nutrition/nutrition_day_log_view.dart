import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/domain/nutrition_history.dart';
import '../../../core/models/nutrition_day_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';


/// ONE DAY'S FOOD, EXACTLY AS IT WAS LOGGED.
///
/// The nutrition twin of `WorkoutDayLogView`, and built to the same rule:
///
/// **Nothing here is computed to fill a gap.** Every figure is summed from the
/// entries' FROZEN `consumed` snapshots — the macros as they stood when the
/// member logged them — so a coach editing a food's macros tomorrow can never
/// rewrite what someone ate today. A meal nobody logged is absent, not an
/// empty row. A meal with no stated time shows no time rather than the
/// document's write time, which is a different fact.
///
/// ── WHY THE MEALS ARE A TIMELINE AND NOT A TABLE ──────────────────────────
///
/// A fixed six-row grid (Breakfast … Bedtime) with four "—" rows is a FORM: it
/// asks the member what they failed to log. A member's day is a sequence of
/// things they actually ate, so only the meals with food in them render, in
/// the canonical slot order, each carrying its own total and time. The absence
/// of Bedtime is not information worth four rows of the screen.
class NutritionDayLogView extends StatelessWidget {
  final NutritionDayLog log;

  /// Opens the Food Log for editing. Null for any day that is not today — see
  /// the caller. History is a record; only the open day is editable, exactly
  /// as in Workout History.
  final VoidCallback? onEdit;

  const NutritionDayLogView({super.key, required this.log, this.onEdit});

  static const Color _accent = Color(0xFF1F9E55);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summary(p),
        const SizedBox(height: 16),
        Text('MEALS',
            style: AppText.label(size: 11)
                .copyWith(color: p.textMuted, letterSpacing: 1.0)),
        const SizedBox(height: 10),
        for (final meal in log.meals) _meal(p, meal),
        if (onEdit != null) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 17),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.textPrimary,
                side: BorderSide(color: p.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              // Shrinks rather than clipping — the same measurement the
              // workout twin's button is built around: at 2.0x accessibility
              // text on a 320dp phone the label plus its icon wants more than
              // the card can give, and a primary action that paints an
              // overflow stripe over its own name is not a primary action.
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Edit Food Log',
                    maxLines: 1,
                    style: AppText.label(size: 13.5)
                        .copyWith(color: p.textPrimary)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── THE DAY'S OWN TOTALS ─────────────────────────────────────────────────

  Widget _summary(AppPalette p) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: glassCard(p, radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('EEEE, d MMMM y').format(log.date),
                        style: AppText.cardTitle(size: 15)
                            .copyWith(color: p.textPrimary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _entryLine(),
                        style: AppText.body(size: 12)
                            .copyWith(color: p.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Calories lead because they are the figure the member and
                // their coach both quote. The unit is a caption, not a
                // same-size word competing with the number.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${log.calories.round()}',
                        style: AppText.display(size: 22)
                            .copyWith(color: _accent)),
                    Text('kcal',
                        style: AppText.body(size: 10.5)
                            .copyWith(color: p.textMuted)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Wrap, not Row: five macros at 2.0x accessibility text on a 320dp
            // phone do not fit one line, and a figure that overflows its own
            // card is worse than one that wraps.
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                _macro(p, 'Protein', log.protein),
                _macro(p, 'Carbs', log.carbs),
                _macro(p, 'Fat', log.fat),
                _macro(p, 'Fiber', log.fiber),
              ],
            ),
          ],
        ),
      );

  String _entryLine() {
    final n = log.entryCount;
    final meals = log.meals.length;
    return '$n ${n == 1 ? 'item' : 'items'}  ·  '
        '$meals ${meals == 1 ? 'meal' : 'meals'}';
  }

  Widget _macro(AppPalette p, String label, double grams) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.body(size: 10.5).copyWith(color: p.textMuted)),
          const SizedBox(height: 1),
          Text(formatMacroGrams(grams),
              style:
                  AppText.cardTitle(size: 14).copyWith(color: p.textPrimary)),
        ],
      );

  // ── ONE MEAL ─────────────────────────────────────────────────────────────

  Widget _meal(AppPalette p, MealGroup meal) {
    final time = meal.time;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: glassCard(p, radius: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    meal.label,
                    style: AppText.cardTitle(size: 14)
                        .copyWith(color: p.textPrimary),
                  ),
                ),
                // The time the member said they ATE, when they said one.
                // Absent rather than fabricated from the write time.
                if (time != null) ...[
                  Text(DateFormat('h:mm a').format(time),
                      style: AppText.body(size: 11.5)
                          .copyWith(color: p.textMuted)),
                  const SizedBox(width: 10),
                ],
                Text('${meal.calories.round()} kcal',
                    style: AppText.cardTitle(size: 13)
                        .copyWith(color: _accent)),
              ],
            ),
            const SizedBox(height: 10),
            for (final e in meal.entries) _entry(p, e),
          ],
        ),
      ),
    );
  }

  Widget _entry(AppPalette p, FoodEntry e) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // SNAPSHOTTED at log time, so a renamed or deleted library
                    // food never turns a past day into a list of ids.
                    e.foodName.isEmpty ? 'Food' : e.foodName,
                    style: AppText.body(size: 13)
                        .copyWith(color: p.textPrimary),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    // `entryAmountLabel` is the Food Log's own formatter —
                    // reused, not reimplemented, so "1.5 egg" reads the same
                    // in history as it does on the day it was logged.
                    entryAmountLabel(e),
                    style:
                        AppText.body(size: 11).copyWith(color: p.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('${e.consumed.calories.round()} kcal',
                style: AppText.body(size: 12.5)
                    .copyWith(color: p.textSecondary)),
          ],
        ),
      );
}

/// Grams, at the precision the figure deserves.
///
/// Under 10 g one decimal carries real information (3.2 g of fiber is not
/// 3 g); above it the decimal is noise on a number nobody measured that
/// precisely. The same rule `food_history_screen` already applies, lifted here
/// so both surfaces round one fact one way.
String formatMacroGrams(double g) =>
    '${g.toStringAsFixed(g < 10 ? 1 : 0)} g';
