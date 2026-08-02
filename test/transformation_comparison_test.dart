import 'package:alphaserena/core/domain/transformation_comparison.dart';
import 'package:alphaserena/core/models/transformation_entry.dart';
import 'package:flutter_test/flutter_test.dart';

TransformationEntry _entry({
  required String id,
  double? weight,
  Map<String, double> measurements = const {},
}) => TransformationEntry(
  id: id,
  clientId: 'client',
  adminId: 'admin',
  authUid: 'member',
  recordedAt: DateTime.utc(2026, 8, 1),
  createdAt: null,
  updatedAt: null,
  visibility: TransformationVisibility.shared,
  status: TransformationStatus.complete,
  measurementUnit: 'cm',
  measurements: measurements,
  photos: const {},
  weightKg: weight,
);

void main() {
  test('compares only values present in both chronological checkpoints', () {
    final previous = _entry(
      id: 'previous',
      weight: 73.3,
      measurements: {'waist': 82, 'leftArm': 31},
    );
    final latest = _entry(
      id: 'latest',
      weight: 72.5,
      measurements: {'waist': 80.5, 'neck': 36},
    );

    final changes = compareTransformations(latest, previous);

    expect(changes.map((value) => value.key), ['weightKg', 'waist']);
    expect(changes.first.delta, closeTo(-.8, .0001));
    expect(changes.first.direction, TransformationChangeDirection.reduced);
  });

  test('small sensor/rounding noise is labelled no change', () {
    final change = TransformationChange(
      key: 'waist',
      label: 'Waist',
      before: 80,
      after: 80.04,
      unit: 'cm',
    );

    expect(change.direction, TransformationChangeDirection.unchanged);
    expect(change.directionLabel, 'No change');
  });

  test('labels left/right and legacy symmetric metrics honestly', () {
    expect(transformationMetricLabel('leftCalf'), 'Left calf');
    expect(transformationMetricLabel('arms'), 'Arms');
    expect(transformationMetricLabel('unknownValue'), 'Unknown Value');
  });
}
