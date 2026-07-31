/// THE HOME COMMUNICATION ENTRY — pure presentation rules for the member's
/// conversation with their coach.
///
/// Everything here is derived from the `chats/{clientId}` THREAD document, which
/// the `onMessageCreated` Cloud Function already maintains:
///
///   lastMessage: {text, type, senderId, senderName, senderRole, at}
///   unread:      {member, staff}
///   lastReadAt:  {member, staff}
///   updatedAt
///
/// No backend work was required for any of it. A previous audit concluded the
/// thread carried no preview and deferred it as "needs backend" — that was
/// wrong, reached by reading the member-side service (which never read the
/// field) instead of the writer. The data has been there all along.
///
/// Kept Flutter-free and Firebase-free so every state is unit-testable.
library;

/// Who sent the most recent message.
enum LastSender { member, coach, none }

/// The member's conversation with their coach, as the Home entry needs it.
class CoachConversation {
  /// Unread messages for the MEMBER. 0 → no badge.
  final int unread;

  /// The preview line, already type-aware ("📷 Photo", "🎤 Voice message").
  /// Empty when no conversation exists yet.
  final String preview;

  /// When the last message was sent. Null when no conversation exists.
  final DateTime? lastAt;

  final LastSender lastSender;

  const CoachConversation({
    this.unread = 0,
    this.preview = '',
    this.lastAt,
    this.lastSender = LastSender.none,
  });

  static const CoachConversation empty = CoachConversation();

  /// A conversation has actually started.
  bool get hasHistory => preview.isNotEmpty && lastSender != LastSender.none;

  bool get hasUnread => unread > 0;

  /// Builds from a raw `chats/{clientId}` document.
  ///
  /// Tolerant by construction: a thread that exists but has no `lastMessage`
  /// (created by the call subsystem before anyone chatted) resolves to
  /// [empty]-like state rather than rendering a blank preview line.
  factory CoachConversation.fromThread(Map<String, dynamic>? doc) {
    if (doc == null) return empty;

    final unreadRaw = (doc['unread'] as Map?)?['member'];
    final unread = unreadRaw is num ? unreadRaw.toInt() : 0;

    final last = doc['lastMessage'];
    if (last is! Map) {
      return CoachConversation(unread: unread < 0 ? 0 : unread);
    }

    final role = (last['senderRole'] ?? '').toString().toLowerCase();
    // Anything that is not the member is the coaching side — an org may send
    // as an admin, a trainer, or a system actor, and to the member they are all
    // simply "your coach". Only an explicit member role reads as "You".
    final sender = role.isEmpty
        ? LastSender.none
        : (role == 'member' || role == 'client')
        ? LastSender.member
        : LastSender.coach;

    return CoachConversation(
      unread: unread < 0 ? 0 : unread,
      preview: messagePreview(
        (last['type'] ?? 'text').toString(),
        (last['text'] ?? '').toString(),
      ),
      lastAt: _date(last['at']),
      lastSender: sender,
    );
  }

  /// The line shown under the coach's name.
  ///
  /// Prefixed with "You: " when the MEMBER spoke last — the single cheapest
  /// signal that the ball is in the coach's court, and the reason a member does
  /// not re-open a thread to check whether they already replied.
  String get previewLine {
    if (!hasHistory) return '';
    return lastSender == LastSender.member ? 'You: $preview' : preview;
  }
}

/// The member-app mirror of the backend's `messagePreview`
/// (`functions/src/lib/notification_center.ts`).
///
/// Deliberately identical, including the emoji, so the text in a push
/// notification and the text on Home are the same string. A member who taps a
/// notification saying "📷 Photo" and lands on a row saying "Image" has been
/// shown two descriptions of one event.
String messagePreview(String type, String text) {
  final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (type == 'image') return trimmed.isNotEmpty ? '📷 $trimmed' : '📷 Photo';
  if (type == 'voice') return '🎤 Voice message';
  return trimmed.length > 120 ? '${trimmed.substring(0, 117)}…' : trimmed;
}

/// A compact relative timestamp for the entry: `now`, `5m`, `3h`, `2d`,
/// `12 Mar`.
///
/// Deliberately terse — this sits at the end of a row, not in a paragraph, and
/// a member reading it wants an order of magnitude, not a date. Anything under a
/// minute reads "now" because "0m" looks like a bug.
String conversationAge(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  final ref = now ?? DateTime.now();
  final d = ref.difference(at);
  // A clock skew (server timestamp marginally ahead of the device) must never
  // render a negative age.
  if (d.isNegative || d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return '${at.day} ${_months[at.month - 1]}';
}

/// The badge label. Caps at "99+" so a neglected thread cannot widen the row.
String unreadLabel(int unread) {
  if (unread <= 0) return '';
  return unread > 99 ? '99+' : '$unread';
}

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

DateTime? _date(dynamic v) {
  if (v == null) return null;
  // Firestore Timestamp arrives with a toDate(); avoid importing cloud_firestore
  // here so this file stays pure.
  try {
    final dyn = v as dynamic;
    final d = dyn.toDate();
    if (d is DateTime) return d;
  } catch (_) {
    // not a Timestamp
  }
  if (v is DateTime) return v;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String) return DateTime.tryParse(v);
  return null;
}
