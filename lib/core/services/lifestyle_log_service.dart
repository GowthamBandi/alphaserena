import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';
import '../models/lifestyle_log_model.dart';

/// Writes the member's daily lifestyle log to `client_lifestyle_logs`
/// (functions-free; ownership enforced by security rules via the linked `clients`
/// doc). One doc per day, id '{clientId}_{dateKey}', upserted as the member logs.
class LifestyleLogService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final MemberController _member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsCollections.clientLifestyleLogs);

  bool get canLog =>
      _member.clientId.isNotEmpty &&
      _member.adminId.isNotEmpty &&
      _member.uid.isNotEmpty;

  String _docId(String dateKey) => '${_member.clientId}_$dateKey';

  Map<String, dynamic> _base(String dateKey) => {
        'clientId': _member.clientId,
        'adminId': _member.adminId,
        'authorId': _member.uid,
        'date': dateKey,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Live stream of one day's log (null until the member logs something).
  Stream<LifestyleLogModel?> watchDay(String dateKey) {
    if (!canLog) return Stream.value(null);
    return _col.doc(_docId(dateKey)).snapshots().map(
        (s) => s.exists ? LifestyleLogModel.fromMap(s.data()!, s.id) : null);
  }

  /// Sets one numeric metric ('waterMl'|'steps'|'sleepHours'), tagging manual.
  Future<bool> setMetric({
    required String dateKey,
    required String field,
    required double value,
    int? quality,
  }) async {
    if (!canLog) return false;
    final metric = <String, dynamic>{
      'value': value,
      'source': 'manual',
      'quality': ?quality,
    };
    try {
      await _col.doc(_docId(dateKey)).set(
            {..._base(dateKey), field: metric},
            SetOptions(merge: true),
          );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Writes the full supplement checklist for the day.
  Future<bool> setSupplements(
      String dateKey, List<SupplementIntake> supplements) async {
    if (!canLog) return false;
    try {
      await _col.doc(_docId(dateKey)).set(
        {
          ..._base(dateKey),
          'supplements': supplements.map((s) => s.toMap()).toList(),
        },
        SetOptions(merge: true),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
