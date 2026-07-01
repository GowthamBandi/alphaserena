// Coach-authored lifestyle targets + supplement stack, read off the member's
// live `clients` doc (mirrors trainersHQ's on-ClientModel classes). Standalone
// here because this app reads the client record as a raw map.

double? _toDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _toIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// Per-client daily lifestyle targets, stored as a `lifestyleTargets` map on the
/// client doc. Any target may be null (unset → member logs without a goal ring).
/// `glassSizeMl` always has a value (defaults to 250) so water display is stable.
class LifestyleTargets {
  final double? waterTargetMl;
  final double glassSizeMl;
  final int? stepsTarget;
  final double? sleepHoursTarget;

  const LifestyleTargets({
    this.waterTargetMl,
    this.glassSizeMl = 250,
    this.stepsTarget,
    this.sleepHoursTarget,
  });

  bool get hasAny =>
      waterTargetMl != null || stepsTarget != null || sleepHoursTarget != null;

  factory LifestyleTargets.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const LifestyleTargets();
    final glass = _toDoubleOrNull(m['glassSizeMl']);
    return LifestyleTargets(
      waterTargetMl: _toDoubleOrNull(m['waterTargetMl']),
      glassSizeMl: (glass != null && glass > 0) ? glass : 250,
      stepsTarget: _toIntOrNull(m['stepsTarget']),
      sleepHoursTarget: _toDoubleOrNull(m['sleepHoursTarget']),
    );
  }

  Map<String, dynamic> toMap() => {
        if (waterTargetMl != null) 'waterTargetMl': waterTargetMl,
        'glassSizeMl': glassSizeMl,
        if (stepsTarget != null) 'stepsTarget': stepsTarget,
        if (sleepHoursTarget != null) 'sleepHoursTarget': sleepHoursTarget,
      };
}

/// One supplement in a client's coach-defined daily stack (on the client doc as
/// a `supplementPlan` array). `id` is a stable client-minted id so daily logs
/// can reference it across renames.
class SupplementPlanItem {
  final String id;
  final String name;
  final String? dose;
  final String? timing;

  const SupplementPlanItem({
    required this.id,
    required this.name,
    this.dose,
    this.timing,
  });

  factory SupplementPlanItem.fromMap(Map<String, dynamic> m) {
    String? s(dynamic v) {
      final t = (v ?? '').toString().trim();
      return t.isEmpty ? null : t;
    }

    return SupplementPlanItem(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      dose: s(m['dose']),
      timing: s(m['timing']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (dose != null) 'dose': dose,
        if (timing != null) 'timing': timing,
      };
}
