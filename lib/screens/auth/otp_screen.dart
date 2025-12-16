import 'package:alphaserena/controllers/theme_controller.dart';
import 'package:alphaserena/screens/dashboard/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pinput/pinput.dart';

class OTPVerificationScreen extends StatefulWidget {
  final String phone;
  const OTPVerificationScreen({super.key, required this.phone});

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  final TextEditingController otpController = TextEditingController();

  /// ✅ USE THEME CONTROLLER ONLY
  final ThemeController theme = Get.find<ThemeController>();

  // Reactive resend timer
  late RxInt remainingSeconds = 30.obs;
  late RxBool canResend = false.obs;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    remainingSeconds.value = 30;
    canResend.value = false;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (remainingSeconds.value == 0) {
        canResend.value = true;
        return false;
      }
      remainingSeconds.value--;
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isDark = theme.isDarkMode.value;

      final bgColor = isDark ? Colors.black : Colors.white;
      final textColor = isDark ? Colors.white : Colors.black;
      final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
      final accentColor = Colors.redAccent.shade700;

      final defaultPinTheme = PinTheme(
        width: 56,
        height: 60,
        textStyle: GoogleFonts.poppins(
          color: textColor,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        decoration: BoxDecoration(
          color: isDark ? Colors.white12 : Colors.grey[200],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.transparent),
        ),
      );

      final focusedPinTheme = defaultPinTheme.copyWith(
        decoration: BoxDecoration(
          color: isDark ? Colors.white24 : Colors.redAccent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor, width: 1.5),
        ),
      );

      final submittedPinTheme = defaultPinTheme.copyWith(
        decoration: BoxDecoration(
          color: accentColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor),
        ),
      );

      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          iconTheme: IconThemeData(color: textColor),
          actions: [
            IconButton(
              onPressed: theme.toggleTheme, // ✅ FIXED
              icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Verify OTP",
                  style: GoogleFonts.poppins(
                    color: textColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "We have sent a 6-digit code to ${widget.phone}",
                  style: GoogleFonts.poppins(
                    color: secondaryTextColor,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 40),

                Center(
                  child: Pinput(
                    controller: otpController,
                    length: 6,
                    defaultPinTheme: defaultPinTheme,
                    focusedPinTheme: focusedPinTheme,
                    submittedPinTheme: submittedPinTheme,
                    keyboardType: TextInputType.number,
                    showCursor: true,
                    onCompleted: (pin) {
                      debugPrint("Entered OTP: $pin");
                    },
                  ),
                ),
                const SizedBox(height: 30),

                // Verify Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (otpController.text.trim().length != 6) {
                        Get.snackbar(
                          "Error",
                          "Please enter a valid 6-digit OTP",
                          backgroundColor: Colors.redAccent.withOpacity(0.8),
                          colorText: Colors.white,
                          snackPosition: SnackPosition.BOTTOM,
                          margin: const EdgeInsets.all(16),
                          borderRadius: 12,
                        );
                        return;
                      }
                      Get.offAll(() => ClientDashboard());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Verify OTP',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Resend Section
                Center(
                  child: Obx(
                    () => TextButton(
                      onPressed: canResend.value
                          ? () {
                              _startTimer();
                              Get.snackbar(
                                "OTP Sent",
                                "A new OTP has been sent to your number.",
                                backgroundColor: Colors.greenAccent.withOpacity(
                                  0.2,
                                ),
                                colorText: Colors.white,
                                snackPosition: SnackPosition.BOTTOM,
                                margin: const EdgeInsets.all(16),
                                borderRadius: 12,
                              );
                            }
                          : null,
                      child: Text(
                        canResend.value
                            ? "Resend OTP"
                            : "Resend in ${remainingSeconds.value}s",
                        style: GoogleFonts.poppins(
                          color: canResend.value
                              ? accentColor
                              : secondaryTextColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
