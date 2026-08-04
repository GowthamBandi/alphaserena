import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';

/// One day of the SERVER-COMPUTED nutrition rollup.
///
/// Every number here was calculated by `onNutritionDayWritten`
/// (`trainershq-backend/functions/src/nutrition.ts`) from the member's own food
/// log. Nothing is re-derived on the client — the trigger owns that arithmetic
/// and this reads its output, which is what lets a member's Progress screen and
/// their coach's dashboard state the same figure for the same day.
class NutritionRollupDay {
  final DateTime date;

  /// Per-macro consumed/target in 0..1, as the backend clamped it. EMPTY when
  /// the day had no targets — an unset target is never scored as a miss.
  final Map<String, double> targetAdherence;

  /// Consumed totals (calories / protein / carbs / fat / fiber). A macro the
  /// day never recorded is ABSENT, never zero.
  final Map<String, double> totals;

  final int entryCount;

  const NutritionRollupDay({
    required this.date,
    this.targetAdherence = const {},
    this.totals = const {},
    this.entryCount = 0,
  });

  double? get calories => totals['calories'];
  double? get protein => totals['protein'];

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static Map<String, double> _numMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, double>{};
    for (final e in raw.entries) {
      final v = _num(e.value);
      if (v != null) out[e.key.toString()] = v;
    }
    return out;
  }

  /// Parses one `days.{yyyy-MM-dd}` cell.
  ///
  /// Returns null for an unparseable day key rather than falling back to "now":
  /// a corrupt cell that impersonates today would silently join every window,
  /// average and streak the member is shown. That exact fallback has bitten
  /// this platform before in the lifestyle read model.
  static NutritionRollupDay? fromCell(String dateKey, Object? raw) {
    final date = DateTime.tryParse(dateKey);
    if (date == null || raw is! Map) return null;
    final cell = Map<String, dynamic>.from(raw);
    return NutritionRollupDay(
      date: DateTime(date.year, date.month, date.day),
      targetAdherence: _numMap(cell['targetAdherence']),
      totals: _numMap(cell['totals']),
      entryCount: (_num(cell['entryCount']) ?? 0).round(),
    );
  }
}

/// THE MEMBER'S OWN NUTRITION HISTORY, from `nutrition_rollups`.
///
/// ── WHY THIS SERVICE EXISTS ────────────────────────────────────────────────
///
/// `nutrition_rollups` was a WRITE-ONLY collection. `onNutritionDayWritten` has
/// been maintaining a monthly document per member — schema-versioned, indexed
/// `[adminId, month↓]`, rules-protected, with a member read clause already in
/// place — and a repository-wide search found ZERO readers in either Flutter
/// app. The platform was paying to compute and store a read model nobody
/// opened.
///
/// It is exactly the read model a long-range Progress screen needs. The
/// alternative was opening one `client_nutrition_days` listener per day: a year
/// of nutrition history would be 365 listeners against a collection whose
/// composite index is `[adminId, clientId, dateKey↓]`. This is 12 document
/// reads for the same year, and — more importantly — it returns the SAME
/// numbers the coach's app is looking at rather than a second client-side
/// derivation of them.
///
/// Mirrors `MemberRollupService` (lifestyle) exactly: one listener per month,
/// independent failure, no composite index required (document reads by
/// deterministic id).
class NutritionRollupService extends GetxService {
  NutritionRollupService({FirebaseFirestore? db, MemberController? member})
    : _injectedDb = db,
      _injectedMember = member;

  final FirebaseFirestore? _injectedDb;
  final MemberController? _injectedMember;

  /// Both resolved LAZILY so a fake can stand in without a live Firebase app —
  /// the house pattern. Resolving Firebase in a field initializer is a recurring
  /// defect class in this codebase and has made four services untestable.
  FirebaseFirestore get _db => _injectedDb ?? FirebaseFirestore.instance;

  MemberController get _member =>
      _injectedMember ??
      (Get.isRegistered<MemberController>()
          ? Get.find<MemberController>()
          : Get.put(MemberController()));

  bool get canRead => _member.clientId.isNotEmpty;

  /// `yyyy-MM` keys for the last [months], newest first.
  static List<String> monthKeys(DateTime now, int months) => [
    for (var i = 0; i < months; i++)
      _monthKey(DateTime(now.year, now.month - i)),
  ];

  static String _monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}';

  /// Live stream of the member's nutrition days across the window.
  ///
  /// One listener per month, each emitting independently, so a slow month never
  /// blocks the rest and a month that FAILS to read leaves its own days empty
  /// rather than taking the whole history down. A missing document reads as
  /// EMPTY, not as an error — the rules carry the `resource == null` clause for
  /// precisely this, because a member who has not logged in a given month has no
  /// document for it and the first such month would otherwise deny the read.
  Stream<List<NutritionRollupDay>> watchDays({
    int months = 3,
    DateTime? now,
  }) {
    if (!canRead) return Stream.value(const []);
    final keys = monthKeys(now ?? DateTime.now(), months);
    final latest = <String, List<NutritionRollupDay>>{};
    late final StreamController<List<NutritionRollupDay>> controller;
    final subs = <StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>[];

    void publish() {
      if (controller.isClosed) return;
      final all = <NutritionRollupDay>[];
      for (final k in keys) {
        all.addAll(latest[k] ?? const []);
      }
      all.sort((a, b) => b.date.compareTo(a.date)); // newest first
      controller.add(all);
    }

    controller = StreamController<List<NutritionRollupDay>>(
      onListen: () {
        for (final key in keys) {
          subs.add(
            _db
                .collection(FsCollections.nutritionRollups)
                .doc('${_member.clientId}_$key')
                .snapshots()
                .listen(
                  (snap) {
                    latest[key] = daysFrom(snap.data());
                    publish();
                  },
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

  /// Parses a monthly rollup document into its days.
  ///
  /// `days` is a NESTED map, read that way rather than by a dotted key. `set()`
  /// does not interpret dots as field paths — only `update()` does — and a
  /// computed key of `days.2026-08-14` was once written as ONE field whose
  /// literal NAME contained dots, leaving the document with no `days` map at
  /// all and every reader silently seeing an empty rollup. That defect shipped
  /// in the lifestyle twin and was caught here before any reader existed;
  /// `functions/test/` pins the written shape on the backend side.
  static List<NutritionRollupDay> daysFrom(Map<String, dynamic>? doc) {
    if (doc == null) return const [];
    final days = doc['days'];
    if (days is! Map) return const [];
    final out = <NutritionRollupDay>[];
    for (final e in days.entries) {
      final day = NutritionRollupDay.fromCell(e.key.toString(), e.value);
      if (day != null) out.add(day);
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }
}
