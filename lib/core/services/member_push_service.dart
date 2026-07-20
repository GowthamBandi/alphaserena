import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:get/get.dart';

import '../../screens/dashboard/check_in_screen.dart';
import '../../screens/dashboard/client_chat_screen.dart';
import '../../screens/dashboard/membership_screen.dart';
import '../../screens/dashboard/my_plans_screen.dart';
import '../../screens/dashboard/notification_center_screen.dart';
import 'call_service.dart';
import 'incoming_call_handler.dart';

/// Member push notifications (FCM) — Communication Platform M0. This app had
/// NO push at all before; a coach message was invisible until the member
/// happened to open the thread.
///
/// - `init()` (after the member is linked): requests permission, registers the
///   device token via the `registerFcmToken` Cloud Function (the ONLY token
///   write path — direct `fcmTokens` writes are blocked by rules), and keeps
///   it fresh on rotation.
/// - Tapping a `kind: chat_message` notification (background or cold start)
///   deep-links into the coach chat.
/// - `removeTokenOnSignOut()` must run BEFORE FirebaseAuth.signOut() so the
///   next member on this device never receives this member's messages.
class MemberPushService extends GetxService {
  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  final FirebaseFunctions _fns = FirebaseFunctions.instance;

  bool _started = false;
  bool _refreshBound = false;
  bool _bound = false; // a signed-in member currently owns this device token
  String? _token;

  Future<void> init() async {
    _bound = true;
    if (_started) {
      await _registerCurrent();
      return;
    }
    _started = true;
    // Wire CallKit events + sweep any stale call lock (M3.3). Fire-and-
    // forget: call init failing must never affect the member session.
    try {
      final call = Get.isRegistered<CallService>()
          ? Get.find<CallService>()
          : Get.put(CallService(), permanent: true);
      call.init();
    } catch (_) {}
    try {
      await _fm.requestPermission();
      FirebaseMessaging.onMessage.listen((msg) {
        // Foreground ring: native incoming-call UI + a doc watcher so a
        // caller-cancelled ring dismisses immediately (certified M3.2.5).
        if (msg.data['kind'] == 'incoming_call') {
          if (_bound) {
            showIncomingCallKit(msg.data);
            final callId = (msg.data['callId'] ?? '').toString();
            if (callId.isNotEmpty) {
              try {
                Get.find<CallService>().trackIncomingRing(callId);
              } catch (_) {}
            }
          }
          return;
        }
        final n = msg.notification;
        if (n == null) return;
        final title = (n.title ?? '').trim();
        final body = (n.body ?? '').trim();
        if (title.isEmpty && body.isEmpty) return;
        Get.snackbar(title.isEmpty ? 'New message' : title, body,
            snackPosition: SnackPosition.TOP);
      });
      FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);
      final initial = await _fm.getInitialMessage();
      if (initial != null) _openFromMessage(initial);
      await _registerCurrent();
      _fm.onTokenRefresh.listen((t) {
        _token = t;
        // Only while a member is signed in — never register for a signed-out
        // device (the next member would inherit this token otherwise).
        if (_bound) _register(t).catchError((_) {});
      });
      _refreshBound = true;
    } catch (_) {
      // Permission/APNs failures are non-fatal — chat still works in-app.
    }
  }

  Future<void> _registerCurrent() async {
    try {
      final token = await _fm.getToken();
      if (token != null && token.isNotEmpty) {
        _token = token;
        await _register(token);
      }
    } catch (_) {
      // Token retrieval can fail (e.g. iOS without APNs) — non-fatal.
    }
  }

  Future<void> _register(String token) async {
    await _fns.httpsCallable('registerFcmToken').call({'token': token});
  }

  void _openFromMessage(RemoteMessage msg) {
    if (!_bound) return; // signed out — never deep-link into a session
    switch (msg.data['kind']) {
      case 'chat_message':
      case 'missed_call':
      case 'trainer_changed':
        Get.to(() => const ClientChatScreen());
        break;
      case 'checkin_reviewed':
        Get.to(() => const CheckInScreen());
        break;
      case 'membership_expiring':
      case 'membership_expired':
      case 'membership_activated':
        // All membership lifecycle taps land on the renewal/membership screen —
        // matches the in-app center's tap routing for the same kinds.
        Get.to(() => MembershipScreen());
        break;
      case 'plan_assigned_workout':
      case 'plan_assigned_diet':
      case 'plan_updated_workout':
      case 'plan_updated_diet':
      case 'plan_removed_workout':
      case 'plan_removed_diet':
        Get.to(() => const MyPlansScreen());
        break;
      case 'incoming_call':
        break; // handled by CallKit, never a deep-link
      default:
        // membership_expired + any future/unknown kind lands on the durable
        // history — the notification center — instead of being dropped.
        Get.to(() => const NotificationCenterScreen());
    }
  }

  /// Best-effort, short-timeout token removal — must never block sign-out.
  Future<void> removeTokenOnSignOut() async {
    final t = _token;
    _bound = false;
    if (t == null) return;
    try {
      await _fns
          .httpsCallable('unregisterFcmToken')
          .call({'token': t}).timeout(const Duration(seconds: 5));
    } catch (_) {
      // The stale token dies on the next send-prune or rotation.
    }
  }

  // ignore: unused_field — kept for parity with future multi-listener needs.
  bool get refreshBound => _refreshBound;
}
