import 'package:alphaserena/controllers/auth_controller.dart';
import 'package:alphaserena/controllers/dashboard_controller.dart';
import 'package:alphaserena/controllers/theme_controller.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/auth/splash_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Permanent singletons.
  Get.put<ThemeController>(ThemeController(), permanent: true);
  Get.put<AuthController>(AuthController(), permanent: true);
  Get.put<DashboardController>(DashboardController(), permanent: true);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeCtrl = Get.find<ThemeController>();

    return Obx(
      () => GetMaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AlphaSerena',

        // Shared design system (brand red + Teko/Poppins/Inter). Dark-first.
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode:
            themeCtrl.isDarkMode.value ? ThemeMode.dark : ThemeMode.light,

        home: const SplashScreen(),
      ),
    );
  }
}
