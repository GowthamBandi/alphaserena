/// NIP PHASE B WIRE CONTRACT — the member-side mirror of
/// `client_nutrition_days/{clientId}_{yyyy-MM-dd}` (NOT written in Phase A).
///
/// Shipped ahead of the collection so the UI can bind to typed models now and
/// Phase B only swaps the repository implementation — no schema change lands
/// on screens later. Mirrors the backend's pure core (`lib/nutrition.ts`):
/// `entries` is a MAP keyed by entryId (never an array), each entry carries a
/// FROZEN `consumed` snapshot (historical truth — later food/plan edits can
/// never change it), and `computed` is SERVER-written and read-only here (the
/// client parses it, never serializes it back).
///
/// Pure and Firebase-free. Parsing is tolerant: unknown fields are ignored,
/// malformed values coerce to safe defaults, nothing throws — a member's day
/// must render even when a doc predates (or postdates) this binary.
library;

double _toNum(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

double? _toNumOrNull(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}


/// MEAL VOCABULARY — the client mirror of the backend's canonical taxonomy
/// (`MEAL_SLOTS` / `MEAL_LABELS` / `canonicalMealSlot` in
/// `functions/src/lib/nutrition.ts`). Pinned against it by twin tests.
///
/// SLUGS ARE STORED, LABELS ARE RENDERED. `mealSlot` used to be free text, so
/// a typo made a phantom meal and a rename was a data migration — the platform
/// is renaming "Mid-morning" to "Mid-Morning Snack" right now, and because the
/// stored value is `mid_morning` that rename touches no document.
const List<String> kMealSlots = [
  'breakfast',
  'mid_morning',
  'lunch',
  'evening_snack',
  'dinner',
  'bedtime',
];

const String kOtherMealSlot = 'other';

/// The ONLY place a human-facing meal name is written on this side.
const Map<String, String> kMealLabels = {
  'breakfast': 'Breakfast',
  'mid_morning': 'Mid-Morning Snack',
  'lunch': 'Lunch',
  'evening_snack': 'Evening Snack',
  'dinner': 'Dinner',
  'bedtime': 'Bedtime',
  'other': 'Other',
};

/// Keys are already normalized (lowercased, non-alphanumerics dropped).
const Map<String, String> _kMealAliases = {
  'breakfast': 'breakfast',
  'morningbreakfast': 'breakfast',
  'earlymorning': 'breakfast',
  'midmorning': 'mid_morning',
  'midmorningsnack': 'mid_morning',
  'morningsnack': 'mid_morning',
  'brunch': 'mid_morning',
  'lunch': 'lunch',
  'afternoon': 'lunch',
  'eveningsnack': 'evening_snack',
  'snacks': 'evening_snack',
  'snack': 'evening_snack',
  'teatime': 'evening_snack',
  'evening': 'evening_snack',
  'dinner': 'dinner',
  'supper': 'dinner',
  'bedtime': 'bedtime',
  'beforebed': 'bedtime',
  'nightcap': 'bedtime',
  'postdinner': 'bedtime',
};

/// Any spelling in, a canonical slug out. Unknown input becomes
/// [kOtherMealSlot] — a member's food is filed, never lost to a typo.
String canonicalMealSlot(Object? raw) {
  final key =
      raw.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (key.isEmpty) return kOtherMealSlot;
  return _kMealAliases[key] ?? kOtherMealSlot;
}

/// Canonical display order; `other` always sorts last.
int mealSlotOrder(String slot) {
  final i = kMealSlots.indexOf(slot);
  return i == -1 ? kMealSlots.length : i;
}

/// The meal's time = the EARLIEST entry logged in it, or null when no entry
/// stated one. Derived, never stored: a stored copy could disagree with the
/// entries it summarises.
int? mealStartedAt(Iterable<FoodEntry> entriesInMeal) {
  int? earliest;
  for (final e in entriesInMeal) {
    final t = e.loggedAt;
    if (t == null || e.deleted) continue;
    if (earliest == null || t < earliest) earliest = t;
  }
  return earliest;
}

/// How an entry got onto the day (backend `ENTRY_SOURCES`).
enum FoodEntrySource { plan, search, custom, quick }

/// Mark on a plan-sourced entry (backend `PLAN_STATUSES`).
enum PlanEntryStatus { eaten, partial, skipped, swapped }

/// Which library a food came from (backend `FOOD_TIERS`).
///
/// Orthogonal to [FoodEntrySource], which says how the entry got onto the day:
/// an org-library food can arrive via the plan OR via a search, so one field
/// cannot answer both. Null for custom/quick entries with no library food.
enum FoodTier { org, global }

FoodTier? _tierFrom(dynamic v) => switch (v?.toString()) {
      'org' => FoodTier.org,
      'global' => FoodTier.global,
      _ => null,
    };

FoodEntrySource _sourceFrom(dynamic v) => switch (v?.toString()) {
      'plan' => FoodEntrySource.plan,
      'search' => FoodEntrySource.search,
      'custom' => FoodEntrySource.custom,
      // Backend rule: an unknown source parses as 'quick', never dropped.
      _ => FoodEntrySource.quick,
    };

PlanEntryStatus? _statusFrom(dynamic v) => switch (v?.toString()) {
      'eaten' => PlanEntryStatus.eaten,
      'partial' => PlanEntryStatus.partial,
      'skipped' => PlanEntryStatus.skipped,
      'swapped' => PlanEntryStatus.swapped,
      _ => null,
    };

/// The frozen consumed-nutrition snapshot (backend `MacroTotals`): what the
/// member actually consumed for this entry, stamped at log time.
class ConsumedSnapshot {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final double sugar;
  final double saturatedFat;

  const ConsumedSnapshot({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fiber = 0,
    this.sugar = 0,
    this.saturatedFat = 0,
  });

  factory ConsumedSnapshot.fromMap(Map<String, dynamic> m) => ConsumedSnapshot(
        calories: _toNum(m['calories']),
        protein: _toNum(m['protein']),
        carbs: _toNum(m['carbs']),
        fat: _toNum(m['fat']),
        fiber: _toNum(m['fiber']),
        sugar: _toNum(m['sugar']),
        saturatedFat: _toNum(m['saturatedFat']),
      );

  Map<String, dynamic> toMap() => {
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'fiber': fiber,
        'sugar': sugar,
        'saturatedFat': saturatedFat,
      };
}

/// One logged food entry (backend `DayEntry`), keyed by [entryId] in the
/// day doc's `entries` map.
class FoodEntry {
  final String entryId;
  final FoodEntrySource source;

  /// The prescribed plan entry this mark belongs to (plan-sourced only).
  final String? planEntryId;

  /// Library food identity; null for freehand/custom entries.
  final String? foodId;

  /// The food's label, SNAPSHOTTED at log time — so a renamed, archived or
  /// deleted library food never turns a past day into a list of ids. The same
  /// discipline the frozen [consumed] macros beside it already follow.
  final String foodName;

  /// Which library the food came from; null for custom/quick entries.
  final FoodTier? foodTier;

  final String mealSlot;

  /// How much was eaten in human terms — 150 + 'g', or 1 + 'katori'.
  /// [portionFactor] is a multiplier against a prescription and cannot express
  /// a freely logged amount. Null when the member only marked a plan item.
  final double? quantity;
  final String unit;

  /// The MASS this entry represents, in grams. Null when unknown.
  ///
  /// [quantity] + [unit] cannot answer "how much was that?" for a named
  /// portion — "2 katori" is only 300 g if you also know a katori is 150 g,
  /// and that lives in the food document, which may change afterwards. Without
  /// it the edit path had to FABRICATE a gram basis: the calories stayed
  /// correct (the reparameterization is exact) but every gram figure shown was
  /// wrong, and switching such an edit to grams mode wrote the fabricated
  /// number back as the member's amount.
  ///
  /// Absent on entries written before this field existed; they read as unknown
  /// and the UI declines to state a mass rather than inventing one.
  final double? grams;

  final ConsumedSnapshot consumed;

  /// eaten|partial|skipped|swapped for plan-sourced entries, else null.
  final PlanEntryStatus? planStatus;

  /// Fraction of the prescription consumed for `partial` (backend default 0.5).
  final double? portionFactor;

  /// When the food was actually EATEN (epoch ms) — distinct from when the
  /// document was written. Null when the member stated no time.
  final int? loggedAt;

  /// The member's own note on this entry.
  final String? note;

  /// Soft delete — analytics skip it; the data is never destroyed.
  final bool deleted;

  const FoodEntry({
    required this.entryId,
    this.source = FoodEntrySource.quick,
    this.planEntryId,
    this.foodId,
    this.foodName = '',
    this.foodTier,
    this.mealSlot = kOtherMealSlot,
    this.quantity,
    this.unit = '',
    this.grams,
    this.consumed = const ConsumedSnapshot(),
    this.planStatus,
    this.portionFactor,
    this.loggedAt,
    this.note,
    this.deleted = false,
  });

  factory FoodEntry.fromMap(String entryId, Map<String, dynamic> m) {
    final rawConsumed = m['consumed'];
    final rawFoodId = m['foodId']?.toString() ?? '';
    return FoodEntry(
      entryId: entryId,
      source: _sourceFrom(m['source']),
      planEntryId: m['planEntryId']?.toString(),
      // Backend rule: '' is "no library food" and parses to null.
      foodId: rawFoodId.isEmpty ? null : rawFoodId,
      // Backend truncates at MAX_FOOD_NAME; mirrored so a long label can never
      // round-trip to a different value than the server stored.
      foodName: (m['foodName'] ?? '').toString().trim(),
      foodTier: _tierFrom(m['foodTier']),
      mealSlot: canonicalMealSlot(m['mealSlot']),
      quantity: _toNumOrNull(m['quantity']),
      unit: (m['unit'] ?? '').toString().trim(),
      grams: _toNumOrNull(m['grams']),
      consumed: rawConsumed is Map
          ? ConsumedSnapshot.fromMap(Map<String, dynamic>.from(rawConsumed))
          : const ConsumedSnapshot(),
      planStatus: _statusFrom(m['planStatus']),
      portionFactor: _toNumOrNull(m['portionFactor']),
      loggedAt: _toNumOrNull(m['loggedAt'])?.round(),
      note: () {
        final n = (m['note'] ?? '').toString().trim();
        return n.isEmpty ? null : n;
      }(),
      deleted: m['deleted'] == true,
    );
  }

  /// Serializes the entry VALUE (the key is the map position — [entryId] is
  /// not duplicated inside, matching the wire doc).
  Map<String, dynamic> toMap() => {
        'source': source.name,
        if (planEntryId != null) 'planEntryId': planEntryId,
        if (foodId != null) 'foodId': foodId,
        if (foodName.isNotEmpty) 'foodName': foodName,
        if (foodTier != null) 'foodTier': foodTier!.name,
        'mealSlot': mealSlot,
        if (quantity != null) 'quantity': quantity,
        if (unit.isNotEmpty) 'unit': unit,
        if (grams != null) 'grams': grams,
        'consumed': consumed.toMap(),
        if (planStatus != null) 'planStatus': planStatus!.name,
        if (portionFactor != null) 'portionFactor': portionFactor,
        if (loggedAt != null) 'loggedAt': loggedAt,
        if (note != null) 'note': note,
        if (deleted) 'deleted': true,
      };
}

/// The server-computed rollup (`computed` on the day doc) — READ-ONLY on the
/// member side; the Phase B trigger owns every number here.
class NutritionDaySummary {
  final ConsumedSnapshot totals;

  /// Per-macro consumed/target adherence in [0,1]; null when no targets.
  final Map<String, double>? targetAdherence;

  /// Legacy plan-compliance signal; null when no plan-sourced entries.
  final double? planCompliance;

  final int entryCount;

  const NutritionDaySummary({
    this.totals = const ConsumedSnapshot(),
    this.targetAdherence,
    this.planCompliance,
    this.entryCount = 0,
  });

  factory NutritionDaySummary.fromMap(Map<String, dynamic> m) {
    final rawTotals = m['totals'];
    Map<String, double>? adherence;
    final rawAdh = m['targetAdherence'];
    if (rawAdh is Map) {
      adherence = {};
      for (final e in rawAdh.entries) {
        final v = _toNumOrNull(e.value);
        if (v != null) adherence[e.key.toString()] = v;
      }
      if (adherence.isEmpty) adherence = null;
    }
    return NutritionDaySummary(
      totals: rawTotals is Map
          ? ConsumedSnapshot.fromMap(Map<String, dynamic>.from(rawTotals))
          : const ConsumedSnapshot(),
      targetAdherence: adherence,
      planCompliance: _toNumOrNull(m['planCompliance']),
      entryCount: (m['entryCount'] is num) ? (m['entryCount'] as num).toInt() : 0,
    );
  }
}

/// One member-day (`client_nutrition_days/{clientId}_{dateKey}`).
class NutritionDayModel {
  /// Doc id '{clientId}_{yyyy-MM-dd}'.
  final String id;
  final String dateKey;

  /// Entries MAP keyed by entryId — sparse, order-free, merge-friendly.
  final Map<String, FoodEntry> entries;

  /// Server-computed rollup; null until the trigger first runs.
  final NutritionDaySummary? computed;

  /// The org this day was OPENED under.
  ///
  /// The security rules pin `adminId` immutable on update, so every write
  /// after the first must resend the value the document was created with —
  /// NOT the member's current org. They differ for exactly one member: one who
  /// transferred gyms partway through a day. Reading it from the document is
  /// the only source that survives a restart, which is precisely when the
  /// alternative (remembering what was seen first) has nothing to remember.
  ///
  /// Empty only for a day document that predates the field being written.
  final String adminId;

  const NutritionDayModel({
    required this.id,
    this.dateKey = '',
    this.entries = const {},
    this.computed,
    this.adminId = '',
  });

  factory NutritionDayModel.fromMap(Map<String, dynamic> m, String id) {
    final entries = <String, FoodEntry>{};
    final raw = m['entries'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final v = e.value;
        if (v is Map) {
          entries[e.key.toString()] = FoodEntry.fromMap(
            e.key.toString(),
            Map<String, dynamic>.from(v),
          );
        }
      }
    }
    final rawComputed = m['computed'];
    return NutritionDayModel(
      id: id,
      dateKey: (m['dateKey'] ?? '').toString(),
      adminId: (m['adminId'] ?? '').toString(),
      entries: entries,
      computed: rawComputed is Map
          ? NutritionDaySummary.fromMap(Map<String, dynamic>.from(rawComputed))
          : null,
    );
  }

  /// Serializes the CLIENT-OWNED fields only: `computed` is server-written and
  /// deliberately excluded (a member write must never claim server numbers).
  Map<String, dynamic> toMap() => {
        'dateKey': dateKey,
        'entries': {
          for (final e in entries.entries) e.key: e.value.toMap(),
        },
      };

  /// Live (non-deleted) entries — the analytics population.
  Iterable<FoodEntry> get liveEntries =>
      entries.values.where((e) => !e.deleted);
}
