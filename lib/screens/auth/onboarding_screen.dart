import 'dart:ui';
import 'package:alphaserena/controllers/dashboard_controller.dart';
import 'package:alphaserena/controllers/onboarding_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_swipe/liquid_swipe.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final onboardingCtrl = Get.put(OnboardingController());
  final dashboardCtrl = Get.find<DashboardController>();
  final LiquidController liquidController = LiquidController();

  final questions = [
    {
      "title": "What’s your diet type?",
      "options": ["Vegetarian", "Vegan", "Keto", "Balanced", "Other"],
    },
    {
      "title": "Have you followed any diet before?",
      "options": ["Yes", "No", "Sometimes", "Other"],
    },
    {
      "title": "Do you have any medical conditions?",
      "options": ["Diabetes", "PCOS", "Thyroid", "None", "Other"],
    },
    {
      "title": "What’s your primary fitness goal?",
      "options": ["Weight Loss", "Muscle Gain", "Endurance", "Other"],
    },
    {
      "title": "How active are you daily?",
      "options": ["Sedentary", "Moderate", "Active", "Very Active", "Other"],
    },
  ];

  @override
  Widget build(BuildContext context) {
    final controllers = [
      onboardingCtrl.dietTypeController,
      onboardingCtrl.previousDietController,
      onboardingCtrl.medicalConditionController,
      onboardingCtrl.fitnessGoalController,
      onboardingCtrl.activityLevelController,
    ];

    return Obx(() {
      final currentIndex = dashboardCtrl.selectedIndex.value;

      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            LiquidSwipe(
              liquidController: liquidController,
              pages: List.generate(questions.length, (index) {
                return _buildGlassPage(
                  title: questions[index]["title"] as String,
                  options: (questions[index]["options"] as List).cast<String>(),
                  controller: controllers[index],
                  pageIndex: index,
                  onNext: () {
                    if (index < questions.length - 1) {
                      liquidController.animateToPage(
                        page: index + 1,
                        duration: 700,
                      );
                      dashboardCtrl.selectedIndex.value = index + 1;
                    } else {
                      dashboardCtrl.selectedIndex.value = 0;
                      Get.offAllNamed('/dashboard');
                    }
                  },
                  isLast: index == questions.length - 1,
                );
              }),
              enableLoop: false,
              enableSideReveal: false, // hide next page peek
              waveType: WaveType.liquidReveal,
              positionSlideIcon: 0.85,
              slideIconWidget: const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white70,
              ),
              onPageChangeCallback: (i) {
                dashboardCtrl.selectedIndex.value = i;
              },
            ),

            // Back button
            if (currentIndex > 0)
              Positioned(
                top: 40,
                left: 16,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                  onPressed: () {
                    if (currentIndex > 0) {
                      liquidController.animateToPage(
                        page: currentIndex - 1,
                        duration: 700,
                      );
                      dashboardCtrl.selectedIndex.value = currentIndex - 1;
                    }
                  },
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _buildGlassPage({
    required String title,
    required List<String> options,
    required TextEditingController controller,
    required VoidCallback onNext,
    required int pageIndex,
    bool isLast = false,
  }) {
    RxString selected = "".obs;
    RxBool showOtherField = false.obs;

    return Obx(() {
      bool isActive = dashboardCtrl.selectedIndex.value == pageIndex;

      return Stack(
        fit: StackFit.expand,
        children: [
          // Always black background
          Container(color: Colors.black),

          // Show glass card only when active
          if (isActive)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 80,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Obx(
                          () => Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: options.map((option) {
                              return ChoiceChip(
                                label: Text(option),
                                selected: selected.value == option,
                                onSelected: (value) {
                                  selected.value = option;
                                  showOtherField.value = option == "Other";
                                  controller.text = option == "Other"
                                      ? ""
                                      : option;
                                },
                                backgroundColor: Colors.white.withOpacity(0.2),
                                selectedColor: Colors.redAccent.withOpacity(
                                  0.8,
                                ),
                                labelStyle: TextStyle(
                                  color: selected.value == option
                                      ? Colors.white
                                      : Colors.white70,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        Obx(
                          () => showOtherField.value
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: TextField(
                                    controller: controller,
                                    style: const TextStyle(color: Colors.white),
                                    textAlign: TextAlign.center,
                                    decoration: InputDecoration(
                                      hintText: "Enter your answer...",
                                      hintStyle: const TextStyle(
                                        color: Colors.white54,
                                      ),
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.1),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: onNext,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 60,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            isLast ? "Finish" : "Next",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}
