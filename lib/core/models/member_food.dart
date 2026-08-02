/// NIP PHASE 3A — one searchable food, as the member receives it.
///
/// The wire shape of `MemberFoodCard` from the `searchMemberFoods` callable.
/// A member has NO read access to `foodDatabase` (the rules grant the org
/// library to its owning org and its trainers only), so this arrives already
/// projected, already tier-ordered and already deduped — the client's job is
/// to render it and compute a portion, never to decide which foods exist.
///
/// Pure and Firebase-free; parsing is tolerant so a card written by a newer
/// backend still renders on an older binary.
library;

import '../domain/food_portion_math.dart';

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

/// Which library a food came from. The member sees this: a coach-authored food
/// is the one their plan was built against, and saying so is what makes
/// choosing between two similar rows an informed choice rather than a guess.
enum MemberFoodTier { org, global }

class MemberFood {
  final String foodId;
  final String name;
  final String? brand;
  final MemberFoodTier tier;

  /// The authored serving label ("1 katori", "100 g"), or null.
  final String? serving;

  /// Nutrition per [kFoodBaseGrams] grams.
  final Map<String, double> per100;

  /// Household portions the food offers, already cleaned server-side.
  final List<FoodPortionOption> portions;

  /// 'official' marks a platform-curated food — a trust signal, not a filter.
  final String verification;

  /// Whether a real gram mass is known for this food's portions.
  ///
  /// True for anything from the library (portions carry their gram weight).
  /// False only when EDITING an entry logged before `grams` was stored, where
  /// the gram basis is a scaling pivot rather than a measurement — the sheet
  /// then declines to state a mass instead of showing a derived guess.
  final bool massKnown;

  const MemberFood({
    required this.foodId,
    required this.name,
    this.brand,
    this.tier = MemberFoodTier.global,
    this.serving,
    this.per100 = const {},
    this.portions = const [],
    this.verification = 'unverified',
    this.massKnown = true,
  });

  factory MemberFood.fromMap(Map<String, dynamic> m) {
    final rawPer100 = m['per100'];
    final rawPortions = m['portions'];
    return MemberFood(
      foodId: (m['foodId'] ?? '').toString(),
      name: (m['name'] ?? '').toString().trim(),
      brand: () {
        final b = (m['brand'] ?? '').toString().trim();
        return b.isEmpty ? null : b;
      }(),
      tier: m['tier']?.toString() == 'org'
          ? MemberFoodTier.org
          : MemberFoodTier.global,
      serving: () {
        final s = (m['serving'] ?? '').toString().trim();
        return s.isEmpty ? null : s;
      }(),
      per100: rawPer100 is Map
          ? {
              for (final k in kMacroFields) k: _num(rawPer100[k]),
            }
          : const {},
      portions: rawPortions is List
          ? rawPortions
              .whereType<Map>()
              .map((p) => FoodPortionOption.fromMap(Map<String, dynamic>.from(p)))
              .where((p) => p.isUsable)
              .toList()
          : const [],
      verification: (m['verification'] ?? 'unverified').toString(),
    );
  }

  /// Round-trips a card through the recents cache. Only what a card needs to
  /// be re-rendered and re-portioned — never a cached copy of a food document.
  Map<String, dynamic> toCache() => {
        'foodId': foodId,
        'name': name,
        if (brand != null) 'brand': brand,
        'tier': tier.name,
        if (serving != null) 'serving': serving,
        'per100': per100,
        'portions': [
          for (final p in portions) {'label': p.label, 'grams': p.grams},
        ],
        'verification': verification,
      };

  bool get isOfficial => verification == 'official';

  /// Calories in one [kFoodBaseGrams]-gram serving — the at-a-glance number on
  /// a search row.
  double get caloriesPer100 => per100['calories'] ?? 0;

  /// The default amount to preselect when the member opens this food.
  ///
  /// A named portion beats raw grams: "1 katori" is how the member thinks, and
  /// preselecting it means the common case is zero taps of adjustment. Falls
  /// back to a 100 g baseline, which is exactly what the stored numbers mean,
  /// so the preview is never a number the member has to reverse-engineer.
  PortionSelection get defaultSelection => portions.isNotEmpty
      ? PortionSelection(
          mode: PortionMode.portion,
          quantity: 1,
          portionLabel: portions.first.label,
          gramsPerPortion: portions.first.grams,
        )
      : const PortionSelection.grams(kFoodBaseGrams);
}
