import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:patrol/patrol.dart';

import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/home/daily_progress_card.dart';

/// PATROL — THE HOME LIFESTYLE + NUTRITION DASHBOARD, ON A REAL DEVICE.
///
/// Drives the REAL `DailyProgressCard` — the single widget behind both Home
/// sections — through every state a member can be in. Home's own scaffold
/// needs a live member session (phone OTP is externally blocked on this
/// emulator), so the section is exercised directly; what a device uniquely
/// proves here is layout under real text scaling, rotation and themes.
void main() {
  Future<void> boot() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    Get.reset();
  }

  DailyMetric metric({
    String label = 'Water',
    double? current,
    double? target,
    String unit = 'glasses',
  }) =>
      DailyMetric(
        label: label,
        icon: Icons.water_drop_outlined,
        unit: unit,
        format: (v) => v.round().toString(),
        current: current,
        target: target,
      );

  List<DailyMetric> lifestyle() => [
        metric(label: 'Water', current: 6, target: 12),
        metric(label: 'Steps', current: 9200, target: 8000, unit: ''),
        metric(label: 'Sleep', current: 7.5, target: 8, unit: 'h'),
        metric(label: 'Supplements', current: 2, target: 3, unit: ''),
      ];

  List<DailyMetric> nutrition() => [
        metric(label: 'Calories', current: 1850, target: 2200, unit: 'kcal'),
        metric(label: 'Protein', current: 120, target: 160, unit: 'g'),
        metric(label: 'Carbs', current: 210, target: 220, unit: 'g'),
        metric(label: 'Fat', current: 62, target: 70, unit: 'g'),
        metric(label: 'Fiber', current: 22, unit: 'g'),
      ];

  Future<void> open(
    PatrolIntegrationTester $, {
    required List<DailyMetric> metrics,
    String title = 'Lifestyle progress',
    String? subtitle,
    double textScale = 1.0,
    Brightness brightness = Brightness.dark,
    Size? surface,
  }) async {
    await boot();
    if (surface != null) await $.tester.binding.setSurfaceSize(surface);
    await $.pumpWidgetAndSettle(
      MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: DailyProgressCard(
                title: title,
                titleIcon: Icons.favorite_border,
                metrics: metrics,
                subtitle: subtitle ??
                    DailyProgressCard.onTrackSummary(metrics),
                actionLabel: 'Log',
                onAction: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  tearDown(Get.reset);

  patrolTest('lifestyle progress shows current against target', ($) async {
    await open($, metrics: lifestyle(), surface: const Size(390, 1600));
    expect($('Lifestyle progress').exists, true);
    expect($('Water').exists, true);
    expect($('6 / 12 glasses').exists, true);
    expect($('Supplements').exists, true);
  });

  patrolTest('nutrition progress shows only consumed vs target', ($) async {
    await open($,
        metrics: nutrition(),
        title: 'Nutrition progress',
        surface: const Size(390, 1600));
    expect($('Calories').exists, true);
    expect($('1850 / 2200 kcal').exists, true);
    // Fiber has no target — its value shows, but never a fabricated ratio.
    expect($('22 g').exists, true);
  });

  patrolTest('NO adherence vocabulary reaches the dashboard', ($) async {
    await open($, metrics: nutrition(), surface: const Size(390, 1600));
    for (final w in ['eaten', 'skipped', 'partial', 'adherence']) {
      expect($(w).exists, false, reason: '"$w" must not appear');
    }
  });

  patrolTest('an unlogged day shows a dash, never a fabricated zero',
      ($) async {
    await open($, metrics: [
      metric(label: 'Water', target: 12),
      metric(label: 'Steps', target: 8000, unit: ''),
    ], surface: const Size(390, 1600));
    expect($('— / 12 glasses').exists, true);
    expect($('0 / 12 glasses').exists, false);
  });

  patrolTest('a member with NO targets is not shown a shortfall', ($) async {
    await open($, metrics: [
      metric(label: 'Water', current: 6),
      metric(label: 'Steps', current: 9200, unit: ''),
    ], subtitle: 'No coach targets yet — you can still track your day',
        surface: const Size(390, 1600));
    expect($(RegExp('No coach targets yet')).exists, true);
    expect($('6 glasses').exists, true);
  });

  patrolTest('passing a target is not flattened to complete', ($) async {
    await open($, metrics: [
      metric(label: 'Steps', current: 16000, target: 8000, unit: ''),
    ], surface: const Size(390, 1600));
    expect($('16000 / 8000').exists, true);
  });

  patrolTest('320dp at 2.0x accessibility text does not overflow', ($) async {
    await open($,
        metrics: lifestyle(), textScale: 2.0, surface: const Size(320, 3000));
    expect($.tester.takeException(), isNull);
    expect($('Water').exists, true);
  });

  patrolTest('landscape renders cleanly', ($) async {
    await open($, metrics: lifestyle(), surface: const Size(900, 500));
    expect($.tester.takeException(), isNull);
  });

  patrolTest('tablet renders cleanly', ($) async {
    await open($, metrics: nutrition(), surface: const Size(1024, 1600));
    expect($.tester.takeException(), isNull);
  });

  patrolTest('light mode renders cleanly', ($) async {
    await open($,
        metrics: lifestyle(),
        brightness: Brightness.light,
        surface: const Size(390, 1600));
    expect($.tester.takeException(), isNull);
    expect($('Water').exists, true);
  });
}
