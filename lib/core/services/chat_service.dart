import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../constants/firestore_collections.dart';
import '../domain/coach_conversation.dart';
import '../models/chat_message_model.dart';

/// The member's coach thread (`chats/{clientId}/messages`) + the thread doc
/// (`chats/{clientId}`, maintained by the onMessageCreated Cloud Function).
/// Keep the write shape in sync with trainersHQ `chat_service.dart`.
class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _messages(String clientId) => _db
      .collection(FsCollections.chats)
      .doc(clientId)
      .collection(FsCollections.chatMessages);

  DocumentReference<Map<String, dynamic>> _thread(String clientId) =>
      _db.collection(FsCollections.chats).doc(clientId);

  /// The member's UNREAD message count on this thread.
  ///
  /// `unread.member` is already maintained on the thread document — [markRead]
  /// resets it — but nothing ever displayed it, so a member with five messages
  /// waiting saw an inert "Message" button. The coach writes, the member never
  /// learns, and the coaching relationship quietly stops working.
  ///
  /// Emits 0 rather than an error when no thread exists yet (nobody has sent a
  /// message) or the read fails: a badge is an embellishment and must never be
  /// able to break the header it lives in.
  Stream<int> watchUnread(String clientId) =>
      watchConversation(clientId).map((c) => c.unread);

  /// The member's conversation state for the Home entry: unread count, last
  /// message preview, who sent it and when.
  ///
  /// One listener on the thread document serves all four — the same document
  /// the unread count already required, so the richer entry costs nothing extra.
  /// Every field is maintained by the `onMessageCreated` trigger.
  ///
  /// Emits [CoachConversation.empty] rather than erroring when the thread does
  /// not exist yet or the read fails: this drives a header, and a header must
  /// never be able to break.
  Stream<CoachConversation> watchConversation(String clientId) {
    if (clientId.isEmpty) return Stream.value(CoachConversation.empty);
    return _thread(clientId)
        .snapshots()
        .map((s) => CoachConversation.fromThread(s.data()))
        .handleError((Object _) {});
  }

  /// The most recent [window] messages, oldest→newest — windowed server-side
  /// so a years-long thread never streams in full (the previous implementation
  /// streamed the ENTIRE collection). Metadata changes included so a just-sent
  /// message renders a "sending" state until the server acks it.
  Stream<List<ChatMessageModel>> watchMessages(String clientId,
      {int window = 200}) {
    return _messages(clientId)
        .orderBy('createdAt')
        .limitToLast(window)
        .snapshots(includeMetadataChanges: true)
        .map((s) => s.docs
            .map((d) => ChatMessageModel.fromMap(d.data(), d.id,
                pending: d.metadata.hasPendingWrites))
            .toList());
  }

  /// One page of history OLDER than [before], for "load earlier messages".
  Future<List<ChatMessageModel>> fetchOlder(
    String clientId, {
    required DateTime before,
    int limit = 100,
  }) async {
    final s = await _messages(clientId)
        .orderBy('createdAt')
        .endBefore([Timestamp.fromDate(before)])
        .limitToLast(limit)
        .get();
    return s.docs
        .map((d) => ChatMessageModel.fromMap(d.data(), d.id))
        .toList();
  }

  /// Client-generated message id — the idempotency key: retrying the same
  /// message re-writes the SAME doc instead of duplicating it.
  String newMessageId(String clientId) => _messages(clientId).doc().id;

  Future<void> sendWithId(
    String clientId,
    String messageId,
    Map<String, dynamic> data, {
    String type = 'text',
    Map<String, dynamic>? media,
  }) async {
    await _messages(clientId).doc(messageId).set({
      ...data,
      'clientMessageId': messageId,
      'type': type,
      'media': ?media,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// The canonical storage location for an image belonging to [messageId] —
  /// message-id-keyed so a retried upload OVERWRITES instead of duplicating.
  /// Keep in sync with trainersHQ (`chat_media/{clientId}/{messageId}/…`).
  String mediaPath(String clientId, String messageId) =>
      'chat_media/$clientId/$messageId/photo.jpg';

  /// Voice note location — same id-keyed idempotent convention (M2).
  String voicePath(String clientId, String messageId) =>
      'chat_media/$clientId/$messageId/voice.m4a';

  /// Starts the image upload and returns the live task (progress + cancel).
  UploadTask uploadImage(String clientId, String messageId, File file) {
    return FirebaseStorage.instance
        .ref(mediaPath(clientId, messageId))
        .putFile(file, SettableMetadata(contentType: 'image/jpeg'));
  }

  /// Resets the MEMBER unread counter + read marker (rules allow a participant
  /// to zero only their own side). No thread doc yet → no-op.
  Future<void> markReadMember(String clientId) async {
    try {
      await _thread(clientId).update({
        'unread.member': 0,
        'lastReadAt.member': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code != 'not-found') rethrow;
    }
  }
}
