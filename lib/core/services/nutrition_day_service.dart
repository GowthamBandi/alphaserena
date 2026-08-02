import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';
import '../models/nutrition_day_model.dart';
import 'diet_log_service.dart' show DietSaveResult;

export 'diet_log_service.dart' show DietSaveResult;

/// NIP PHASE 3A — the member's Food Log writer (`client_nutrition_days`).
///
/// Records what the member ACTUALLY ate. Its sibling [DietLogService] records
/// adherence to what the coach PRESCRIBED; the two are deliberately separate
/// documents because a recommendation never changes and a log must be free to
/// record a food no plan mentions.
///
/// THREE PROPERTIES THIS FILE EXISTS TO GUARANTEE:
///
///  1. **One tap writes one field path.** Every write is a NESTED
///     `{'entries': {entryId: {...}}}` under `SetOptions(merge: true)`, which
///     deep-merges: sibling entries are untouched. Two devices adding
///     different foods to the same meal both land. The legacy diet log
///     rewrites a whole array, which is how concurrent edits get lost.
///
///  2. **Never a dotted key.** `set()` does NOT interpret dots as field paths
///     — only `update()` does — so `{'entries.$id': …}` would write ONE field
///     whose literal NAME contained a dot and no `entries` map would exist.
///     That exact defect shipped twice in this platform's rollup writers and
///     returned empty analytics for every member until it was found. Nested
///     maps only, here and everywhere.
///
///  3. **Offline is not failure.** Firestore applies the write to the local
///     cache immediately and replays it on reconnect. [DietSaveResult.queued]
///     is reused rather than reinvented so the member sees the same honest
///     "saved on this device" language they already get for diet and lifestyle.
class NutritionDayService {
  NutritionDayService({FirebaseFirestore? db, MemberController? member})
      : _injectedDb = db,
        _injectedMember = member;

  final FirebaseFirestore? _injectedDb;
  final MemberController? _injectedMember;

  /// Both resolved LAZILY. `FirebaseFirestore.instance` and constructing a
  /// `MemberController` each require a live Firebase app, and doing that in a
  /// constructor makes the class untestable even when every method is faked.
  FirebaseFirestore get _db => _injectedDb ?? FirebaseFirestore.instance;

