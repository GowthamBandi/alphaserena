import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/auth_controller.dart';
import '../../core/services/account_role_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/widgets/gradient_button.dart';

/// The hard stop for a PROFESSIONAL account that signed into the member app.
///
/// A trainer, organization owner or platform administrator has no member
/// surface here. Rather than route them into the join funnel — where they could
/// buy a membership and become a client of the platform they staff — the app
/// ends the session and says plainly which application is theirs.
///
/// This screen is deliberately terminal: no bottom navigation, no back route,
/// nothing to tap through to. By the time it is shown the session is ALREADY
/// signed out and no member controller has been constructed, so there is no
/// member state to leak and nothing to "continue" into.
class WrongAppScreen extends StatelessWidget {
  final AccountRole role;

  const WrongAppScreen({super.key, required this.role});

  String get _headline => switch (role) {
    AccountRole.trainer => 'This account is registered as a Trainer',
    AccountRole.admin => 'This account is registered as an Organization Owner',
    AccountRole.platformAdmin =>
      'This account is registered as a Platform Administrator',
    // Never constructed for a member; kept exhaustive rather than defaulted so
    // a new role cannot silently inherit the wrong copy.
    AccountRole.member => 'This account cannot be used here',
  };

  String get _body => switch (role) {
    AccountRole.trainer || AccountRole.admin =>
      'AlphaSerena is the member app. Please use the TrainerHQ application to '
          'coach your members.',
    AccountRole.platformAdmin =>
      'AlphaSerena is the member app. Platform administration lives in the '
          'AlphaSerena Admin console.',
    AccountRole.member => 'Please sign in with a member account.',
  };

  @override
  Widget build(BuildContext context) {
    // Back must not escape into a half-built member app. There is nothing
    // behind this route anyway (it replaces the stack), but a hardware back on
    // Android would otherwise close to a black frame.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: BrandColors.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: BrandColors.accent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.badge_outlined,
                      size: 34,
                      color: BrandColors.accent,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    _headline,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _body,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 14.5,
                      height: 1.55,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.09),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 17,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            'You have been signed out of this device for your '
                            'security.',
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              height: 1.45,
                              color: Colors.white.withValues(alpha: 0.62),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  GradientButton(
                    label: 'Back to sign in',
                    onPressed: () =>
                        Get.find<AuthController>().returnToLoginFromWrongApp(),
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
