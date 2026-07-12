import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';

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
      if (rating != null) 'rating': rating,
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
