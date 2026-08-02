import '../models/transformation_entry.dart';

const transformationMeasurementLabels = <String, String>{
  'chest': 'Chest',
  'waist': 'Waist',
  'hips': 'Hips',
  'neck': 'Neck',
  'leftArm': 'Left arm',
  'rightArm': 'Right arm',
  'leftThigh': 'Left thigh',
  'rightThigh': 'Right thigh',
  'leftCalf': 'Left calf',
  'rightCalf': 'Right calf',
  // Legacy symmetric measurements remain readable.
  'arms': 'Arms',
  'thighs': 'Thighs',
};

String transformationMetricLabel(String key) =>
    transformationMeasurementLabels[key] ?? _humanize(key);

String _humanize(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  if (spaced.isEmpty) return spaced;
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

enum TransformationChangeDirection { increased, reduced, unchanged }

class TransformationChange {
  const TransformationChange({
    required this.key,
    required this.label,
    required this.before,
    required this.after,
    required this.unit,
  });

  final String key;
  final String label;
  final double before;
  final double after;
  final String unit;

  double get delta => after - before;

  TransformationChangeDirection get direction {
    if (delta.abs() < 0.05) return TransformationChangeDirection.unchanged;
    return delta > 0
        ? TransformationChangeDirection.increased
        : TransformationChangeDirection.reduced;
  }

  String get directionLabel => switch (direction) {
    TransformationChangeDirection.increased => 'Increased',
    TransformationChangeDirection.reduced => 'Reduced',
    TransformationChangeDirection.unchanged => 'No change',
  };
}

/// Compares only values genuinely present in both checkpoints. Direction is
/// factual, never labelled "improved" without a member goal or clinical context.
List<TransformationChange> compareTransformations(
  TransformationEntry latest,
  TransformationEntry previous,
) {
  final changes = <TransformationChange>[];
  if (latest.weightKg != null && previous.weightKg != null) {
    changes.add(
      TransformationChange(
        key: 'weightKg',
        label: 'Weight',
        before: previous.weightKg!,
        after: latest.weightKg!,
        unit: 'kg',
      ),
    );
  }
  for (final key in transformationMeasurementLabels.keys) {
    final after = latest.measurements[key];
    final before = previous.measurements[key];
    if (after == null || before == null) continue;
    changes.add(
      TransformationChange(
        key: key,
        label: transformationMetricLabel(key),
        before: before,
        after: after,
        unit: latest.measurementUnit,
      ),
    );
  }
  return changes;
}
