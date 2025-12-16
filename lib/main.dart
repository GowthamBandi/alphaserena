import 'package:alphaserena/controllers/dashboard_controller.dart';
import 'package:alphaserena/controllers/theme_controller.dart';
import 'package:alphaserena/screens/auth/login_screen.dart';
import 'package:alphaserena/screens/dashboard/dashboard_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  /// ✅ REGISTER CONTROLLERS BEFORE UI
  Get.put<ThemeController>(ThemeController(), permanent: true);
  Get.put<DashboardController>(DashboardController(), permanent: true);
  Get.put<ClientDashboard>(ClientDashboard(), permanent: true);

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

        /// 🌗 THEMING
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: themeCtrl.isDarkMode.value
            ? ThemeMode.dark
            : ThemeMode.light,

        home: const PhoneLoginScreen(),
      ),
    );
  }
}
