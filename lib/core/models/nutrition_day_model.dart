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

/// How an entry got onto the day (backend `ENTRY_SOURCES`).
enum FoodEntrySource { plan, search, custom, quick }

/// Mark on a plan-sourced entry (backend `PLAN_STATUSES`).
enum PlanEntryStatus { eaten, partial, skipped, swapped }

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

  final String mealSlot;
  final ConsumedSnapshot consumed;

  /// eaten|partial|skipped|swapped for plan-sourced entries, else null.
  final PlanEntryStatus? planStatus;

  /// Fraction of the prescription consumed for `partial` (backend default 0.5).
  final double? portionFactor;

  /// Soft delete — analytics skip it; the data is never destroyed.
  final bool deleted;

  const FoodEntry({
    required this.entryId,
    this.source = FoodEntrySource.quick,
    this.planEntryId,
    this.foodId,
    this.mealSlot = 'other',
    this.consumed = const ConsumedSnapshot(),
    this.planStatus,
    this.portionFactor,
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
      mealSlot: (m['mealSlot'] ?? 'other').toString(),
      consumed: rawConsumed is Map
          ? ConsumedSnapshot.fromMap(Map<String, dynamic>.from(rawConsumed))
          : const ConsumedSnapshot(),
      planStatus: _statusFrom(m['planStatus']),
      portionFactor: _toNumOrNull(m['portionFactor']),
      deleted: m['deleted'] == true,
    );
  }

  /// Serializes the entry VALUE (the key is the map position — [entryId] is
  /// not duplicated inside, matching the wire doc).
  Map<String, dynamic> toMap() => {
        'source': source.name,
        if (planEntryId != null) 'planEntryId': planEntryId,
        if (foodId != null) 'foodId': foodId,
        'mealSlot': mealSlot,
        'consumed': consumed.toMap(),
        if (planStatus != null) 'planStatus': planStatus!.name,
        if (portionFactor != null) 'portionFactor': portionFactor,
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

  const NutritionDayModel({
    required this.id,
    this.dateKey = '',
    this.entries = const {},
    this.computed,
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
