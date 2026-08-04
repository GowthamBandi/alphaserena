import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';
import '../models/lifestyle_log_model.dart';

/// Writes the member's daily lifestyle log to `client_lifestyle_logs`
/// (functions-free; ownership enforced by security rules via the linked `clients`
/// doc). One doc per day, id '{clientId}_{dateKey}'.
///
/// SINCE WS-6 THIS IS A COMPATIBILITY PROJECTION, NOT THE RECORD. The member
/// records events in `client_lifestyle_days`; this document exists so
/// TrainerHQ's lifestyle review keeps rendering during the migration window.
/// It is derived, never typed.
class LifestyleLogService {
  LifestyleLogService({
    FirebaseFirestore? db,
    MemberController? member,
    this.ackTimeout = const Duration(seconds: 4),
  })  : _injectedDb = db,
        _injectedMember = member;

  final FirebaseFirestore? _injectedDb;
  final MemberController? _injectedMember;

  /// Both resolved LAZILY so a subclass can fake this service without a live
  /// Firebase app (see [CoachingEventWriter]).
  FirebaseFirestore get _db => _injectedDb ?? FirebaseFirestore.instance;

  MemberController get _member =>
      _injectedMember ??
      (Get.isRegistered<MemberController>()
          ? Get.find<MemberController>()
          : Get.put(MemberController()));

  /// Firestore's `set` Future resolves only on SERVER acknowledgement, so with
  /// no timeout it NEVER completes while offline. Every caller here used to
  /// await that Future, so a member tapping a glass on a train left a pending
  /// Future for the rest of the session — and any caller awaiting the mirror
  /// hung with it. Matches [CoachingEventWriter.ackTimeout].
  final Duration ackTimeout;

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

  /// Writes the whole projected day in ONE write.
  ///
  /// Was three sequential `setMetric` round trips per member tap (water, then
  /// sleep, then steps) — three writes, three acknowledgements, and the
  /// supplement checklist written by none of them, which is why a coach never
  /// saw a supplement the member had ticked.
  ///
  /// Returns true when the server acknowledged, false when the write was
  /// queued or rejected. Callers treat this as best-effort: the event is the
  /// record, this is only the bridge.
  Future<bool> mirrorDay({
    required String dateKey,
    required double waterMl,
    double? sleepHours,
    double? steps,
    List<SupplementIntake>? supplements,
  }) async {
    if (!canLog) return false;
    Map<String, dynamic> metric(double value) =>
        {'value': value, 'source': 'derived'};

    final op = _col.doc(_docId(dateKey)).set(
      {
        ..._base(dateKey),
        'waterMl': metric(waterMl),
        if (sleepHours != null) 'sleepHours': metric(sleepHours),
        if (steps != null) 'steps': metric(steps),
        if (supplements != null)
          'supplements': supplements.map((s) => s.toMap()).toList(),
      },
      SetOptions(merge: true),
    );
    try {
      await op.timeout(ackTimeout);
      return true;
    } on TimeoutException {
      // Committed to the local cache and replayed by the SDK on reconnect.
      // Adopt the orphaned Future so a late failure cannot surface as an
      // unhandled async error.
      unawaited(op.catchError((Object _) {}));
      return false;
    } catch (_) {
      return false;
    }
  }
}
