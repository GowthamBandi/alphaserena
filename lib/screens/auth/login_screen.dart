import 'package:alphaserena/controllers/theme_controller.dart';
import 'package:alphaserena/screens/auth/otp_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:country_picker/country_picker.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final TextEditingController phoneController = TextEditingController();

  /// ✅ USE THEME CONTROLLER ONLY
  final ThemeController theme = Get.find<ThemeController>();

  // Default Country (India 🇮🇳)
  Country selectedCountry = Country(
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
  Widget build(BuildContext context) {
    return Obx(() {
      final isDark = theme.isDarkMode.value;

      final bgColor = isDark ? Colors.black : Colors.white;
      final textColor = isDark ? Colors.white : Colors.black;
      final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
      final accentColor = Colors.redAccent.shade700;

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
                  "Welcome to Fitopia",
                  style: GoogleFonts.poppins(
                    color: textColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Enter your phone number to continue",
                  style: GoogleFonts.poppins(
                    color: secondaryTextColor,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 40),

                // Country Picker + Phone Input
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white12 : Colors.grey[200],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          showCountryPicker(
                            context: context,
                            showPhoneCode: true,
                            countryListTheme: CountryListThemeData(
                              backgroundColor: isDark
                                  ? const Color(0xFF1A1A1D)
                                  : Colors.white,
                              textStyle: TextStyle(
                                color: textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              bottomSheetHeight: 500,
                              inputDecoration: InputDecoration(
                                labelText: 'Search Country',
                                labelStyle: TextStyle(
                                  color: secondaryTextColor,
                                ),
                                prefixIcon: const Icon(Icons.search),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Colors.grey.withOpacity(0.3),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: accentColor,
                                    width: 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            onSelect: (Country country) {
                              setState(() => selectedCountry = country);
                            },
                          );
                        },
                        child: Row(
                          children: [
                            Text(
                              "${selectedCountry.flagEmoji} ",
                              style: const TextStyle(fontSize: 24),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "+${selectedCountry.phoneCode}",
                              style: GoogleFonts.poppins(
                                color: textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Colors.grey,
                              size: 22,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                            hintText: 'Enter phone number',
                            hintStyle: TextStyle(color: secondaryTextColor),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Continue Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (phoneController.text.trim().isEmpty) {
                        Get.snackbar(
                          "Error",
                          "Please enter your phone number",
                          backgroundColor: Colors.redAccent.shade700,
                          colorText: Colors.white,
                          snackPosition: SnackPosition.BOTTOM,
                          margin: const EdgeInsets.all(16),
                          borderRadius: 12,
                        );
                        return;
                      }
                      Get.to(
                        () => OTPVerificationScreen(
                          phone:
                              "+${selectedCountry.phoneCode}${phoneController.text.trim()}",
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Continue',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                Center(
                  child: Text(
                    'By continuing you agree to our Terms & Conditions',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: secondaryTextColor,
                      fontSize: 12,
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
