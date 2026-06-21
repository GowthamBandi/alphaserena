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
    await Future.delayed(const Duration(milliseconds: 1400));
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Get.offAll(() => const PhoneLoginScreen());
      return;
    }
    final done = await ClientProfileService().isOnboardingComplete(user.uid);
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
