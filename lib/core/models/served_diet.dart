/// NIP PHASE A — the typed view of `getMyTraining.diet`.
///
/// The served diet map has always been consumed raw (`Map<String, dynamic>`
/// with per-screen key reads). This model parses it ONCE into a typed shape so
/// later phases plug into fields, not string keys. It is strictly ADDITIVE:
/// [TrainingController] keeps exposing the raw map and `dietItems`, and no
/// screen is required to switch — Phase A ships zero visible change.
///
/// Wire contract (backend `buildDiet` in trainershq-backend):
///  - legacy flat fields `targetCalories…targetFiber` (nullable) — unchanged;
///  - additive `description` (coach's plan notes, absent when empty);
///  - additive `targets` map `{calories, protein, carbs, fat, fiber, waterMl,
///    micros, note, version, source}` with source ∈
///    'nutritionTargets' | 'dietTargets' | 'none';
///  - `items[]` served by `dietItemForMember` (+ additive nullable `entryId`).
///
/// Pure and Firebase-free; tolerant of absent/malformed fields (an old backend
/// serving the legacy shape must parse without error).
library;

double? _toD(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// One served food, exactly as `dietItemForMember` emits it.
class ServedDietItem {
  final String name;
  final String foodId;

  /// The template entry's stable id (NIP). Null on legacy plans authored
  /// before entry ids existed — Phase B keys plan-sourced entries on this.
  final String? entryId;

  final String quantity;
  final String meal;

  /// Portion-true prescription (null on legacy items without grams).
  final double? grams;
  final String? portionLabel;
  final double? portionQty;

  final double? calories;
  final double? protein;
  final double? carbs;
  final double? fat;
  final double? fiber;
  final double? sugar;
  final double? saturatedFat;

  const ServedDietItem({
    required this.name,
    this.foodId = '',
    this.entryId,
    this.quantity = '',
    this.meal = '',
    this.grams,
    this.portionLabel,
    this.portionQty,
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.fiber,
    this.sugar,
    this.saturatedFat,
  });

  factory ServedDietItem.fromMap(Map<String, dynamic> m) => ServedDietItem(
        name: (m['name'] ?? 'Food').toString(),
        foodId: (m['foodId'] ?? '').toString(),
        entryId: m['entryId']?.toString(),
        quantity: (m['quantity'] ?? '').toString(),
        meal: (m['meal'] ?? '').toString(),
        grams: _toD(m['grams']),
        portionLabel: m['portionLabel']?.toString(),
        portionQty: _toD(m['portionQty']),
        calories: _toD(m['calories']),
        protein: _toD(m['protein']),
        carbs: _toD(m['carbs']),
        fat: _toD(m['fat']),
        fiber: _toD(m['fiber']),
        sugar: _toD(m['sugar']),
        saturatedFat: _toD(m['saturatedFat']),
      );
}

/// The additive `targets` map — the versioned coach-target contract
/// (mirrors the backend's `ServedTargets`).
class ServedDietTargets {
  final double? calories;
  final double? protein;
  final double? carbs;
  final double? fat;
  final double? fiber;
  final double? waterMl;

  /// Micronutrient goals keyed by the food platform's registry keys.
  final Map<String, double> micros;

  final String note;
  final double? version;

  /// 'nutritionTargets' | 'dietTargets' | 'none' — provenance, verbatim.
  final String source;

  const ServedDietTargets({
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.fiber,
    this.waterMl,
    this.micros = const {},
    this.note = '',
    this.version,
    this.source = 'none',
  });

  factory ServedDietTargets.fromMap(Map<String, dynamic> m) {
    final micros = <String, double>{};
    final rawMicros = m['micros'];
    if (rawMicros is Map) {
      for (final e in rawMicros.entries) {
        final v = _toD(e.value);
        if (v != null) micros[e.key.toString()] = v;
      }
    }
    return ServedDietTargets(
      calories: _toD(m['calories']),
      protein: _toD(m['protein']),
      carbs: _toD(m['carbs']),
      fat: _toD(m['fat']),
      fiber: _toD(m['fiber']),
      waterMl: _toD(m['waterMl']),
      micros: micros,
      note: (m['note'] ?? '').toString(),
      version: _toD(m['version']),
      source: (m['source'] ?? 'none').toString(),
    );
  }

  /// A real coach target exists (the backend never fabricates: `none` means
  /// neither `nutritionTargets` nor `dietTargets` carried a number).
  bool get hasTargets => source != 'none';
}

/// The whole served diet, parsed once.
class ServedDiet {
  final String name;

  /// Coach's plan notes ('' when the plan has none / old backend).
  final String description;

  final List<ServedDietItem> items;

  // Legacy flat targets — kept so nothing depends on the new map existing.
  final double? targetCalories;
  final double? targetProtein;
  final double? targetCarbs;
  final double? targetFat;
  final double? targetFiber;

  /// The additive targets map; null when the backend predates NIP Phase A.
  final ServedDietTargets? targets;

  const ServedDiet({
    this.name = '',
    this.description = '',
    this.items = const [],
    this.targetCalories,
    this.targetProtein,
    this.targetCarbs,
    this.targetFat,
    this.targetFiber,
    this.targets,
  });

  factory ServedDiet.fromMap(Map<String, dynamic> m) {
    final rawItems = (m['items'] as List?) ?? const [];
    final rawTargets = m['targets'];
    return ServedDiet(
      name: (m['name'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      items: rawItems
          .whereType<Map>()
          .map((e) => ServedDietItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      targetCalories: _toD(m['targetCalories']),
      targetProtein: _toD(m['targetProtein']),
      targetCarbs: _toD(m['targetCarbs']),
      targetFat: _toD(m['targetFat']),
      targetFiber: _toD(m['targetFiber']),
      targets: rawTargets is Map
          ? ServedDietTargets.fromMap(Map<String, dynamic>.from(rawTargets))
          : null,
    );
  }
}
