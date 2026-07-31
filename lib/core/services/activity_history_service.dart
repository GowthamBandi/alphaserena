import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';
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
      final cutoff = DateTime.now().subtract(Duration(days: windowDays));
      final keys = <String>{};
      for (final d in snap.docs) {
        final raw = d.data()['date'];
        DateTime? date;
        if (raw is Timestamp) date = raw.toDate();
        if (raw is String) date = DateTime.tryParse(raw);
        if (date == null || date.isBefore(cutoff)) continue;
        keys.add(dayKey(date));
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
  Future<Set<String>?> dietDayKeys({int windowDays = 60}) async {
    if (!canRead) return null;
    try {
      final snap = await _db
          .collection(FsCollections.clientDietLogs)
          .where('authorId', isEqualTo: _member.uid)
          .get();
      final cutoff = DateTime.now().subtract(Duration(days: windowDays));
      final keys = <String>{};
      for (final d in snap.docs) {
        final data = d.data();
        final items = data['items'];
        if (items is! List || items.isEmpty) continue;
        final key = (data['dateKey'] ?? '').toString();
        final date = DateTime.tryParse(key);
        if (date == null || date.isBefore(cutoff)) continue;
        keys.add(key);
      }
      return keys;
    } catch (_) {
      return null;
    }
  }
}
