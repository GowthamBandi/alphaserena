/// One day's diet-adherence log (`client_diet_logs/{clientId}_{yyyy-MM-dd}`).
/// The member marks each prescribed food eaten/partial/skipped; the trainer app
/// reads `adherencePct` + `items`. `idx` is an app-private field (the food's
/// position in the assigned plan) used to restore the logger UI exactly — the
/// coach side ignores it.
class DietLogItem {
  final int idx;
  final String foodName;
  final String quantity;
  final String meal;
  final double? calories;
  final String status;
  final String? note;

  const DietLogItem({
    required this.idx,
    required this.foodName,
    required this.status,
    this.quantity = '',
    this.meal = '',
    this.calories,
    this.note,
  });

  factory DietLogItem.fromMap(Map<String, dynamic> m) => DietLogItem(
        idx: (m['idx'] is num) ? (m['idx'] as num).toInt() : -1,
        foodName: (m['foodName'] ?? '').toString(),
        quantity: (m['quantity'] ?? '').toString(),
        meal: (m['meal'] ?? '').toString(),
        calories: (m['calories'] is num) ? (m['calories'] as num).toDouble() : null,
        status: (m['status'] ?? '').toString(),
        note: m['note']?.toString(),
      );

  Map<String, dynamic> toMap() => {
        'idx': idx,
        'foodName': foodName,
        if (quantity.isNotEmpty) 'quantity': quantity,
        if (meal.isNotEmpty) 'meal': meal,
        if (calories != null) 'calories': calories,
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

  /// Prescribed-food index → status, for restoring the logger's marked state.
  Map<int, String> get statusByIndex => {
        for (final it in items)
          if (it.idx >= 0 && it.status.isNotEmpty) it.idx: it.status,
      };
}
