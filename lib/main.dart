import 'package:alphaserena/controllers/auth_controller.dart';
import 'package:alphaserena/controllers/connectivity_controller.dart';
import 'package:alphaserena/controllers/dashboard_controller.dart';
import 'package:alphaserena/controllers/theme_controller.dart';
import 'package:alphaserena/core/route_observer.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/auth/splash_screen.dart';
import 'package:alphaserena/screens/common/no_internet_screen.dart';
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
  Get.put<ConnectivityController>(ConnectivityController(), permanent: true);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeCtrl = Get.find<ThemeController>();
    final connectivity = Get.find<ConnectivityController>();

    return Obx(
      () => GetMaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AlphaSerena',
        navigatorObservers: [appRouteObserver],

        // Shared design system (brand red + Teko/Poppins/Inter). Dark-first.
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeCtrl.isDarkMode.value
            ? ThemeMode.dark
            : ThemeMode.light,

        home: const SplashScreen(),

        // App-wide offline takeover: sits ABOVE every route/dialog/snackbar and
        // auto-dismisses the moment connectivity returns.
        builder: (context, child) => Stack(
          children: [
            child ?? const SizedBox.shrink(),
            Obx(() => connectivity.isOnline.value
                ? const SizedBox.shrink()
                : const SizedBox.expand(child: NoInternetScreen())),
          ],
        ),
      ),
    );
  }
}
