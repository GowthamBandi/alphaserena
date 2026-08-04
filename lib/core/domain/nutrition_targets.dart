/// THE daily-nutrition-target rule for the member app.
///
/// Home, My Plans and the Diet screen each answered "what is my daily target?"
/// differently: the Diet screen preferred the coach's served target and fell
/// back to the prescription sum, while Home and My Plans ALWAYS summed the
/// prescribed items. A member with a coach-set goal of 2000 kcal and a 1750 kcal
/// sample day therefore read 2000 on one screen and 1750 on two others — and
/// Home's "kcal left" ring divided by the wrong denominator.
///
/// The backend is explicit about provenance (`buildDiet` in the functions repo):
/// targets come from `clients/{id}.dietTargets`, NEVER from the plan, and are
/// served as nullable `targetCalories` / `targetProtein` / … alongside `items`.
/// A plan's own `targetCalories` is only an authoring-time default that the
/// coach-side copies onto the client document at assignment time.
///
/// Two different numbers, so they are never conflated:
///   • the COACH's daily goal — a real prescription to hit
///   • the plan's SUM — merely what the assigned foods add up to
/// [NutritionTarget.source] keeps them distinguishable, so a screen can avoid
/// presenting a sample day's total as though the coach set it as a goal.
library;

/// Where a resolved target came from.
enum NutritionTargetSource {
  /// `clients/{id}.dietTargets` — a real daily goal set by the coach.
  coach,

  /// Derived by summing the assigned items. Informative, but NOT a coach goal.
  prescription,

  /// Neither available — no target may be claimed.
  none,
}

/// A resolved daily target plus its provenance.
class NutritionTarget {
  final double value;
  final NutritionTargetSource source;

  /// NIP Phase A additive extras, carried only when the served `targets` map
  /// resolved the value (null on the flat-field and prescription paths — the
  /// legacy wire simply doesn't carry them):
  ///  • [waterMl] — the coach's daily water goal;
  ///  • [note]    — the coach's free-text note on the targets;
  ///  • [version] — the targets version stamp (audit/idempotency handle).
  final double? waterMl;
  final String? note;
  final double? version;

  const NutritionTarget(
    this.value,
    this.source, {
    this.waterMl,
    this.note,
    this.version,
  });

  static const NutritionTarget empty = NutritionTarget(
    0,
    NutritionTargetSource.none,
  );

  /// A number exists that may be shown at all.
  bool get hasValue => value > 0 && source != NutritionTargetSource.none;

  /// The coach genuinely set this goal — only then may a screen frame it as a
  /// target to hit, show "remaining", or compute a completion ring against it.
  bool get isCoachGoal => source == NutritionTargetSource.coach;
}

/// Resolves one daily target for [itemKey] (e.g. `'calories'`).
///
/// [servedTargets] is `getMyTraining`'s top-level `nutritionTargets` map
/// (`TrainingController.servedTargets`) — the member's own daily goal, served
/// INDEPENDENTLY of any plan. It is checked first and is the canonical source.
/// [diet] is the served diet map from `getMyTraining` (`TrainingController.diet`).
/// [targetKey] is its nullable coach-goal field (e.g. `'targetCalories'`).
/// [items] are the assigned diet items, used only for the fallback sum.
NutritionTarget resolveNutritionTarget({
  required Map<String, dynamic>? diet,
  required String targetKey,
  required String itemKey,
  required List<Map<String, dynamic>> items,
  Map<String, dynamic>? servedTargets,
}) {
  // A member's daily goal lives on `clients/{id}` and belongs to the MEMBER,
  // not to a plan. The backend used to resolve it only inside `buildDiet`,
  // which runs solely when an ACTIVE diet assignment exists — so with no plan,
  // or a paused/ended/soft-deleted one, `diet` was null and every target went
  // with it: the calorie ring and all four macro goals read as "no goal set"
  // while the numbers sat correctly on the client document.
  //
  // The top-level map is therefore tried FIRST and survives `diet == null`.
  final fromServed = _fromTargetsMap(servedTargets, itemKey);
  if (fromServed != null) return fromServed;

  // NIP PHASE A — the additive served `targets` map wins when present with a
  // real provenance (source != 'none'). By construction this changes NO
  // number: the backend serves the SAME values in `targets.<macro>` and the
  // legacy flat `target<Macro>` field, so a member sees today what they saw
  // yesterday — but the resolution now rides the versioned contract and can
  // carry waterMl/note/version. An old backend (no `targets` key) or an
  // explicit 'none' falls straight through to the legacy flat-field path.
  //
  // Both copies come from the backend's one `servedTargetsWire` producer, so
  // they agree; this remains the path for an APK talking to an older backend.
  final rawTargets = diet?['targets'];
  final fromDiet = _fromTargetsMap(
    rawTargets is Map ? Map<String, dynamic>.from(rawTargets) : null,
    itemKey,
  );
  if (fromDiet != null) return fromDiet;

  // The coach's goal wins whenever one is set. `> 0` mirrors the existing
  // screen-level check: a stored 0 is treated as "not set" rather than as a
  // real goal of zero, which no coach prescribes.
  final coach = _num(diet?[targetKey]);
  if (coach > 0) return NutritionTarget(coach, NutritionTargetSource.coach);

  var sum = 0.0;
  for (final item in items) {
    sum += _num(item[itemKey]);
  }
  if (sum > 0) return NutritionTarget(sum, NutritionTargetSource.prescription);

  // No goal and nothing prescribed for this macro — say nothing.
  return NutritionTarget.empty;
}

/// Reads one macro out of a served `targets`-shaped map.
///
/// Returns null — meaning "this map has nothing to say about [itemKey]" — when
/// the map is absent, carries no provenance, was explicitly withdrawn
/// (`source: 'none'`), or simply does not prescribe this particular macro. A
/// coach may set calories only, and the caller then falls through to the plan
/// sum; a null here is what makes that fall-through possible without ever
/// fabricating a goal of zero.
NutritionTarget? _fromTargetsMap(Map<String, dynamic>? map, String itemKey) {
  if (map == null) return null;
  final source = map['source'];
  if (source == null || source.toString() == 'none') return null;
  final v = _num(map[itemKey]);
  if (v <= 0) return null;
  final waterMl = map['waterMl'];
  final version = map['version'];
  final note = map['note']?.toString() ?? '';
  return NutritionTarget(
    v,
    NutritionTargetSource.coach,
    waterMl: waterMl == null ? null : _num(waterMl),
    note: note.isEmpty ? null : note,
    version: version == null ? null : _num(version),
  );
}

/// Tolerant numeric read: the wire carries numbers, but legacy documents and
/// hand-edited plans have been seen storing them as strings.
double _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}
