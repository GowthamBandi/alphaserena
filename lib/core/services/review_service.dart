import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/firestore_collections.dart';

/// The signed-in member's review of their organization. One per member per org.
class OrgReview {
  final int rating; // 1..5
  final String comment;
  final DateTime? updatedAt;

  const OrgReview({required this.rating, this.comment = '', this.updatedAt});

  factory OrgReview.fromMap(Map<String, dynamic> m) => OrgReview(
    rating: (m['rating'] is num) ? (m['rating'] as num).round() : 0,
    comment: (m['comment'] ?? '').toString(),
    updatedAt: _date(m['updatedAt']) ?? _date(m['createdAt']),
  );
}

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

class CoachReview {
  final String coachId;
  final String clientId;
  final int rating;
  final String comment;
  final DateTime? updatedAt;

  const CoachReview({
    required this.coachId,
    required this.clientId,
    required this.rating,
    this.comment = '',
    this.updatedAt,
  });

  factory CoachReview.fromMap(Map<String, dynamic> map) => CoachReview(
    coachId: (map['coachId'] ?? '').toString(),
    clientId: (map['clientId'] ?? '').toString(),
    rating: map['rating'] is num ? (map['rating'] as num).round() : 0,
    comment: (map['comment'] ?? '').toString(),
    updatedAt: _date(map['updatedAt']) ?? _date(map['createdAt']),
  );
}

/// Writes/reads a member's rating + comment for their organization.
///
/// The document id is deterministic — `{adminId}_{clientId}` — so a member has
/// exactly one review per org and re-submitting edits it. The security rules
/// only allow the write when the member's `clients` doc has
/// `membershipActive == true`. The aggregate rating/reviewCount on
/// `organizationProfiles` is recomputed server-side by the onOrgReviewWritten
/// Cloud Function (members can't write those fields directly).
class ReviewService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _docId(String adminId, String clientId) => '${adminId}_$clientId';

  DocumentReference<Map<String, dynamic>> _ref(
    String adminId,
    String clientId,
  ) => _db.collection(FsCollections.orgReviews).doc(_docId(adminId, clientId));

  /// Live stream of the member's own review (null until they've rated).
  Stream<OrgReview?> watchMyReview(String adminId, String clientId) {
    if (adminId.isEmpty || clientId.isEmpty) {
      return const Stream<OrgReview?>.empty();
    }
    return _ref(adminId, clientId).snapshots().map(
      (snap) => snap.exists ? OrgReview.fromMap(snap.data() ?? {}) : null,
    );
  }

  /// Create or update the member's review. [rating] must be 1..5.
  Future<void> submit({
    required String adminId,
    required String clientId,
    required String authUid,
    required String memberName,
    required int rating,
    required String comment,
  }) async {
    final ref = _ref(adminId, clientId);
    final exists = (await ref.get()).exists;
    final now = FieldValue.serverTimestamp();
    await ref.set({
      'adminId': adminId,
      'clientId': clientId,
      'authUid': authUid,
      'memberName': memberName,
      'rating': rating,
      'comment': comment.trim(),
      'updatedAt': now,
      if (!exists) 'createdAt': now,
    }, SetOptions(merge: true));
  }
}

/// Normalized coach reviews. Current review is deterministic; history is the
/// same collection filtered by author, never a duplicated snapshot timeline.
class CoachReviewService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _docId(String coachId, String clientId) => '${coachId}_$clientId';

  Stream<CoachReview?> watchCurrent(String coachId, String clientId) {
    if (coachId.isEmpty || clientId.isEmpty) return Stream.value(null);
    return _db
        .collection(FsCollections.coachReviews)
        .doc(_docId(coachId, clientId))
        .snapshots()
        .map(
          (d) => d.exists ? CoachReview.fromMap(d.data() ?? const {}) : null,
        );
  }

  Stream<List<CoachReview>> watchMine(String authUid) {
    if (authUid.isEmpty) return Stream.value(const []);
    return _db
        .collection(FsCollections.coachReviews)
        .where('authUid', isEqualTo: authUid)
        .snapshots()
        .map((q) {
          final list = q.docs
              .map((d) => CoachReview.fromMap(d.data()))
              .toList();
          list.sort(
            (a, b) => (b.updatedAt ?? DateTime(1970)).compareTo(
              a.updatedAt ?? DateTime(1970),
            ),
          );
          return list;
        });
  }

  Future<void> submit({
    required String coachId,
    required String adminId,
    required String clientId,
    required String authUid,
    required int rating,
    required String comment,
  }) async {
    final ref = _db
        .collection(FsCollections.coachReviews)
        .doc(_docId(coachId, clientId));
    final exists = (await ref.get()).exists;
    final now = FieldValue.serverTimestamp();
    await ref.set({
      'coachId': coachId,
      'adminId': adminId,
      'clientId': clientId,
      'authUid': authUid,
      'rating': rating,
      'comment': comment.trim(),
      'updatedAt': now,
      if (!exists) 'createdAt': now,
    }, SetOptions(merge: true));
  }
}
