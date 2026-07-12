import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../core/services/coach_service.dart';
import '../core/services/call_service.dart';
import '../core/services/member_push_service.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/otp_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/join/join_coach_screen.dart';
import 'client_razorpay_controller.dart';
import 'member_controller.dart';
import 'membership_controller.dart';
import 'training_controller.dart';
import 'diet_log_controller.dart';
import 'check_in_controller.dart';
import 'lifestyle_controller.dart';
import 'home_controller.dart';
import 'onboarding_controller.dart';
import 'progress_controller.dart';

/// Phone-OTP auth + post-auth routing for the member app.
///
/// TESTING: enable Phone sign-in in Firebase Auth. On a real Android device you
/// need the app's SHA-1/SHA-256 in the Firebase project; for quick testing add a
/// test phone number + fixed OTP under Auth → Sign-in method → Phone.
class AuthController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final RxBool isLoading = false.obs;

  /// Resend has its own busy flag so tapping "Resend OTP" never makes the
  /// Verify button spin (they are different actions to the member).
  final RxBool isResending = false.obs;

  String? _verificationId;
  int? _resendToken;
  String _phone = '';

  StreamSubscription<User?>? _authSub;
  bool _hadUser = false;
  bool _tearingDown = false;

  String get phone => _phone;

  @override
  void onInit() {
    super.onInit();
    _hadUser = _auth.currentUser != null;
    // Session sentinel: if the account is disabled/deleted or the credential is
    // revoked mid-session, Firestore streams start failing silently — without
    // this listener the member would stare at a frozen dashboard forever.
    _authSub = _auth.authStateChanges().listen((user) {
      if (user != null) {
        _hadUser = true;
        return;
      }
      if (!_hadUser || _tearingDown) return; // cold start / already leaving
      _hadUser = false;
      _teardownToLogin();
      Get.snackbar('Signed out', 'Your session ended. Please log in again.');
    });
  }

  @override
  void onClose() {
    _authSub?.cancel();
    super.onClose();
  }

  /// Sends an OTP to [phone]. On the FIRST send we navigate to the OTP screen;
  /// on a [isResend] we stay on it (otherwise a duplicate OTP screen would be
  /// pushed on top). A stored [_resendToken] makes the resend trigger a fresh SMS.
  Future<void> sendOtp(String phone, {bool isResend = false}) async {
    _phone = phone;
    final busy = isResend ? isResending : isLoading;
    busy.value = true;
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: isResend ? _resendToken : null,
        verificationCompleted: (PhoneAuthCredential cred) async {
          // Android auto-retrieval: sign in silently if it works, but never
          // leave the button spinning if it doesn't.
          try {
            await _auth.signInWithCredential(cred);
            await routeAfterAuth();
          } catch (_) {
            busy.value = false;
            Get.snackbar('Almost there', 'Enter the code to continue.');
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          busy.value = false;
          Get.snackbar('Verification failed', _authMessage(e));
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          busy.value = false;
          // Only push the OTP screen on the first send; a resend refreshes in
          // place (we're already on it).
          if (!isResend) Get.to(() => const OtpScreen());
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      // Any synchronous/async failure starting verification (network, etc.).
      busy.value = false;
      Get.snackbar('Could not send code', 'Please try again in a moment.');
    }
  }

  String _authMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'That phone number looks invalid.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'quota-exceeded':
        return 'SMS limit reached. Please try again later.';
      case 'network-request-failed':
        return 'No internet connection.';
      default:
        // Never surface raw Firebase SDK copy to a member.
        return 'Something went wrong verifying your number. Please try again.';
    }
  }

  /// Returns true when the code signed the member in (so the OTP screen can
  /// clear the pin boxes for a fresh retry when it didn't).
  Future<bool> verifyOtp(String smsCode) async {
    // Guard against double-submit: the OTP screen auto-fires this on the 6th
    // digit AND on the button tap, and the sign-in + routing round-trip takes a
    // few seconds.
    if (isLoading.value) return false;
    final vid = _verificationId;
    if (vid == null) {
      Get.snackbar('Error', 'Request a code first.');
      return false;
    }
    try {
      isLoading.value = true;
      final cred = PhoneAuthProvider.credential(
        verificationId: vid,
        smsCode: smsCode,
      );
      await _auth.signInWithCredential(cred);
      await routeAfterAuth();
      return true;
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'invalid-verification-code' => 'Incorrect code. Please re-check it.',
        'session-expired' => 'Code expired. Tap "Resend code" for a new one.',
        _ => 'Check the OTP and try again.',
      };
      Get.snackbar('Invalid code', msg);
    } catch (_) {
      Get.snackbar('Something went wrong', 'Please try again.');
    } finally {
      isLoading.value = false;
    }
    return false;
  }

  /// Routes a signed-in member: org discovery until they hold an active
  /// membership, then the dashboard. (Onboarding is org-specific and runs
  /// post-purchase inside the join flow, not here.)
  Future<void> routeAfterAuth() async {
    final user = _auth.currentUser;
    if (user == null) return;
    bool active;
    try {
      active = await CoachService().hasActiveMembership(user.uid);
    } catch (_) {
      // Network hiccup right after a successful sign-in: the user IS
      // authenticated, so don't strand them on the OTP screen or bounce them to
      // discovery. Send them into the dashboard, whose own controllers surface
      // the not-linked / no-membership states with a retry and re-check.
      active = true;
    }
    Get.offAll(
        () => active ? const ClientDashboard() : const JoinCoachScreen());
  }

  Future<void> signOut() async {
    if (_tearingDown) return;
    // Clear the sentinel BEFORE the SDK emits null so the listener doesn't
    // treat a manual sign-out as a revoked session (double teardown + wrong
    // "session ended" message).
    _hadUser = false;
    // End any live call + release the call lock BEFORE auth dies so the next
    // member on this device never inherits a call or a stuck busy state.
    if (Get.isRegistered<CallService>()) {
      await Get.find<CallService>().endForSignOut();
    }
    // Release this device's push token BEFORE auth dies (the callable needs
    // the session) so the next member here never gets this member's messages.
    if (Get.isRegistered<MemberPushService>()) {
      await Get.find<MemberPushService>().removeTokenOnSignOut();
    }
    _teardownToLogin();
    try {
      await _auth.signOut();
    } catch (_) {
      // Even if the network call fails, the local session UI is already gone;
      // the auth-state listener stays armed for when the SDK settles.
    }
  }

  /// Leaves the member session: navigate to login FIRST, then delete the
  /// member-scoped controllers on the next frame. Navigating first means no
  /// still-mounted dashboard `Obx` can run its `Get.put` fallback and resurrect
  /// a controller mid-teardown — the exact race that let a second member on the
  /// same device inherit the previous member's state.
  void _teardownToLogin() {
    _tearingDown = true;
    Get.offAll(() => const PhoneLoginScreen());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deleteIfRegistered<MembershipController>();
      _deleteIfRegistered<ClientRazorpayController>();
      _deleteIfRegistered<TrainingController>();
      _deleteIfRegistered<DietLogController>();
      _deleteIfRegistered<CheckInController>();
      _deleteIfRegistered<LifestyleController>();
      _deleteIfRegistered<MemberController>();
      _deleteIfRegistered<HomeController>();
      _deleteIfRegistered<OnboardingController>();
      _deleteIfRegistered<ProgressController>();
      _tearingDown = false;
    });
  }

  void _deleteIfRegistered<T>() {
    if (Get.isRegistered<T>()) Get.delete<T>(force: true);
  }
}
