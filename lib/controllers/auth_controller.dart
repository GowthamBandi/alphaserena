import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../core/services/client_profile_service.dart';
import '../core/services/coach_service.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/onboarding_screen.dart';
import '../screens/auth/otp_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/join/join_coach_screen.dart';
import 'client_razorpay_controller.dart';
import 'member_controller.dart';
import 'membership_controller.dart';
import 'training_controller.dart';

/// Phone-OTP auth + post-auth routing for the member app.
///
/// TESTING: enable Phone sign-in in Firebase Auth. On a real Android device you
/// need the app's SHA-1/SHA-256 in the Firebase project; for quick testing add a
/// test phone number + fixed OTP under Auth → Sign-in method → Phone.
class AuthController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ClientProfileService _profiles = ClientProfileService();

  final RxBool isLoading = false.obs;
  String? _verificationId;
  String _phone = '';

  String get phone => _phone;

  Future<void> sendOtp(String phone) async {
    _phone = phone;
    isLoading.value = true;
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential cred) async {
          // Android auto-retrieval: sign in silently if it works, but never
          // leave the button spinning if it doesn't.
          try {
            await _auth.signInWithCredential(cred);
            await routeAfterAuth();
          } catch (_) {
            isLoading.value = false;
            Get.snackbar('Almost there', 'Enter the code to continue.');
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          isLoading.value = false;
          Get.snackbar('Verification failed', _authMessage(e));
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          isLoading.value = false;
          Get.to(() => const OtpScreen());
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      // Any synchronous/async failure starting verification (network, etc.).
      isLoading.value = false;
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
        return e.message ?? 'Please try again.';
    }
  }

  Future<void> verifyOtp(String smsCode) async {
    final vid = _verificationId;
    if (vid == null) {
      Get.snackbar('Error', 'Request a code first.');
      return;
    }
    try {
      isLoading.value = true;
      final cred = PhoneAuthProvider.credential(
        verificationId: vid,
        smsCode: smsCode,
      );
      await _auth.signInWithCredential(cred);
      await routeAfterAuth();
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'invalid-verification-code' => 'Incorrect code. Please re-check it.',
        'session-expired' => 'Code expired. Tap "Resend code" for a new one.',
        _ => e.message ?? 'Check the OTP and try again.',
      };
      Get.snackbar('Invalid code', msg);
    } catch (_) {
      Get.snackbar('Something went wrong', 'Please try again.');
    } finally {
      isLoading.value = false;
    }
  }

  /// Routes a signed-in member: onboarding (first time) → join a coach (no
  /// active membership) → dashboard.
  Future<void> routeAfterAuth() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final done = await _profiles.isOnboardingComplete(user.uid);
    if (!done) {
      Get.offAll(() => const OnboardingScreen());
      return;
    }
    final active = await CoachService().hasActiveMembership(user.uid);
    Get.offAll(
        () => active ? const ClientDashboard() : const JoinCoachScreen());
  }

  Future<void> signOut() async {
    // Tear down member-scoped controllers (and their Firestore streams) FIRST so
    // the next login starts clean — otherwise a different member on the same
    // device would reuse the previous member's controller + data.
    _deleteIfRegistered<MembershipController>();
    _deleteIfRegistered<ClientRazorpayController>();
    _deleteIfRegistered<TrainingController>();
    _deleteIfRegistered<MemberController>();

    await _auth.signOut();
    Get.offAll(() => const PhoneLoginScreen());
  }

  void _deleteIfRegistered<T>() {
    if (Get.isRegistered<T>()) Get.delete<T>(force: true);
  }
}
