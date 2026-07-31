import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
import '../core/services/workout_draft_store.dart';
import 'training_controller.dart';
import 'diet_log_controller.dart';
import 'check_in_controller.dart';
import 'lifestyle_controller.dart';
import 'streak_controller.dart';
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

  /// Google sign-in owns its own busy flag so the phone CTA never spins while
  /// the Google chooser is up (and vice versa). Each flow also refuses to start
  /// while the other is mid-flight.
  final RxBool isGoogleLoading = false.obs;

  bool _googleInitialized = false;

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
    if (isGoogleLoading.value) return; // one sign-in flow at a time
    // Double-fire guard: the login field's onSubmitted and the CTA can land in
    // the same frame; a second verifyPhoneNumber would burn SMS quota.
    if (isResend ? isResending.value : isLoading.value) return;
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
            // Reset BEFORE routing: when auto-retrieval wins the race with
            // codeSent, nothing else ever clears this flag — a stale true here
            // would swallow every future "Send OTP" tap after a sign-out.
            busy.value = false;
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
    if (isLoading.value || isGoogleLoading.value) return false;
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

  /// Signs the member in with Google. Same downstream path as phone OTP:
  /// Firebase Auth issues the uid, [routeAfterAuth] decides membership vs join
  /// flow, and the join flow owns all Firestore user/profile creation — no
  /// provider-specific user records are written here.
  Future<void> signInWithGoogle() async {
    // Double-tap + cross-flow guard: sign-in takes seconds and the member can
    // still see the phone CTA underneath the chooser.
    if (isGoogleLoading.value || isLoading.value) return;
    isGoogleLoading.value = true;
    try {
      if (kIsWeb) {
        // Web: the v7 plugin can't hand Firebase an ID token via renderButton,
        // so use firebase_auth's own popup flow.
        await _auth.signInWithPopup(GoogleAuthProvider());
      } else {
        final signIn = GoogleSignIn.instance;
        if (!_googleInitialized) {
          await signIn.initialize();
          _googleInitialized = true;
        }
        final account = await signIn.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) {
          Get.snackbar(
            'Google sign-in failed',
            'Please try again in a moment.',
          );
          return;
        }
        await _auth.signInWithCredential(
          GoogleAuthProvider.credential(idToken: idToken),
        );
      }
      await routeAfterAuth();
    } on GoogleSignInException catch (e) {
      // Closing the account chooser is a decision, not an error — stay quiet.
      if (e.code != GoogleSignInExceptionCode.canceled &&
          e.code != GoogleSignInExceptionCode.interrupted) {
        Get.snackbar('Google sign-in failed', _googleMessage(e.code));
      }
    } on FirebaseAuthException catch (e) {
      Get.snackbar('Google sign-in failed', _googleFirebaseMessage(e));
    } catch (_) {
      // Web popup closed, or anything else unexpected.
      Get.snackbar('Google sign-in failed', 'Please try again in a moment.');
    } finally {
      isGoogleLoading.value = false;
    }
  }

  String _googleMessage(GoogleSignInExceptionCode code) => switch (code) {
    GoogleSignInExceptionCode.providerConfigurationError =>
      'Google sign-in isn\'t available right now. Please use your phone number.',
    _ => 'Please try again in a moment.',
  };

  String _googleFirebaseMessage(FirebaseAuthException e) => switch (e.code) {
    'account-exists-with-different-credential' =>
      'This Google email is already linked to another sign-in method.',
    'network-request-failed' => 'No internet connection.',
    'user-disabled' => 'This account has been disabled.',
    _ => 'Please try again in a moment.',
  };

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
    // Branch OUTSIDE the closure: a ternary inside one closure types it as
    // `() => StatefulWidget`, so GetX names the route after that supertype and
    // a later anonymous push with the same closure shape is silently dropped
    // as a "duplicate" (the dead Set Up Profile CTA).
    if (active) {
      Get.offAll(() => const ClientDashboard());
    } else {
      Get.offAll(() => const JoinCoachScreen());
    }
  }

  /// Arms the controller for a DELIBERATE account deletion.
  ///
  /// Deleting the Firebase user makes `authStateChanges` emit null, which the
  /// session sentinel in [onInit] is built to interpret as a revoked or disabled
  /// account — it would tear down and tell the member "Your session ended.
  /// Please log in again." That is the wrong sentence for someone who just chose
  /// to delete their account, and it races the deletion call. Clearing the
  /// sentinel first makes the listener ignore the expected null.
  ///
  /// Call [finishAccountDeletion] once the deletion has resolved, whatever the
  /// outcome.
  void beginAccountDeletion() {
    _hadUser = false;
  }

  /// Completes a deliberate deletion: ends the local session and returns to
  /// login. Safe to call when the auth account is already gone.
  Future<void> finishAccountDeletion() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // The account may already be destroyed; the local teardown below is what
      // actually returns the member to a signed-out app.
    }
    _teardownToLogin();
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
    // Drop the cached Google account so the next sign-in shows the chooser
    // instead of silently re-entering the previous member's Google session.
    if (!kIsWeb && _googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Best effort — Firebase sign-out below is what actually ends the session.
      }
    }
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
    // The in-progress WORKOUT DRAFT is device-local (SharedPreferences) and
    // keyed only by day — it survives everything else this teardown cleans.
    // Without this, a second member signing in on the same device the same
    // day RESUMES THE PREVIOUS MEMBER'S half-finished session: their
    // exercises, their weights, their reps, shown to someone else. The same
    // reasoning that releases the push token above applies here. Best-effort
    // and un-awaited, like every other step — an unflushed prefs write must
    // never block a logout.
    WorkoutDraftStore().clear();
    Get.offAll(() => const PhoneLoginScreen());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deleteIfRegistered<MembershipController>();
      _deleteIfRegistered<ClientRazorpayController>();
      _deleteIfRegistered<TrainingController>();
      _deleteIfRegistered<DietLogController>();
      _deleteIfRegistered<CheckInController>();
      _deleteIfRegistered<LifestyleController>();
      _deleteIfRegistered<StreakController>();
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
