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

  /// Resolved LAZILY, not in a field initializer — the house pattern.
  ///
  /// `FirebaseFirestore.instance` throws without a live Firebase app and
  /// `Get.put(MemberController())` builds a member-scoped controller, and an
  /// eager field runs BOTH for every subclass too — even one that overrides
  /// every method. That is what made this service impossible to fake, and
  /// therefore made every screen built on it impossible to drive in a plain
  /// widget test. Nothing here needs Firebase until a read or a write happens.
  FirebaseFirestore? _injectedDb;
  FirebaseFirestore get _db => _injectedDb ??= FirebaseFirestore.instance;

  MemberController? _injectedMember;
  MemberController get _member {
    final held = _injectedMember;
    if (held != null) return held;
    final resolved = Get.isRegistered<MemberController>()
        ? Get.find<MemberController>()
        : Get.put(MemberController());
    _injectedMember = resolved;
    return resolved;
  }

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
    final all = await fetchSessionHistory();
    return all == null ? const [] : all.take(limit).toList();
  }

  /// EVERY session the member has logged, newest first — the read behind
  /// Workout History.
  ///
  /// The same single-field `authorId` query [fetchRecentSessions] already used,
  /// hoisted so there is exactly one query and one sort for both callers. It is
  /// unpaged on purpose: it is the identical query the streak repository runs
  /// on every cold open, so history costs the member nothing they were not
  /// already paying, and paging by date would need a composite index this
  /// codebase has deliberately never taken on.
  ///
  /// **Null means "could not read", `[]` means "nothing logged".** The two are
  /// different answers to different questions and history renders them
  /// differently: one is a connection problem, the other is a member who has
  /// not trained yet. [fetchRecentSessions] collapses them because exercise
  /// MEMORY genuinely does not care — a silent enhancement either way.
  Future<List<Map<String, dynamic>>?> fetchSessionHistory() async {
    if (!canLog) return null;
    try {
      final snap = await _col
          .where('authorId', isEqualTo: _member.uid)
          .get()
          .timeout(ackTimeout);
      // AN EMPTY CACHE IS NOT AN EMPTY HISTORY — the same rule
      // `ActivityHistoryService.workoutDayKeys` states at length. Offline,
      // `get()` answers from the local cache and does NOT throw, so a fresh
      // install would otherwise tell a member with months of training that they
      // have never trained.
      if (snap.docs.isEmpty && snap.metadata.isFromCache) return null;
      final docs = snap.docs
          .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
          .toList();
      docs.sort((a, b) {
        final da = a['date'], db = b['date'];
        final ma = da is Timestamp ? da.millisecondsSinceEpoch : 0;
        final mb = db is Timestamp ? db.millisecondsSinceEpoch : 0;
        return mb.compareTo(ma);
      });
      return docs;
    } catch (_) {
      return null;
    }
  }

  /// Rewrites the LOGGED PERFORMANCE of an existing session, and nothing else.
  ///
  /// A dedicated minimal write, for the same reason [saveMemberNote] is one and
  /// stated even more strongly here: **a correction must not restate the
  /// session's lifecycle.** Routing an edit through [saveSession] would re-send
  /// `status`, `date`, `startedAt`, `finishedAt` and `durationSeconds` from
  /// whatever the editing screen happened to be holding — so a member fixing a
  /// typo in one set could silently re-open a finished workout, move its date,
  /// or overwrite a two-hour duration with a null. This touches `entries` and
  /// `updatedAt`. The workout stays exactly as completed as it was; only the
  /// numbers inside it change.
  ///
  /// `updatedAt` IS re-stamped, deliberately: the coach's timeline should
  /// surface a session whose logged numbers changed after they read it.
  Future<WorkoutSaveResult> saveEditedEntries({
    required String sessionId,
    required List<Map<String, dynamic>> entries,
  }) async {
    if (!canLog) return WorkoutSaveResult.failed;
    // An empty entries array would ERASE every logged set behind a merge write.
    // No editing flow can legitimately produce one — the editor edits sets that
    // already exist — so an empty list is a bug upstream, and refusing is the
    // only safe answer.
    if (entries.isEmpty) return WorkoutSaveResult.failed;
    final op = _col.doc(sessionId).set(
      {'entries': entries, 'updatedAt': FieldValue.serverTimestamp()},
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

  /// Attaches — or RETRACTS — the member's closing message on an EXISTING
  /// session.
  ///
  /// A dedicated minimal write on purpose: routing this through
  /// [saveSession] would send `entries` and `date` too, and a merge-write
  /// carrying an empty entries list would erase every logged set while
  /// re-stamping the session's time. This touches two fields and nothing
  /// else.
  ///
  /// ── AN EMPTY NOTE IS A DELETION, NOT A FAILURE ────────────────────────
  ///
  /// This used to `return failed` on an empty string, borrowing the guard
  /// [saveEditedEntries] carries for a genuinely destructive case (an empty
  /// entries array erases every logged set). A note is not a set list: empty
  /// is a legitimate value, and clearing one is a thing the member is entitled
  /// to do. The editor's note field enables its Save button on any keystroke —
  /// deletion included — so a member who wrote a note and thought better of it
  /// tapped Save and was told **"Could not send that note — try again"**, at
  /// an action that could never succeed however many times they tried — and
  /// their coach kept reading the retracted note in TrainerHQ's
  /// `member_logs_session_screen`.
  ///
  /// This is the same defect the profile editor was already fixed for — a
  /// writer that skips empty values makes a field impossible to clear.
  ///
  /// The field is written as `''` rather than deleted: both apps parse it as
  /// `(m['memberNote'] ?? '').toString().trim()` and gate rendering on
  /// `isNotEmpty`, so an empty string and an absent field are already the same
  /// fact to every reader, and a plain value keeps the write a simple merge.
  ///
  /// The summary screen — the "add a note" surface, where empty means "I did
  /// not write one" rather than "remove mine" — still refuses empty itself,
  /// before it ever reaches here.
  Future<WorkoutSaveResult> saveMemberNote({
    required String sessionId,
    required String note,
  }) async {
    if (!canLog) return WorkoutSaveResult.failed;
    final trimmed = note.trim();
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
