import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';

/// How a session save landed. Mirrors the diet logger's proven offline
/// contract: [queued] means Firestore's local persistence holds the write and
/// will sync it — the data is safe, the member is told the truth.
enum WorkoutSaveResult { synced, queued, failed }

/// Writes the member's own workout-performance logs to `client_workout_sessions`
/// (functions-free; ownership enforced by security rules using the member's
/// linked `clients` doc). One doc per DAY per member (Phase 1: deterministic
/// identity), upserted as the member progresses.
class WorkoutLogService {
  /// How long a write may wait for the server before being reported as
  /// queued-locally. The write itself is NOT cancelled by the timeout — it
  /// stays pending in Firestore's offline queue and syncs on reconnect.
  static const Duration ackTimeout = Duration(seconds: 4);

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

  String get clientId => _member.clientId;

  /// Fetches one session doc (server first, cache fallback so a same-day
  /// resume works offline). Null when absent or unreadable.
  Future<Map<String, dynamic>?> fetchSession(String sessionId) async {
    try {
      final snap = await _col.doc(sessionId).get().timeout(ackTimeout);
      return snap.data();
    } catch (_) {
      try {
        final snap =
            await _col.doc(sessionId).get(const GetOptions(source: Source.cache));
        return snap.data();
      } catch (_) {
        return null;
      }
    }
  }

  /// The member's own recent sessions — the source of exercise MEMORY ("what
  /// did I do last time"). Single-field query by `authorId` so no composite
  /// index is needed (the same index-free discipline as
  /// `ActivityHistoryService`); sorted and trimmed client-side. Returns []
  /// on any failure — memory is an enhancement and must never block a
  /// workout, and an unreadable history is silence, never invented numbers.
  Future<List<Map<String, dynamic>>> fetchRecentSessions({
    int limit = 30,
  }) async {
    if (!canLog) return const [];
    try {
      final snap = await _col
          .where('authorId', isEqualTo: _member.uid)
          .get()
          .timeout(ackTimeout);
      final docs = snap.docs
          .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
          .toList();
      docs.sort((a, b) {
        final da = a['date'], db = b['date'];
        final ma = da is Timestamp ? da.millisecondsSinceEpoch : 0;
        final mb = db is Timestamp ? db.millisecondsSinceEpoch : 0;
        return mb.compareTo(ma);
      });
      return docs.take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Attaches the member's closing message to an EXISTING session.
  ///
  /// A dedicated minimal write on purpose: routing this through
  /// [saveSession] would send `entries` and `date` too, and a merge-write
  /// carrying an empty entries list would erase every logged set while
  /// re-stamping the session's time. This touches two fields and nothing
  /// else.
  Future<WorkoutSaveResult> saveMemberNote({
    required String sessionId,
    required String note,
  }) async {
    if (!canLog) return WorkoutSaveResult.failed;
    final trimmed = note.trim();
    if (trimmed.isEmpty) return WorkoutSaveResult.failed;
    final op = _col.doc(sessionId).set(
      {'memberNote': trimmed, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    try {
      await op.timeout(ackTimeout);
      return WorkoutSaveResult.synced;
    } on TimeoutException {
      return WorkoutSaveResult.queued;
    } catch (_) {
      return WorkoutSaveResult.failed;
    }
  }

  /// Upserts the session doc with the current [entries] and lifecycle facts.
  /// [markCreated] stamps `createdAt` (first save of the session only).
  Future<WorkoutSaveResult> saveSession({
    required String sessionId,
    required String planName,
    String? planId,
    required DateTime date,
    required List<Map<String, dynamic>> entries,
    required String status,
    DateTime? startedAt,
    DateTime? finishedAt,
    int? durationSeconds,
    bool markCreated = false,
  }) async {
    if (!canLog) return WorkoutSaveResult.failed;
    final effectivePlanId =
        (planId != null && planId.isNotEmpty) ? planId : null;
    final startedTs = startedAt != null ? Timestamp.fromDate(startedAt) : null;
    final finishedTs =
        finishedAt != null ? Timestamp.fromDate(finishedAt) : null;
    final data = <String, dynamic>{
      'clientId': _member.clientId,
      'adminId': _member.adminId,
      'authorId': _member.uid,
      'planId': ?effectivePlanId,
      'planName': planName,
      'date': Timestamp.fromDate(date),
      'entries': entries,
      'status': status,
      'startedAt': ?startedTs,
      'finishedAt': ?finishedTs,
      'durationSeconds': ?durationSeconds,
      'updatedAt': FieldValue.serverTimestamp(),
      if (markCreated) 'createdAt': FieldValue.serverTimestamp(),
    };
    final op = _col.doc(sessionId).set(data, SetOptions(merge: true));
    try {
      await op.timeout(ackTimeout);
      return WorkoutSaveResult.synced;
    } on TimeoutException {
      // `timeout` does not cancel the underlying write — offline it stays in
      // Firestore's persistence queue and syncs on reconnect. That is a SAVED
      // state, not an error, and the member must not be told otherwise.
      return WorkoutSaveResult.queued;
    } catch (_) {
      return WorkoutSaveResult.failed;
    }
  }
}
