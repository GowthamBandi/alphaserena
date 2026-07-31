import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// One of the member's own feedback submissions, including the coach's reply
/// when present — the member-side read view of `client_feedback`.
class MyFeedbackEntry {
  final String id;
  final String category;
  final String message;
  final String status; // 'open' | 'resolved'
  final String? adminResponse;
  final DateTime? respondedAt;
  final DateTime? createdAt;

  const MyFeedbackEntry({
    required this.id,
    required this.category,
    required this.message,
    required this.status,
    this.adminResponse,
    this.respondedAt,
    this.createdAt,
  });

  bool get hasReply =>
      adminResponse != null && adminResponse!.trim().isNotEmpty;
  bool get isResolved => status == 'resolved';

  factory MyFeedbackEntry.fromMap(Map<String, dynamic> m, String id) {
    final resp = (m['adminResponse'] ?? '').toString().trim();
    return MyFeedbackEntry(
      id: id,
      category: (m['category'] ?? 'other').toString(),
      message: (m['message'] ?? '').toString(),
      status: (m['status'] ?? 'open').toString(),
      adminResponse: resp.isEmpty ? null : resp,
      respondedAt: _date(m['respondedAt']),
      createdAt: _date(m['createdAt']),
    );
  }
}

/// Writes member → owning-admin feedback / complaints to `client_feedback`
/// (ownership enforced by rules via the linked `clients` doc, keyed on
/// `authUid`). Trainers cannot read it — only the owning admin responds. One
/// doc per submission.
class FeedbackService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final MemberController _member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsCollections.clientFeedback);

  bool get canSend =>
      _member.clientId.isNotEmpty &&
      _member.adminId.isNotEmpty &&
      _member.uid.isNotEmpty;

  /// The member's own submissions (rules: readable where authUid == uid),
  /// newest first. This is where the coach's reply becomes visible.
  Stream<List<MyFeedbackEntry>> watchMine() {
    final uid = _member.uid;
    if (uid.isEmpty) return const Stream.empty();
    return _col.where('authUid', isEqualTo: uid).snapshots().map((s) {
      final list = s.docs
          .map((d) => MyFeedbackEntry.fromMap(d.data(), d.id))
          .toList();
      // Null createdAt = just-written pending serverTimestamp → rank newest.
      final now = DateTime.now();
      list.sort(
          (a, b) => (b.createdAt ?? now).compareTo(a.createdAt ?? now));
      return list;
    });
  }

  /// Submits a feedback packet. [category] MUST be a canonical FeedbackCategory
  /// id ('trainer'|'plans'|'service'|'app'|'billing'|'other') — TrainerHQ's
  /// `FeedbackCategoryX.fromId` matches these exactly (a display label would
  /// silently collapse into the 'Other' bucket). Pass [trainerId]/[trainerName]
  /// for 'trainer' feedback so the coach inbox can show which trainer it's about.
  /// Returns the doc id, or null if the member isn't linked / the write fails.
  Future<String?> submit({
    required String category,
    required String message,
    int? rating,
    bool anonymous = false,
    bool requestTrainerChange = false,
    String? trainerId,
    String? trainerName,
  }) async {
    if (!canSend) return null;
    final data = <String, dynamic>{
      'authUid': _member.uid,
      'adminId': _member.adminId,
      'clientId': _member.clientId,
      'clientName': _member.name,
      'category': category,
      'message': message.trim(),
      'rating': ?rating,
      if (trainerId != null && trainerId.isNotEmpty) 'trainerId': trainerId,
      if (trainerName != null && trainerName.isNotEmpty)
        'trainerName': trainerName,
      'anonymous': anonymous,
      'requestTrainerChange': requestTrainerChange,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    };
    try {
      final doc = await _col.add(data);
      return doc.id;
    } catch (_) {
      return null;
    }
  }
}
