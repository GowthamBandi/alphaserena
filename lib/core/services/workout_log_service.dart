import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';

/// Writes the member's own workout-performance logs to `client_workout_sessions`
/// (functions-free; ownership enforced by security rules using the member's
/// linked `clients` doc). One doc per workout session, upserted as the member
/// progresses (the screen saves per exercise).
class WorkoutLogService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final MemberController _member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsCollections.clientWorkoutSessions);

  /// The member must be linked to a gym `clients` doc to log (clientId + adminId).
  bool get canLog =>
      _member.clientId.isNotEmpty &&
      _member.adminId.isNotEmpty &&
      _member.uid.isNotEmpty;

  /// A fresh session doc id — generate once when the session starts.
  String newSessionId() => _col.doc().id;

  /// Upserts the session doc with the current [entries]. [markCreated] stamps
  /// `createdAt` (pass true only on the first save of a session). Returns false
  /// if the member isn't linked or the write fails.
  Future<bool> saveSession({
    required String sessionId,
    required String planName,
    String? planId,
    required DateTime date,
    required List<Map<String, dynamic>> entries,
    bool markCreated = false,
  }) async {
    if (!canLog) return false;
    final data = <String, dynamic>{
      'clientId': _member.clientId,
      'adminId': _member.adminId,
      'authorId': _member.uid,
      if (planId != null && planId.isNotEmpty) 'planId': planId,
      'planName': planName,
      'date': Timestamp.fromDate(date),
      'entries': entries,
      'updatedAt': FieldValue.serverTimestamp(),
      if (markCreated) 'createdAt': FieldValue.serverTimestamp(),
    };
    try {
      await _col.doc(sessionId).set(data, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }
}
