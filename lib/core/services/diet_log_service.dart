import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';
import '../models/client_diet_log_model.dart';

/// What happened to a day's save.
///
/// [queued] is deliberately NOT a failure. Distinguishing it from [failed] is
/// the whole point: a member logging meals with no signal has lost nothing —
/// the marks are in the local cache and will replay — and telling them "could
/// not save" would be false and would push them to re-tap or give up.
enum DietSaveResult { synced, queued, failed }

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

  /// How long to wait for the SERVER to acknowledge a save before treating it
  /// as queued offline.
  ///
  /// Firestore applies a write to the local cache immediately but does not
  /// complete the returned Future until the server acknowledges it — so with no
  /// connection it never completes at all. A permission or validation failure,
  /// by contrast, comes back quickly. This window separates the two: long
  /// enough that a slow gym-wifi round trip still reports as saved, short
  /// enough that a member on no signal is not left watching a spinner.
  static const Duration ackTimeout = Duration(seconds: 4);

  /// Upserts the day's adherence. [items] is the full list of marked foods (see
  /// [DietLogItem.toMap]); [adherencePct] is the 0..1 fraction. [markCreated]
  /// stamps `createdAt` (pass true only when the doc doesn't exist yet).
  Future<DietSaveResult> saveDay({
    required String dateKey,
    required String planName,
    required List<Map<String, dynamic>> items,
    required double adherencePct,
    bool markCreated = false,
  }) async {
    if (!canLog) return DietSaveResult.failed;
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
    // The write is already in the local cache by the time this Future is
    // created; awaiting it only waits for the SERVER. Time-boxing that wait is
    // what turns "offline" from an endless spinner into an honest,
    // non-blocking "saved on this device".
    final op = _col.doc(_docId(dateKey)).set(data, SetOptions(merge: true));
    try {
      await op.timeout(ackTimeout);
      return DietSaveResult.synced;
    } on TimeoutException {
      // Not an error: Firestore holds the write and replays it on reconnect,
      // so the member's marks are safe and already visible locally.
      //
      // `timeout` does not cancel the underlying write — it stays pending and
      // may complete or FAIL minutes later, long after nobody is awaiting it.
      // An unawaited failure becomes an unhandled async error and can take the
      // isolate down, so the abandoned operation is adopted here. The member
      // has already been told the truth; a late server rejection is nothing
      // they can act on from this screen.
      unawaited(op.catchError((Object _) {}));
      return DietSaveResult.queued;
    } catch (_) {
      return DietSaveResult.failed;
    }
  }
}
