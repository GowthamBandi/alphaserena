import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../../core/constants/firestore_collections.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';

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
    await col.add({
      'text': text,
      'senderId': _uid,
      'senderName': member.name,
      'senderRole': 'client',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          member.trainerName.isEmpty
              ? 'Chat'
              : 'Chat · ${member.trainerName}',
          style: AppText.title(size: 22).copyWith(color: p.textPrimary),
        ),
      ),
      body: SafeArea(
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

  Widget _messageList(AppPalette p) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _messages!.orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Center(
              child:
                  CircularProgressIndicator(strokeWidth: 2.4, color: p.accent));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text('Say hello to your trainer 👋',
                style: AppText.body(size: 14).copyWith(color: p.textMuted)),
          );
        }
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final m = docs[i].data();
            final mine = (m['senderId'] ?? '') == _uid;
            return _bubble(p, m['text']?.toString() ?? '', mine);
          },
        );
      },
    );
  }

  Widget _bubble(AppPalette p, String text, bool mine) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: mine ? p.accent : p.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: p.border),
        ),
        child: Text(text,
            style: AppText.body(size: 14)
                .copyWith(color: mine ? Colors.white : p.textPrimary)),
      ),
    );
  }

  Widget _composer(AppPalette p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              style: TextStyle(color: p.textPrimary),
              decoration: InputDecoration(
                hintText: 'Message…',
                filled: true,
                fillColor: p.inputFill,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadii.lgR,
                    borderSide: BorderSide(color: p.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: AppRadii.lgR,
                    borderSide: BorderSide(color: p.accent)),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
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
              Text('No trainer chat yet',
                  style:
                      AppText.title(size: 20).copyWith(color: p.textPrimary)),
              const SizedBox(height: 6),
              Text('Once your gym links your membership, you can chat here.',
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 14).copyWith(color: p.textMuted)),
            ],
          ),
        ),
      );
}
