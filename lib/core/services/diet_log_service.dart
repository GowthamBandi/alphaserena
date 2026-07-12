import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';
import '../models/client_diet_log_model.dart';

/// Writes the member's daily diet-adherence log to `client_diet_logs`
/// (functions-free; ownership enforced by security rules via the linked `clients`
/// doc — same shape as the workout/lifestyle logs). One doc per day, id
/// '{clientId}_{dateKey}', upserted as the member marks each prescribed food.
class DietLogService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final MemberController _member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsCollections.clientDietLogs);

  /// The member must be linked to a gym `clients` doc to log (clientId + adminId).
  bool get canLog =>
      _member.clientId.isNotEmpty &&
      _member.adminId.isNotEmpty &&
      _member.uid.isNotEmpty;

  String _docId(String dateKey) => '${_member.clientId}_$dateKey';

  /// Live stream of one day's log (null until the member marks something).
  Stream<ClientDietLogModel?> watchDay(String dateKey) {
    if (!canLog) return Stream.value(null);
    return _col.doc(_docId(dateKey)).snapshots().map(
        (s) => s.exists ? ClientDietLogModel.fromMap(s.data()!, s.id) : null);
  }

  /// Upserts the day's adherence. [items] is the full list of marked foods (see
  /// [DietLogItem.toMap]); [adherencePct] is the 0..1 fraction. [markCreated]
  /// stamps `createdAt` (pass true only when the doc doesn't exist yet).
  Future<bool> saveDay({
    required String dateKey,
    required String planName,
    required List<Map<String, dynamic>> items,
    required double adherencePct,
    bool markCreated = false,
  }) async {
    if (!canLog) return false;
    DateTime? day;
    try {
      day = DateTime.parse(dateKey);
    } catch (_) {
      day = null;
    }
    final data = <String, dynamic>{
      'clientId': _member.clientId,
      'adminId': _member.adminId,
      'authorId': _member.uid,
      'planName': planName,
      'dateKey': dateKey,
      if (day != null) 'date': Timestamp.fromDate(day),
      'adherencePct': adherencePct,
      'items': items,
      'updatedAt': FieldValue.serverTimestamp(),
      if (markCreated) 'createdAt': FieldValue.serverTimestamp(),
    };
    try {
      await _col.doc(_docId(dateKey)).set(data, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }
}
