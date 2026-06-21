import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pinput/pinput.dart';

import '../../controllers/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/gradient_title.dart';
import '../../core/widgets/primary_button.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final TextEditingController _otp = TextEditingController();
  final AuthController _auth = Get.find<AuthController>();

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  void _verify() {
    if (_otp.text.trim().length != 6) {
      Get.snackbar('Enter the code', 'The OTP is 6 digits.');
      return;
    }
    _auth.verifyOtp(_otp.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pinTheme = PinTheme(
      width: 52,
      height: 58,
      textStyle: AppText.title(size: 22).copyWith(color: p.textPrimary),
      decoration: BoxDecoration(
        color: p.inputFill,
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.border),
      ),
    );

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const GradientTitle('VERIFY', size: 36, textAlign: TextAlign.start),
              const SizedBox(height: 8),
              Text(
                'Enter the 6-digit code sent to ${_auth.phone}',
                style: AppText.body(size: 14).copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 36),
              Center(
                child: Pinput(
                  controller: _otp,
                  length: 6,
                  defaultPinTheme: pinTheme,
                  focusedPinTheme: pinTheme.copyWith(
                    decoration: pinTheme.decoration!.copyWith(
                      border: Border.all(color: p.accent, width: 1.5),
                    ),
                  ),
                  submittedPinTheme: pinTheme.copyWith(
                    decoration: pinTheme.decoration!.copyWith(
                      color: p.accent.withValues(alpha: 0.12),
                      border: Border.all(color: p.accent),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  onCompleted: (_) => _verify(),
                ),
              ),
              const SizedBox(height: 32),
              Obx(() => PrimaryButton(
                    label: 'Verify & Continue',
                    isLoading: _auth.isLoading.value,
                    onPressed: _verify,
                  )),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => _auth.sendOtp(_auth.phone),
                  child: Text('Resend code',
                      style: AppText.label(size: 13).copyWith(color: p.accent)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