  MemberController get _member =>
      _injectedMember ??
      (Get.isRegistered<MemberController>()
          ? Get.find<MemberController>()
          : Get.put(MemberController()));

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsCollections.clientNutritionDays);

  /// See [DietLogService.ackTimeout] — the same window, for the same reason.
  static const Duration ackTimeout = Duration(seconds: 4);

  /// The member must be linked to a gym `clients` doc to log.
  bool get canLog =>
      _member.clientId.isNotEmpty &&
      _member.adminId.isNotEmpty &&
      _member.uid.isNotEmpty;

  String docIdFor(String dateKey) => '${_member.clientId}_$dateKey';

  /// Live stream of one day (null until the member logs their first food).
  Stream<NutritionDayModel?> watchDay(String dateKey) {
    if (!canLog) return Stream.value(null);
    return _col.doc(docIdFor(dateKey)).snapshots().map(
          (s) => s.exists ? NutritionDayModel.fromMap(s.data()!, s.id) : null,
        );
  }

  /// The most days a single history fetch may read.
  ///
  /// History is read by DETERMINISTIC ID, one `get` per day, never a query —
  /// so it needs no composite index and can never scan a member's whole
  /// past. The cap is what keeps "one screen open" bounded: a member two
  /// years in still costs at most this many reads per page.
  static const int maxHistoryDays = 31;

  /// Fetches a bounded window of past days, newest first.
  ///
  /// Days the member never logged are simply ABSENT from the result rather
  /// than present-and-empty: "no document" and "a day with nothing in it" are
  /// the same fact to a reader, and returning placeholders would make an
  /// untouched month look like a month of zeroes.
  ///
  /// Reads come from the Firestore CACHE first when offline, because these are
  /// single-document gets — so recently viewed history stays readable on a
  /// train.
  Future<List<NutritionDayModel>> fetchDays(List<String> dateKeys) async {
    if (!canLog || dateKeys.isEmpty) return const [];
    final keys = dateKeys.take(maxHistoryDays).toList();
    final snaps = await Future.wait(
      keys.map((k) => _col.doc(docIdFor(k)).get().catchError(
            // One unreadable day must not blank the whole month.
            (Object _) => _col.doc(docIdFor(k)).get(const GetOptions(
                  source: Source.cache,
                )),
          )),
    );
    final out = <NutritionDayModel>[];
    for (final s in snaps) {
      if (s.exists && s.data() != null) {
        out.add(NutritionDayModel.fromMap(s.data()!, s.id));
      }
    }
    out.sort((a, b) => b.dateKey.compareTo(a.dateKey));
    return out;
  }

  /// The identity block every write must carry.
  ///
  /// The rules validate it on BOTH paths: `create` requires the doc id to equal
  /// `{clientId}_{dateKey}` and the ownership `get()` to match, while `update`
  /// requires clientId / adminId / dateKey / authorUid to be UNCHANGED. Sending
  /// the same block on every write therefore satisfies whichever rule applies,
  /// so a single `set(merge:true)` upserts correctly without the client having
  /// to know whether the document already exists — which it cannot know
  /// offline.
  ///
  /// [existingAdminId] is the crucial subtlety. A member who transfers to a
  /// new gym mid-day gets a NEW adminId on their client doc, but the rules
  /// pin `adminId` immutable on update — so writing the new one would be
  /// DENIED and the rest of their day would silently stop saving. The day
  /// belongs to the org it was opened under; the next day opens under the new
  /// one.
  Map<String, dynamic> _identity(String dateKey, {String? existingAdminId}) => {
        'clientId': _member.clientId,
        'adminId': (existingAdminId != null && existingAdminId.isNotEmpty)
            ? existingAdminId
            : _member.adminId,
        'authorUid': _member.uid,
        'dateKey': dateKey,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// THE WRITE PAYLOAD, as a pure function.
  ///
  /// Separated from the Firestore call so the exact bytes are assertable
  /// without a database. That is not test convenience: the two worst defects
  /// this platform has shipped were both wrong-shaped write payloads that
  /// every unit test and `tsc` accepted because each side was self-consistent
  /// about a shape that never existed. `entries` being a NESTED map rather
  /// than a dotted key is the same class of property, so it is pinned the same
  /// way — by asserting the serialized form.
  static Map<String, dynamic> buildEntryWrite({
    required String clientId,
    required String adminId,
    required String authorUid,
    required String dateKey,
    required String entryId,
    required Map<String, dynamic> patch,
    Object? updatedAt,
  }) =>
      {
        'clientId': clientId,
        'adminId': adminId,
        'authorUid': authorUid,
        'dateKey': dateKey,
        'updatedAt': updatedAt,
        // NESTED — never `'entries.$entryId'`. See property 2 above.
        'entries': {entryId: patch},
      };

  /// Upserts ONE entry into a day. Used for add, edit and soft delete alike —
  /// they differ only in the fields the entry map carries.
  ///
  /// [patch] is merged into `entries.{entryId}`, so an edit may send only the
  /// changed fields and a soft delete may send only `{'deleted': true}`.
  Future<DietSaveResult> writeEntry({
    required String dateKey,
    required String entryId,
    required Map<String, dynamic> patch,
    String? existingAdminId,
  }) async {
    if (!canLog || entryId.isEmpty) return DietSaveResult.failed;

    final identity = _identity(dateKey, existingAdminId: existingAdminId);
    final data = buildEntryWrite(
      clientId: identity['clientId'] as String,
      adminId: identity['adminId'] as String,
      authorUid: identity['authorUid'] as String,
      dateKey: dateKey,
      entryId: entryId,
      patch: patch,
      updatedAt: identity['updatedAt'],
    );

    final op = _col.doc(docIdFor(dateKey)).set(data, SetOptions(merge: true));
    try {
      await op.timeout(ackTimeout);
      return DietSaveResult.synced;
    } on TimeoutException {
      // `timeout` does not cancel the write; it stays pending and may fail
      // minutes later with nobody awaiting it, which would surface as an
      // unhandled async error. Adopt it — the member has already been told the
      // truth and a late rejection is nothing they can act on from here.
      unawaited(op.catchError((Object _) {}));
      return DietSaveResult.queued;
    } catch (_) {
      return DietSaveResult.failed;
    }
  }

  /// Adds a logged food.
  Future<DietSaveResult> addEntry({
    required String dateKey,
    required FoodEntry entry,
    String? existingAdminId,
  }) =>
      writeEntry(
        dateKey: dateKey,
        entryId: entry.entryId,
        patch: entry.toMap(),
        existingAdminId: existingAdminId,
      );

  /// SOFT DELETE — the entry stays, flagged. Analytics skip it and the server
  /// stops counting it, but the record of what the member logged is never
  /// destroyed. `allow delete: if false` on the collection says the same thing
  /// about the document; this says it about a row.
  ///
  /// Sending ONLY `{'deleted': true}` is what makes this safe: a full-entry
  /// rewrite would resurrect a stale copy of the entry held by whichever
  /// device happened to issue the delete.
  Future<DietSaveResult> softDelete({
    required String dateKey,
    required String entryId,
    String? existingAdminId,
  }) =>
      writeEntry(
        dateKey: dateKey,
        entryId: entryId,
        patch: const {'deleted': true},
        existingAdminId: existingAdminId,
      );

  /// Restores a soft-deleted entry — the undo behind the delete toast.
  Future<DietSaveResult> restore({
    required String dateKey,
    required String entryId,
    String? existingAdminId,
  }) =>
      writeEntry(
        dateKey: dateKey,
        entryId: entryId,
        patch: const {'deleted': false},
        existingAdminId: existingAdminId,
      );
}
