import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../controllers/member_controller.dart';
import '../../core/constants/firestore_collections.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';

/// Real-time member ↔ trainer thread (`chats/{clientId}/messages`). Pro layout:
/// a profile app-bar (avatar + name + call/video actions), date separators,
/// grouped bubbles with timestamps, and a pill composer.
class ClientChatScreen extends StatefulWidget {
  const ClientChatScreen({super.key});

  @override
  State<ClientChatScreen> createState() => _ClientChatScreenState();
}

class _ClientChatScreenState extends State<ClientChatScreen> {
  final MemberController member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());
  final TextEditingController _input = TextEditingController();
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  String? get _clientId => member.linkedClientId;

  CollectionReference<Map<String, dynamic>>? get _messages {
    final cid = _clientId;
    if (cid == null) return null;
    return FirebaseFirestore.instance
        .collection(FsCollections.chats)
        .doc(cid)
        .collection(FsCollections.chatMessages);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final col = _messages;
    if (text.isEmpty || col == null) return;
    _input.clear();
    try {
      await col.add({
        'text': text,
        'senderId': _uid,
        'senderName': member.name,
        'senderRole': 'client',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      _input.text = text; // restore so the user doesn't lose their message
      Get.snackbar('Message not sent', 'Please try again.');
    }
  }

  void _comingSoon(String feature) {
    Get.snackbar(
      'Coming Soon',
      '$feature will be available in a future update.',
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(14),
      borderRadius: 12,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: _appBar(p),
      body: SafeArea(
        top: false,
        child: _clientId == null
            ? _noThread(p)
            : Column(
                children: [
                  Expanded(child: _messageList(p)),
                  _composer(p),
                ],
              ),
      ),
    );
  }

  // ── App bar ─────────────────────────────────────────────────────────
  PreferredSizeWidget _appBar(AppPalette p) {
    final name = member.trainerName.isEmpty ? 'Your Coach' : member.trainerName;
    final subtitle = member.gymName.isEmpty ? 'Performance Coach' : member.gymName;
    return AppBar(
      backgroundColor: p.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: p.border)),
      titleSpacing: 0,
      iconTheme: IconThemeData(color: p.textPrimary),
      title: Row(
        children: [
          _avatar(p, 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: p.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(color: p.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        _appBarAction(p, Icons.videocam_outlined, () => _comingSoon('Video call')),
        _appBarAction(p, Icons.call_outlined, () => _comingSoon('Voice call')),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _appBarAction(AppPalette p, IconData icon, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: p.accent, size: 22),
      splashRadius: 22,
    );
  }

  Widget _avatar(AppPalette p, double size) {
    final name = member.trainerName.isEmpty ? 'C' : member.trainerName;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: p.accent.withValues(alpha: 0.5), width: 1.4),
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/trainer.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: p.surfaceAlt,
            alignment: Alignment.center,
            child: Text(
              name[0].toUpperCase(),
              style: AppText.title(size: size * 0.42).copyWith(color: p.accent),
            ),
          ),
        ),
      ),
    );
  }

  // ── Messages ────────────────────────────────────────────────────────
  Widget _messageList(AppPalette p) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _messages!.orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Center(
              child:
                  CircularProgressIndicator(strokeWidth: 2.4, color: p.accent));
        }
        if (snap.hasError) {
          return Center(
            child: Text('Could not load messages.',
                style: AppText.body(size: 13).copyWith(color: p.textMuted)),
          );
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return _emptyConversation(p);

        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final m = docs[i].data();
            final dt = _ts(m);
            final mine = (m['senderId'] ?? '') == _uid;

            // docs are newest→oldest; i+1 is the older neighbour.
            final olderDt =
                i + 1 < docs.length ? _ts(docs[i + 1].data()) : null;
            final newerMine = i - 1 >= 0
                ? (docs[i - 1].data()['senderId'] ?? '') == _uid
                : null;

            final showDay = dt != null && (olderDt == null || !_sameDay(dt, olderDt));
            // Tight spacing while the same sender keeps talking.
            final grouped = newerMine == mine && !showDay;

            return Column(
              children: [
                if (showDay) _dayChip(p, dt),
                _bubble(p, m['text']?.toString() ?? '', mine, dt, grouped),
              ],
            );
          },
        );
      },
    );
  }

  Widget _dayChip(AppPalette p, DateTime dt) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.border),
      ),
      child: Text(
        _dayLabel(dt),
        style: GoogleFonts.poppins(
          color: p.textMuted,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _bubble(
      AppPalette p, String text, bool mine, DateTime? dt, bool grouped) {
    final time = dt == null ? '' : DateFormat('h:mm a').format(dt);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(top: grouped ? 2 : 8),
        padding: const EdgeInsets.fromLTRB(14, 9, 12, 8),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        decoration: BoxDecoration(
          gradient: mine
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFEC1C1C), Color(0xFFC20000)],
                )
              : null,
          color: mine ? null : p.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(mine ? 18 : (grouped ? 6 : 18)),
            topRight: Radius.circular(mine ? (grouped ? 6 : 18) : 18),
            bottomLeft: Radius.circular(mine ? 18 : 6),
            bottomRight: Radius.circular(mine ? 6 : 18),
          ),
          border: mine ? null : Border.all(color: p.border),
          boxShadow: mine
              ? [
                  BoxShadow(
                    color: p.accent.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              text,
              style: GoogleFonts.poppins(
                color: mine ? Colors.white : p.textPrimary,
                fontSize: 13.5,
                height: 1.32,
              ),
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                time,
                style: GoogleFonts.poppins(
                  color: mine ? Colors.white70 : p.textMuted,
                  fontSize: 9,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyConversation(AppPalette p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _avatar(p, 64),
            const SizedBox(height: 16),
            Text(
              'Start the conversation',
              style: AppText.title(size: 19).copyWith(color: p.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask your coach a question, share an update, or say hello 👋',
              textAlign: TextAlign.center,
              style: AppText.body(size: 13).copyWith(color: p.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  // ── Composer ────────────────────────────────────────────────────────
  Widget _composer(AppPalette p) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: p.inputFill,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: p.border),
              ),
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                maxLength: 2000,
                buildCounter: (_,
                        {required currentLength,
                        required isFocused,
                        maxLength}) =>
                    null,
                cursorColor: p.accent,
                style: TextStyle(color: p.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Message your coach…',
                  hintStyle: TextStyle(color: p.textMuted, fontSize: 13.5),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFEC1C1C), Color(0xFFC20000)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: p.accent.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noThread(AppPalette p) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline, size: 42, color: p.textMuted),
              const SizedBox(height: 14),
              Text('No coach chat yet',
                  style:
                      AppText.title(size: 20).copyWith(color: p.textPrimary)),
              const SizedBox(height: 6),
              Text('Once your membership is active, you can chat here.',
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 14).copyWith(color: p.textMuted)),
            ],
          ),
        ),
      );

  // ── Date helpers ────────────────────────────────────────────────────
  DateTime? _ts(Map<String, dynamic> m) {
    final v = m['createdAt'];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('d MMM yyyy').format(dt);
  }
}
