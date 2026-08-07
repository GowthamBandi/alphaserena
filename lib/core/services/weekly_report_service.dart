import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';
import '../models/weekly_report_models.dart';

/// The outcome of a write that may have been queued offline.
///
/// Firestore's `set` resolves only on SERVER ack, so offline it never completes
/// and a naive `await` spins forever. Every write here is bounded and reports
/// honestly which of the two happened — "saved on this device" is not an error,
/// and must never be shown as one.
enum ReportWriteOutcome { acknowledged, queued, failed }

/// Member-side Weekly Reports I/O.
///
/// READS ARE QUERIES, NOT DOCUMENT GETS. The member's own reports are found by
/// `where('authUid','==',uid)` — equality only, sorted in Dart — which is the
/// shape this codebase uses everywhere and needs no composite index.
///
/// WRITES TOUCH ONE COLLECTION. The member owns `weekly_report_submissions` and
/// nothing else: snapshots and reviews are read-only to them at the rules layer,
/// so there is no method here that could even attempt it.
class WeeklyReportService {
  WeeklyReportService({FirebaseFirestore? firestore}) : _injectedDb = firestore;

  /// Resolved LAZILY, and injectable — the house rule. An eager
  /// `FirebaseFirestore.instance` field makes merely CONSTRUCTING this service
  /// throw `[core/no-app]` without a live Firebase app, and it throws for a
  /// subclass that overrides every method too, because a subclass runs its
  /// parent's field initializers first. That is what made the check-in read
  /// path untestable, and it has now been closed in eight other services.
  final FirebaseFirestore? _injectedDb;
  FirebaseFirestore? _resolvedDb;
  FirebaseFirestore get _db =>
      _injectedDb ?? (_resolvedDb ??= FirebaseFirestore.instance);

  final MemberController _member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  static const Duration ackTimeout = Duration(seconds: 4);

  CollectionReference<Map<String, dynamic>> get _snapshots =>
      _db.collection(FsCollections.weeklyReportSnapshots);
  CollectionReference<Map<String, dynamic>> get _submissions =>
      _db.collection(FsCollections.weeklyReportSubmissions);
  CollectionReference<Map<String, dynamic>> get _reviews =>
      _db.collection(FsCollections.weeklyReportReviews);
  CollectionReference<Map<String, dynamic>> get _rollups =>
      _db.collection(FsCollections.weeklyReportRollups);

  bool get canRead => _member.uid.isNotEmpty && _member.clientId.isNotEmpty;

  /// Every report ever issued to this member, newest week first.
  ///
  /// Sorted on `periodKey` (`yyyy-Www`), which sorts lexicographically in
  /// calendar order by construction — that is a property of the ISO key the
  /// engine mints, not a coincidence to rely on quietly.
  Stream<List<WeeklyReportSnapshot>> watchAll() {
    if (!canRead) return Stream.value(const []);
    return _snapshots
        .where('authUid', isEqualTo: _member.uid)
        .snapshots()
        .map((s) {
      final list = s.docs
          .map((d) => WeeklyReportSnapshot.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.periodKey.compareTo(a.periodKey));
      return list;
    });
  }

  Stream<WeeklyReportSubmission?> watchSubmission(String id) {
    if (!canRead || id.isEmpty) return Stream.value(null);
    return _submissions.doc(id).snapshots().map(
          (d) => d.exists
              ? WeeklyReportSubmission.fromMap(d.data() ?? {}, d.id)
              : null,
        );
  }

  Stream<WeeklyReportReview?> watchReview(String id) {
    if (!canRead || id.isEmpty) return Stream.value(null);
    return _reviews.doc(id).snapshots().map(
          (d) =>
              d.exists ? WeeklyReportReview.fromMap(d.data() ?? {}, d.id) : null,
        );
  }

  Stream<WeeklyReportRollup> watchRollup() {
    if (!canRead) return Stream.value(const WeeklyReportRollup());
    return _rollups.doc(_member.clientId).snapshots().map(
          (d) => d.exists
              ? WeeklyReportRollup.fromMap(d.data() ?? {}, d.id)
              : const WeeklyReportRollup(),
        );
  }

