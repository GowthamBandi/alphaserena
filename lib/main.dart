import 'package:alphaserena/controllers/auth_controller.dart';
import 'package:alphaserena/controllers/connectivity_controller.dart';
import 'package:alphaserena/controllers/theme_controller.dart';
import 'package:alphaserena/core/route_observer.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/auth/splash_screen.dart';
import 'package:alphaserena/core/services/incoming_call_handler.dart';
import 'package:alphaserena/screens/common/no_internet_screen.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Killed/backgrounded-app FCM entry point (own isolate — top-level + its own
/// Firebase init). Its ONLY job is ringing (Communication M3.3, mirrors the
/// certified trainersHQ handler).
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Already initialized in this isolate.
  }
  if (message.data['kind'] == 'incoming_call') {
    await showIncomingCallKit(message.data);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // App Check (monitor-only): activate so genuine installs mint attestation
  // tokens, but enforcement stays OFF (Firebase console + backend
  // enforceAppCheck are NOT set) so nothing is blocked yet. Debug builds use
  // the debug provider (register the printed debug token in the console);
  // release uses Play Integrity (Android) / App Attest (iOS). Guarded: a failed
  // attestation must never block startup while enforcement is off.
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kReleaseMode
          ? const AndroidPlayIntegrityProvider()
          : const AndroidDebugProvider(),
      providerApple: kReleaseMode
          ? const AppleAppAttestProvider()
          : const AppleDebugProvider(),
    );
  } catch (_) {
    // Non-fatal — App Check enforcement is off; tokens simply won't mint.
  }

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  }

  // Permanent singletons.
  Get.put<ThemeController>(ThemeController(), permanent: true);
  Get.put<AuthController>(AuthController(), permanent: true);
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
            Obx(
              () => connectivity.isOnline.value
                  ? const SizedBox.shrink()
                  : const SizedBox.expand(child: NoInternetScreen()),
            ),
          ],
        ),
      ),
    );
  }
}
