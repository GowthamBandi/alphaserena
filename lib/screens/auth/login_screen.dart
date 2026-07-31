import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/auth_controller.dart';
import '../../core/utils/phone_validation.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/google_button.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen>
    with SingleTickerProviderStateMixin {
  // Feature flag only controls visibility. Phone auth code and its route stay intact.
  static const bool _showPhoneAuthentication = false;
  final TextEditingController _phone = TextEditingController();
  final FocusNode _phoneFocus = FocusNode();
  final AuthController _auth = Get.find<AuthController>();
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  Country _country = Country(
    phoneCode: '91',
    countryCode: 'IN',
    e164Sc: 0,
    geographic: true,
    level: 1,
    name: 'India',
    example: '9876543210',
    displayName: 'India',
    displayNameNoCountryCode: 'India',
    e164Key: '',
  );

  @override
  void dispose() {
    _entrance.dispose();
    _phone.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  void _continue() {
    if (_auth.isLoading.value || _auth.isGoogleLoading.value) return;
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      Get.snackbar('Enter your number', 'A phone number is required.');
      return;
    }
    final error = PhoneValidation.validate(
      digits,
      phoneCode: _country.phoneCode,
    );
    if (error != null) {
      Get.snackbar('Invalid number', error);
      return;
    }
    FocusScope.of(context).unfocus();
    _auth.sendOtp('+${_country.phoneCode}$digits');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF080808) : const Color(0xFFF8F8F8);
    final primary = isDark ? Colors.white : Colors.black;
    final muted = isDark ? Colors.white60 : Colors.black54;
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 700;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, compact ? 22 : 38, 24, 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - (compact ? 42 : 58),
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _brand(compact, primary, muted),
                        SizedBox(height: compact ? 32 : 52),
                        Text(
                          'Build the strongest\nversion of you.',
                          style: GoogleFonts.poppins(
                            color: primary,
                            fontSize: compact ? 30 : 36,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.1,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Train with intention, fuel your progress, and make every day count.',
                          style: GoogleFonts.poppins(
                            color: muted,
                            fontSize: 14,
                            height: 1.55,
                          ),
                        ),
                        SizedBox(height: compact ? 24 : 32),
                        _highlights(),
                        SizedBox(height: compact ? 28 : 40),
                        Obx(
                          () => GoogleButton(
                            height: 60,
                            isLoading: _auth.isGoogleLoading.value,
                            onPressed: () => _auth.signInWithGoogle(),
                          ),
                        ),
                        if (_showPhoneAuthentication) ...[
                          const SizedBox(height: 24),
                          _phoneAuth(primary, muted),
                        ],
                        const Spacer(),
                        SizedBox(height: compact ? 30 : 54),
                        _footer(muted),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _brand(bool compact, Color primary, Color muted) => Column(
    children: [
      Image.asset(
        'assets/icon/alpha_icon.png',
        width: compact ? 112 : 140,
        height: compact ? 112 : 140,
      ),
      const SizedBox(height: 14),
      const AlphaSerenaWordmark(fontSize: 20),
      const SizedBox(height: 8),
      Text(
        'TRAIN  •  TRANSFORM  •  TRIUMPH',
        style: GoogleFonts.poppins(
          color: muted,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 2.1,
        ),
      ),
    ],
  );

  Widget _highlights() => Wrap(
    spacing: 8,
    runSpacing: 8,
    alignment: WrapAlignment.center,
    children: const [
      _Highlight(icon: Icons.bolt_rounded, label: 'Smart training'),
      _Highlight(icon: Icons.restaurant_rounded, label: 'Better nutrition'),
      _Highlight(icon: Icons.trending_up_rounded, label: 'Real progress'),
    ],
  );

  Widget _phoneAuth(Color primary, Color muted) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Divider(color: muted.withValues(alpha: .2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('OR', style: TextStyle(color: muted, fontSize: 11)),
          ),
          Expanded(child: Divider(color: muted.withValues(alpha: .2))),
        ],
      ),
      const SizedBox(height: 18),
      Text('Continue with phone', style: TextStyle(color: Colors.white)),
      const SizedBox(height: 10),
      _inputRow(),
      const SizedBox(height: 16),
      SizedBox(
        height: 56,
        child: ElevatedButton(
          onPressed: _continue,
          child: const Text('Send OTP'),
        ),
      ),
    ],
  );

  Widget _inputRow() => TextField(
    controller: _phone,
    focusNode: _phoneFocus,
    keyboardType: TextInputType.phone,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(
      prefixIcon: GestureDetector(
        onTap: () => showCountryPicker(
          context: context,
          showPhoneCode: true,
          onSelect: (c) => setState(() => _country = c),
        ),
        child: Center(
          widthFactor: 1.0,
          child: Text('${_country.flagEmoji} +${_country.phoneCode}'),
        ),
      ),
      hintText: 'Mobile number',
    ),
  );

  Widget _footer(Color muted) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline_rounded, color: muted, size: 14),
          const SizedBox(width: 6),
          Text(
            'Your data is encrypted and secure',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        'By continuing, you agree to our Terms of Service and Privacy Policy.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white30, fontSize: 10.5, height: 1.5),
      ),
    ],
  );
}

class _Highlight extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Highlight({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .055),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: .09)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFFD50000), size: 15),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
