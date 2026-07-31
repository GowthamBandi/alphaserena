import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../core/widgets/brand.dart';
import 'login_screen.dart';

/// Brand splash that decides where to send the member on cold start.
///
/// Deliberately minimal: the same identity block the login screen uses (mark,
/// wordmark, tagline) centered on the auth background, with one subtle
/// fade-and-rise. Splash and login share one identity, so a first launch reads
/// as a single continuous surface instead of two different apps.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();
  late final Animation<double> _fade = CurvedAnimation(
    parent: _intro,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _rise = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _decide();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Future<void> _decide() async {
    // Branding beat AND wait for Firebase to restore any persisted session, so
    // a logged-in user is never bounced to login on a slow cold start. The
    // beat is just long enough for the intro animation to land.
    final results = await Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 1200)),
      FirebaseAuth.instance.authStateChanges().first,
    ]);
    if (!mounted) return;

    final user = results[1] as User?;
    if (user == null) {
      Get.offAll(() => const PhoneLoginScreen());
      return;
    }

    // Restored session: hand off to the ONE routing policy (membership →
    // dashboard, else discovery, fail-open on transient network errors) so
    // splash and sign-in can never drift apart.
    await Get.find<AuthController>().routeAfterAuth();
  }

  @override
  Widget build(BuildContext context) {
    // Respect the system reduce-motion setting: show the identity instantly
    // instead of animating it in.
    if (MediaQuery.of(context).disableAnimations && !_intro.isCompleted) {
      _intro.value = 1.0;
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _rise,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icon/alpha_icon.png',
                    width: 140,
                    height: 140,
                  ),
                  const SizedBox(height: 18),
                  const AlphaSerenaWordmark(fontSize: 28),
                  const SizedBox(height: 12),
                  Text(
                    'TRAIN · TRANSFORM · TRIUMPH',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
