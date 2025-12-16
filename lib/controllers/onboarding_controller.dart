import 'package:flutter/material.dart';
import 'package:get/get.dart';

class OnboardingController extends GetxController {
  final dietTypeController = TextEditingController();
  final previousDietController = TextEditingController();
  final medicalConditionController = TextEditingController();
  final fitnessGoalController = TextEditingController();
  final activityLevelController = TextEditingController();

  var currentPage = 0.obs;

  void nextPage() {
    if (currentPage < 4) {
      currentPage++;
    } else {
      _finishOnboarding();
    }
  }

  void prevPage() {
    if (currentPage > 0) currentPage--;
  }

  void _finishOnboarding() {
    Get.offAllNamed('/'); // or navigate to Dashboard
  }

  @override
  void onClose() {
    dietTypeController.dispose();
    previousDietController.dispose();
    medicalConditionController.dispose();
    fitnessGoalController.dispose();
    activityLevelController.dispose();
    super.onClose();
  }
}
