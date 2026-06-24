import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';

import '../../core/services/client_profile_service.dart';
import '../../core/services/coach_service.dart';
import '../../core/widgets/brand.dart';
import '../dashboard/dashboard_screen.dart';
import '../join/join_coach_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

/// Brand splash that decides where to send the member on cold start.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    // Branding beat AND wait for Firebase to restore any persisted session, so
    // a logged-in user is never bounced to login on a slow cold start.
    final results = await Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 1600)),
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
      done = false;
    }
    if (!done) {
      if (!mounted) return;
      Get.offAll(() => const OnboardingScreen());
      return;
    }
    bool active = false;
    try {
      active = await CoachService().hasActiveMembership(user.uid);
    } catch (_) {
      active = false;
    }
    if (!mounted) return;
    Get.offAll(
      () => active ? const ClientDashboard() : const JoinCoachScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Hero photograph (muscular back + red arena glow).
          Image.asset(
            'assets/images/splash_hero.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          // Fade the lower third to black so the wordmark sits cleanly.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black],
                stops: [0.45, 0.92],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 62),
                const AlphaAMark(size: 56),
                const SizedBox(height: 14),
                const AlphasArenaWordmark(fontSize: 26),
                const SizedBox(height: 10),
                Text(
                  'TRAIN. TRANSFORM. TRIUMPH.',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const Spacer(flex: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _dash(const Color(0xFFE10600)),
                    const SizedBox(width: 8),
                    _dash(Colors.white.withValues(alpha: 0.22)),
                    const SizedBox(width: 8),
                    _dash(Colors.white.withValues(alpha: 0.22)),
                  ],
                ),
                const Spacer(flex: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dash(Color color) => Container(
        width: 34,
        height: 5,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      );
}
