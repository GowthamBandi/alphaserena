import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';
import '../domain/workout_session.dart' show sessionCountsAsTrainingDay;
import '../utils/lifestyle_math.dart' show dayKey;

/// Read-side of the member's own activity logs, for streaks/consistency.
/// Index-free by design:
/// - `client_workout_sessions` (random ids): a single-field `authorId == uid`
///   query (auto-indexed), day-keys derived client-side.
/// - `client_diet_logs` (deterministic `{clientId}_{yyyy-MM-dd}` ids): per-day
///   doc gets — the exact read pattern the diet logger's restore already uses,
///   so no new rules or indexes are assumed.
///
/// Every method returns null on failure (offline / rules) so callers can show
/// an honest "unavailable" state instead of a fabricated zero.
class ActivityHistoryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final MemberController _member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  bool get canRead => _member.clientId.isNotEmpty && _member.uid.isNotEmpty;

  /// Day keys (local calendar) on which the member saved a workout session,
  /// within the last [windowDays]. Null on query failure.
  Future<Set<String>?> workoutDayKeys({int windowDays = 60}) async {
    if (!canRead) return null;
    try {
      final snap = await _db
          .collection(FsCollections.clientWorkoutSessions)
          .where('authorId', isEqualTo: _member.uid)
          .get();
      // AN EMPTY CACHE IS NOT AN EMPTY HISTORY.
      //
      // Offline, `get()` answers from the local cache and does NOT throw — so
      // a fresh install (or a cleared cache) returned an empty SET rather than
      // null, and a member with three months of training read "0 day streak ·
      // Start your first session." Only a served answer may assert that a
      // member has never trained; an unserved empty one is unavailable, which
      // the card already renders as "Offline — your streak is safe."
      if (snap.docs.isEmpty && snap.metadata.isFromCache) return null;
      // Day-ALIGNED cutoff. A raw `now - windowDays` is a time of day, so the
      // oldest day in the window was admitted or dropped depending on the hour
      // the member happened to open the app — the same session could be inside
      // the window at 9am and outside it at 6pm, moving a streak that had not
      // changed. The window is a set of CALENDAR days, so its edge is one too.
      final t = DateTime.now();
      final cutoff = DateTime(t.year, t.month, t.day)
          .subtract(Duration(days: windowDays - 1));
      final keys = <String>{};
      for (final d in snap.docs) {
        final data = d.data();
        final raw = data['date'];
        DateTime? date;
        if (raw is Timestamp) date = raw.toDate();
        if (raw is String) date = DateTime.tryParse(raw);
        if (date == null) continue;
        final day = DateTime(date.year, date.month, date.day);
        if (day.isBefore(cutoff)) continue;
        // THE definition of a training day — the same predicate the live
        // in-session update uses, so the number cannot change across a
        // restart. A session that is only skips marks presence for the coach
        // and is still readable by them; it is not a day the member trained.
        if (!sessionCountsAsTrainingDay(data)) continue;
        keys.add(dayKey(day));
      }
      return keys;
    } catch (_) {
      return null;
    }
  }

  /// Day keys on which the member logged their diet (≥1 marked item), within
  /// the last [windowDays]. Same rule-provable `authorId == uid` single-field
  /// query as workouts. (Per-day doc gets were the first design, but a read
  /// rule that references `resource.data` cannot evaluate against a
  /// NON-existent day doc — "no log yet" then reads as permission-denied and
  /// the whole streak went honest-unavailable.) Null on query failure.
  /// Days the member recorded ANY nutrition, for the streak.
  ///
  /// PHASE 3C — reads the canonical `client_nutrition_days` FIRST and unions
  /// the legacy `client_diet_logs` behind it.
  ///
  /// The union is what makes the migration invisible: Phase 3B stopped writing
  /// the legacy collection, so reading only that would have frozen every
  /// member's diet streak at the release, while reading only the new one would
  /// have ERASED the streak they had already built. A day counts if either
  /// source recorded it; a set naturally de-duplicates the overlap, so a member
  /// mid-migration is never counted twice.
  ///
  /// "Recorded nutrition" means at least one LIVE entry — a day whose only
  /// entry was removed is not a logged day, the same rule the day totals use.
  Future<Set<String>?> dietDayKeys({int windowDays = 60}) async {
    if (!canRead) return null;
    final cutoff = DateTime.now().subtract(Duration(days: windowDays));
    final keys = <String>{};
    var anySucceeded = false;

    bool inWindow(String key) {
      final date = DateTime.tryParse(key);
      return date != null && !date.isBefore(cutoff);
    }

    try {
      final snap = await _db
          .collection(FsCollections.clientNutritionDays)
          .where('authorUid', isEqualTo: _member.uid)
          .get();
      // Same rule as the workout half: an unserved empty answer is unknown,
      // not proof the member has never logged (see [workoutDayKeys]).
      if (!(snap.docs.isEmpty && snap.metadata.isFromCache)) anySucceeded = true;
      for (final d in snap.docs) {
        final data = d.data();
        final entries = data['entries'];
        if (entries is! Map) continue;
        final hasLive = entries.values.any(
          (e) => e is Map && e['deleted'] != true,
        );
        if (!hasLive) continue;
        final key = (data['dateKey'] ?? '').toString();
        if (inWindow(key)) keys.add(key);
      }
    } catch (_) {
      // Fall through: the legacy half may still answer.
    }

    try {
      final snap = await _db
          .collection(FsCollections.clientDietLogs)
          .where('authorId', isEqualTo: _member.uid)
          .get();
      if (!(snap.docs.isEmpty && snap.metadata.isFromCache)) anySucceeded = true;
      for (final d in snap.docs) {
        final data = d.data();
        final items = data['items'];
        if (items is! List || items.isEmpty) continue;
        final key = (data['dateKey'] ?? '').toString();
        if (inWindow(key)) keys.add(key);
      }
    } catch (_) {
      // Fall through.
    }

    // Null means "could not read", which the streak renders as unknown rather
    // than as a broken streak. Only claim that when BOTH reads failed.
    return anySucceeded ? keys : null;
  }
}
