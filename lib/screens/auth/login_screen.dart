import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../core/constants/quotes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/gradient_title.dart';
import '../../core/widgets/primary_button.dart';

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
    final num = _phone.text.trim();
    if (num.length < 6) {
      Get.snackbar('Enter your number', 'A valid phone number is required.');
      return;
    }
    _auth.sendOtp('+${_country.phoneCode}$num');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const GradientTitle('ALPHASERENA', size: 40,
                  textAlign: TextAlign.start),
              const SizedBox(height: 6),
              Text(
                'THE ARENA FOR ALPHAS',
                style: AppText.label(size: 12)
                    .copyWith(color: p.textSecondary, letterSpacing: 4),
              ),
              const SizedBox(height: 28),
              Text(
                Quotes.daily(),
                style: AppText.body(size: 15).copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 40),
              Text('Enter your phone number to continue',
                  style: AppText.label(size: 14)
                      .copyWith(color: p.textSecondary)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: p.inputFill,
                  borderRadius: AppRadii.smR,
                  border: Border.all(color: p.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => showCountryPicker(
                        context: context,
                        showPhoneCode: true,
                        onSelect: (c) => setState(() => _country = c),
                      ),
                      child: Row(
                        children: [
                          Text(_country.flagEmoji,
                              style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 6),
                          Text('+${_country.phoneCode}',
                              style: AppText.label(size: 15)
                                  .copyWith(color: p.textPrimary)),
                          Icon(Icons.keyboard_arrow_down_rounded,
                              color: p.textMuted, size: 22),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        style: TextStyle(color: p.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Phone number',
                          hintStyle: TextStyle(color: p.textMuted),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                        ),
                        onSubmitted: (_) => _continue(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Obx(() => PrimaryButton(
                    label: 'Enter the Arena',
                    icon: Icons.bolt,
                    isLoading: _auth.isLoading.value,
                    onPressed: _continue,
                  )),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'By continuing you agree to our Terms & Conditions',
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 12).copyWith(color: p.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
