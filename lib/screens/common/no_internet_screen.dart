import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';

import '../../controllers/connectivity_controller.dart';
import '../../core/widgets/gradient_button.dart';

/// Branded full-screen "you're offline" takeover. Mounted globally above every
/// route by `GetMaterialApp.builder` whenever [ConnectivityController.isOnline]
/// is false; it auto-dismisses the instant connectivity returns.
///
/// The Lottie animation is loaded from
/// `assets/animations/no_internet_connection.json`; if it ever fails to load it
/// falls back to a branded Wi-Fi-off icon.
class NoInternetScreen extends StatelessWidget {
  const NoInternetScreen({super.key});

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);

  @override
  Widget build(BuildContext context) {
    final c = Get.find<ConnectivityController>();
    // PopScope blocks the hardware back button — there's nothing behind this to
    // go back to while offline.
    return PopScope(
      canPop: false,
      child: Material(
        color: _bg,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 220,
                    child: Lottie.asset(
                      'assets/animations/no_internet_connection.json',
                      repeat: true,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _fallbackIcon(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No Internet Connection',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "You're offline. Check your Wi-Fi or mobile data, "
                    'then tap refresh.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: _muted,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Obx(
                    () => GradientButton(
                      label: 'Refresh',
                      leadingIcon: Icons.refresh_rounded,
                      isLoading: c.isChecking.value,
                      onPressed: () => c.recheck(),
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

  Widget _fallbackIcon() => Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          color: _red.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.wifi_off_rounded, color: _red, size: 66),
      );
}
