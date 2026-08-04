import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:patrol/patrol.dart';

import 'package:alphaserena/controllers/lifestyle_history_controller.dart';
import 'package:alphaserena/core/services/member_rollup_service.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/lifestyle_history_screen.dart';

/// PATROL — THE MEMBER'S LIFESTYLE HISTORY, ON A REAL DEVICE.
///
/// The REAL screen over the REAL controller, with only the Firestore boundary
/// faked. Every figure comes from `coaching_rollups`, the same read model the
/// coach uses, so this also certifies that the two apps cannot disagree.
class _FakeRollups extends MemberRollupService {
  _FakeRollups(this._days);
  final List<RollupDay> _days;
  bool fail = false;

  @override
  bool get canRead => true;

  @override
  Stream<List<RollupDay>> watchDays({int months = 3, DateTime? now}) =>
      fail ? Stream.error(Exception('offline')) : Stream.value(_days);
}

void main() {
  final now = DateTime(2026, 8, 15, 10);
  DateTime dayAgo(int n) {
    final d = now.subtract(Duration(days: n));
    return DateTime(d.year, d.month, d.day);
  }

  RollupDay day(int daysAgo,
          {double? waterMl,
          double? steps,
          double? sleepHours,
          int? supplementItems}) =>
      RollupDay(
        date: dayAgo(daysAgo),
        waterMl: waterMl,
        steps: steps,
        sleepHours: sleepHours,
        supplementItems: supplementItems,
      );

  Map<String, dynamic> client({int stack = 2, bool targets = true}) => {
        'lifestyleTargets': targets
            ? {
                'waterTargetMl': 3000,
                'stepsTarget': 8000,
                'sleepHoursTarget': 8,
              }
            : <String, dynamic>{},
        'supplementPlan': [for (var i = 0; i < stack; i++) {'id': 's$i'}],
      };

  Future<void> open(
    PatrolIntegrationTester $, {
    List<RollupDay> days = const [],
    Map<String, dynamic>? doc,
    bool fail = false,
    double textScale = 1.0,
    Brightness brightness = Brightness.dark,
    Size? surface,
  }) async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    Get.reset();
    if (surface != null) await $.tester.binding.setSurfaceSize(surface);
    Get.put(LifestyleHistoryController(
      rollups: _FakeRollups(days)..fail = fail,
      clientDoc: () => doc ?? client(),
      now: now,
    ));
    await $.pumpWidgetAndSettle(
      GetMaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const LifestyleHistoryScreen(),
        ),
      ),
    );
  }

  List<RollupDay> aMonth() => [
        for (var i = 1; i <= 20; i++)
          day(i,
              waterMl: i.isEven ? 3200 : 1800,
              steps: i.isEven ? 9000 : 5000,
              sleepHours: i.isEven ? 8.2 : 6.0,
              supplementItems: i.isEven ? 2 : 1),
      ];

  /// `yyyy-MM-dd`, the key the rollup document is actually keyed by.
  String key(DateTime d) => d.toIso8601String().substring(0, 10);

  /// One `tracks.lifestyle.days.{key}` cell EXACTLY as `deriveLifestyleMetrics`
  /// emits it: a metric with no events of its type is null, never zero.
  Map<String, dynamic> cell({double? waterMl, double? steps, int? items}) => {
        'metrics': {
          'waterMl': waterMl,
          'steps': steps,
          'sleepMinutes': null,
          'supplementDoses': items,
          'supplementItems': items,
        },
        'eventCount': 1,
        'flags': <String>[],
        'origin': 'events',
      };

  tearDown(Get.reset);

  // LS-02, driven through the REAL parser over the shape the BACKEND emits.
  //
  // Every other fixture in this file — and in the unit suite — hand-builds
  // `RollupDay` objects supplying only the metric under test. That habit is
  // precisely why LS-02 was invisible to a fully green suite, and it is the
  // third time this repository has been bitten by it. This one starts from a
  // literal `coaching_rollups` document and lets `MemberRollupService.daysFrom`
  // parse it, exactly as production does.
  patrolTest('a day the member logged only steps is absent from Water',
      ($) async {
    final parsed = MemberRollupService.daysFrom({
      'tracks': {
        'lifestyle': {
          'days': {
            // Two real water days...
            key(dayAgo(1)): cell(waterMl: 3200, steps: 9000),
            key(dayAgo(3)): cell(waterMl: 3200, steps: 9000),
            // ...and one the member only logged STEPS on. The server sends
            // `waterMl: null` for it; it used to send 0, which read as a
            // logged day that missed the goal.
            key(dayAgo(2)): cell(steps: 9000),
          },
        },
      },
    });

    await open($, days: parsed, surface: const Size(390, 2200));
    final c = Get.find<LifestyleHistoryController>();
    final water = c.historyFor(HabitKind.water);

    expect(water.dayValues.containsKey(dayAgo(2)), false,
        reason: 'no drink events is not "drank 0 ml"');
    expect(water.dayValues.length, 2);
    expect(water.avg7, 3200, reason: 'never dragged down by an absent day');
    expect(water.goalHitRate, 1.0);
    expect(water.worstDay?.value, 3200,
        reason: 'the worst day must be one the member claimed something about');
  });

  patrolTest('history opens on Water with its statistics', ($) async {
    await open($, days: aMonth(), surface: const Size(390, 2200));
    expect($('Your history').exists, true);
    expect($('streak').exists, true);
    expect($('best').exists, true);
    expect($('7d avg').exists, true);
    expect($('30d avg').exists, true);
    expect($('goal hit').exists, true);
    expect($('trend').exists, true);
  });

  patrolTest('every habit is selectable and renders', ($) async {
    await open($, days: aMonth(), surface: const Size(390, 2200));
    for (final label in ['Water', 'Steps', 'Sleep', 'Supplements']) {
      await $(label).tap();
      await $.pumpAndSettle();
      expect($.tester.takeException(), isNull, reason: '$label must render');
      expect($('7d avg').exists, true);
    }
  });

  patrolTest('best and toughest day are named', ($) async {
    await open($, days: aMonth(), surface: const Size(390, 2200));
    expect($('Best day').exists, true);
    expect($('Toughest day').exists, true);
  });

  patrolTest('the calendar legend distinguishes not-logged from below-goal',
      ($) async {
    await open($, days: aMonth(), surface: const Size(390, 2200));
    await $('Not logged').scrollTo();
    expect($('Goal hit').exists, true);
    expect($('Below goal').exists, true);
    expect($('Not logged').exists, true);
  });

  patrolTest('month navigation is bounded at the current month', ($) async {
    await open($, days: aMonth(), surface: const Size(390, 2200));
    final next = $.tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next.onPressed, isNull, reason: 'no browsing into the future');
  });

  patrolTest('a habit with NO target shows no goal, not a zero rate',
      ($) async {
    await open($,
        days: aMonth(),
        doc: client(targets: false),
        surface: const Size(390, 2200));
    await $(RegExp('No goal set')).scrollTo();
    expect($(RegExp('No goal set')).exists, true);
    expect($('goal hit').exists, false);
  });

  patrolTest('a member who never logged sees an empty state, not an error',
      ($) async {
    await open($, days: const [], surface: const Size(390, 2200));
    expect($(RegExp('No water history yet')).exists, true);
    expect($('Try again').exists, false);
  });

  patrolTest('a failed read is an error with retry, never empty', ($) async {
    await open($, fail: true, surface: const Size(390, 2200));
    expect($("Couldn't load your history").exists, true);
    expect($('Try again').exists, true);
  });

  patrolTest('the read window is disclosed', ($) async {
    await open($, days: aMonth(), surface: const Size(390, 2200));
    await $(RegExp('months of recorded history')).scrollTo();
    expect($(RegExp('months of recorded history')).exists, true);
  });

  patrolTest('320dp at 2.0x accessibility text does not overflow', ($) async {
    await open($,
        days: aMonth(), textScale: 2.0, surface: const Size(320, 4000));
    expect($.tester.takeException(), isNull);
  });

  patrolTest('landscape and tablet render cleanly', ($) async {
    await open($, days: aMonth(), surface: const Size(900, 1400));
    expect($.tester.takeException(), isNull);
  });

  patrolTest('light mode renders cleanly', ($) async {
    await open($,
        days: aMonth(),
        brightness: Brightness.light,
        surface: const Size(390, 2200));
    expect($.tester.takeException(), isNull);
    expect($('Your history').exists, true);
  });
}
