/// NIP PHASE 3A — PORTION ARITHMETIC, the member-side mirror of the backend's
/// `scaleHydratedMacros` (`functions/src/lib/nutrition.ts`).
///
/// WHY THIS LIVES ON THE CLIENT AT ALL. The `consumed` block on a logged entry
/// is FROZEN at log time — that is what makes a past day readable after a food
/// is re-costed, renamed or archived. The member is the one choosing the
/// portion, and the preview must update as they drag, so the client computes
/// the number it is about to store. The server cannot compute it after the
/// fact without re-reading a food that may have changed.
///
/// That makes this a cross-binary contract, and this codebase has already been
/// bitten by one: the two copies of `lifestyle_math.dart` drifted silently
/// once. So the fixtures in `test/food_portion_math_test.dart` are asserted
/// against values pinned in the backend's own `nutrition.test.mjs`
/// (`scaleHydratedMacros: scales per-100 by the item's grams`). A change to
/// either side fails on that side.
///
/// Pure and Firebase-free.
library;

/// The grams a food's stored nutrition is expressed per — the platform's
/// storage base (`FOOD_BASE_GRAMS`). A food row is "per 100 g" everywhere.
const double kFoodBaseGrams = 100;

/// The macro keys a consumed snapshot carries, in the backend's order
/// (`MACRO_FIELDS`). Calories ride along with the macros: a hydrated item used
/// to serve real macros and 0 kcal because they were scaled separately.
const List<String> kMacroFields = [
  'calories',
  'protein',
  'carbs',
  'fat',
  'fiber',
  'sugar',
  'saturatedFat',
];

/// One decimal place — the backend's `round1`. Mirrored exactly so a value
/// computed here and a value recomputed there are the same number, not two
/// numbers that agree to within a rounding error.
double round1(double v) => (v * 10).round() / 10;

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

/// How a quantity was expressed. Stored on the entry as `quantity` + `unit`,
/// so a coach reading the day sees "2 katori", not only the macros.
enum PortionMode {
  /// A named household portion — "1 katori", "2 roti".
  portion,

  /// Raw grams — "150 g".
  grams,
}

/// A household portion a food offers ("1 katori" = 150 g).
class FoodPortionOption {
  final String label;
  final double grams;

  const FoodPortionOption({required this.label, required this.grams});

  factory FoodPortionOption.fromMap(Map<String, dynamic> m) => FoodPortionOption(
        label: (m['label'] ?? '').toString().trim(),
        grams: _num(m['grams']),
      );

  bool get isUsable => label.isNotEmpty && grams > 0;
}

/// A chosen amount, resolved to the grams the macros will be scaled by.
class PortionSelection {
  final PortionMode mode;

  /// Portion mode: how many of [portionLabel]. Grams mode: the gram amount.
  final double quantity;

  /// The portion's label; empty in grams mode.
  final String portionLabel;

  /// Grams in ONE unit of the chosen portion; [kFoodBaseGrams] is irrelevant
  /// here — this is the food's own household measure.
  final double gramsPerPortion;

  const PortionSelection({
    required this.mode,
    required this.quantity,
    this.portionLabel = '',
    this.gramsPerPortion = 0,
  });

  /// A raw-grams selection.
  const PortionSelection.grams(double g)
      : mode = PortionMode.grams,
        quantity = g,
        portionLabel = '',
        gramsPerPortion = 0;

  /// Total grams this selection represents — the ONLY number the macros scale
  /// by, whichever way the member expressed it.
  double get totalGrams => switch (mode) {
        PortionMode.grams => quantity,
        PortionMode.portion => quantity * gramsPerPortion,
      };

  /// What is STORED as the entry's human-readable amount. A portion keeps its
  /// own label ("2" + "katori"); grams store the gram count with unit 'g'.
  double get storedQuantity => quantity;

  String get storedUnit =>
      mode == PortionMode.grams ? 'g' : portionLabel;

  /// Whether this selection may be logged at all.
  bool get isValid =>
      quantity > 0 &&
      totalGrams > 0 &&
      totalGrams <= kMaxEntryGrams &&
      (mode == PortionMode.grams || portionLabel.isNotEmpty);
}

/// Backend `MAX_ENTRY_GRAMS`. Mirrored so the UI can refuse locally instead of
/// letting the member log something the trigger will only flag afterwards.
const double kMaxEntryGrams = 5000;

/// Backend `MAX_ENTRY_CALORIES` — the trigger flags an entry above this.
const double kMaxEntryCalories = 5000;

/// Backend `MAX_ENTRIES_PER_DAY`. Past this the trigger truncates and flags
/// rather than stopping, but the UI should warn long before it gets there.
const int kMaxEntriesPerDay = 80;

/// Scales a food's per-100 g nutrition to an actual gram amount.
///
/// Mirrors `scaleHydratedMacros`: when [grams] is null or non-positive the
/// per-100 values are returned UNSCALED, matching the historical behaviour for
/// legacy per-serving items that carry no grams — no existing number moves.
Map<String, double> scaleMacros(Map<String, dynamic> per100, double? grams) {
  final factor = (grams != null && grams > 0) ? grams / kFoodBaseGrams : 1.0;
  return {
    for (final k in kMacroFields) k: round1(_num(per100[k]) * factor),
  };
}

/// Sums consumed snapshots — the client-side preview of what the server's
/// `computeDayTotals` will report for the same entries.
Map<String, double> sumMacros(Iterable<Map<String, double>> parts) {
  final out = {for (final k in kMacroFields) k: 0.0};
  for (final p in parts) {
    for (final k in kMacroFields) {
      out[k] = round1(out[k]! + (p[k] ?? 0));
    }
  }
  return out;
}
