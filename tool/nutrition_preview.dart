// DEV TOOL — not shipped. Renders the Nutrition surface with the canonical
// served-contract fixture for the certification's visual record.
// Run: flutter run -t tool/nutrition_preview.dart -d emulator-5554
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:alphaserena/controllers/training_controller.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/client_diet_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final t = Get.put(TrainingController());
  Map<String, dynamic> food(String name, String meal, double kcal, double p,
          double c, double f, String qty) =>
      {
        'name': name,
        'foodId': name.toLowerCase().replaceAll(' ', '-'),
        'quantity': qty,
        'calories': kcal,
        'protein': p,
        'carbs': c,
        'fat': f,
        'fiber': 3.0,
        'sugar': 2.0,
        'saturatedFat': 1.5,
        'meal': meal,
        'grams': 100,
        'portionLabel': null,
        'portionQty': null,
      };
  t.diet.value = {
    'name': 'Cutting Plan A',
    'items': [
      food('Oats with Whey', 'Breakfast', 420, 32, 52, 9, '80 g + 1 scoop'),
      food('Banana', 'Breakfast', 105, 1, 27, 0, '1 medium'),
      food('Chicken & Rice Bowl', 'Lunch', 650, 45, 70, 14, '350 g'),
      food('Paneer Salad', 'Dinner', 380, 24, 12, 22, '250 g'),
      food('Greek Yogurt', 'snacks', 150, 15, 8, 4, '170 g'),
    ],
    'targetCalories': 1800,
    'targetProtein': 150,
    'targetCarbs': 160,
    'targetFat': 60,
    'targetFiber': 30,
  };
  t.isLoading.value = false;
  runApp(GetMaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    home: ClientDietScreen(),
  ));
}
