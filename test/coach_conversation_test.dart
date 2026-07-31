import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/coach_conversation.dart';

/// SECTION 1.5 — the Home communication entry.
///
/// Every value here comes from the `chats/{clientId}` thread document that the
/// `onMessageCreated` Cloud Function already maintains:
/// `lastMessage {text,type,senderId,senderName,senderRole,at}`, `unread.member`,
/// `lastReadAt`, `updatedAt`. No backend change was needed for any of it.
///
/// (A previous audit claimed the thread carried no preview and deferred it as
/// "needs backend". That was wrong — it read the member-side service, which
/// never read the field, instead of the writer.)
void main() {
  Map<String, dynamic> thread({
    int unread = 0,
    String text = '',
    String type = 'text',
    String role = '',
    DateTime? at,
  }) => {
    'unread': {'member': unread},
    if (role.isNotEmpty || text.isNotEmpty)
      'lastMessage': {
        'text': text,
        'type': type,
        'senderRole': role,
        'at': at,
      },
  };

  group('unread counts — 0 / 1 / 5 / 25 / 100+', () {
    test('zero yields no badge label', () {
      expect(unreadLabel(0), isEmpty);
      expect(unreadLabel(-3), isEmpty, reason: 'a negative can never render');
    });

    test('single digits render exactly', () {
      expect(unreadLabel(1), '1');
      expect(unreadLabel(5), '5');
      expect(unreadLabel(9), '9');
    });

    test('double digits render exactly — no premature truncation', () {
      expect(unreadLabel(25), '25');
      expect(unreadLabel(99), '99');
    });

    test('beyond 99 caps, so a neglected thread cannot widen the row', () {
      expect(unreadLabel(100), '99+');
      expect(unreadLabel(4821), '99+');
    });

    test('a negative stored count is clamped, not shown', () {
      expect(CoachConversation.fromThread(thread(unread: -5)).unread, 0);
    });
  });

  group('preview — parity with the push notification', () {
    test('plain text passes through', () {
      final c = CoachConversation.fromThread(
        thread(text: 'How was leg day?', role: 'trainer'),
      );
      expect(c.previewLine, 'How was leg day?');
    });

    test('an image with no caption reads exactly as the push does', () {
      // The backend's messagePreview emits "📷 Photo". A member who taps a
      // notification saying that must not land on a row saying "Image".
      final c = CoachConversation.fromThread(
        thread(text: '', type: 'image', role: 'trainer'),
      );
      expect(c.previewLine, '📷 Photo');
    });

    test('an image WITH a caption shows the caption', () {
      final c = CoachConversation.fromThread(
        thread(text: 'form check', type: 'image', role: 'trainer'),
      );
      expect(c.previewLine, '📷 form check');
    });

    test('a voice note reads as one', () {
      final c = CoachConversation.fromThread(
        thread(text: '', type: 'voice', role: 'trainer'),
      );
      expect(c.previewLine, '🎤 Voice message');
    });

    test('newlines collapse so a multi-line message stays one row', () {
      final c = CoachConversation.fromThread(
        thread(text: 'Line one\n\nLine two', role: 'trainer'),
      );
      expect(c.previewLine, 'Line one Line two');
    });

    test('a very long message is truncated with an ellipsis', () {
      final c = CoachConversation.fromThread(
        thread(text: 'x' * 400, role: 'trainer'),
      );
      expect(c.preview.length, 118);
      expect(c.preview.endsWith('…'), isTrue);
    });
  });

  group('who spoke last — the "ball in whose court" signal', () {
    test('the member sees "You:" on their own last message', () {
      // Without this a member re-opens the thread just to check whether they
      // already replied.
      final c = CoachConversation.fromThread(
        thread(text: 'Will do', role: 'member'),
      );
      expect(c.lastSender, LastSender.member);
      expect(c.previewLine, 'You: Will do');
    });

    test('a coach message carries no prefix', () {
      final c = CoachConversation.fromThread(
        thread(text: 'Nice work', role: 'trainer'),
      );
      expect(c.lastSender, LastSender.coach);
      expect(c.previewLine, 'Nice work');
    });

    test('an ADMIN-sent message reads as the coach, not as the member', () {
      // A solo owner sends as an admin. To the member they are simply "coach".
      final c = CoachConversation.fromThread(
        thread(text: 'Welcome!', role: 'admin'),
      );
      expect(c.lastSender, LastSender.coach);
      expect(c.previewLine, 'Welcome!');
    });

    test('an unknown role is not attributed to anyone', () {
      final c = CoachConversation.fromThread({
        'lastMessage': {'text': 'hi', 'type': 'text'},
      });
      expect(c.lastSender, LastSender.none);
      expect(c.hasHistory, isFalse, reason: 'unattributable → no preview line');
    });
  });

  group('empty and malformed threads never break the header', () {
    test('no document at all', () {
      final c = CoachConversation.fromThread(null);
      expect(c.hasHistory, isFalse);
      expect(c.hasUnread, isFalse);
      expect(c.previewLine, isEmpty);
    });

    test('a thread created by the CALL subsystem before anyone chatted', () {
      // calls.ts can create chats/{clientId} without a lastMessage.
      final c = CoachConversation.fromThread({
        'clientId': 'c1',
        'unread': {'member': 0},
      });
      expect(c.hasHistory, isFalse);
      expect(c.previewLine, isEmpty);
    });

    test('unread survives even when lastMessage is missing', () {
      final c = CoachConversation.fromThread({
        'unread': {'member': 3},
      });
      expect(c.unread, 3);
      expect(c.hasHistory, isFalse);
    });

    test('a non-map lastMessage is ignored rather than thrown on', () {
      final c = CoachConversation.fromThread({
        'lastMessage': 'corrupt',
        'unread': {'member': 1},
      });
      expect(c.unread, 1);
      expect(c.hasHistory, isFalse);
    });
  });

  group('relative age', () {
    final now = DateTime(2026, 3, 14, 12, 0);

    test('under a minute reads "now", never "0m"', () {
      expect(conversationAge(now.subtract(const Duration(seconds: 40)), now: now), 'now');
    });

    test('minutes, hours and days', () {
      expect(conversationAge(now.subtract(const Duration(minutes: 5)), now: now), '5m');
      expect(conversationAge(now.subtract(const Duration(minutes: 59)), now: now), '59m');
      expect(conversationAge(now.subtract(const Duration(hours: 3)), now: now), '3h');
      expect(conversationAge(now.subtract(const Duration(days: 2)), now: now), '2d');
      expect(conversationAge(now.subtract(const Duration(days: 6)), now: now), '6d');
    });

    test('a week or more becomes a date', () {
      expect(conversationAge(DateTime(2026, 3, 2), now: now), '2 Mar');
      expect(conversationAge(DateTime(2025, 12, 25), now: now), '25 Dec');
    });

    test('a server clock slightly AHEAD of the device never reads negative', () {
      // Server timestamps routinely land a few ms in the future relative to the
      // handset. "-1m" would look like a bug on a premium surface.
      expect(conversationAge(now.add(const Duration(seconds: 30)), now: now), 'now');
      expect(conversationAge(now.add(const Duration(hours: 2)), now: now), 'now');
    });

    test('no timestamp yields no age rather than a placeholder', () {
      expect(conversationAge(null), isEmpty);
    });
  });

  group('the states the entry actually renders', () {
    test('unread drives both the badge and the emphasis', () {
      final c = CoachConversation.fromThread(
        thread(unread: 2, text: 'Check your macros', role: 'trainer'),
      );
      expect(c.hasUnread, isTrue);
      expect(unreadLabel(c.unread), '2');
      expect(c.previewLine, 'Check your macros');
    });

    test('read conversation keeps the preview but drops the badge', () {
      final c = CoachConversation.fromThread(
        thread(unread: 0, text: 'Check your macros', role: 'trainer'),
      );
      expect(c.hasUnread, isFalse);
      expect(unreadLabel(c.unread), isEmpty);
      expect(c.hasHistory, isTrue, reason: 'reading does not erase history');
    });
  });
}
