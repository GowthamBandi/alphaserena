import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:flutter_webrtc/flutter_webrtc.dart'
    hide navigator; // GetX also exports `navigator`
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../../screens/call/call_screen.dart';

/// Local (screen-facing) call phase — projected from the Firestore call doc,
/// which stays the single source of truth. Keep in sync with the CERTIFIED
/// trainersHQ implementation (M3.2.5) — this is a mirror, not a fork.
enum CallPhase { idle, dialing, connecting, connected, reconnecting, ended }

/// Member (AlphaSerena) side of the voice-call state machine. Identity
/// differences from trainersHQ are the ONLY differences: senderRole is
/// 'client', the callee is the member's coach (assigned trainer, else the
/// org owner), and the member's own membershipActive gates dialing.
class CallService extends GetxService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _fns = FirebaseFunctions.instance;

  final Rx<CallPhase> phase = CallPhase.idle.obs;
  final RxString peerName = ''.obs;
  final RxString endLabel = ''.obs;
  final RxBool isMuted = false.obs;
  final RxBool isSpeaker = false.obs;
  final RxInt callSeconds = 0.obs;

  String? _callId;
  bool _isCaller = false;
  String _mySide = 'caller';

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription? _callSub;
  StreamSubscription? _candSub;
  StreamSubscription? _callkitSub;
  StreamSubscription? _ringWatchSub;
  Timer? _restartTimer;
  Timer? _heartbeat;
  Timer? _ticker;
  Timer? _ringTimeout;
  bool _tearingDown = false;

  /// SDP of the last-applied remote description (answer for the caller,
  /// offer for the callee) — a CHANGED value on the doc means the peer
  /// started an ICE-restart renegotiation (M3.4).
  String _appliedRemoteSdp = '';

  // ICE gathering starts at setLocalDescription — BEFORE the call doc/lane
  // exists. Candidates emitted in that window are buffered and flushed by
  // _publishLocalCandidates (certified M3.2.5 fix — dropping them breaks
  // or slows connection setup).
  final List<RTCIceCandidate> _pendingLocalCandidates = [];
  String? _candidateLanePath;

  // Remote candidates that arrive (on the separate candidate listener) before
  // setRemoteDescription is applied would be dropped by addCandidate — buffer
  // them until the remote description exists, then flush (M3.5).
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _remoteDescriptionSet = false;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  DocumentReference<Map<String, dynamic>> _callRef(String id) =>
      _db.collection('calls').doc(id);
  DocumentReference<Map<String, dynamic>> _lockRef(String uid) =>
      _db.collection('call_locks').doc(uid);

  bool get inCall => phase.value != CallPhase.idle;

  /// Wire CallKit events once (after the member links) + sweep a stale lock
  /// from a previous crash so this member isn't stuck "busy".
  Future<void> init() async {
    _callkitSub ??= FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;

      final callId = switch (event) {
        CallEventActionCallAccept e =>
          (e.callKitParams.extra?['callId'] ?? '').toString(),
        CallEventActionCallDecline e =>
          (e.callKitParams.extra?['callId'] ?? '').toString(),
        CallEventActionCallTimeout e => e.id,
        _ => '',
      };

      switch (event) {
        case CallEventActionCallAccept():
          if (callId.isNotEmpty) answer(callId);
          break;
        case CallEventActionCallDecline():
          if (callId.isNotEmpty) decline(callId);
          break;
        case CallEventActionCallTimeout():
          // Unanswered ring timed out — a MISSED call, NOT a decline. Writing
          // 'declined' here suppressed the missed-call badge/push (and the rules
          // don't let the callee write 'missed'): leave the doc 'ringing' so the
          // backend janitor marks it 'missed' and fans out the badge + push. The
          // native ring UI has already dismissed itself.
          break;
        default:
          break;
      }
    });
    await _recoverStaleLock();
    // Killed-app receive recovery: join a call the member accepted while the app
    // was terminated (its accept event fired before this listener existed).
    await _reconcileAcceptedCall();
  }

  /// Killed-app receive recovery. When the app was TERMINATED, the OS relaunches
  /// it from the CallKit accept — but onEvent is a broadcast stream that never
  /// replays the actionCallAccept fired before this service subscribed, so
  /// answer() never ran and the call rang out to "missed". On startup we ask the
  /// plugin for a call the user already ACCEPTED and join it, reconciling against
  /// the live Firestore state first. Safe by construction: if the plugin reports
  /// no accepted call this is a no-op — it never auto-answers a mere ring.
  Future<void> _reconcileAcceptedCall() async {
    if (inCall) return;
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final params in calls) {
        // Only a call the user actually ACCEPTED (the plugin flags these).
        if (!params.isAccepted) continue;
        final callId = (params.extra?['callId'] ?? '').toString();
        if (callId.isEmpty) continue;
        final call = (await _callRef(callId).get()).data();
        if (call == null) continue;
        if (call['state'] == 'ringing' && call['calleeUid'] == _myUid) {
          await answer(callId);
        } else {
          await FlutterCallkitIncoming.endAllCalls();
        }
        return; // one call at a time
      }
    } catch (_) {
      // Best-effort — the caller's ring timeout + janitor are the backstop.
    }
  }

  Future<void> _recoverStaleLock() async {
    final uid = _myUid;
    if (uid.isEmpty || inCall) return;
    try {
      final lock = await _lockRef(uid).get();
      if (!lock.exists) return;
      final callId = (lock.data()?['callId'] ?? '').toString();
      if (callId.isNotEmpty) {
        final call = await _callRef(callId).get();
        final state = (call.data()?['state'] ?? '').toString();
        const terminal = [
          'ended',
          'declined',
          'busy',
          'missed',
          'cancelled',
          'failed',
        ];
        if (call.exists && !terminal.contains(state)) {
          await _callRef(callId)
              .update({
                'state': state == 'ringing' ? 'cancelled' : 'ended',
                'endedAt': FieldValue.serverTimestamp(),
                'endReason': 'abandoned_restart',
              })
              .catchError((_) {});
        }
      }
      await _lockRef(uid).delete();
    } catch (_) {
      // Best-effort — the janitor is the backstop.
    }
  }

  // ── Outgoing: the member calls their coach ─────────────────────────────

  Future<void> dialCoach() async {
    if (inCall) {
      Get.snackbar('Call', 'You are already in a call.');
      return;
    }
    final member = Get.isRegistered<MemberController>()
        ? Get.find<MemberController>()
        : null;
    final clientId = member?.linkedClientId;
    if (member == null || clientId == null) {
      Get.snackbar('Call', 'Your account is not linked to a coach yet.');
      return;
    }
    Map<String, dynamic>? cl;
    try {
      cl = (await _db.collection('clients').doc(clientId).get()).data();
    } catch (_) {}
    if (cl == null) {
      Get.snackbar('Call', 'Could not load your membership.');
      return;
    }
    if (cl['membershipActive'] != true) {
      Get.snackbar(
        'Call',
        'Calls need an active membership. You can still message your coach.',
      );
      return;
    }
    // Callee = the responsible coach (assigned trainer, else the org owner)
    // — the same derivation the rules enforce.
    final calleeUid = (cl['trainerId'] ?? '').toString().isNotEmpty
        ? (cl['trainerId'] ?? '').toString()
        : (cl['adminId'] ?? '').toString();
    if (calleeUid.isEmpty) {
      Get.snackbar('Call', 'No coach is available to call right now.');
      return;
    }

    peerName.value = member.trainerName.isEmpty
        ? 'Your Coach'
        : member.trainerName;
    endLabel.value = '';
    phase.value = CallPhase.dialing;
    _isCaller = true;
    _mySide = 'caller';
    Get.to(() => const CallScreen(), fullscreenDialog: true);

    try {
      await _setupMedia();
      final offer = await _pc!.createOffer({'offerToReceiveAudio': true});
      await _pc!.setLocalDescription(offer);

      final callRef = _db.collection('calls').doc();
      _callId = callRef.id;
      await _db.runTransaction((tx) async {
        final lock = await tx.get(_lockRef(_myUid));
        if (lock.exists) throw Exception('busy');
        tx.set(_lockRef(_myUid), {
          'callId': callRef.id,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.set(callRef, {
          'clientId': clientId,
          'adminId': (cl!['adminId'] ?? '').toString(),
          'callerUid': _myUid,
          // `member.name` is now honestly empty when no name is known (it no
          // longer invents one). An incoming-call screen must still say WHO is
          // calling, so fall back to a neutral ROLE — never to a made-up name.
          'callerName': member.name.isNotEmpty ? member.name : 'Member',
          'callerRole': 'client',
          'calleeUid': calleeUid,
          'type': 'audio',
          'state': 'ringing',
          'offer': {'sdp': offer.sdp, 'type': offer.type},
          'createdAt': FieldValue.serverTimestamp(),
          'lastActivityAt': FieldValue.serverTimestamp(),
          'heartbeat': <String, dynamic>{},
        });
      });

      _listenCall(callRef.id);
      _listenRemoteCandidates(callRef.id, remoteLane: 'candidates_callee');
      _publishLocalCandidates(callRef.id, myLane: 'candidates_caller');
      _startHeartbeat();

      _ringTimeout = Timer(const Duration(seconds: 60), () async {
        if (phase.value == CallPhase.dialing) {
          await _writeTerminal('cancelled', 'ring_timeout');
          _finish('No answer');
        }
      });
    } catch (e) {
      await _teardownRtc();
      _finish(
        e.toString().contains('busy')
            ? 'You are already in a call.'
            : 'Could not start the call.',
      );
    }
  }

  Future<void> cancel() async {
    _ringTimeout?.cancel();
    await _writeTerminal('cancelled', 'caller_cancelled');
    _finish('Call cancelled');
  }

  // ── Incoming ───────────────────────────────────────────────────────────

  /// Watches an incoming ring BEFORE it is answered so a caller-cancelled
  /// (or janitor-missed) call dismisses the native ring immediately
  /// (certified M3.2.5 fix).
  void trackIncomingRing(String callId) {
    _ringWatchSub?.cancel();
    _ringWatchSub = _callRef(callId).snapshots().listen((snap) {
      const terminal = [
        'ended',
        'declined',
        'busy',
        'missed',
        'cancelled',
        'failed',
      ];
      final state = (snap.data()?['state'] ?? '').toString();
      if (!snap.exists || terminal.contains(state)) {
        FlutterCallkitIncoming.endAllCalls();
        _ringWatchSub?.cancel();
        _ringWatchSub = null;
      }
    }, onError: (_) {});
  }

  Future<void> answer(String callId) async {
    if (inCall) return;
    final snap = await _callRef(callId).get();
    final call = snap.data();
    if (call == null || call['state'] != 'ringing') {
      await FlutterCallkitIncoming.endAllCalls();
      Get.snackbar('Call', 'That call has already ended.');
      return;
    }
    _callId = callId;
    _isCaller = false;
    _mySide = 'callee';
    peerName.value = (call['callerName'] ?? 'Your Coach').toString();
    endLabel.value = '';
    phase.value = CallPhase.connecting;
    Get.to(() => const CallScreen(), fullscreenDialog: true);

    try {
      await _setupMedia();
      final offer = call['offer'] as Map?;
      await _pc!.setRemoteDescription(
        RTCSessionDescription(
          (offer?['sdp'] ?? '').toString(),
          (offer?['type'] ?? 'offer').toString(),
        ),
      );
      _appliedRemoteSdp = (offer?['sdp'] ?? '').toString();
      await _markRemoteDescriptionSet();
      final answerDesc = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answerDesc);

      await _db.runTransaction((tx) async {
        final fresh = await tx.get(_callRef(callId));
        if ((fresh.data()?['state'] ?? '') != 'ringing') {
          throw Exception('gone');
        }
        final lock = await tx.get(_lockRef(_myUid));
        if (lock.exists) throw Exception('busy');
        tx.set(_lockRef(_myUid), {
          'callId': callId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(_callRef(callId), {
          'state': 'accepted',
          'answer': {'sdp': answerDesc.sdp, 'type': answerDesc.type},
          'acceptedAt': FieldValue.serverTimestamp(),
          'lastActivityAt': FieldValue.serverTimestamp(),
        });
      });

      _listenCall(callId);
      _listenRemoteCandidates(callId, remoteLane: 'candidates_caller');
      _publishLocalCandidates(callId, myLane: 'candidates_callee');
      _startHeartbeat();
    } catch (e) {
      await _teardownRtc();
      _finish(
        e.toString().contains('gone')
            ? 'That call has already ended.'
            : 'Could not join the call.',
      );
    }
  }

  Future<void> decline(String callId) async {
    try {
      await _callRef(callId).update({
        'state': 'declined',
        'endedAt': FieldValue.serverTimestamp(),
        'endReason': 'declined',
      });
    } catch (_) {
      // Already terminal — nothing to do.
    }
    await FlutterCallkitIncoming.endAllCalls();
  }

  // ── In-call controls ───────────────────────────────────────────────────

  void toggleMute() {
    final track = _localStream?.getAudioTracks().firstOrNull;
    if (track == null) return;
    track.enabled = isMuted.value;
    isMuted.value = !isMuted.value;
  }

  Future<void> toggleSpeaker() async {
    isSpeaker.value = !isSpeaker.value;
    try {
      await Helper.setSpeakerphoneOn(isSpeaker.value);
    } catch (_) {}
  }

  Future<void> hangUp() async {
    _ringTimeout?.cancel();
    if (phase.value == CallPhase.dialing) {
      await cancel();
      return;
    }
    await _writeTerminal('ended', 'hangup');
    _finish('Call ended');
  }

  // ── Internals (byte-mirrors of the certified trainersHQ logic) ─────────

  Future<void> _setupMedia() async {
    Map<String, dynamic> ice;
    try {
      final res = await _fns.httpsCallable('getTurnCredentials').call();
      ice = Map<String, dynamic>.from(res.data as Map);
    } catch (_) {
      ice = {
        'iceServers': [
          {
            'urls': ['stun:stun.l.google.com:19302'],
          },
        ],
      };
    }
    _localStream = await webrtc.navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    _pc = await createPeerConnection({
      'iceServers': ice['iceServers'],
      'sdpSemantics': 'unified-plan',
    });
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
    isMuted.value = false;
    isSpeaker.value = false;

    _pendingLocalCandidates.clear();
    _candidateLanePath = null;
    _pendingRemoteCandidates.clear();
    _remoteDescriptionSet = false;
    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      final lane = _candidateLanePath;
      if (lane == null) {
        _pendingLocalCandidates.add(candidate);
      } else {
        _writeCandidate(lane, candidate);
      }
    };

    _pc!.onConnectionState = (state) async {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          phase.value = CallPhase.connected;
          if (_ticker == null) _startTicker();
          try {
            await _callRef(_callId!).update({
              'state': 'connected',
              'connectedAt': FieldValue.serverTimestamp(),
              'lastActivityAt': FieldValue.serverTimestamp(),
            });
          } catch (_) {}
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          if (phase.value == CallPhase.connected) {
            phase.value = CallPhase.reconnecting;
            try {
              await _callRef(_callId!).update({
                'state': 'reconnecting',
                'lastActivityAt': FieldValue.serverTimestamp(),
              });
            } catch (_) {}
            // Brief blips self-heal via ICE consent checks. If still down
            // after 3s, the CALLER drives a real ICE-restart renegotiation —
            // restartIce() alone never renegotiates (M3.4 verified defect).
            if (_isCaller) {
              _restartTimer?.cancel();
              _restartTimer = Timer(const Duration(seconds: 3), () {
                if (phase.value == CallPhase.reconnecting) _renegotiate();
              });
            }
          }
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          await _writeTerminal('failed', 'ice_failed');
          _finish('Call failed — poor connection.');
          break;
        default:
          break;
      }
    };
  }

  void _listenCall(String callId) {
    _callSub?.cancel();
    _callSub = _callRef(callId).snapshots().listen((snap) async {
      final call = snap.data();
      if (call == null) return;
      final state = (call['state'] ?? '').toString();

      // Caller: an answer arrived (initial handshake, or a NEW answer to an
      // ICE-restart re-offer — detected by a changed SDP).
      if (_isCaller && call['answer'] is Map) {
        final ans = call['answer'] as Map;
        final sdp = (ans['sdp'] ?? '').toString();
        if (sdp.isNotEmpty && sdp != _appliedRemoteSdp) {
          _ringTimeout?.cancel();
          try {
            await _pc?.setRemoteDescription(
              RTCSessionDescription(sdp, (ans['type'] ?? 'answer').toString()),
            );
            _appliedRemoteSdp = sdp;
            await _markRemoteDescriptionSet();
            if (phase.value == CallPhase.dialing) {
              phase.value = CallPhase.connecting;
            }
          } catch (_) {}
        }
      }

      // Callee: the caller published an ICE-restart re-offer -> apply it and
      // publish a fresh answer through the renegotiation rules branch.
      if (!_isCaller && call['offer'] is Map) {
        final off = call['offer'] as Map;
        final sdp = (off['sdp'] ?? '').toString();
        if (sdp.isNotEmpty &&
            _appliedRemoteSdp.isNotEmpty &&
            sdp != _appliedRemoteSdp) {
          try {
            await _pc?.setRemoteDescription(
              RTCSessionDescription(sdp, (off['type'] ?? 'offer').toString()),
            );
            _appliedRemoteSdp = sdp;
            await _markRemoteDescriptionSet();
            final answerDesc = await _pc!.createAnswer();
            await _pc!.setLocalDescription(answerDesc);
            await _callRef(callId).update({
              'answer': {'sdp': answerDesc.sdp, 'type': answerDesc.type},
              'lastActivityAt': FieldValue.serverTimestamp(),
            });
          } catch (_) {}
        }
      }

      switch (state) {
        case 'busy':
          _finish('${peerName.value} is on another call.');
          break;
        case 'declined':
          _finish(_isCaller ? 'Call declined' : 'Call ended');
          break;
        case 'missed':
          _finish(_isCaller ? 'No answer' : 'Missed call');
          break;
        case 'cancelled':
          await FlutterCallkitIncoming.endAllCalls();
          _finish(_isCaller ? 'Call cancelled' : 'Call ended');
          break;
        case 'failed':
          _finish('Call failed');
          break;
        case 'ended':
          _finish('Call ended');
          break;
        default:
          break;
      }
    }, onError: (_) {});
  }

  void _publishLocalCandidates(String callId, {required String myLane}) {
    _candidateLanePath = 'calls/$callId/$myLane';
    for (final c in _pendingLocalCandidates) {
      _writeCandidate(_candidateLanePath!, c);
    }
    _pendingLocalCandidates.clear();
  }

  void _writeCandidate(String lanePath, RTCIceCandidate candidate) {
    _db
        .collection(lanePath)
        .add({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        })
        .then((_) {}, onError: (_) {});
  }

  void _listenRemoteCandidates(String callId, {required String remoteLane}) {
    _candSub?.cancel();
    _candSub = _callRef(callId).collection(remoteLane).snapshots().listen((
      snap,
    ) async {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final d = change.doc.data();
        if (d == null) continue;
        final cand = RTCIceCandidate(
          (d['candidate'] ?? '').toString(),
          d['sdpMid']?.toString(),
          (d['sdpMLineIndex'] is num) ? (d['sdpMLineIndex'] as num).toInt() : 0,
        );
        if (!_remoteDescriptionSet) {
          _pendingRemoteCandidates.add(cand);
        } else {
          try {
            await _pc?.addCandidate(cand);
          } catch (_) {}
        }
      }
    }, onError: (_) {});
  }

  /// Marks the remote description as applied and flushes any remote ICE
  /// candidates that arrived before it (addCandidate before setRemoteDescription
  /// is dropped by libwebrtc, causing intermittent connect failures).
  Future<void> _markRemoteDescriptionSet() async {
    _remoteDescriptionSet = true;
    if (_pendingRemoteCandidates.isEmpty) return;
    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final c in pending) {
      try {
        await _pc?.addCandidate(c);
      } catch (_) {}
    }
  }

  /// Caller-driven ICE restart: a fresh offer with new ICE credentials,
  /// published through the renegotiation rules branch. The callee answers it
  /// in _listenCall; new candidates trickle through the same lanes.
  Future<void> _renegotiate() async {
    final id = _callId;
    final pc = _pc;
    if (id == null || pc == null || !_isCaller) return;
    try {
      final offer = await pc.createOffer({
        'iceRestart': true,
        'offerToReceiveAudio': true,
      });
      await pc.setLocalDescription(offer);
      await _callRef(id).update({
        'offer': {'sdp': offer.sdp, 'type': offer.type},
        'lastActivityAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // The janitor's stale-heartbeat sweep is the final backstop.
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      final id = _callId;
      if (id == null) return;
      _callRef(id)
          .update({
            'heartbeat.$_mySide': FieldValue.serverTimestamp(),
            'lastActivityAt': FieldValue.serverTimestamp(),
          })
          .catchError((_) {});
    });
  }

  void _startTicker() {
    _ticker?.cancel();
    callSeconds.value = 0;
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => callSeconds.value++,
    );
  }

  Future<void> _writeTerminal(String state, String reason) async {
    final id = _callId;
    if (id == null) return;
    try {
      await _callRef(id).update({
        'state': state,
        'endedAt': FieldValue.serverTimestamp(),
        'endReason': reason,
      });
    } catch (_) {}
  }

  Future<void> _finish(String label) async {
    if (_tearingDown) return;
    _tearingDown = true;
    _ringTimeout?.cancel();
    _heartbeat?.cancel();
    _ticker?.cancel();
    _ticker = null;
    _callSub?.cancel();
    _candSub?.cancel();
    _ringWatchSub?.cancel();
    _restartTimer?.cancel();
    _pendingLocalCandidates.clear();
    _candidateLanePath = null;
    _pendingRemoteCandidates.clear();
    _remoteDescriptionSet = false;
    _appliedRemoteSdp = '';
    await _teardownRtc();
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
    final uid = _myUid;
    if (uid.isNotEmpty) {
      _lockRef(uid).delete().catchError((_) {});
    }
    endLabel.value = label;
    phase.value = CallPhase.ended;
    await Future.delayed(const Duration(milliseconds: 1200));
    if (phase.value == CallPhase.ended) {
      if (Get.key.currentState?.canPop() == true) Get.back();
    }
    phase.value = CallPhase.idle;
    _callId = null;
    _tearingDown = false;
    callSeconds.value = 0;
  }

  Future<void> _teardownRtc() async {
    try {
      await _localStream?.dispose();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    _localStream = null;
    _pc = null;
  }

  /// Sign-out teardown: end any live call + release the lock BEFORE auth
  /// dies so the next member on this device never inherits a call/lock.
  /// No-ops when idle — running the full teardown then would delay sign-out
  /// and could pop an unrelated route.
  Future<void> endForSignOut() async {
    if (!inCall || phase.value == CallPhase.ended) return;
    await _writeTerminal('ended', 'signout');
    await _finish('');
  }

  @override
  void onClose() {
    _callkitSub?.cancel();
    _finish('');
    super.onClose();
  }
}
