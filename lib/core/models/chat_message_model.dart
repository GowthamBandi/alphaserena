import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// Media payload of an image message (M1). `storagePath` is canonical;
/// `url` is the tokenized display URL.
class ChatMedia {
  final String storagePath;
  final String url;
  final String mime;
  final int sizeBytes;
  final int width;
  final int height;

  /// Voice messages (M2): duration + a small normalized amplitude series
  /// (0–100, ≤48 samples) for the waveform bubble.
  final int durationMs;
  final List<int> waveform;

  const ChatMedia({
    required this.storagePath,
    required this.url,
    required this.mime,
    required this.sizeBytes,
    this.width = 0,
    this.height = 0,
    this.durationMs = 0,
    this.waveform = const [],
  });

  double get aspectRatio =>
      (width > 0 && height > 0) ? width / height : 4 / 3;

  factory ChatMedia.fromMap(Map<String, dynamic> m) {
    int i(dynamic v) => v is num ? v.toInt() : 0;
    return ChatMedia(
      storagePath: (m['storagePath'] ?? '').toString(),
      url: (m['url'] ?? '').toString(),
      mime: (m['mime'] ?? '').toString(),
      sizeBytes: i(m['sizeBytes']),
      width: i(m['width']),
      height: i(m['height']),
      durationMs: i(m['durationMs']),
      waveform: (m['waveform'] is List)
          ? (m['waveform'] as List).map(i).toList()
          : const [],
    );
  }

  Map<String, dynamic> toMap() => {
        'storagePath': storagePath,
        'url': url,
        'mime': mime,
        'sizeBytes': sizeBytes,
        if (width > 0) 'width': width,
        if (height > 0) 'height': height,
        if (durationMs > 0) 'durationMs': durationMs,
        if (waveform.isNotEmpty) 'waveform': waveform,
      };
}

/// A message in the member's coach thread (`chats/{clientId}/messages`).
/// Keep in sync with trainersHQ `chat_message_model.dart`.
class ChatMessageModel {
  final String id;
  final String text;
  final String senderId;
  final String senderName;
  final String senderRole; // admin | trainer | client
  final String type; // 'text' | 'image'

  /// Present when [type] == 'image'.
  final ChatMedia? media;
  final DateTime? createdAt;

  /// Soft delete (set by the sender): content hidden, doc retained.
  final DateTime? deletedAt;

  /// Local-only send state: true while this device's write hasn't been
  /// acknowledged by the server (from snapshot metadata, never stored).
  final bool pending;

  const ChatMessageModel({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    this.type = 'text',
    this.media,
    this.createdAt,
    this.deletedAt,
    this.pending = false,
  });

  bool get isDeleted => deletedAt != null;
  bool get isImage => type == 'image' && media != null;
  bool get isVoice => type == 'voice' && media != null;

  factory ChatMessageModel.fromMap(
    Map<String, dynamic> m,
    String id, {
    bool pending = false,
  }) {
    return ChatMessageModel(
      id: id,
      text: (m['text'] ?? '').toString(),
      senderId: (m['senderId'] ?? '').toString(),
      senderName: (m['senderName'] ?? '').toString(),
      senderRole: (m['senderRole'] ?? '').toString(),
      type: (m['type'] ?? 'text').toString(),
      media: (m['media'] is Map)
          ? ChatMedia.fromMap(Map<String, dynamic>.from(m['media'] as Map))
          : null,
      createdAt: _date(m['createdAt']),
      deletedAt: _date(m['deletedAt']),
      pending: pending,
    );
  }
}
