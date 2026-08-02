import 'package:alphaserena/core/models/transformation_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V2 parses one canonical check-in with pose-labelled media', () {
    final entry = TransformationEntry.fromMap({
      'schemaVersion': 2,
      'clientId': 'client-1',
      'adminId': 'admin-1',
      'authUid': 'member-1',
      'status': 'complete',
      'visibility': 'private',
      'recordedAt': '2026-08-01T10:00:00Z',
      'measurementUnit': 'cm',
      'weightKg': 81.2,
      'measurements': {
        'waist': 88.5,
        'leftArm': '31.2',
        'rightCalf': 37,
        'bad': -3,
      },
      'photos': {
        'front': {
          'url': 'https://example.test/front.jpg',
          'storagePath': 'progress_photos/u/transformations/id/front.jpg',
        },
        'side': {
          'url': 'https://example.test/side.jpg',
          'storagePath': 'progress_photos/u/transformations/id/side.jpg',
        },
      },
    }, 'id');

    expect(entry.schemaVersion, 2);
    expect(entry.isComplete, isTrue);
    expect(entry.isPrivate, isTrue);
    expect(entry.weightKg, 81.2);
    expect(entry.measurements, {
      'waist': 88.5,
      'leftArm': 31.2,
      'rightCalf': 37,
    });
    expect(entry.photos.keys, {
      TransformationPose.front,
      TransformationPose.side,
    });
  });

  test('legacy photo and date remain readable without fabricating values', () {
    final entry = TransformationEntry.fromMap({
      'date': '2026-07-01T10:00:00Z',
      'photoUrl': 'https://example.test/legacy.jpg',
    }, 'legacy');

    expect(entry.status, TransformationStatus.complete);
    expect(entry.photos[TransformationPose.front]?.url, contains('legacy'));
    expect(entry.weightKg, isNull);
    expect(entry.measurements, isEmpty);
  });

  test('recordedAt wins over device timestamp and missing dates use epoch', () {
    final serverDated = TransformationEntry.fromMap({
      'recordedAt': '2026-08-02T12:00:00Z',
      'clientRecordedAt': '2099-01-01T00:00:00Z',
    }, 'server');
    final undated = TransformationEntry.fromMap({}, 'undated');

    expect(serverDated.recordedAt, DateTime.utc(2026, 8, 2, 12));
    expect(undated.recordedAt.millisecondsSinceEpoch, 0);
  });
}
