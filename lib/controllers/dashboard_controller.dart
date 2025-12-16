import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DashboardController extends GetxController {
  // =========================
  // Daily Goals & Totals
  // =========================
  final RxDouble dailyGoal = 2000.0.obs;
  final RxDouble dailyCalories = 0.0.obs;
  final RxDouble protein = 0.0.obs;
  final RxDouble carbs = 0.0.obs;
  final RxDouble fats = 0.0.obs;
  final RxDouble fiber = 0.0.obs;

  // =========================
  // Theme Mode
  // =========================
  RxBool isDarkMode = true.obs;

  void toggleTheme() {
    isDarkMode.value = !isDarkMode.value;
    Get.changeThemeMode(isDarkMode.value ? ThemeMode.dark : ThemeMode.light);
  }

  // =========================
  // Navigation / Selected Index
  // =========================
  RxInt selectedIndex = 0.obs;

  // =========================
  // Meals & Food Tracking
  // =========================
  final List<String> standardMeals = [
    'Breakfast',
    'Morning Snack',
    'Lunch',
    'Evening Snack',
    'Dinner',
  ];

  late RxMap<String, RxDouble> mealCalories;
  late RxMap<String, RxDouble> mealProtein;
  late RxMap<String, RxDouble> mealCarbs;
  late RxMap<String, RxDouble> mealFats;
  late RxMap<String, RxDouble> mealFiber;
  late RxMap<String, RxList<Map<String, dynamic>>> meals;

  @override
  void onInit() {
    super.onInit();

    // Initialize reactive maps
    mealCalories = <String, RxDouble>{}.obs;
    mealProtein = <String, RxDouble>{}.obs;
    mealCarbs = <String, RxDouble>{}.obs;
    mealFats = <String, RxDouble>{}.obs;
    mealFiber = <String, RxDouble>{}.obs;
    meals = <String, RxList<Map<String, dynamic>>>{}.obs;

    for (var meal in standardMeals) {
      mealCalories[meal] = 0.0.obs;
      mealProtein[meal] = 0.0.obs;
      mealCarbs[meal] = 0.0.obs;
      mealFats[meal] = 0.0.obs;
      mealFiber[meal] = 0.0.obs;
      meals[meal] = <Map<String, dynamic>>[].obs;
    }
  }

  // =========================
  // Meal Management
  // =========================
  void addMeal(
    String meal, {
    required String name,
    required double calories,
    required double proteinVal,
    required double carbsVal,
    required double fatsVal,
    required double fiberVal,
  }) {
    // Add food to meal list
    meals[meal]?.add({
      'name': name,
      'calories': calories,
      'protein': proteinVal,
      'carbs': carbsVal,
      'fats': fatsVal,
      'fiber': fiberVal,
    });

    // Update meal totals
    mealCalories[meal]?.value += calories;
    mealProtein[meal]?.value += proteinVal;
    mealCarbs[meal]?.value += carbsVal;
    mealFats[meal]?.value += fatsVal;
    mealFiber[meal]?.value += fiberVal;

    // Update daily totals
    dailyCalories.value += calories;
    protein.value += proteinVal;
    carbs.value += carbsVal;
    fats.value += fatsVal;
    fiber.value += fiberVal;
  }

  void removeMealItem(String meal, Map<String, dynamic> food) {
    if (meals[meal]?.remove(food) ?? false) {
      mealCalories[meal]?.value -= food['calories'] as double;
      mealProtein[meal]?.value -= food['protein'] as double;
      mealCarbs[meal]?.value -= food['carbs'] as double;
      mealFats[meal]?.value -= food['fats'] as double;
      mealFiber[meal]?.value -= food['fiber'] as double;

      dailyCalories.value -= food['calories'] as double;
      protein.value -= food['protein'] as double;
      carbs.value -= food['carbs'] as double;
      fats.value -= food['fats'] as double;
      fiber.value -= food['fiber'] as double;
    }
  }

  void clearMeal(String meal) {
    for (var food in meals[meal] ?? []) {
      removeMealItem(meal, food);
    }
  }

  void clearAllMeals() {
    for (var meal in standardMeals) {
      clearMeal(meal);
    }
  }

  // =========================
  // Progress Calculations
  // =========================
  double get calorieProgress =>
      (dailyCalories.value / dailyGoal.value).clamp(0, 1);
  double mealProgress(String meal) =>
      (mealCalories[meal]?.value ?? 0) / dailyGoal.value;
}
