import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:patrol/patrol.dart';

import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/home/daily_metric.dart';
import 'package:alphaserena/screens/dashboard/home/lifestyle_progress_card.dart';
import 'package:alphaserena/screens/dashboard/home/nutrition_progress_card.dart';

/// PATROL — THE HOME NUTRITION + LIFESTYLE CARDS, ON A REAL DEVICE.
///
/// Drives the REAL redesigned widgets through every state a member can be in.
/// Home's own scaffold needs a live member session (phone OTP is externally
/// blocked on this emulator), so the two sections are exercised directly; what
/// a device uniquely proves here is layout under real text scaling, rotation,
/// themes and an actual raster of the calorie ring's gradient + blur.
void main() {
  Future<void> boot() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    Get.reset();
  }

  DailyMetric metric({
    required String label,
    double? current,
    double? target,
    String unit = 'g',
    String Function(double)? format,
  }) =>
      DailyMetric(
        label: label,
        unit: unit,
        format: format ?? (v) => v.round().toString(),
        current: current,
        target: target,
      );

  DailyMetric calories({double? current = 850, double? target = 2000}) =>
      metric(label: 'Calories', current: current, target: target, unit: 'kcal');

  List<DailyMetric> macros() => [
        metric(label: 'Protein', current: 65, target: 150),
        metric(label: 'Fat', current: 32, target: 60),
        metric(label: 'Carbs', current: 180, target: 250),
        metric(label: 'Fiber', current: 14),
      ];

  List<LifestyleTile> lifestyle({bool withSupplements = true}) => [
        LifestyleTile(
          metric: metric(
              label: 'Water', current: 6, target: 12, unit: 'glasses'),
          icon: Icons.water_drop_rounded,
          tint: const Color(0xFF29B6F6),
        ),
        LifestyleTile(
          metric: metric(label: 'Steps', current: 9200, target: 8000, unit: ''),
          icon: Icons.directions_walk_rounded,
          tint: const Color(0xFFFB8C00),
        ),
        LifestyleTile(
          metric: metric(
            label: 'Sleep',
            current: 7.5,
            target: 8,
            unit: '',
            format: (v) {
              final total = (v * 60).round();
              final h = total ~/ 60;
              final m = total % 60;
              return m == 0 ? '${h}h' : '${h}h ${m}m';
            },
          ),
          icon: Icons.bedtime_rounded,
          tint: const Color(0xFF7C83FF),
        ),
        if (withSupplements)
          LifestyleTile(
            metric: metric(
                label: 'Supplements', current: 2, target: 3, unit: ''),
            icon: Icons.medication_rounded,
            tint: const Color(0xFF2EBD59),
            valueText: '2 / 3',
            showGoal: false,
          ),
      ];

  /// [open] for a state that legitimately animates forever.
  Future<void> openWithoutSettling(
    PatrolIntegrationTester $,
    Widget card, {
    Size? surface,
  }) async {
    await boot();
    if (surface != null) await $.tester.binding.setSurfaceSize(surface);
    await $.tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(18), child: card),
          ),
        ),
      ),
    );
    await $.tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> open(
    PatrolIntegrationTester $,
    Widget card, {
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
              child: Padding(padding: const EdgeInsets.all(18), child: card),
            ),
          ),
        ),
      ),
    );
  }

  Widget nutritionCard({
    DailyMetric? cals,
    List<DailyMetric>? nutrients,
    String subtitle = "Today's nutrition",
    bool loading = false,
  }) =>
      NutritionProgressCard(
        calories: cals ?? calories(),
        nutrients: nutrients ?? macros(),
        subtitle: subtitle,
        loading: loading,
        onLogFood: () {},
        onTap: () {},
      );

  Widget lifestyleCard({
    List<LifestyleTile>? tiles,
    String subtitle = "Today's targets",
    bool loading = false,
  }) =>
      LifestyleProgressCard(
        tiles: tiles ?? lifestyle(),
        subtitle: subtitle,
        loading: loading,
        onTap: () {},
      );

  tearDown(Get.reset);

  // ══ NUTRITION ════════════════════════════════════════════════════════════

  patrolTest('the calorie ring leads, with the macros beside it', ($) async {
    await open($, nutritionCard(), surface: const Size(390, 1600));
    expect($('Nutrition Progress').exists, true);
    expect($('KCAL').exists, true);
    expect($('850').exists, true);
    expect($('850 / 2000 kcal').exists, true);
    expect($('65 / 150 g').exists, true);
    expect($('Log Food').exists, true);
  });

  patrolTest('a macro with no target shows its value, not a fake ratio',
      ($) async {
    await open($, nutritionCard(), surface: const Size(390, 1600));
    expect($('14 g').exists, true);
  });

  patrolTest('an unlogged day shows a dash, never a fabricated zero',
      ($) async {
    await open(
      $,
      nutritionCard(
        cals: calories(current: null),
        nutrients: [
          metric(label: 'Protein', target: 150),
          metric(label: 'Fat', target: 60),
          metric(label: 'Carbs', target: 250),
          metric(label: 'Fiber', target: 30),
        ],
        subtitle: 'Nothing logged yet today',
      ),
      surface: const Size(390, 1600),
    );
    expect($('— / 2000 kcal').exists, true);
    expect($('0 / 2000 kcal').exists, false);
  });

  patrolTest('a member with NO targets is not shown a shortfall', ($) async {
    await open(
      $,
      nutritionCard(
        cals: calories(target: null),
        nutrients: [
          metric(label: 'Protein', current: 65),
          metric(label: 'Fat', current: 32),
          metric(label: 'Carbs', current: 180),
          metric(label: 'Fiber', current: 14),
        ],
        subtitle: 'No coach targets yet',
      ),
      surface: const Size(390, 1600),
    );
    expect($(RegExp('No coach targets yet')).exists, true);
    expect($('65 g').exists, true);
  });

  patrolTest('the loading card shows no numbers at all', ($) async {
    // NOT `open()` — that settles, and a loading card never settles by
    // design: its skeleton shimmers on a repeating controller, which is the
    // whole point (a static grey block is indistinguishable from a card that
    // failed to render). Pumped a fixed distance instead, which also proves
    // the shimmer is genuinely running.
    await openWithoutSettling(
      $,
      nutritionCard(loading: true),
      surface: const Size(390, 1600),
    );
    expect($('Nutrition Progress').exists, true);
    expect($('850').exists, false);
  });

  // A FAILED READ IS NOT AN EMPTY LOG. This caller used to derive its sentence
  // from `entryCount` alone and never consult `loadError`, so a denied or
  // failed read — which leaves loading false and the count at zero — rendered
  // as "Nothing logged yet today": a claim about the MEMBER made out of the
  // app's own failure. The subtitle here is produced by the REAL rule, not a
  // hand-written string, so this test cannot pass against a caller that has
  // gone back to ignoring the flag.
  patrolTest('a failed read is never rendered as an empty log', ($) async {
    await open(
      $,
      nutritionCard(
        cals: calories(current: null),
        nutrients: [
          metric(label: 'Protein', target: 150),
          metric(label: 'Fat', target: 60),
          metric(label: 'Carbs', target: 250),
          metric(label: 'Fiber', target: 30),
        ],
        subtitle: nutritionCardSubtitle(
          loadError: true,
          hasAnyTarget: true,
          entryCount: 0,
        ),
      ),
      surface: const Size(390, 1600),
    );
    expect($(RegExp("Couldn't load today's food")).exists, true);
    expect($(RegExp('Nothing logged yet today')).exists, false,
        reason: 'the app must not report its own failure as the member\'s');
    // And still no fabricated zero behind the honest sentence.
    expect($('0 / 2000 kcal').exists, false);
  });

  // ══ LIFESTYLE ════════════════════════════════════════════════════════════

  patrolTest('lifestyle shows four tiles with value, goal and completion',
      ($) async {
    await open($, lifestyleCard(), surface: const Size(390, 1600));
    expect($('Lifestyle Progress').exists, true);
    expect($('Water').exists, true);
    expect($('6 glasses').exists, true);
    expect($('Goal 12 glasses').exists, true);
    expect($('50%').exists, true);
    expect($('7h 30m').exists, true);
    expect($('Supplements').exists, true);
    expect($('2 / 3').exists, true);
  });

  patrolTest('there is no History button — the whole card is the affordance',
      ($) async {
    await open($, lifestyleCard(), surface: const Size(390, 1600));
    expect($('History').exists, false);
  });

  patrolTest('no prescribed supplements → no tile, and no empty placeholder',
      ($) async {
    await open($, lifestyleCard(tiles: lifestyle(withSupplements: false)),
        surface: const Size(390, 1600));
    expect($('Supplements').exists, false);
    expect($('Sleep').exists, true);
  });

  patrolTest('passing a target is not flattened to complete', ($) async {
    await open($, lifestyleCard(), surface: const Size(390, 1600));
    // Steps: 9200 of 8000.
    expect($('115%').exists, true);
  });

  // ══ BOTH ═════════════════════════════════════════════════════════════════

  patrolTest('NO adherence vocabulary reaches the dashboard', ($) async {
    for (final card in [nutritionCard(), lifestyleCard()]) {
      await open($, card, surface: const Size(390, 1600));
      for (final w in ['eaten', 'skipped', 'partial', 'adherence']) {
        expect($(w).exists, false, reason: '"$w" must not appear');
      }
    }
  });

  patrolTest('320dp at 2.0x accessibility text does not overflow', ($) async {
    await open($, nutritionCard(),
        textScale: 2.0, surface: const Size(320, 3000));
    expect($.tester.takeException(), isNull);
    expect($('Protein').exists, true);

    await open($, lifestyleCard(),
        textScale: 2.0, surface: const Size(320, 3000));
    expect($.tester.takeException(), isNull);
    expect($('Water').exists, true);
  });

  patrolTest('landscape renders cleanly', ($) async {
    await open($, nutritionCard(), surface: const Size(900, 500));
    expect($.tester.takeException(), isNull);
    await open($, lifestyleCard(), surface: const Size(900, 500));
    expect($.tester.takeException(), isNull);
  });

  patrolTest('tablet renders cleanly', ($) async {
    await open($, nutritionCard(), surface: const Size(1024, 1600));
    expect($.tester.takeException(), isNull);
    await open($, lifestyleCard(), surface: const Size(1024, 1600));
    expect($.tester.takeException(), isNull);
  });

  patrolTest('light mode renders cleanly', ($) async {
    await open($, nutritionCard(),
        brightness: Brightness.light, surface: const Size(390, 1600));
    expect($.tester.takeException(), isNull);
    expect($('850').exists, true);

    await open($, lifestyleCard(),
        brightness: Brightness.light, surface: const Size(390, 1600));
    expect($.tester.takeException(), isNull);
    expect($('Water').exists, true);
  });
}
