import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/constants/quotes.dart';
import '../../core/services/client_profile_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/gradient_title.dart';
import '../dashboard/dashboard_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

/// Brand splash that decides where to send the member on cold start.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final String _quote = Quotes.daily();

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    // Branding beat AND wait for Firebase to restore any persisted session, so
    // a logged-in user is never bounced to login on a slow cold start.
    final results = await Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 1400)),
      FirebaseAuth.instance.authStateChanges().first,
    ]);
    if (!mounted) return;

    final user = results[1] as User?;
    if (user == null) {
      Get.offAll(() => const PhoneLoginScreen());
      return;
    }

    bool done;
    try {
      done = await ClientProfileService().isOnboardingComplete(user.uid);
    } catch (_) {
      // Transient/offline read — fall back to onboarding, which is self-healing
      // (it re-checks and re-saves the profile). Never strand the user here.
      done = false;
    }
    if (!mounted) return;
    Get.offAll(
      () => done ? const ClientDashboard() : const OnboardingScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [p.background, p.backgroundGradientEnd],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                const GradientTitle('ALPHASERENA', size: 44),
                const SizedBox(height: 8),
                Text(
                  'THE ARENA FOR ALPHAS',
                  style: AppText.label(size: 13)
                      .copyWith(color: p.textSecondary, letterSpacing: 4),
                ),
                const Spacer(),
                Text(
                  '"$_quote"',
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 14).copyWith(color: p.textMuted),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: p.accent,
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
