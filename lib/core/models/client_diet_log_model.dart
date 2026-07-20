/// One day's diet-adherence log (`client_diet_logs/{clientId}_{yyyy-MM-dd}`).
/// The member marks each prescribed food eaten/partial/skipped; the trainer app
/// reads `adherencePct` + `items`.
///
/// `foodId` (V2A) is the food's stable identity — the referential key readers
/// use so a food is never re-identified from its name or array position. It is
/// '' for legacy logs (pre-V2A) and for freehand items with no library food.
/// `idx` is an app-private field (the food's position in the assigned plan when
/// logged) kept only as a legacy restore fallback; the coach side ignores it.
/// Coerce a wire value to a nullable double (null when absent/unparseable).
double? _toD(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

class DietLogItem {
  final int idx;
  final String foodId;
  final String foodName;
  final String quantity;
  final String meal;
  final String status;
  final String? note;

  /// Consumed-nutrition SNAPSHOT (V2B) — the food's prescribed per-item macros
  /// frozen at log time. Consumed = macro × status score, computed by readers
  /// (mirroring how [calories] has always worked). These are historical truth:
  /// a later food/plan edit can never change them. null on legacy logs and
  /// freehand items the plan served without that macro.
  final double? calories;
  final double? protein;
  final double? carbs;
  final double? fat;
  final double? fiber;
  final double? sugar;
  final double? saturatedFat;

  const DietLogItem({
    required this.idx,
    required this.foodName,
    required this.status,
    this.foodId = '',
    this.quantity = '',
    this.meal = '',
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.fiber,
    this.sugar,
    this.saturatedFat,
    this.note,
  });

  factory DietLogItem.fromMap(Map<String, dynamic> m) => DietLogItem(
        idx: (m['idx'] is num) ? (m['idx'] as num).toInt() : -1,
        foodId: (m['foodId'] ?? '').toString(),
        foodName: (m['foodName'] ?? '').toString(),
        quantity: (m['quantity'] ?? '').toString(),
        meal: (m['meal'] ?? '').toString(),
        calories: _toD(m['calories']),
        protein: _toD(m['protein']),
        carbs: _toD(m['carbs']),
        fat: _toD(m['fat']),
        fiber: _toD(m['fiber']),
        sugar: _toD(m['sugar']),
        saturatedFat: _toD(m['saturatedFat']),
        status: (m['status'] ?? '').toString(),
        note: m['note']?.toString(),
      );

  /// Builds a logged item from a getMyTraining SERVED food map (Foundation V2B).
  /// The served item uses key 'name' for the food and carries foodId + the 7
  /// nutrient values — this freezes them as the consumed-nutrition snapshot at
  /// log time. Absent nutrients stay null (legacy/freehand foods).
  factory DietLogItem.fromServedFood(
    Map<String, dynamic> f, {
    required int idx,
    required String status,
  }) {
    double? mv(String k) {
      final v = f[k];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    return DietLogItem(
      idx: idx,
      foodId: (f['foodId'] ?? '').toString(),
      foodName: (f['name'] ?? 'Food').toString(),
      quantity: (f['quantity'] ?? '').toString(),
      meal: (f['meal'] ?? '').toString(),
      calories: mv('calories'),
      protein: mv('protein'),
      carbs: mv('carbs'),
      fat: mv('fat'),
      fiber: mv('fiber'),
      sugar: mv('sugar'),
      saturatedFat: mv('saturatedFat'),
      status: status,
    );
  }

  Map<String, dynamic> toMap() => {
        'idx': idx,
        if (foodId.isNotEmpty) 'foodId': foodId,
        'foodName': foodName,
        if (quantity.isNotEmpty) 'quantity': quantity,
        if (meal.isNotEmpty) 'meal': meal,
        if (calories != null) 'calories': calories,
        if (protein != null) 'protein': protein,
        if (carbs != null) 'carbs': carbs,
        if (fat != null) 'fat': fat,
        if (fiber != null) 'fiber': fiber,
        if (sugar != null) 'sugar': sugar,
        if (saturatedFat != null) 'saturatedFat': saturatedFat,
        'status': status,
        if (note != null && note!.isNotEmpty) 'note': note,
      };
}

class ClientDietLogModel {
  final String id;
  final String dateKey;
  final String planName;
  final double adherencePct;
  final List<DietLogItem> items;

  const ClientDietLogModel({
    required this.id,
    this.dateKey = '',
    this.planName = '',
    this.adherencePct = 0,
    this.items = const [],
  });

  factory ClientDietLogModel.fromMap(Map<String, dynamic> m, String id) {
    final raw = (m['items'] as List?) ?? const [];
    return ClientDietLogModel(
      id: id,
      dateKey: (m['dateKey'] ?? '').toString(),
      planName: (m['planName'] ?? '').toString(),
      adherencePct:
          (m['adherencePct'] is num) ? (m['adherencePct'] as num).toDouble() : 0,
      items: raw
          .whereType<Map>()
          .map((e) => DietLogItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
