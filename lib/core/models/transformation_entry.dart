import 'package:cloud_firestore/cloud_firestore.dart';

enum TransformationVisibility { shared, private }

enum TransformationStatus { uploading, complete, abandoned }

enum TransformationPose { front, side, back }

DateTime? _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

double? _number(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// Canonical member transformation record shared by AlphaSerena and TrainersHQ.
///
/// One completed document represents one chronological check-in. Every field is
/// optional, but a completed record must contain at least one real observation.
/// Uploading records are private recovery envelopes and never coach-visible.
class TransformationEntry {
  const TransformationEntry({
    required this.id,
    required this.clientId,
    required this.adminId,
    required this.authUid,
    required this.recordedAt,
    required this.createdAt,
    required this.updatedAt,
    this.editedAt,
    required this.visibility,
    required this.status,
    required this.measurementUnit,
    required this.measurements,
    required this.photos,
    this.weightKg,
    this.bodyFatPercent,
    this.note,
    this.schemaVersion = 2,
  });

  final String id;
  final String clientId;
  final String adminId;
  final String authUid;
  final int schemaVersion;
  final DateTime recordedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Stamped by the backend contract on every owner correction of an already
  /// published checkpoint, and absent on one that has never been touched. It is
  /// therefore PROOF of an edit rather than an inference from timestamp drift —
  /// publishing a draft also moves [updatedAt], so that comparison would report
  /// a normal upload as an edit.
  final DateTime? editedAt;
  bool get wasEdited => editedAt != null;

  final TransformationVisibility visibility;
  final TransformationStatus status;
  final String measurementUnit;
  final double? weightKg;
  final double? bodyFatPercent;
  final Map<String, double> measurements;
  final Map<TransformationPose, TransformationPhoto> photos;
  final String? note;

  bool get isComplete => status == TransformationStatus.complete;
  bool get isPrivate => visibility == TransformationVisibility.private;
  bool get hasPhotos => photos.isNotEmpty;
  bool get hasMeasurements => measurements.isNotEmpty;
  bool get hasContent =>
      weightKg != null ||
      bodyFatPercent != null ||
      hasMeasurements ||
      hasPhotos ||
      (note?.trim().isNotEmpty ?? false);

  factory TransformationEntry.fromMap(Map<String, dynamic> map, String id) {
    final rawMeasurements = map['measurements'];
    final measurements = <String, double>{};
    if (rawMeasurements is Map) {
      for (final entry in rawMeasurements.entries) {
        final value = _number(entry.value);
        if (value != null && value > 0) {
          measurements[entry.key.toString()] = value;
        }
      }
    }

    final photos = <TransformationPose, TransformationPhoto>{};
    final rawPhotos = map['photos'];
    if (rawPhotos is Map) {
      for (final pose in TransformationPose.values) {
        final raw = rawPhotos[pose.name];
        if (raw is Map) {
          final photo = TransformationPhoto.fromMap(
            Map<String, dynamic>.from(raw),
          );
          if (photo.url.isNotEmpty) photos[pose] = photo;
        }
      }
    }

    // V1 compatibility: the old record carried one untyped photoUrl.
    final legacyPhoto = (map['photoUrl'] ?? '').toString().trim();
    if (photos.isEmpty && legacyPhoto.isNotEmpty) {
      photos[TransformationPose.front] = TransformationPhoto(
        url: legacyPhoto,
        storagePath: '',
      );
    }

    final statusName = (map['status'] ?? 'complete').toString();
    final visibilityName = (map['visibility'] ?? 'shared').toString();
    final recordedAt =
        _date(map['recordedAt']) ??
        _date(map['clientRecordedAt']) ??
        _date(map['date']) ??
        _date(map['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    return TransformationEntry(
      id: id,
      clientId: (map['clientId'] ?? '').toString(),
      adminId: (map['adminId'] ?? '').toString(),
      authUid: (map['authUid'] ?? '').toString(),
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
      recordedAt: recordedAt,
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
      editedAt: _date(map['editedAt']),
      visibility: visibilityName == 'private'
          ? TransformationVisibility.private
          : TransformationVisibility.shared,
      status: TransformationStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () => TransformationStatus.complete,
      ),
      measurementUnit: (map['measurementUnit'] ?? 'cm').toString(),
      weightKg: _number(map['weightKg']),
      bodyFatPercent: _number(map['bodyFatPercent']),
      measurements: measurements,
      photos: photos,
      note: (map['note'] ?? '').toString().trim().isEmpty
          ? null
          : map['note'].toString().trim(),
    );
  }
}

class TransformationPhoto {
  const TransformationPhoto({required this.url, required this.storagePath});

  final String url;
  final String storagePath;

  factory TransformationPhoto.fromMap(Map<String, dynamic> map) =>
      TransformationPhoto(
        url: (map['url'] ?? '').toString().trim(),
        storagePath: (map['storagePath'] ?? '').toString().trim(),
      );

  Map<String, dynamic> toMap() => {'url': url, 'storagePath': storagePath};
}
