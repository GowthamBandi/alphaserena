import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pinput/pinput.dart';

import '../../controllers/auth_controller.dart';
import '../../core/widgets/gradient_button.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final TextEditingController _otp = TextEditingController();
  final AuthController _auth = Get.find<AuthController>();

  Timer? _timer;
  int _seconds = 30;

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _muted = Color(0xFF9A9A9A);
  static const Color _red = Color(0xFFE10600);

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _seconds = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_seconds <= 1) {
        t.cancel();
        if (mounted) setState(() => _seconds = 0);
      } else {
        if (mounted) setState(() => _seconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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

  void _resend() {
    if (_seconds > 0) return;
    _auth.sendOtp(_auth.phone);
    _startCountdown();
  }

  String get _prettyPhone {
    final p = _auth.phone;
    final digits = p.replaceAll(RegExp(r'\D'), '');
    if (p.startsWith('+91') && digits.length == 12) {
      final n = digits.substring(2);
      return '+91 ${n.substring(0, 5)} ${n.substring(5)}';
    }
    return p;
  }

  @override
  Widget build(BuildContext context) {
    final pinTheme = PinTheme(
      width: 46,
      height: 54,
      textStyle: GoogleFonts.poppins(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
    );

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Get.back(),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(height: 18),
              Center(child: _shieldGlow()),
              const SizedBox(height: 22),
              Center(
                child: Text(
                  'Verify OTP',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Enter the 6-digit code sent to',
                  style: GoogleFonts.poppins(color: _muted, fontSize: 14),
                ),
              ),
              const SizedBox(height: 2),
              Center(
                child: Text(
                  _prettyPhone,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: Pinput(
                  controller: _otp,
                  length: 6,
                  defaultPinTheme: pinTheme,
                  focusedPinTheme: pinTheme.copyWith(
                    decoration: pinTheme.decoration!.copyWith(
                      border: Border.all(color: _red, width: 1.6),
                    ),
                  ),
                  submittedPinTheme: pinTheme.copyWith(
                    decoration: pinTheme.decoration!.copyWith(
                      border: Border.all(color: const Color(0xFF3A3A3A)),
                    ),
                  ),
                  cursor: Container(width: 2, height: 24, color: _red),
                  keyboardType: TextInputType.number,
                  onCompleted: (_) => _verify(),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  "Didn't receive the code?",
                  style: GoogleFonts.poppins(color: _muted, fontSize: 13.5),
                ),
              ),
              const SizedBox(height: 4),
              Center(child: _resendLine()),
              const SizedBox(height: 24),
              GradientButton(
                label: 'Verify & Continue',
                height: 56,
                onPressed: _verify,
              ),
              const SizedBox(height: 28),
              _footerNote(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resendLine() {
    if (_seconds > 0) {
      final m = (_seconds ~/ 60).toString().padLeft(2, '0');
      final s = (_seconds % 60).toString().padLeft(2, '0');
      return RichText(
        text: TextSpan(
          style: GoogleFonts.poppins(fontSize: 13.5),
          children: [
            TextSpan(
                text: 'Resend OTP in ', style: const TextStyle(color: _muted)),
            TextSpan(
              text: '$m:$s',
              style: const TextStyle(
                  color: _red, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: _resend,
      child: Text(
        'Resend OTP',
        style: GoogleFonts.poppins(
          color: _red,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
      ),
    );
  }

  Widget _shieldGlow() {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            _red.withValues(alpha: 0.22),
            _red.withValues(alpha: 0.05),
            Colors.transparent,
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      child: Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF161010),
            border: Border.all(color: _red.withValues(alpha: 0.4)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: const [
              Icon(Icons.shield_outlined, color: _red, size: 34),
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.lock, color: _red, size: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footerNote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF131313),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_outlined, color: _red, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'We never share your information with anyone.',
              style: GoogleFonts.poppins(color: _muted, fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
