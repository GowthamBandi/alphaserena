import 'package:cloud_firestore/cloud_firestore.dart';

const List<String> kCheckInRatingKeys = [
  'energy', 'sleep', 'stress', 'hunger', 'motivation', 'training', 'diet',
];

const Map<String, String> kCheckInRatingLabels = {
  'energy': 'Energy',
  'sleep': 'Sleep',
  'stress': 'Stress',
  'hunger': 'Hunger',
  'motivation': 'Motivation',
  'training': 'Training',
  'diet': 'Diet',
};

class CheckInSubmissionStatus {
  static const String submitted = 'submitted';
  static const String reviewed = 'reviewed';
}

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

/// A member-submitted weekly check-in packet. `ratings` is an open map (1..5 per
/// key); invalid/out-of-range values are dropped on parse. Coach writes the
/// response fields.
class CheckInSubmissionModel {
  final String id;
  final String clientId;
  final String adminId;
  final String authorId;
  final String clientName;
  final double? weightKg;
  final Map<String, int> ratings;
  final String note;
  final List<String> photoUrls;
  final String status;
  final DateTime? submittedAt;
  final DateTime? updatedAt;
  final DateTime? reviewedAt;
  final String coachResponse;

  /// `yyyy-Www` — the ISO week this review covers. Empty on legacy documents
  /// written before the weekly window existed; readers fall back to
  /// `weekKeyFor(submittedAt)`.
  final String weekOf;
  final String reviewedByName;

  const CheckInSubmissionModel({
    required this.id,
    required this.clientId,
    required this.adminId,
    required this.authorId,
    this.clientName = '',
    this.weightKg,
    this.ratings = const {},
    this.note = '',
    this.photoUrls = const [],
    this.status = CheckInSubmissionStatus.submitted,
    this.weekOf = '',
    this.submittedAt,
    this.updatedAt,
    this.reviewedAt,
    this.coachResponse = '',
    this.reviewedByName = '',
  });

  bool get isReviewed => status == CheckInSubmissionStatus.reviewed;
  bool get hasAnyRating => ratings.isNotEmpty;
  int? ratingFor(String key) => ratings[key];

  static Map<String, int> _parseRatings(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((k, v) {
      final i = _toInt(v);
      if (i != null && i >= 1 && i <= 5) out[k.toString()] = i;
    });
    return out;
  }

  factory CheckInSubmissionModel.fromMap(Map<String, dynamic> m, String id) {
    final photos = m['photoUrls'];
    return CheckInSubmissionModel(
      id: id,
      clientId: (m['clientId'] ?? '').toString(),
      adminId: (m['adminId'] ?? '').toString(),
      authorId: (m['authorId'] ?? '').toString(),
      clientName: (m['clientName'] ?? '').toString(),
      weightKg: _toDouble(m['weightKg']),
      ratings: _parseRatings(m['ratings']),
      note: (m['note'] ?? '').toString(),
      photoUrls: photos is List
          ? photos.map((e) => e.toString()).toList()
          : const <String>[],
      status: (m['status'] ?? CheckInSubmissionStatus.submitted).toString(),
      submittedAt: _date(m['submittedAt']),
      updatedAt: _date(m['updatedAt']),
      reviewedAt: _date(m['reviewedAt']),
      coachResponse: (m['coachResponse'] ?? '').toString(),
      weekOf: (m['weekOf'] ?? '').toString(),
      reviewedByName: (m['reviewedByName'] ?? '').toString(),
    );
  }

  /// Data fields only (no server timestamps — the service stamps those).
  Map<String, dynamic> toMap() => {
        'clientId': clientId,
        'adminId': adminId,
        'authorId': authorId,
        'clientName': clientName,
        if (weightKg != null) 'weightKg': weightKg,
        'ratings': ratings,
        'note': note,
        'photoUrls': photoUrls,
        'status': status,
        if (weekOf.isNotEmpty) 'weekOf': weekOf,
      };
}
