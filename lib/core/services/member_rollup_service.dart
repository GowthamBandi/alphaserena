import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';

/// One day of a member's lifestyle, as the SERVER derived it.
///
/// Every value here was computed by `onLifestyleDayWritten` from the member's
/// own recorded events. Neither app re-derives them.
class RollupDay {
  final DateTime date;
  final double? waterMl;
  final double? steps;
  final double? sleepHours;

  /// Supplement items TAKEN that day, and how many doses they represent.
  final int? supplementItems;
  final int? supplementDoses;

  const RollupDay({
    required this.date,
    this.waterMl,
    this.steps,
    this.sleepHours,
    this.supplementItems,
    this.supplementDoses,
  });

  static double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Parses one `tracks.lifestyle.days.{yyyy-MM-dd}` cell.
  ///
  /// A metric the day never recorded stays NULL rather than becoming 0 —
  /// "did not log" and "logged none" are different facts, and every surface in
  /// this platform keeps them apart.
  static RollupDay? fromCell(String dateKey, Object? raw) {
    final date = DateTime.tryParse(dateKey);
    if (date == null || raw is! Map) return null;
    final metrics = raw['metrics'];
    if (metrics is! Map) {
      return RollupDay(date: DateTime(date.year, date.month, date.day));
    }
    final items = _num(metrics['supplementItems']);
    final doses = _num(metrics['supplementDoses']);
    return RollupDay(
      date: DateTime(date.year, date.month, date.day),
      waterMl: _num(metrics['waterMl']),
      steps: _num(metrics['steps']),
      sleepHours: _sleepHours(metrics),
      supplementItems: items?.round(),
      supplementDoses: doses?.round(),
    );
  }

  /// Sleep, from the field the SERVER actually writes.
  ///
  /// 🔴 This read `metrics['sleepHours']`, a key nothing has ever written.
  /// `deriveLifestyleMetrics` emits **`sleepMinutes`** (and so does the legacy
  /// converter, which multiplies stored hours BY 60 on the way in) — TrainerHQ
  /// reads `sleepMinutes` and divides. So every sleep the member recorded
  /// reached their coach correctly and read as NULL in their own app: the
  /// member's sleep history was permanently "No sleep history yet", with no
  /// streak, average, trend or calendar, no matter how faithfully they logged.
  ///
  /// It survived because the parser's test fed it a hand-made
  /// `{'sleepHours': 7.5}` cell — a fixture asserting the wrong contract
  /// rather than the one the backend emits.
  ///
  /// `sleepHours` is still accepted as a fallback: it costs nothing and covers
  /// any cell an older build may have written.
  static double? _sleepHours(Map metrics) {
    final minutes = _num(metrics['sleepMinutes']);
    if (minutes != null) return minutes / 60.0;
    return _num(metrics['sleepHours']);
  }
}

/// THE MEMBER'S OWN LIFESTYLE HISTORY, from `coaching_rollups`.
///
/// Deliberately the SAME collection TrainerHQ reads. The member's history and
/// their coach's are then the same server-derived numbers rather than two apps
/// deriving history separately from raw events — which is the only way the two
/// can be guaranteed never to disagree about a past day.
///
/// The member's read is permitted by the rules' own clause
/// (`clients/{clientId}.authUid == request.auth.uid`) and is proven in
/// `trainershq-backend/tests/rules/member_rollup_read.mjs`, including that a
/// MISSING month reads as empty rather than denied — the defect that once
/// showed coaches a connection error for a member whose history was intact.
///
/// One document per MONTH, not one per day: a 3-month history is three reads.
class MemberRollupService extends GetxService {
  MemberRollupService({FirebaseFirestore? db, MemberController? member})
      : _injectedDb = db,
        _injectedMember = member;

  final FirebaseFirestore? _injectedDb;
  final MemberController? _injectedMember;

  /// Both resolved LAZILY so a subclass can fake this service without a live
  /// Firebase app — the pattern the rest of this codebase now follows.
  FirebaseFirestore get _db => _injectedDb ?? FirebaseFirestore.instance;

  MemberController get _member =>
      _injectedMember ??
      (Get.isRegistered<MemberController>()
          ? Get.find<MemberController>()
          : Get.put(MemberController()));

  /// How many months of history a screen reads by default.
  ///
  /// Matches TrainerHQ's `CoachingRollupService.defaultMonths`, so a member and
  /// their coach see the same depth. Changing one without the other would let
  /// a coach reference a month the member cannot open.
  static const int defaultMonths = 3;

  bool get canRead => _member.clientId.isNotEmpty;

  /// `yyyy-MM` keys for the last [months], newest first.
  static List<String> monthKeys(DateTime now, int months) => [
        for (var i = 0; i < months; i++)
          _monthKey(DateTime(now.year, now.month - i)),
      ];

  static String _monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}';

  /// Live stream of the member's lifestyle days across the window.
  ///
  /// One listener per month. Each month emits independently and the merged
  /// view re-renders with whatever has arrived, so a slow month never blocks
  /// the rest — and a month that FAILS to read leaves its own days empty
  /// rather than taking the whole history down.
  Stream<List<RollupDay>> watchDays({int months = defaultMonths, DateTime? now}) {
    if (!canRead) return Stream.value(const []);
    final keys = monthKeys(now ?? DateTime.now(), months);
    final latest = <String, List<RollupDay>>{};
    late final StreamController<List<RollupDay>> controller;
    final subs = <StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>[];

    void publish() {
      if (controller.isClosed) return;
      final all = <RollupDay>[];
      for (final k in keys) {
        all.addAll(latest[k] ?? const []);
      }
      all.sort((a, b) => b.date.compareTo(a.date)); // newest first
      controller.add(all);
    }

    controller = StreamController<List<RollupDay>>(
      onListen: () {
        for (final key in keys) {
          subs.add(
            _db
                .collection(FsCollections.coachingRollups)
                .doc('${_member.clientId}_$key')
                .snapshots()
                .listen(
              (snap) {
                latest[key] = daysFrom(snap.data());
                publish();
              },
              // A month that cannot be read must not take the window down.
              onError: (_) {
                latest[key] = const [];
                publish();
              },
            ),
          );
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return controller.stream;
  }

  /// Parses a monthly rollup document into its lifestyle days.
  ///
  /// `tracks.lifestyle.days` is a NESTED map. It is read that way rather than
  /// by a dotted key because `set()` does not interpret dots as field paths —
  /// the writer's dotted key once produced one field whose literal NAME
  /// contained dots and no `tracks` map at all, and every reader silently saw
  /// an empty rollup. Pinned on the backend by `coaching_rollup_shape.test.mjs`.
  static List<RollupDay> daysFrom(Map<String, dynamic>? doc) {
    if (doc == null) return const [];
    final tracks = doc['tracks'];
    if (tracks is! Map) return const [];
    final lifestyle = tracks['lifestyle'];
    if (lifestyle is! Map) return const [];
    final days = lifestyle['days'];
    if (days is! Map) return const [];
    final out = <RollupDay>[];
    for (final entry in days.entries) {
      final day = RollupDay.fromCell(entry.key.toString(), entry.value);
      if (day != null) out.add(day);
    }
    return out;
  }
}
