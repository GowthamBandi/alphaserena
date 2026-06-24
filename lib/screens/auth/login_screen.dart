import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/auth_controller.dart';
import '../../core/widgets/gradient_button.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final TextEditingController _phone = TextEditingController();
  final AuthController _auth = Get.find<AuthController>();

  Country _country = Country(
    phoneCode: "91",
    countryCode: "IN",
    e164Sc: 0,
    geographic: true,
    level: 1,
    name: "India",
    example: "9876543210",
    displayName: "India",
    displayNameNoCountryCode: "India",
    e164Key: "",
  );

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _continue() {
    if (_auth.isLoading.value) return;
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      Get.snackbar('Enter your number', 'A phone number is required.');
      return;
    }
    if (digits.length < 6 || digits.length > 15) {
      Get.snackbar('Invalid number', 'Enter a valid phone number.');
      return;
    }
    FocusScope.of(context).unfocus();
    _auth.sendOtp('+${_country.phoneCode}$digits');
  }

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _muted = Color(0xFF9A9A9A);
  static const Color _red = Color(0xFFE10600);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: _red,
                    minimumSize: const Size(0, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => Get.snackbar(
                    'Sign in required',
                    'Verify your phone number to enter the arena.',
                  ),
                  child: Text(
                    'Skip',
                    style: GoogleFonts.poppins(
                      color: _red,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Welcome to',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Alphas Arena',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your fitness journey\nstarts here.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: _muted,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 28),
              _phoneGlowIcon(),
              const SizedBox(height: 30),
              Text(
                'Enter Your Mobile Number',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'We will send you a 6-digit OTP\nto verify your number',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: _muted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 22),
              _inputRow(),
              const SizedBox(height: 18),
              Obx(() => GradientButton(
                    label: 'Send OTP',
                    showChevron: true,
                    height: 58,
                    isLoading: _auth.isLoading.value,
                    onPressed: _continue,
                  )),
              const SizedBox(height: 26),
              _orContinueWith(),
              const SizedBox(height: 22),
              _supportButton(),
              const SizedBox(height: 10),
              Text(
                'Need Help?',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.verified_user_outlined,
                      color: _muted, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    'Your data is safe with us',
                    style: GoogleFonts.poppins(color: _muted, fontSize: 12.5),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phoneGlowIcon() {
    return Container(
      width: 130,
      height: 130,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            _red.withValues(alpha: 0.28),
            _red.withValues(alpha: 0.06),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: const Icon(Icons.phone_iphone, color: _red, size: 46),
    );
  }

  Widget _inputRow() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => showCountryPicker(
              context: context,
              showPhoneCode: true,
              onSelect: (c) => setState(() => _country = c),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Text(_country.flagEmoji,
                      style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 6),
                  Text(
                    '+${_country.phoneCode}',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      color: _muted, size: 22),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 26, color: const Color(0xFF2E2E2E)),
          Expanded(
            child: TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(15),
              ],
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Enter mobile number',
                hintStyle: GoogleFonts.poppins(color: _muted, fontSize: 15),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                isCollapsed: true,
              ),
              onSubmitted: (_) => _continue(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orContinueWith() {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFF262626), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or continue with',
            style: GoogleFonts.poppins(color: _muted, fontSize: 13),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFF262626), thickness: 1)),
      ],
    );
  }

  Widget _supportButton() {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF161616),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: const Icon(Icons.headset_mic_outlined, color: _red, size: 24),
    );
  }
}
