import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// One item in the member's notification center
/// (`notifications/{uid}/items/{id}`, written by Cloud Functions only — the
/// client may set ONLY `readAt` / `archivedAt`, each as a server timestamp).
class AppNotification {
  final String id;
  final String kind; // e.g. missed_call | trainer_changed | membership_expired
  final String category; // calls | coaching | membership | billing | system
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime? createdAt;
  final DateTime? readAt;
  final DateTime? archivedAt;
  final DateTime? expireAt;

  const AppNotification({
    required this.id,
    required this.kind,
    required this.category,
    required this.title,
    required this.body,
    this.data = const {},
    this.createdAt,
    this.readAt,
    this.archivedAt,
    this.expireAt,
  });

  bool get isUnread => readAt == null;
  bool get isArchived => archivedAt != null;

  factory AppNotification.fromMap(Map<String, dynamic> m, String id) {
    return AppNotification(
      id: id,
      kind: (m['kind'] ?? '').toString(),
      category: (m['category'] ?? 'system').toString(),
      title: (m['title'] ?? '').toString(),
      body: (m['body'] ?? '').toString(),
      data: (m['data'] is Map)
          ? Map<String, dynamic>.from(m['data'] as Map)
          : const {},
      createdAt: _date(m['createdAt']),
      readAt: _date(m['readAt']),
      archivedAt: _date(m['archivedAt']),
      expireAt: _date(m['expireAt']),
    );
  }
}

/// The `notifications/{uid}` summary doc — a server-maintained unread counter.
/// The client may only reset `unread` to 0 (rules-enforced).
class NotificationSummary {
  final int unread;
  final DateTime? updatedAt;

  const NotificationSummary({this.unread = 0, this.updatedAt});

  factory NotificationSummary.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const NotificationSummary();
    final u = m['unread'];
    return NotificationSummary(
      unread: u is num ? u.toInt() : 0,
      updatedAt: _date(m['updatedAt']),
    );
  }
}
