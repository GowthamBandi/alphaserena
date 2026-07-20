import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../constants/firestore_collections.dart';
import '../models/app_notification.dart';

/// The member's in-app notification center (`notifications/{uid}` summary +
/// `notifications/{uid}/items`). Items are written by Cloud Functions only;
/// this service performs the ONLY writes the rules allow the client:
/// summary `unread → 0`, and `readAt` / `archivedAt` as server timestamps.
class NotificationCenterService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  DocumentReference<Map<String, dynamic>> _summary(String uid) =>
      _db.collection(FsCollections.notifications).doc(uid);

  CollectionReference<Map<String, dynamic>> _items(String uid) =>
      _summary(uid).collection(FsCollections.notificationItems);

  /// Live unread counter for the bell badge.
  Stream<NotificationSummary> watchSummary(String uid) => _summary(uid)
      .snapshots()
      .map((d) => NotificationSummary.fromMap(d.data()));

  /// Most recent [limit] items, newest first. Single-field orderBy on
  /// createdAt — deliberately NO composite index; archived items are
  /// filtered client-side.
  Stream<List<AppNotification>> watchItems(String uid, {int limit = 50}) {
    return _items(uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map((d) => AppNotification.fromMap(d.data(), d.id))
            .where((n) => !n.isArchived)
            .toList());
  }

  /// One-shot older page for infinite scroll — appended below the live first
  /// page (which stays on [watchItems]). Cursors on the boundary item's
  /// DOCUMENT SNAPSHOT (not its createdAt value), so `startAfterDocument`
  /// disambiguates by `__name__` and never skips items that share the
  /// boundary's exact createdAt (createdAt is only millisecond-precise, so
  /// same-ms ties are real). No composite index needed.
  Future<List<AppNotification>> loadMore(
    String uid, {
    required String afterId,
    int limit = 30,
  }) async {
    if (uid.isEmpty || afterId.isEmpty) return const [];
    final anchor = await _items(uid).doc(afterId).get();
    if (!anchor.exists) return const [];
    final snap = await _items(uid)
        .orderBy('createdAt', descending: true)
        .startAfterDocument(anchor)
        .limit(limit)
        .get();
    return snap.docs
        .map((d) => AppNotification.fromMap(d.data(), d.id))
        .where((n) => !n.isArchived)
        .toList();
  }

  /// "Mark all read" — one batch over the ids currently loaded on screen
  /// (live page + any paginated pages), server-timestamped like [markRead].
  Future<void> markAllRead(List<String> ids) async {
    final uid = _uid;
    if (uid.isEmpty || ids.isEmpty) return;
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(_items(uid).doc(id), {
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code != 'not-found') rethrow;
    }
  }

  /// Rules require readAt == request.time — must be a server timestamp.
  Future<void> markRead(String id) async {
    final uid = _uid;
    if (uid.isEmpty) return;
    try {
      await _items(uid).doc(id).update({
        'readAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code != 'not-found') rethrow;
    }
  }

  /// Rules require archivedAt == request.time — must be a server timestamp.
  Future<void> archive(String id) async {
    final uid = _uid;
    if (uid.isEmpty) return;
    try {
      await _items(uid).doc(id).update({
        'archivedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code != 'not-found') rethrow;
    }
  }

  /// Zeroes the badge counter (the ONLY summary write the rules allow the
  /// client). No summary doc yet → nothing to clear.
  Future<void> markAllSeen() async {
    final uid = _uid;
    if (uid.isEmpty) return;
    try {
      await _summary(uid).update({'unread': 0});
    } on FirebaseException catch (e) {
      if (e.code != 'not-found') rethrow;
    }
  }
}
