import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/models/nutrition_day_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/glass_card.dart';
import 'add_food_screen.dart';

/// WHAT THE COACH TOLD THE MEMBER TO EAT — read only, shared by both surfaces.
///
/// Extracted from `DietScreen` when My Plans became the module's home. My Plans
/// is supposed to answer *"what has my trainer assigned me?"*, and on the Diet
/// tab it answered that with two number chips — `Plan items 2 · Meals 1` —
/// while the actual foods the coach prescribed lived on a different screen. The
/// member could see everything they had eaten and nothing they were asked to.
///
/// It is a shared WIDGET rather than a copied layout for the same reason
/// `FoodLogSection` is: two implementations of "the coach's plan" would drift,
/// and the coach's words are exactly the thing that must not be paraphrased
/// differently in two places.
///
/// **Read only, and contributes NOTHING to any total.** A recommendation is the
/// coach's statement; the member cannot amend it, and counting it would report
/// calories nobody ate.
class CoachRecommendedMeals extends StatelessWidget {
  /// The served `diet.items[]` — `getMyTraining`'s shape, verbatim.
  final List<Map<String, dynamic>> items;

  /// The coach's plan-level note (`diet.description`). Empty renders nothing.
  ///
  /// It is PLAN-level. The data model has no per-meal note, and inventing one
  /// would attribute words to a coach who never wrote them.
  final String note;

  /// The plan's name, when this section is the one naming it. My Plans passes
  /// '' because its hero card already does.
  final String planName;

  /// The colour of the per-meal "Log" action. Null follows the app's brand
  /// accent, which is correct on the Diet screen.
  ///
  /// My Plans passes its DIET-TAB green. The brand accent is red, and a red
  /// action button dropped into a green tab reads as a third accent competing
  /// with the tab's own identity — the same reason Home's red "Log Food" pill
  /// was kept off that tab. An action should wear the colour of the surface it
  /// sits on.
  final Color? accent;

  /// `foodId`s the member has ALREADY LOGGED today.
  ///
  /// This is what turns the section from a reference list into an answer to
  /// *"what do I still need?"* — the member's own question, which this screen
  /// could not answer at all.
  ///
  /// **A factual match, never an adherence score.** A marked food means "you
  /// logged this food today". It makes no claim about the AMOUNT, because the
  /// coach's portion and the member's are two different numbers and equating
  /// them would invent compliance the data does not support. Empty (the
  /// default) shows no markers, so the Diet screen is unchanged unless it
  /// opts in.
  final Set<String> loggedFoodIds;

  const CoachRecommendedMeals({
    super.key,
    required this.items,
    this.note = '',
    this.planName = '',
    this.accent,
    this.loggedFoodIds = const {},
  });

  static const Color _logged = Color(0xFF2EBD59);

  bool _isLogged(Map<String, dynamic> f) {
    if (loggedFoodIds.isEmpty) return false;
    final id = (f['foodId'] ?? '').toString();
    return id.isNotEmpty && loggedFoodIds.contains(id);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (items.isEmpty) return const SizedBox.shrink();

    // Grouped by the CANONICAL slug, so the coach's free-text meal labels
    // ("Mid-morning", legacy "Snacks") land in the same buckets the food log
    // uses. Without this the plan and the log would file one meal under two
    // different headings on the same screen.
    final byMeal = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      byMeal.putIfAbsent(canonicalMealSlot(item['meal']), () => []).add(item);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (planName.isNotEmpty || note.isNotEmpty)
          _planHeader(p, planName, note),
        // Canonical meal ORDER, not insertion order: breakfast before lunch
        // before dinner, whatever sequence the coach happened to author in.
        for (final slot in [...kMealSlots, kOtherMealSlot])
          if (byMeal[slot] != null && byMeal[slot]!.isNotEmpty)
            _meal(context, p, slot, byMeal[slot]!),
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
                  Icon(Icons.format_quote_rounded, size: 15, color: p.textMuted),
                  const SizedBox(width: 7),
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

  Widget _meal(
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

    final loggedHere = foods.where(_isLogged).length;
    final allLogged = loggedFoodIds.isNotEmpty && loggedHere == foods.length;

    // The coach's MACROS for this meal — served on every plan item and, until
    // now, summed nowhere: the member saw calories and nothing else. A macro
    // the plan does not carry is omitted rather than printed as a zero.
    String macroPart(String key, String label) {
      final v = sum(key);
      return v > 0 ? '${v.round()}g $label' : '';
    }

    final macroLine = [
      macroPart('protein', 'P'),
      macroPart('carbs', 'C'),
      macroPart('fat', 'F'),
    ].where((s) => s.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: glassCard(p, radius: 16).copyWith(
          border: allLogged
              ? Border.all(color: _logged.withValues(alpha: 0.35))
              : null,
        ),
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
                        (kMealLabels[slot] ?? 'Other').toUpperCase(),
                        style: AppText.label(size: 11)
                            .copyWith(color: p.textPrimary, letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('${sum('calories').round()} kcal',
                              style: AppText.body(size: 11)
                                  .copyWith(color: p.textMuted)),
                          if (macroLine.isNotEmpty)
                            Text(macroLine,
                                style: AppText.body(size: 11)
                                    .copyWith(color: p.textMuted)),
                          if (loggedFoodIds.isNotEmpty)
                            Text('$loggedHere of ${foods.length} logged',
                                style: AppText.body(size: 11).copyWith(
                                  color: allLogged ? _logged : p.textMuted,
                                  fontWeight: FontWeight.w600,
                                )),
                        ],
                      ),
                    ],
                  ),
                ),
                // The bridge from recommendation to log. It does NOT mark the
                // recommendation — it opens Add Food on this meal, so what
                // gets recorded is still a thing the member says they ate.
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: accent ?? p.accent,
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
            for (final f in foods) _food(p, f),
          ],
        ),
      ),
    );
  }

  Widget _food(AppPalette p, Map<String, dynamic> f) {
    final logged = _isLogged(f);
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
            child: logged
                ? const Icon(Icons.check_circle_rounded,
                    size: 13, color: _logged)
                : Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.all(4),
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
                    style:
                        AppText.body(size: 13.5).copyWith(color: p.textPrimary)),
                if (amount.isNotEmpty)
                  Text(amount,
                      style:
                          AppText.body(size: 11.5).copyWith(color: p.textMuted)),
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
}
