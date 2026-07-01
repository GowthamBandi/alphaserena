import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// A single tracked metric value plus its provenance. `source` is 'manual' in
/// v1; a future health-sync writes the same shape with 'health'. `quality`
/// (1..5) is only used by sleep.
class MetricValue {
  final double value;
  final String source;
  final int? quality;

  const MetricValue({required this.value, this.source = 'manual', this.quality});

  /// Null when the map is missing or has no numeric `value` (metric not logged).
  static MetricValue? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final v = _toDouble(m['value']);
    if (v == null) return null;
    final src = (m['source'] ?? 'manual').toString();
    return MetricValue(
      value: v,
      source: src.isEmpty ? 'manual' : src,
      quality: _toInt(m['quality']),
    );
  }

  Map<String, dynamic> toMap() => {
        'value': value,
        'source': source,
        if (quality != null) 'quality': quality,
      };
}

/// A supplement snapshotted into a day's log (name/dose copied from the stack so
/// history is stable if the coach later edits the stack).
class SupplementIntake {
  final String id;
  final String name;
  final String? dose;
  final bool taken;

  const SupplementIntake({
    required this.id,
    required this.name,
    this.dose,
    this.taken = false,
  });

  factory SupplementIntake.fromMap(Map<String, dynamic> m) {
    final dose = (m['dose'] ?? '').toString().trim();
    return SupplementIntake(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      dose: dose.isEmpty ? null : dose,
      taken: m['taken'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (dose != null) 'dose': dose,
        'taken': taken,
      };

  SupplementIntake copyWith({bool? taken}) => SupplementIntake(
        id: id, name: name, dose: dose, taken: taken ?? this.taken);
}

/// One day of member-logged lifestyle metrics.
class LifestyleLogModel {
  final String id;
  final String clientId;
  final String adminId;
  final String authorId;
  final String dateKey;
  final DateTime date;
  final MetricValue? waterMl;
  final MetricValue? steps;
  final MetricValue? sleepHours;
  final List<SupplementIntake> supplements;
  final DateTime? updatedAt;

  const LifestyleLogModel({
    required this.id,
    required this.clientId,
    required this.adminId,
    required this.authorId,
    this.dateKey = '',
    required this.date,
    this.waterMl,
    this.steps,
    this.sleepHours,
    this.supplements = const [],
    this.updatedAt,
  });

  int get supplementCount => supplements.length;
  int get takenCount => supplements.where((s) => s.taken).length;

  factory LifestyleLogModel.fromMap(Map<String, dynamic> m, String id) {
    Map<String, dynamic>? sub(dynamic v) =>
        v is Map ? Map<String, dynamic>.from(v) : null;
    final rawSupps = m['supplements'];
    final supps = rawSupps is List
        ? rawSupps
            .whereType<Map>()
            .map((e) => SupplementIntake.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : <SupplementIntake>[];
    return LifestyleLogModel(
      id: id,
      clientId: (m['clientId'] ?? '').toString(),
      adminId: (m['adminId'] ?? '').toString(),
      authorId: (m['authorId'] ?? '').toString(),
      dateKey: (m['date'] ?? '').toString(),
      date: _date(m['date']) ?? DateTime.now(),
      waterMl: MetricValue.fromMap(sub(m['waterMl'])),
      steps: MetricValue.fromMap(sub(m['steps'])),
      sleepHours: MetricValue.fromMap(sub(m['sleepHours'])),
      supplements: supps,
      updatedAt: _date(m['updatedAt']),
    );
  }
}
