import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:patrol/patrol.dart';

import 'package:alphaserena/controllers/auth_controller.dart';
import 'package:alphaserena/core/services/account_role_service.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/auth/role_check_failed_screen.dart';
import 'package:alphaserena/screens/auth/wrong_app_screen.dart';

/// PATROL — THE CROSS-APP ROLE GATE, ON A REAL DEVICE.
///
/// AlphaSerena is the MEMBER app. A trainer, organization owner or platform
/// administrator signing in here used to be routed straight into the member
/// experience: either into `ClientDashboard` (which bootstraps twelve member
/// controllers and fires `claimClientAccount`, the session's first Firestore
/// write) or into `JoinCoachScreen`, the purchase funnel, where they could buy
/// a membership and become a client of the platform they staff.
///
/// The DECISION is unit-tested (`test/account_role_gate_test.dart`) and the
/// Firestore reads behind it are proven on a real emulator against the real
/// rules (`trainershq-backend/tests/rules/member_role_gate_reads.mjs`). What a
/// DEVICE uniquely proves — and what this suite covers — is the terminal
/// surfaces themselves: that they render, that they name the right application,
/// that they cannot be escaped back into a half-built member app, and that they
/// hold up in landscape, on a tablet and at accessibility text sizes.
void main() {
  Future<void> boot() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    Get.reset();
    // The screens' only action resolves this; registering the real controller
    // keeps the harness honest (nothing about the gate is stubbed here).
    Get.put(AuthController());
  }

  Future<void> open(
    PatrolIntegrationTester $,
    Widget screen, {
    double textScale = 1.0,
    Size surface = const Size(390, 844),
  }) async {
    await boot();
    await $.tester.binding.setSurfaceSize(surface);
    await $.pumpWidgetAndSettle(
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: screen,
        ),
      ),
    );
  }

  /// Delivers the SYSTEM back press at the Flutter level.
  ///
  /// Not `native.pressBack()`: these screens are the ROOT of a bare harness, so
  /// an Android back would finish the activity and tear down Patrol's app
  /// service mid-run. Dispatching `popRoute` is exactly what the OS back
  /// delivers to Flutter, so it exercises `PopScope` for real without touching
  /// the activity.
  Future<void> systemBack(PatrolIntegrationTester $) async {
    await $.tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(
        const MethodCall('popRoute'),
      ),
      (_) {},
    );
    await $.pumpAndSettle();
  }

  // ── A coach is told, precisely, which app is theirs ──────────────────────

  patrolTest('a TRAINER is named as a Trainer and sent to TrainerHQ', ($) async {
    await open($, const WrongAppScreen(role: AccountRole.trainer));

    expect($('This account is registered as a Trainer').exists, true);
    expect($(RegExp('TrainerHQ')).exists, true);
    // It must never read as a member problem.
    expect($(RegExp('membership', caseSensitive: false)).exists, false);
  });

  patrolTest('an ORGANIZATION OWNER gets owner copy, still TrainerHQ', (
    $,
  ) async {
    await open($, const WrongAppScreen(role: AccountRole.admin));

    expect($('This account is registered as an Organization Owner').exists, true);
    expect($(RegExp('TrainerHQ')).exists, true);
  });

  patrolTest('PLATFORM STAFF are pointed at the Admin console, not TrainerHQ', (
    $,
  ) async {
    await open($, const WrongAppScreen(role: AccountRole.platformAdmin));

    expect(
      $('This account is registered as a Platform Administrator').exists,
      true,
    );
    expect($(RegExp('AlphaSerena Admin console')).exists, true);
  });

  patrolTest('the coach is told the session was ended', ($) async {
    // The gate signs out BEFORE navigating here, so the screen must say so —
    // otherwise a coach is left wondering whether they are still signed in.
    await open($, const WrongAppScreen(role: AccountRole.trainer));
    expect($(RegExp('signed out')).exists, true);
  });

  patrolTest('there is exactly ONE way forward: back to sign in', ($) async {
    await open($, const WrongAppScreen(role: AccountRole.trainer));
    expect($('Back to sign in').exists, true);
    // No member surface may be reachable from here.
    for (final leak in const ['Home', 'My Plans', 'Progress', 'Profile',
        'Find a Coach', 'Continue', 'Skip']) {
      expect($(leak).exists, false, reason: '"$leak" would be a way in');
    }
  });

  patrolTest('BACK cannot escape the wrong-app screen', ($) async {
    await open($, const WrongAppScreen(role: AccountRole.trainer));
    // PopScope(canPop:false) — a hardware back must not drop the coach into a
    // black frame or, worse, a partially-built member app.
    await systemBack($);
    expect($('This account is registered as a Trainer').exists, true);
  });

  // ── An unverifiable session fails CLOSED, and says so kindly ─────────────

  patrolTest('a failed role check STOPS the session but blames nobody', (
    $,
  ) async {
    await open($, const RoleCheckFailedScreen());

    expect($(RegExp("couldn't verify your account", caseSensitive: false)).exists,
        true);
    // It is a retryable network state, not a rejection — the copy must not
    // imply the account is wrong.
    expect($(RegExp('Nothing is wrong with your account')).exists, true);
    expect($('Back to sign in').exists, true);
  });

  patrolTest('BACK cannot escape the check-failed screen either', ($) async {
    await open($, const RoleCheckFailedScreen());
    await systemBack($);
    expect($(RegExp("couldn't verify", caseSensitive: false)).exists, true);
  });

  // ── It holds up wherever a coach opens it ───────────────────────────────

  patrolTest('renders at 2.0x accessibility text without overflowing', (
    $,
  ) async {
    await open(
      $,
      const WrongAppScreen(role: AccountRole.platformAdmin),
      textScale: 2.0,
      surface: const Size(320, 800),
    );
    expect($.tester.takeException(), isNull);
    expect($('Back to sign in').exists, true);
  });

  patrolTest('renders in landscape', ($) async {
    await open(
      $,
      const WrongAppScreen(role: AccountRole.trainer),
      surface: const Size(844, 390),
    );
    expect($.tester.takeException(), isNull);
    expect($('Back to sign in').exists, true);
  });

  patrolTest('renders on a tablet', ($) async {
    await open(
      $,
      const WrongAppScreen(role: AccountRole.admin),
      surface: const Size(1024, 1366),
    );
    expect($.tester.takeException(), isNull);
    expect($(RegExp('TrainerHQ')).exists, true);
  });

  patrolTest('repeated opens leak nothing and throw nothing', ($) async {
    for (final role in const [
      AccountRole.trainer,
      AccountRole.admin,
      AccountRole.platformAdmin,
    ]) {
      await open($, WrongAppScreen(role: role));
      expect($.tester.takeException(), isNull);
      expect($('Back to sign in').exists, true);
    }
  });
}
