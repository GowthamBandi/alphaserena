import 'package:alphaserena/controllers/progress_controller.dart';
import 'package:alphaserena/core/models/transformation_entry.dart';
import 'package:flutter_test/flutter_test.dart';

TransformationEntry _entry({
  required String id,
  required DateTime at,
  double? weight,
}) => TransformationEntry(
  id: id,
  clientId: 'client',
  adminId: 'admin',
  authUid: 'member',
  recordedAt: at,
  createdAt: null,
  updatedAt: null,
  visibility: TransformationVisibility.private,
  status: TransformationStatus.complete,
  measurementUnit: 'cm',
  measurements: weight == null ? const {'waist': 80} : const {},
  photos: const {},
  weightKg: weight,
);

void main() {
  test('weight delta uses chronology and skips partial checkpoints', () {
    final change = transformationWeightChange([
      _entry(id: 'older', at: DateTime.utc(2026, 7, 1), weight: 73.3),
      _entry(id: 'measurements', at: DateTime.utc(2026, 7, 20)),
      _entry(id: 'latest', at: DateTime.utc(2026, 8, 1), weight: 72.5),
    ]);

    expect(change, closeTo(-.8, .0001));
  });
}
