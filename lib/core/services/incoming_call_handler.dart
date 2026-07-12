import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Deterministic UUID-shaped id from a Firestore call id (iOS CallKit
/// requires UUID format; Android doesn't care). Same call → same UUID, so a
/// duplicate ring push replaces rather than stacks.
String uuidForCallId(String callId) {
  final hex = StringBuffer();
  for (var i = 0; hex.length < 32; i++) {
    final c = callId.isEmpty ? 48 : callId.codeUnitAt(i % callId.length);
    hex.write(((c * (i + 31)) % 256).toRadixString(16).padLeft(2, '0'));
  }
  final h = hex.toString().substring(0, 32);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20, 32)}';
}

/// Renders the NATIVE incoming-call UI (ConnectionService / CallKit) from a
/// ring push's data payload. Shared by the foreground listener and the
/// killed/background FCM handler — the only two entry points for a ring.
Future<void> showIncomingCallKit(Map<String, dynamic> data) async {
  final callId = (data['callId'] ?? '').toString();
  if (callId.isEmpty) return;
  await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
    id: uuidForCallId(callId),
    nameCaller: (data['callerName'] ?? 'Incoming call').toString(),
    appName: 'AlphaSerena',
    handle: 'Voice call',
    type: 0, // audio
    duration: 55000, // dismiss just before the backend's 60s missed sweep
    extra: <String, dynamic>{
      'callId': callId,
      'clientId': (data['clientId'] ?? '').toString(),
    },
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#10131A',
      actionColor: '#34C759',
      isShowCallID: false,
    ),
    ios: const IOSParams(
      supportsVideo: false,
      maximumCallGroups: 1,
      maximumCallsPerCallGroup: 1,
      ringtonePath: 'system_ringtone_default',
    ),
  ));
}
