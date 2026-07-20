import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../controllers/member_controller.dart';
import '../../core/models/chat_message_model.dart';
import '../../core/services/call_service.dart';
import '../../core/services/chat_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import 'chat_image_viewer.dart';
import 'chat_widgets/chat_audio_player.dart';
import 'chat_widgets/voice_message_bubble.dart';

/// Real-time member ↔ trainer thread (`chats/{clientId}/messages`). Pro layout:
/// profile app-bar, date separators, grouped bubbles, send-state ticks, failed
/// send retry, history pagination and a pill composer. Windowed stream — never
/// loads an entire multi-year thread (Communication Platform M0).
class ClientChatScreen extends StatefulWidget {
  const ClientChatScreen({super.key});

  @override
  State<ClientChatScreen> createState() => _ClientChatScreenState();
}

/// A send the server rejected — kept until the member retries or discards.
/// A media failure carries the local file path so retry re-uploads it.
class _FailedMessage {
  final String id; // client-generated message id (idempotency key)
  final String text;
  final String imagePath; // '' for text
  final String kind; // 'text' | 'image' | 'voice'
  final int durationMs;
  final List<int> waveform;
  const _FailedMessage(this.id, this.text,
      [this.imagePath = '',
      this.kind = 'text',
      this.durationMs = 0,
      this.waveform = const []]);
  bool get isImage => kind == 'image';
  bool get isVoice => kind == 'voice';
  bool get isMedia => imagePath.isNotEmpty;
}

/// A media upload in flight (progress bubble with cancel).
class _PendingUpload {
  final String id;
  final String filePath;
  final String kind; // 'image' | 'voice'
  final int durationMs;
  final List<int> waveform;
  double progress = 0;
  UploadTask? task;
  _PendingUpload(this.id, this.filePath,
      [this.kind = 'image', this.durationMs = 0, this.waveform = const []]);
  bool get isVoice => kind == 'voice';
}