  /// Every submission the member has, so history can show answers without
  /// opening a listener per week.
  Stream<Map<String, WeeklyReportSubmission>> watchAllSubmissions() {
    if (!canRead) return Stream.value(const {});
    return _submissions
        .where('authorId', isEqualTo: _member.uid)
        .snapshots()
        .map((s) => {
              for (final d in s.docs)
                d.id: WeeklyReportSubmission.fromMap(d.data(), d.id),
            });
  }

  Stream<Map<String, WeeklyReportReview>> watchAllReviews() {
    if (!canRead) return Stream.value(const {});
    return _reviews
        .where('clientId', isEqualTo: _member.clientId)
        .snapshots()
        .map((s) => {
              for (final d in s.docs)
                d.id: WeeklyReportReview.fromMap(d.data(), d.id),
            });
  }

  /// Saves a draft.
  ///
  /// The identity fields are re-sent on every write because the rules compare
  /// them against the SNAPSHOT — a create that omits them is refused, and a
  /// create that disagrees with the snapshot is refused too. Sending the
  /// snapshot's own values is what makes the rule a tautology rather than a
  /// trap.
  Future<ReportWriteOutcome> saveDraft({
    required WeeklyReportSnapshot snapshot,
    required Map<String, dynamic> answers,
  }) =>
      _write(snapshot: snapshot, answers: answers, submit: false);

  /// Submits. The LAST write a client may ever make to this document — after
  /// this the rules refuse every update, from the member and the coach alike.
  Future<ReportWriteOutcome> submit({
    required WeeklyReportSnapshot snapshot,
    required Map<String, dynamic> answers,
  }) =>
      _write(snapshot: snapshot, answers: answers, submit: true);

  Future<ReportWriteOutcome> _write({
    required WeeklyReportSnapshot snapshot,
    required Map<String, dynamic> answers,
    required bool submit,
  }) async {
    if (!canRead || snapshot.id.isEmpty) return ReportWriteOutcome.failed;

    final data = <String, dynamic>{
      'schemaVersion': kWeeklyReportSchema,
      'clientId': snapshot.clientId,
      'adminId': snapshot.adminId,
      'authorId': _member.uid,
      'periodKey': snapshot.periodKey,
      'status': submit ? 'submitted' : 'draft',
      'answers': answers,
      'lastSavedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (submit) 'submittedAt': FieldValue.serverTimestamp(),
    };

    try {
      // `set(merge:true)` rather than `update`: the first save must CREATE the
      // document, and a member who starts answering offline has no round trip
      // in which to discover it does not exist yet.
      final future =
          _submissions.doc(snapshot.id).set(data, SetOptions(merge: true));
      await future.timeout(ackTimeout);
      return ReportWriteOutcome.acknowledged;
    } on TimeoutException {
      // The write is in Firestore's local queue and WILL land on reconnect.
      // Reporting this as a failure would invite the member to retype a week's
      // worth of answers they have not actually lost.
      return ReportWriteOutcome.queued;
    } catch (_) {
      return ReportWriteOutcome.failed;
    }
  }
}

/// Re-exported so callers do not need the engine import just for the constant.
const int kWeeklyReportSchema = 1;

/// Uploads a weekly-report photo and returns its download URL.
///
/// PATH IS DELIBERATE: `progress_photos/{uid}/…`, the tree whose Storage rule is
/// ALREADY DEPLOYED (owner-write, image-only). A new path would have needed a
/// `storage.rules` change and a deploy before a single member could attach a
/// photo — and until that deploy the upload would fail silently at the rules
/// layer, which reads to the member as "the button does nothing".
extension WeeklyReportPhotoUpload on WeeklyReportService {
  Future<String?> uploadPhoto({
    required String periodKey,
    required File file,
    required String filename,
    FirebaseStorage? storage,
  }) async {
    if (!canRead) return null;
    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : 'jpg';
    final safeExt = const {'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(ext)
        ? ext
        : 'jpg';
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final path = 'progress_photos/${_member.uid}/weekly_reports/'
        '$periodKey/$stamp.$safeExt';
    try {
      final ref = (storage ?? FirebaseStorage.instance).ref(path);
      await ref.putFile(
        file,
        SettableMetadata(
          contentType: safeExt == 'png' ? 'image/png' : 'image/jpeg',
        ),
      );
      return await ref.getDownloadURL();
    } catch (_) {
      // A failed upload must not take the whole report down. The member keeps
      // every other answer and can retry the photo.
      return null;
    }
  }
}
