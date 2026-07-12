import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/auth_controller.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/gradient_button.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final TextEditingController _phone = TextEditingController();
  final FocusNode _phoneFocus = FocusNode();
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
  void initState() {
    super.initState();
    _phoneFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _phone.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  void _continue() {
    if (_auth.isLoading.value) return;
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      Get.snackbar('Enter your number', 'A phone number is required.');
      return;
    }
    final error = _validatePhone(digits);
    if (error != null) {
      Get.snackbar('Invalid number', error);
      return;
    }
    FocusScope.of(context).unfocus();
    _auth.sendOtp('+${_country.phoneCode}$digits');
  }

  /// Per-country phone validation. India (+91) mobiles are exactly 10 digits
  /// starting 6–9; other countries get a sane generic length check.
  String? _validatePhone(String digits) {
    if (_country.phoneCode == '91') {
      if (digits.length != 10 || !RegExp(r'^[6-9]').hasMatch(digits)) {
        return 'Enter a valid 10-digit Indian mobile number.';
      }
      return null;
    }
    if (digits.length < 6 || digits.length > 15) {
      return 'Enter a valid phone number.';
    }
    return null;
  }

  // Brand-aligned dark tokens (consistent with the Discover surface).
  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _card = Color(0xFF141414);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _border = Color(0xFF242424);
  static const Color _red = Color(0xFFD50000);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 40),
                      _brand(),
                      const SizedBox(height: 48),
                      Text(
                        'Sign in',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter your mobile number and we\'ll send a '
                        '6-digit code to verify it\'s you.',
                        style: GoogleFonts.poppins(
                          color: _muted,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _label('Mobile number'),
                      const SizedBox(height: 10),
                      _inputRow(),
                      const SizedBox(height: 24),
                      Obx(() => GradientButton(
                            label: 'Send OTP',
                            showChevron: true,
                            height: 56,
                            isLoading: _auth.isLoading.value,
                            onPressed: _continue,
                          )),
                      const Spacer(),
                      const SizedBox(height: 24),
                      _footer(),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _brand() {
    return Column(
      children: [
        const AlphaAMark(size: 46),
        const SizedBox(height: 14),
        const AlphaSerenaWordmark(fontSize: 22),
        const SizedBox(height: 10),
        Text(
          'TRAIN · TRANSFORM · TRIUMPH',
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.5,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        color: Colors.white,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _inputRow() {
    final focused = _phoneFocus.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 58,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: focused ? _red : _border,
          width: focused ? 1.5 : 1,
        ),
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
          Container(width: 1, height: 28, color: _border),
          Expanded(
            child: TextField(
              controller: _phone,
              focusNode: _phoneFocus,
              keyboardType: TextInputType.phone,
              cursorColor: _red,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(15),
              ],
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
              decoration: InputDecoration(
                hintText: 'Enter mobile number',
                hintStyle: GoogleFonts.poppins(
                    color: _muted, fontSize: 15, fontWeight: FontWeight.w400),
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

  Widget _footer() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline_rounded, color: _muted, size: 14),
            const SizedBox(width: 6),
            Text(
              'Your data is encrypted and secure',
              style: GoogleFonts.poppins(color: _muted, fontSize: 12.5),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'By continuing, you agree to our Terms of Service\n'
          'and Privacy Policy.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: Colors.white.withValues(alpha: 0.3),
            fontSize: 11,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
