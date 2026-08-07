import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';
import '../models/check_in_submission_model.dart';

/// Member-side check-in submissions: reads the member's own submissions and
/// upserts the OPEN one (functions-free; rules enforce ownership via the linked
/// `clients` doc). One open (status=='submitted') doc at a time.
class CheckInSubmissionService {
  CheckInSubmissionService({FirebaseFirestore? firestore})
    : _injectedDb = firestore;

  /// Resolved LAZILY, and injectable.
  ///
  /// 🔴 This was `final FirebaseFirestore _db = FirebaseFirestore.instance;` —
  /// an eager field, so merely CONSTRUCTING this service threw `[core/no-app]`
  /// without a live Firebase app, and it threw for a SUBCLASS that overrides
  /// every method too, because a subclass runs its parent's field initializers
  /// first. That is what made the check-in read path untestable.
  ///
  /// It is the same defect `WorkoutLogService` already carries a comment about,
  /// and the one this codebase has now closed in seven other services:
  /// **never resolve a Firebase singleton in a field initializer.**
  final FirebaseFirestore? _injectedDb;
  FirebaseFirestore? _resolvedDb;
  FirebaseFirestore get _db =>
      _injectedDb ?? (_resolvedDb ??= FirebaseFirestore.instance);

  final MemberController _member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsCollections.clientCheckInSubmissions);

  bool get canLog =>
      _member.clientId.isNotEmpty &&
      _member.adminId.isNotEmpty &&
      _member.uid.isNotEmpty;

  /// The member's current OPEN submission (null if none), newest first.
  Stream<CheckInSubmissionModel?> watchOpen() {
    if (!canLog) return Stream.value(null);
    return _col
        .where('authorId', isEqualTo: _member.uid)
        .where('status', isEqualTo: CheckInSubmissionStatus.submitted)
        .snapshots()
        .map((s) {
      final list = s.docs
          .map((d) => CheckInSubmissionModel.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => (b.submittedAt ?? DateTime(2000))
          .compareTo(a.submittedAt ?? DateTime(2000)));
      return list.isEmpty ? null : list.first;
    });
  }

  /// All of the member's submissions, newest first.
  Stream<List<CheckInSubmissionModel>> watchMine() {
    if (!canLog) return Stream.value(const []);
    return _col
        .where('authorId', isEqualTo: _member.uid)
        .snapshots()
        .map((s) {
      final list = s.docs
          .map((d) => CheckInSubmissionModel.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => (b.submittedAt ?? DateTime(2000))
          .compareTo(a.submittedAt ?? DateTime(2000)));
      return list;
    });
  }

  /// Upserts the open submission ([id] = existing open doc, else a new doc).
  /// Returns the doc id, or null if the member isn't linked / the write fails.
  Future<String?> submit({
    String? id,
    required String weekOf,
    double? weightKg,
    required Map<String, int> ratings,
    required String note,
  }) async {
    if (!canLog) return null;
    final model = CheckInSubmissionModel(
      id: id ?? '',
      clientId: _member.clientId,
      adminId: _member.adminId,
      authorId: _member.uid,
      clientName: _member.name,
      weightKg: weightKg,
      ratings: ratings,
      note: note.trim(),
      status: CheckInSubmissionStatus.submitted,
      weekOf: weekOf,
    );
    // DETERMINISTIC PER-WEEK IDENTITY — what makes a duplicate impossible.
    //
    // This used to be `_col.doc()`, a fresh random id, whenever there was no
    // open packet. Nothing else in the stack constrained uniqueness either, so
    // a member could file any number of reviews for one week and the coach
    // would see them as separate submissions. Addressing the week's own
    // document means a second submission overwrites the first rather than
    // creating a sibling — the same discipline the member-day collections use.
    final doc = (id != null && id.isNotEmpty)
        ? _col.doc(id)
        : _col.doc('${_member.clientId}_$weekOf');
    final data = <String, dynamic>{
      ...model.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (id == null || id.isEmpty) 'submittedAt': FieldValue.serverTimestamp(),
    };
    try {
      await doc.set(data, SetOptions(merge: true));
      return doc.id;
    } catch (_) {
      return null;
    }
  }
}
