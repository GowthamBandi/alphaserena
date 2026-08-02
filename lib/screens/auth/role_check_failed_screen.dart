import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/auth_controller.dart';
import '../../core/widgets/gradient_button.dart';

/// Shown when the app could NOT establish what kind of account signed in.
///
/// The role gate fails closed: "we could not check" is never treated as "you
/// are a member", because degrading to member would admit a coach whenever the
/// network is slow — exactly the hole the gate exists to close. So an
/// unverifiable session stops here instead of proceeding.
///
/// This is a retryable state, not a rejection, and the copy says so: nothing is
/// wrong with the account, the check simply did not complete.
class RoleCheckFailedScreen extends StatelessWidget {
  const RoleCheckFailedScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Icon(
                      Icons.wifi_off_rounded,
                      size: 32,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    "We couldn't verify your account",
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
                    'Check your connection and sign in again. Nothing is wrong '
                    'with your account — we just need to finish the check '
                    'before opening the app.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 14.5,
                      height: 1.55,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                  const SizedBox(height: 30),
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
