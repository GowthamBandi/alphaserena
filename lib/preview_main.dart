// TEMPORARY design-preview entry. Run with:
//   flutter run -t lib/preview_main.dart -d <device>
// Lets every redesigned screen render without the phone-OTP gate.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controllers/auth_controller.dart';
import 'controllers/theme_controller.dart';
import 'core/theme/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/join/checkout_screen.dart';
import 'screens/join/coach_storefront_screen.dart';
import 'screens/join/discover_models.dart';
import 'screens/join/join_coach_screen.dart';
import 'screens/join/payment_success_screen.dart';
import 'screens/join/plan_details_screen.dart';
import 'screens/join/plans_screen.dart';
import 'screens/join/processing_payment_screen.dart';
import 'screens/join/razorpay_secure_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  Get.put<ThemeController>(ThemeController(), permanent: true);
  Get.put<AuthController>(AuthController(), permanent: true);
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();
  @override
  Widget build(BuildContext context) => GetMaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const _Gallery(),
      );
}

class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final org = kSampleOrgs[0];
    final plan = kPlans[0];
    final items = <(String, Widget)>[
      ('Login', const PhoneLoginScreen()),
      ('OTP', const OtpScreen()),
      ('Discovery', const JoinCoachScreen()),
      ('Org Profile', CoachStorefrontScreen(org: org)),
      ('Plans', PlansScreen(org: org)),
      ('Plan Details', PlanDetailsScreen(org: org, plan: plan)),
      ('Checkout', CheckoutScreen(org: org, plan: plan)),
      ('Razorpay', RazorpaySecureScreen(org: org, plan: plan, total: 3199)),
      ('Processing',
          ProcessingPaymentScreen(org: org, plan: plan, total: 3199)),
      ('Success', PaymentSuccessScreen(org: org, plan: plan, total: 3199)),
      ('Dashboard Home', const ClientDashboard()),
      ('Dashboard My Plans', const ClientDashboard(initialIndex: 1)),
      ('Dashboard Progress', const ClientDashboard(initialIndex: 2)),
      ('Dashboard Profile', const ClientDashboard(initialIndex: 3)),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(title: const Text('Preview Gallery')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => ElevatedButton(
          onPressed: () => Get.to(() => items[i].$2),
          child: Text(items[i].$1),
        ),
      ),
    );
  }
}