class _ClientChatScreenState extends State<ClientChatScreen> {
  final MemberController member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());
  final ChatService _chat = ChatService();
  final TextEditingController _input = TextEditingController();
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  StreamSubscription? _sub;
  Worker? _linkWorker;
  List<ChatMessageModel> _live = const [];
  final List<ChatMessageModel> _older = [];
  final List<_FailedMessage> _failed = [];
  final List<_PendingUpload> _uploads = [];
  bool _loading = true;
  bool _error = false;
  bool _loadingOlder = false;
  bool _hasMoreHistory = true;

  String? get _clientId => member.linkedClientId;

  List<ChatMessageModel> get _all => [..._older, ..._live];

  @override
  void initState() {
    super.initState();
    _subscribe();
    // The claim CF may still be linking when this screen opens — without
    // this, an early open sticks on "No coach chat yet" until reopened.
    _linkWorker = ever(member.isLinked, (bool linked) {
      if (linked && _sub == null && mounted) {
        setState(() {});
        _subscribe();
      }
    });
  }

  void _subscribe() {
    final cid = _clientId;
    if (cid == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = _all.isEmpty;
      _error = false;
    });
    _sub?.cancel();
    _sub = _chat.watchMessages(cid).listen((list) {
      final hadNewIncoming = list.isNotEmpty &&
          list.last.senderId != _uid &&
          (_live.isEmpty || list.last.id != _live.last.id);
      final liveIds = list.map((m) => m.id).toSet();
      _older.removeWhere((m) => liveIds.contains(m.id));
      setState(() {
        _live = list;
        // Ambiguous-success reconciliation: a send that actually committed
        // but errored client-side must leave the failed list (its retry
        // would be rejected forever — messages are immutable server-side).
        _failed.removeWhere((f) => liveIds.contains(f.id));
        _loading = false;
        _error = false;
      });
      // The thread is on screen — reading is implicit.
      if (hadNewIncoming) _markRead();
    }, onError: (_) {
      setState(() {
        _loading = false;
        _error = true;
      });
    });
    _markRead();
  }

  void _markRead() {
    final cid = _clientId;
    if (cid != null) _chat.markReadMember(cid).catchError((_) {});
  }

  @override
  void dispose() {
    // Stop any voice note still playing so it doesn't keep playing after the
    // member leaves the thread (the audio player is a chat-scoped singleton).
    ChatAudioPlayer.instance.stop();
    _linkWorker?.dispose();
    _sub?.cancel();
    _recTimer?.cancel();
    _ampSub?.cancel();
    _recorder.dispose();
    _input.dispose();
    super.dispose();
  }

  // ── Sending (outbox) ──────────────────────────────────────────────────
  void _send() {
    final text = _input.text.trim();
    final cid = _clientId;
    if (text.isEmpty || cid == null) return;
    _input.clear();
    _dispatch(_FailedMessage(_chat.newMessageId(cid), text));
  }

  /// Fire-and-track: offline sends sit in Firestore's write queue and render
  /// as "sending" from snapshot metadata; only a server REJECTION lands the
  /// message in [_failed] with a tap-to-retry bubble. The client-generated id
  /// makes every retry idempotent (rewrites the same doc, never duplicates).
  void _dispatch(_FailedMessage msg) {
    final cid = _clientId;
    if (cid == null) return;
    _chat.sendWithId(cid, msg.id, {
      'text': msg.text,
      'senderId': _uid,
      'senderName': member.name,
      'senderRole': 'client',
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        if (!_failed.any((f) => f.id == msg.id)) _failed.add(msg);
      });
      Get.snackbar('Message not sent', 'Tap the message to retry.');
    });
  }

  void _retry(_FailedMessage f) {
    setState(() => _failed.removeWhere((x) => x.id == f.id));
    if (f.isMedia) {
      if (!File(f.imagePath).existsSync()) {
        Get.snackbar(
            'Chat',
            f.isVoice
                ? 'Recording no longer available. Please record again.'
                : 'Image no longer available. Please pick it again.');
        return;
      }
      _startUpload(_PendingUpload(
          f.id, f.imagePath, f.kind, f.durationMs, f.waveform));
      return;
    }
    _dispatch(f);
  }

  // ── Image sending (M1) ────────────────────────────────────────────────
  Future<void> _attachImage(ImageSource source) async {
    final cid = _clientId;
    if (cid == null) return;
    final XFile? picked;
    try {
      // Picker-level downscale + re-encode — the house pattern (progress
      // photos use the same; no extra compression dependency needed).
      picked = await ImagePicker()
          .pickImage(source: source, maxWidth: 1600, imageQuality: 78);
    } catch (_) {
      Get.snackbar('Chat', 'Could not open the picker.');
      return;
    }
    if (picked == null) return;
    // ── DIAGNOSTIC STEP 1 & 2 (image selected + picker-level compression) ──
    // The picker downscales/re-encodes inline (maxWidth 1600, quality 78), so
    // the returned file IS the compressed one; the pre-compression original
    // size is not exposed by image_picker (origSize=n/a). Diagnostic-only.
    final dbgPath = picked.path;
    final dbgExt = dbgPath.contains('.') ? dbgPath.split('.').last : '';
    var dbgSize = 0;
    try {
      dbgSize = await picked.length();
    } catch (_) {}
    debugPrint('IMG STEP1 selected · path=$dbgPath ext=$dbgExt size=$dbgSize');
    debugPrint('IMG STEP2 compressed · origSize=n/a compSize=$dbgSize '
        'mime=image/jpeg path=$dbgPath');
    _startUpload(
        _PendingUpload(_chat.newMessageId(cid), picked.path, 'image'));
  }

  void _startUpload(_PendingUpload up) {
    setState(() => _uploads.add(up));
    _runUpload(up);
  }

  Future<void> _runUpload(_PendingUpload up) async {
    final cid = _clientId;
    if (cid == null) return;
    final file = File(up.filePath);
    final voice = up.isVoice;
    final path = voice
        ? _chat.voicePath(cid, up.id)
        : _chat.mediaPath(cid, up.id);
    // ── DIAGNOSTIC STEP 3 (auth + the clients doc the Storage rule evaluates) ──
    final dbgAuthUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    debugPrint(
        'IMG STEP3 auth · uid=$dbgAuthUid clientId=$cid messageId=${up.id}');
    try {
      final dbgClientSnap = await FirebaseFirestore.instance
          .collection('clients')
          .doc(cid)
          .get();
      final dbgClientData = dbgClientSnap.data();
      final dbgAdminId = dbgClientData?['adminId'];
      final dbgAuthUidField = dbgClientData?['authUid'];
      final dbgTrainerId = dbgClientData?['trainerId'];
      debugPrint('IMG STEP3 clients/$cid · exists=${dbgClientSnap.exists} '
          'adminId=$dbgAdminId authUid=$dbgAuthUidField trainerId=$dbgTrainerId');
      debugPrint('IMG STEP3 match · adminId==uid=${dbgAdminId == dbgAuthUid} '
          'authUid==uid=${dbgAuthUidField == dbgAuthUid}');
      final dbgTrainerSnap = await FirebaseFirestore.instance
          .collection('trainers')
          .doc(dbgAuthUid)
          .get();
      final dbgTrainerData = dbgTrainerSnap.data();
      final dbgAssignedBy = dbgTrainerData?['assignedBy'];
      debugPrint(
          'IMG STEP3 trainers/$dbgAuthUid · exists=${dbgTrainerSnap.exists} '
          'assignedBy=$dbgAssignedBy assignedBy==adminId=${dbgAssignedBy == dbgAdminId}');
    } catch (e) {
      debugPrint('IMG STEP3 read FAILED · $e');
    }
    // ── DIAGNOSTIC STEP 4 (storage target) ──
    debugPrint('IMG STEP4 storage · bucket=${FirebaseStorage.instance.bucket} '
        'path=$path contentType=${voice ? 'audio/mp4' : 'image/jpeg'}');
    try {
      final task = FirebaseStorage.instance.ref(path).putFile(
          file,
          SettableMetadata(
              contentType: voice ? 'audio/mp4' : 'image/jpeg'));
      up.task = task;
      // ── DIAGNOSTIC STEP 5 (upload lifecycle) ──
      debugPrint('IMG STEP5 upload STARTED · path=$path');
      task.snapshotEvents.listen((s) {
        debugPrint('IMG STEP5 progress · '
            '${s.bytesTransferred}/${s.totalBytes} state=${s.state}');
        if (s.totalBytes > 0 && mounted) {
          final next = s.bytesTransferred / s.totalBytes;
          // Throttle: snapshotEvents fire per chunk; rebuilding the whole
          // list for sub-2% deltas causes scroll jank during uploads.
          if (next - up.progress >= 0.02 || next >= 1) {
            setState(() => up.progress = next);
          }
        }
      }, onError: (_) {});
      final snap = await task;
      debugPrint('IMG STEP5 upload COMPLETED · bytes=${snap.bytesTransferred}');
      final url = await snap.ref.getDownloadURL();
      debugPrint(
          'IMG STEP8 downloadURL · ${url.isNotEmpty ? 'YES' : 'NO'} url=$url');
      final dims = voice ? null : await _imageDims(file);
      await _chat.sendWithId(
        cid,
        up.id,
        {
          'text': '',
          'senderId': _uid,
          'senderName': member.name,
          'senderRole': 'client',
        },
        type: voice ? 'voice' : 'image',
        media: ChatMedia(
          storagePath: path,
          url: url,
          mime: voice ? 'audio/mp4' : 'image/jpeg',
          sizeBytes: file.lengthSync(),
          width: dims?.width ?? 0,
          height: dims?.height ?? 0,
          durationMs: voice ? up.durationMs : 0,
          waveform: voice ? up.waveform : const [],
        ).toMap(),
      );
      debugPrint('IMG STEP7 firestore message created · '
          'YES (chats/$cid/messages/${up.id})');
      if (mounted) setState(() => _uploads.removeWhere((u) => u.id == up.id));
    } on FirebaseException catch (e, st) {
      debugPrint(
          'IMG STEP6 FAILED · plugin=${e.plugin} code=${e.code} path=$path');
      debugPrint('IMG STEP6 message · ${e.message}');
      debugPrint('IMG STEP6 stack · $st');
      debugPrint('IMG STEP7 firestore message created · NO');
      if (mounted) setState(() => _uploads.removeWhere((u) => u.id == up.id));
      if (e.code == 'canceled') return;
      _failImage(up);
    } catch (e, st) {
      debugPrint('IMG STEP6 FAILED (non-firebase) · $e');
      debugPrint('IMG STEP6 stack · $st');
      debugPrint('IMG STEP7 firestore message created · NO');
      if (mounted) setState(() => _uploads.removeWhere((u) => u.id == up.id));
      _failImage(up);
    }
  }

  void _failImage(_PendingUpload up) {
    if (!mounted) return;
    setState(() {
      if (!_failed.any((f) => f.id == up.id)) {
        _failed.add(_FailedMessage(
            up.id, '', up.filePath, up.kind, up.durationMs, up.waveform));
      }
    });
    Get.snackbar(
        'Chat',
        up.isVoice
            ? 'Voice message not sent. Tap it to retry.'
            : 'Photo not sent. Tap it to retry.');
  }

  void _cancelUpload(_PendingUpload up) {
    up.task?.cancel();
    setState(() => _uploads.removeWhere((u) => u.id == up.id));
  }

  // ── Voice recording (M2) ──────────────────────────────────────────────

  static const int _maxRecordMs = 5 * 60 * 1000;

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  int _recordMs = 0;
  final List<int> _ampSamples = [];
  final List<int> _liveWave = [];
  Timer? _recTimer;
  StreamSubscription? _ampSub;

  Future<void> _startRecording() async {
    if (_isRecording || _clientId == null) return;
    // Never record over an active playback (the mic would capture it).
    ChatAudioPlayer.instance.stop();
    try {
      if (!await _recorder.hasPermission()) {
        Get.snackbar(
            'Chat', 'Microphone permission is needed for voice messages.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 48000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      setState(() {
        _isRecording = true;
        _recordMs = 0;
        _ampSamples.clear();
        _liveWave.clear();
      });
      _recTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        setState(() => _recordMs += 250);
        if (_recordMs >= _maxRecordMs) _stopRecording(send: true);
      });
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 250))
          .listen((amp) {
        // Non-finite samples (silent mic on some devices) count as silence.
        final raw = ((amp.current + 45) / 45) * 100;
        final v = raw.isFinite ? raw.clamp(0, 100).round() : 0;
        _ampSamples.add(v);
        _liveWave.add(v);
        if (_liveWave.length > 36) _liveWave.removeAt(0);
      }, onError: (_) {});
    } catch (_) {
      if (mounted) setState(() => _isRecording = false);
      Get.snackbar('Chat', 'Could not start recording.');
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    if (!_isRecording) return;
    _recTimer?.cancel();
    _ampSub?.cancel();
    final durationMs = _recordMs;
    setState(() => _isRecording = false);
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = null;
    }
    if (path == null) return;
    if (!send || durationMs < 800) {
      try {
        File(path).deleteSync();
      } catch (_) {}
      return;
    }
    final cid = _clientId;
    if (cid == null) return;
    _startUpload(_PendingUpload(_chat.newMessageId(cid), path, 'voice',
        durationMs, _downsampleWave(_ampSamples, 48)));
  }

  List<int> _downsampleWave(List<int> samples, int buckets) {
    if (samples.isEmpty) return const [];
    if (samples.length <= buckets) return List<int>.from(samples);
    final out = <int>[];
    final size = samples.length / buckets;
    for (var b = 0; b < buckets; b++) {
      final start = (b * size).floor();
      final end = ((b + 1) * size).ceil().clamp(start + 1, samples.length);
      var sum = 0;
      for (var i = start; i < end; i++) {
        sum += samples[i];
      }
      out.add((sum / (end - start)).round());
    }
    return out;
  }

  Future<({int width, int height})?> _imageDims(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final r = (width: frame.image.width, height: frame.image.height);
      frame.image.dispose();
      return r;
    } catch (_) {
      return null;
    }
  }

  // ── History pagination ────────────────────────────────────────────────
  Future<void> _loadOlder() async {
    final cid = _clientId;
    if (cid == null || _loadingOlder || !_hasMoreHistory) return;
    DateTime? anchor;
    for (final m in _all) {
      if (m.createdAt != null) {
        anchor = m.createdAt;
        break;
      }
    }
    if (anchor == null) return;
    setState(() => _loadingOlder = true);
    try {
      const pageSize = 100;
      final page =
          await _chat.fetchOlder(cid, before: anchor, limit: pageSize);
      final known = _all.map((m) => m.id).toSet();
      if (!mounted) return;
      setState(() {
        if (page.length < pageSize) _hasMoreHistory = false;
        _older.insertAll(0, page.where((m) => !known.contains(m.id)));
        _loadingOlder = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingOlder = false);
      Get.snackbar('Chat', 'Could not load earlier messages.');
    }
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
        // REAL now (Communication M3.3) — dials through the frozen backend.
        IconButton(
          tooltip: 'Call your coach',
          icon: Icon(Icons.call_outlined, color: p.textPrimary),
          onPressed: () {
            final call = Get.isRegistered<CallService>()
                ? Get.find<CallService>()
                : Get.put(CallService(), permanent: true);
            call.dialCoach();
          },
        ),
      ],
    );
  }

  /// The trainer's INITIALS — honest, always correct. (The previous static
  /// bundled photo showed a stranger's face for every trainer.)
  Widget _avatar(AppPalette p, double size) {
    final name = member.trainerName.isEmpty ? 'C' : member.trainerName.trim();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.surfaceAlt,
        border: Border.all(color: p.accent.withValues(alpha: 0.5), width: 1.4),
      ),
      alignment: Alignment.center,
      child: Text(
        name[0].toUpperCase(),
        style: AppText.title(size: size * 0.42).copyWith(color: p.accent),
      ),
    );
  }

  // ── Messages ────────────────────────────────────────────────────────
  Widget _messageList(AppPalette p) {
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(strokeWidth: 2.4, color: p.accent));
    }
    if (_error && _all.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load messages.',
                style: AppText.body(size: 13).copyWith(color: p.textMuted)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _subscribe,
              icon: Icon(Icons.refresh, size: 16, color: p.accent),
              label: Text('Retry',
                  style: AppText.body(size: 13).copyWith(color: p.accent)),
            ),
          ],
        ),
      );
    }
    final all = _all;
    if (all.isEmpty && _failed.isEmpty && _uploads.isEmpty) {
      return _emptyConversation(p);
    }

    // Render newest-first for the bottom-anchored reverse list. Order (from
    // the bottom): failed, uploads in flight, messages, the history loader.
    final showLoadOlder =
        _hasMoreHistory && (all.length >= 200 || _older.isNotEmpty);
    final itemCount = all.length +
        _failed.length +
        _uploads.length +
        (showLoadOlder ? 1 : 0);

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      itemCount: itemCount,
      itemBuilder: (context, i) {
        if (i < _failed.length) {
          return _failedBubble(p, _failed[_failed.length - 1 - i]);
        }
        final upIdx = i - _failed.length;
        if (upIdx < _uploads.length) {
          return _uploadBubble(p, _uploads[_uploads.length - 1 - upIdx]);
        }
        final mi = upIdx - _uploads.length;
        if (mi >= all.length) return _loadOlderRow(p);

        final idx = all.length - 1 - mi; // chronological index
        final m = all[idx];
        final mine = m.senderId == _uid;
        final olderM = idx > 0 ? all[idx - 1] : null;
        final newerM = idx + 1 < all.length ? all[idx + 1] : null;

        final showDay = m.createdAt != null &&
            (olderM?.createdAt == null ||
                !_sameDay(m.createdAt!, olderM!.createdAt!));
        // Tight spacing while the same sender keeps talking.
        final grouped =
            newerM != null && (newerM.senderId == _uid) == mine && !showDay;

        return Column(
          children: [
            if (showDay) _dayChip(p, m.createdAt!),
            _bubble(p, m, mine, grouped),
          ],
        );
      },
    );
  }

  Widget _loadOlderRow(AppPalette p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: _loadingOlder
            ? SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: p.accent),
              )
            : TextButton.icon(
                onPressed: _loadOlder,
                icon: Icon(Icons.history, size: 16, color: p.accent),
                label: Text(
                  'Load earlier messages',
                  style: GoogleFonts.poppins(
                    color: p.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
      ),
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

  Widget _bubble(AppPalette p, ChatMessageModel m, bool mine, bool grouped) {
    final time =
        m.createdAt == null ? '' : DateFormat('h:mm a').format(m.createdAt!);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        // Copy applies to TEXT only — copying a voice/image message would
        // put an empty string on the clipboard and lie "copied".
        onLongPress: (m.isDeleted || m.isVoice || m.isImage)
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: m.text));
                Get.snackbar('Chat', 'Message copied.');
              },
        child: Container(
          margin: EdgeInsets.only(top: grouped ? 2 : 8),
          padding: const EdgeInsets.fromLTRB(14, 9, 12, 8),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.76),
          decoration: BoxDecoration(
            gradient: mine
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: BrandColors.selectedGradient,
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
              if (m.isDeleted)
                Text(
                  'Message deleted',
                  style: GoogleFonts.poppins(
                    color: mine ? Colors.white70 : p.textMuted,
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else if (m.type == 'call')
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      m.text.startsWith('Missed')
                          ? Icons.phone_missed
                          : Icons.call_outlined,
                      size: 15,
                      color: m.text.startsWith('Missed')
                          ? const Color(0xFFFF5252)
                          : (mine ? Colors.white70 : p.textMuted),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      m.text,
                      style: GoogleFonts.poppins(
                        color: mine ? Colors.white : p.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                )
              else if (m.isImage)
                _imageContent(p, m)
              else if (m.isVoice)
                VoiceMessageBubble(
                  messageId: m.id,
                  url: m.media!.url,
                  durationMs: m.media!.durationMs,
                  waveform: m.media!.waveform,
                  fg: mine ? Colors.white : p.accent,
                  fgMuted: mine
                      ? Colors.white.withValues(alpha: 0.45)
                      : p.textMuted.withValues(alpha: 0.55),
                )
              else
                Text(
                  m.text,
                  style: GoogleFonts.poppins(
                    color: mine ? Colors.white : p.textPrimary,
                    fontSize: 13.5,
                    height: 1.32,
                  ),
                ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m.pending ? 'Sending…' : time,
                    style: GoogleFonts.poppins(
                      color: mine ? Colors.white70 : p.textMuted,
                      fontSize: 9,
                    ),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 3),
                    Icon(
                      m.pending ? Icons.schedule : Icons.check_rounded,
                      size: 11,
                      color: Colors.white70,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Delivered image: tappable thumbnail (Hero into the full-screen viewer).
  Widget _imageContent(AppPalette p, ChatMessageModel m) {
    final media = m.media!;
    final ar = media.aspectRatio.clamp(0.6, 1.8);
    final heroTag = 'chatimg_${m.id}';
    return GestureDetector(
      onTap: () =>
          ChatImageViewer.open(context, url: media.url, heroTag: heroTag),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 220,
          child: AspectRatio(
            aspectRatio: ar,
            child: Hero(
              tag: heroTag,
              child: CachedNetworkImage(
                imageUrl: media.url,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: p.surfaceAlt,
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: p.accent),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: p.surfaceAlt,
                  child: Icon(Icons.broken_image_outlined,
                      color: p.textMuted, size: 32),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Upload in flight: local thumbnail + progress ring + cancel.
  Widget _uploadBubble(AppPalette p, _PendingUpload up) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 210,
            height: 210,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(File(up.filePath), fit: BoxFit.cover),
                Container(color: Colors.black.withValues(alpha: 0.45)),
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          value: up.progress > 0 ? up.progress : null,
                          color: Colors.white,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel upload',
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 20),
                        onPressed: () => _cancelUpload(up),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _failedBubble(AppPalette p, _FailedMessage f) {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: () => _retry(f),
        onLongPress: () =>
            setState(() => _failed.removeWhere((x) => x.id == f.id)),
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.fromLTRB(14, 9, 12, 8),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.76),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.red.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (f.isVoice)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.mic, color: Colors.red, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Voice message (${(f.durationMs / 1000).round()}s)',
                      style: GoogleFonts.poppins(
                          color: p.textPrimary, fontSize: 13),
                    ),
                  ],
                )
              else if (f.isImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: File(f.imagePath).existsSync()
                      ? Image.file(File(f.imagePath),
                          width: 190, height: 190, fit: BoxFit.cover)
                      : Container(
                          width: 190,
                          height: 110,
                          color: Colors.black12,
                          child: const Icon(Icons.broken_image_outlined,
                              color: Colors.red),
                        ),
                )
              else
                Text(
                  f.text,
                  style: GoogleFonts.poppins(
                      color: p.textPrimary, fontSize: 13.5, height: 1.32),
                ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 12, color: Colors.red),
                  const SizedBox(width: 4),
                  Text(
                    'Not sent — tap to retry',
                    style: GoogleFonts.poppins(
                      color: Colors.red,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
      child: _isRecording ? _recordingBar(p) : Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Send a photo',
            icon: Icon(Icons.add_photo_alternate_outlined,
                color: p.textMuted, size: 24),
            onPressed: _attachSheet,
          ),
          IconButton(
            tooltip: 'Record a voice message',
            icon: Icon(Icons.mic_none_rounded, color: p.textMuted, size: 24),
            onPressed: _startRecording,
          ),
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
                buildCounter: (context,
                        {required currentLength,
                        required isFocused,
                        maxLength}) =>
                    null,
                cursorColor: p.accent,
                style: TextStyle(color: p.textPrimary),
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
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
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: BrandColors.selectedGradient,
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

  /// Recording mode: pulsing dot + timer + live wave + Delete / Send.
  Widget _recordingBar(AppPalette p) {
    final s = _recordMs ~/ 1000;
    return Row(
      children: [
        IconButton(
          tooltip: 'Discard recording',
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _stopRecording(send: false),
        ),
        Icon(Icons.fiber_manual_record, color: Colors.red.shade600, size: 14),
        const SizedBox(width: 6),
        Text(
          '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}',
          style: GoogleFonts.poppins(
              color: p.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 26,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final v in _liveWave)
                  Container(
                    width: 3,
                    height: (4 + v * 0.22).clamp(4, 26).toDouble(),
                    margin: const EdgeInsets.symmetric(horizontal: 1.2),
                    decoration: BoxDecoration(
                      color: p.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => _stopRecording(send: true),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: BrandColors.selectedGradient,
              ),
            ),
            child:
                const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }

  void _attachSheet() {
    final p = context.palette;
    showModalBottomSheet(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: p.accent),
              title: Text('Photo from gallery',
                  style:
                      AppText.body(size: 14.5).copyWith(color: p.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _attachImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: p.accent),
              title: Text('Take a photo',
                  style:
                      AppText.body(size: 14.5).copyWith(color: p.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _attachImage(ImageSource.camera);
              },
            ),
          ],
        ),
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
