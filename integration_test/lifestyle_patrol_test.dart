import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:patrol/patrol.dart';

import 'package:alphaserena/controllers/lifestyle_controller.dart';
import 'package:alphaserena/controllers/lifestyle_history_controller.dart';
import 'package:alphaserena/controllers/member_controller.dart';
import 'package:alphaserena/core/domain/coaching_event.dart';
import 'package:alphaserena/core/models/lifestyle_log_model.dart';
import 'package:alphaserena/core/models/lifestyle_targets.dart';
import 'package:alphaserena/core/services/coaching_event_writer.dart';
import 'package:alphaserena/core/services/lifestyle_event_service.dart';
import 'package:alphaserena/core/services/lifestyle_log_service.dart';
import 'package:alphaserena/core/services/member_rollup_service.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/core/utils/lifestyle_math.dart';
import 'package:alphaserena/screens/dashboard/home/daily_metric.dart';
import 'package:alphaserena/screens/dashboard/home/lifestyle_progress_card.dart';
import 'package:alphaserena/screens/dashboard/lifestyle_history_screen.dart';
import 'package:alphaserena/screens/dashboard/lifestyle_today_screen.dart';

/// PATROL — THE COMPLETE LIFESTYLE FLOW, ON A REAL DEVICE.
///
/// Drives the REAL screens over the REAL `LifestyleController` and the REAL
/// derivations. Only the Firestore boundary is faked, by an in-memory event
/// store that behaves as the day document does: append-only, soft deletes, and
/// a snapshot stream every reader re-derives from.
///
/// ⚠️ WHAT THIS CANNOT PROVE. Phone OTP is externally blocked on this
/// emulator, so there is no live member session and no live backend: the
/// `onLifestyleDayWritten` Cloud Function that turns the member's events into
/// `coaching_rollups` is NOT exercised here. History is therefore driven from
/// a rollup fake seeded with the day the events derive to — which certifies
/// the READ path and the parse, not the trigger. The trigger has its own
/// backend tests.
///
/// [_Store] deliberately OUTLIVES the widget tree so a "restart" (tear the app
/// down, reset GetX, rebuild from scratch) reads back what was written —
/// exactly what a real relaunch does against Firestore's cache.
class _Store {
  final Map<String, CoachingEvent> events = {};
  final StreamController<List<CoachingEvent>> _stream =
      StreamController<List<CoachingEvent>>.broadcast();
  int seq = 0;

  void emit() => _stream.add(events.values.toList());

  List<CoachingEvent> get live =>
      events.values.where((e) => !e.deleted).toList();
}

class _Events extends LifestyleEventService {
  _Events(this.store) : super(writer: _Writer(), legacy: _Log());

  final _Store store;

  @override
  bool get canLog => true;

  @override
  Stream<List<CoachingEvent>> watchDay(String dateKey) async* {
    yield store.events.values.toList();
    yield* store._stream.stream;
  }

  Future<EventWriteResult> _put(String type, Map<String, dynamic> payload) async {
    final id = '${type}_${store.seq++}';
    store.events[id] = CoachingEvent(
      eventId: id,
      type: type,
      // Monotonic, so "the latest manual reading wins" means the newest tap.
      at: DateTime(2026, 8, 2, 6).add(Duration(minutes: store.seq)),
      payload: payload,
    );
    store.emit();
    return EventWriteResult.synced;
  }

  @override
  Future<EventWriteResult> logDrink({
    required String dateKey,
    required int ml,
    String source = EventSource.manual,
    String? sourceKey,
  }) =>
      _put(LifestyleEventType.drink, {'ml': ml});

  @override
  Future<EventWriteResult> logSteps({
    required String dateKey,
    required int count,
    String source = EventSource.manual,
    String? sourceKey,
  }) =>
      _put(LifestyleEventType.stepsSample, {'count': count});

  @override
  Future<EventWriteResult> logSleep({
    required String dateKey,
    DateTime? start,
    DateTime? end,
    int? minutes,
    String source = EventSource.manual,
    String? sourceKey,
  }) {
    final period = start != null && end != null && end.isAfter(start);
    return _put(
        LifestyleEventType.sleep,
        period
            ? {
                'start': start.millisecondsSinceEpoch,
                'end': end.millisecondsSinceEpoch,
              }
            : {'minutes': minutes ?? 0});
  }

  @override
  Future<EventWriteResult> logSupplementDose({
    required String dateKey,
    required String itemId,
    String? name,
    String? dose,
  }) =>
      _put(LifestyleEventType.supplementTaken, {'itemId': itemId});

  @override
  Future<EventWriteResult> withdraw({
    required String dateKey,
    required String eventId,
  }) async {
    final e = store.events[eventId];
    if (e != null) store.events[eventId] = e.copyWith(deleted: true);
    store.emit();
    return EventWriteResult.synced;
  }

  @override
  Future<void> mirrorLegacyTotals({
    required String dateKey,
    required List<CoachingEvent> events,
    List<SupplementPlanItem> stack = const [],
  }) async {}
}

class _Writer extends CoachingEventWriter {
  _Writer() : super(collection: 'x');
}

class _Log extends LifestyleLogService {
  /// Mutable so a device test can land linkage mid-session, which is what a
  /// member experiences while `claimClientAccount` resolves.
  bool linked = true;

  @override
  bool get canLog => linked;

  @override
  Stream<LifestyleLogModel?> watchDay(String dateKey) => Stream.value(null);

  @override
  Future<bool> mirrorDay({
    required String dateKey,
    required double waterMl,
    double? sleepHours,
    double? steps,
    List<SupplementIntake>? supplements,
  }) async =>
      true;
}

class _Member extends MemberController {
  _Member(Map<String, dynamic>? doc) {
    client.value = doc;
  }

  // Deliberately does NOT call super: the real onInit starts the auth and
  // Firestore listeners this fixture exists to avoid.
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Rollups extends MemberRollupService {
  _Rollups(this.days);
  final List<RollupDay> days;

  @override
  bool get canRead => true;

  @override
  Stream<List<RollupDay>> watchDays({int months = 3, DateTime? now}) =>
      Stream.value(days);
}

void main() {
  const stack = [
    {'id': 'a', 'name': 'Creatine', 'dose': '5 g'},
    {'id': 'b', 'name': 'Vitamin D3'},
  ];

  Map<String, dynamic> clientDoc() => {
        'lifestyleTargets': {
          'waterTargetMl': 2500,
          'glassSizeMl': 250,
          'stepsTarget': 10000,
          'sleepHoursTarget': 8,
        },
        'supplementPlan': stack,
      };

  late _Store store;

  /// Boots the app fresh over the SAME store — a relaunch.
  Future<LifestyleController> boot(PatrolIntegrationTester $) async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    Get.reset();
    final member = _Member(clientDoc());
    Get.put<MemberController>(member);
    final c = Get.put(LifestyleController(
      service: _Log(),
      events: _Events(store),
      member: member,
    ));
    return c;
  }

  Future<void> openToday(PatrolIntegrationTester $) async {
    await boot($);
    await $.pumpWidgetAndSettle(
      GetMaterialApp(
        theme: AppTheme.dark,
        home: const LifestyleTodayScreen(),
      ),
    );
  }

  /// The HOME lifestyle card, built from the SAME controller the Today screen
  /// just wrote through — which is the whole synchronisation claim.
  Future<void> openHomeCard(PatrolIntegrationTester $) async {
    final c = Get.find<LifestyleController>();
    await $.pumpWidgetAndSettle(
      GetMaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Obx(() {
            final supplements = c.supplementChecklist;
            final taken = supplements.where((s) => s.taken).length;
            return LifestyleProgressCard(
              subtitle: "Today's targets",
              loading: c.isLoading.value,
              tiles: [
                LifestyleTile(
                  metric: DailyMetric(
                    label: 'Water',
                    unit: 'glasses',
                    format: (v) => v.round().toString(),
                    current:
                        c.waterMl > 0 ? c.waterGlasses.toDouble() : null,
                    target: c.waterTargetGlasses.toDouble(),
                  ),
                  icon: Icons.water_drop_rounded,
                  tint: const Color(0xFF29B6F6),
                ),
                LifestyleTile(
                  metric: DailyMetric(
                    label: 'Steps',
                    unit: '',
                    format: (v) => v.round().toString(),
                    current: c.steps?.toDouble(),
                    target: c.targets.stepsTarget?.toDouble(),
                  ),
                  icon: Icons.directions_walk_rounded,
                  tint: const Color(0xFFFB8C00),
                ),
                LifestyleTile(
                  metric: DailyMetric(
                    label: 'Sleep',
                    unit: '',
                    format: hoursMinutes,
                    current: c.sleepHours,
                    target: c.targets.sleepHoursTarget,
                  ),
                  icon: Icons.bedtime_rounded,
                  tint: const Color(0xFF7C83FF),
                ),
                if (supplements.isNotEmpty)
                  LifestyleTile(
                    metric: DailyMetric(
                      label: 'Supplements',
                      unit: '',
                      format: (v) => v.round().toString(),
                      current: taken.toDouble(),
                      target: supplements.length.toDouble(),
                    ),
                    icon: Icons.medication_rounded,
                    tint: const Color(0xFF2EBD59),
                    valueText: '$taken / ${supplements.length}',
                    showGoal: false,
                  ),
              ],
              onTap: () {},
            );
          }),
        ),
      ),
    );
  }

  setUp(() => store = _Store());
  tearDown(Get.reset);

  // ══ WATER ════════════════════════════════════════════════════════════════

  patrolTest('Today\'s Targets opens with every section', ($) async {
    await openToday($);
    expect($("Today's Targets").exists, true);
    expect($('History').exists, true);
    expect($('WATER').exists, true);
    expect($('STEPS').exists, true);
    // On a real phone the lower cards are BELOW THE FOLD, and a lazy ListView
    // never builds what it has not reached — so they have to be scrolled to
    // before they exist to assert on at all.
    await $('SLEEP').scrollTo();
    expect($('SLEEP').exists, true);
    await $('SUPPLEMENTS').scrollTo();
    expect($('SUPPLEMENTS').exists, true);
  });

  patrolTest('adding water moves the counter, the ml and the ring', ($) async {
    await openToday($);
    expect($('0 ml / 2,500 ml').exists, true);

    await $.tester.tap(find.bySemanticsLabel('Add a glass of water'));
    await $.pumpAndSettle();
    expect($('1').exists, true);
    expect($('250 ml / 2,500 ml').exists, true);

    await $.tester.tap(find.bySemanticsLabel('Add a glass of water'));
    await $.pumpAndSettle();
    expect($('500 ml / 2,500 ml').exists, true);
    expect(Get.find<LifestyleController>().waterGlasses, 2);
  });

  patrolTest('removing water takes exactly one glass back', ($) async {
    await openToday($);
    for (var i = 0; i < 3; i++) {
      await $.tester.tap(find.bySemanticsLabel('Add a glass of water'));
      await $.pumpAndSettle();
    }
    expect($('750 ml / 2,500 ml').exists, true);

    await $.tester.tap(find.bySemanticsLabel('Remove a glass of water'));
    await $.pumpAndSettle();
    expect($('500 ml / 2,500 ml').exists, true);
    expect(Get.find<LifestyleController>().waterGlasses, 2);
  });

  // ══ LINKAGE ══════════════════════════════════════════════════════════════

  patrolTest('an unlinked member sees the join prompt, not an error',
      ($) async {
    // LS-01. `canLog` short-circuits on a NON-REACTIVE linkage field, so for a
    // member whose claim had not resolved the body `Obx` observed nothing and
    // GetX threw — a framework error box where the prompt should be, on a
    // screen every member opens. No test had ever run the false branch.
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    Get.reset();
    final member = _Member(null);
    Get.put<MemberController>(member);
    final log = _Log()..linked = false;
    Get.put(LifestyleController(
      service: log,
      events: _Events(store),
      member: member,
    ));
    await $.pumpWidgetAndSettle(
      GetMaterialApp(theme: AppTheme.dark, home: const LifestyleTodayScreen()),
    );

    expect($('Join a coach to start tracking your day.').exists, true);
    expect($('WATER').exists, false);

    // Linkage lands mid-session: the screen must follow without a reopen.
    log.linked = true;
    member.client.value = clientDoc();
    member.isLinked.value = true;
    await $.pumpAndSettle();

    expect($('WATER').exists, true);
    expect($('Join a coach to start tracking your day.').exists, false);
  });

  patrolTest('water past the goal is still recorded', ($) async {
    // LS-03. This test used to assert the opposite — that two taps past the
    // goal "wrote nothing" — and so it CERTIFIED the defect on real hardware:
    // a member who drank more than their target could not record it, and their
    // intake was truncated in their coach's analytics for good.
    await openToday($);
    for (var i = 0; i < 12; i++) {
      await $.tester.tap(find.bySemanticsLabel('Add a glass of water'));
      await $.pumpAndSettle();
    }
    final c = Get.find<LifestyleController>();
    expect(c.waterGlasses, 12, reason: 'every glass the member drank counts');
    expect(store.live.length, 12, reason: 'no tap is ever refused');
    // Reaching the goal is still celebrated — it is just not a wall.
    expect($('Goal reached — nice work.').exists, true);
    expect($('of 10 glasses').exists, true);
  });

  // ══ HOME SYNCHRONISATION ═════════════════════════════════════════════════

  patrolTest('the Home card reflects a change made on Today, with no restart',
      ($) async {
    await openToday($);
    await $.tester.tap(find.bySemanticsLabel('Add a glass of water'));
    await $.pumpAndSettle();
    await $.tester.tap(find.bySemanticsLabel('Add a glass of water'));
    await $.pumpAndSettle();

    await openHomeCard($);
    expect($('Water').exists, true);
    expect($('2 glasses').exists, true);
    expect($('20%').exists, true, reason: '2 of 10 glasses');
  });

  // ══ STEPS ════════════════════════════════════════════════════════════════

  patrolTest('steps save, then edit the SAME day', ($) async {
    await openToday($);
    await $.tester.enterText(find.byType(TextField), '6500');
    await $.pumpAndSettle();
    await $.tester.tap(find.bySemanticsLabel('Save').first);
    await $.pumpAndSettle();
    expect($('6,500').exists, true);
    expect($('65%').exists, true);

    await $.tester.tap(find.bySemanticsLabel('Edit'));
    await $.pumpAndSettle();
    await $.tester.enterText(find.byType(TextField), '11000');
    await $.pumpAndSettle();
    await $.tester.tap(find.bySemanticsLabel('Save').first);
    await $.pumpAndSettle();

    expect($('11,000').exists, true);
    final c = Get.find<LifestyleController>();
    expect(c.steps, 11000, reason: 'a correction, never 17 500');
  });

  // ══ SLEEP ════════════════════════════════════════════════════════════════

  patrolTest('two EQUAL sleep times are refused on device', ($) async {
    // LS-04. `w > b ? w - b : 1440 - b + w` cannot yield 0, so the guard that
    // was supposed to catch "same time twice" was unreachable and the card
    // silently recorded a TWENTY-FOUR HOUR night — accepted by validation and
    // by the server's own derivation, and shown to the coach as a real night.
    //
    // Seeding that exact corrupt state means Edit reloads two equal times,
    // which is the state a member would have to correct.
    await openToday($);
    final c = Get.find<LifestyleController>();
    await c.setSleep(24,
        start: DateTime(2026, 8, 1, 22, 30),
        end: DateTime(2026, 8, 2, 22, 30),
        replacing: true);
    await $.pumpAndSettle();
    final beforeLive = store.live.length;

    // The sleep card is BELOW THE FOLD on a real phone, and opening its editor
    // moves the Save further down again — so each control is scrolled into
    // view immediately before it is used, rather than once at the start.
    await $('SLEEP').scrollTo();
    await $(find.bySemanticsLabel('Edit')).last.scrollTo();
    await $(find.bySemanticsLabel('Edit')).last.tap();
    await $.pumpAndSettle();
    await $(find.bySemanticsLabel('Save')).last.scrollTo();
    await $(find.bySemanticsLabel('Save')).last.tap();
    await $.pumpAndSettle();

    await $("Sleep and wake time can't be the same.").scrollTo();
    expect($("Sleep and wake time can't be the same.").exists, true);
    expect(store.live.length, beforeLive,
        reason: 'a refused save writes nothing and withdraws nothing');
  });

  patrolTest('sleep records a period and derives the duration', ($) async {
    await openToday($);
    final c = Get.find<LifestyleController>();
    // The pickers are native dialogs; the WRITE they perform is what matters,
    // and it goes through the same controller call the card makes.
    await c.setSleep(7.75,
        start: DateTime(2026, 8, 1, 22, 45),
        end: DateTime(2026, 8, 2, 6, 30),
        replacing: true);
    await $.pumpAndSettle();

    expect($('7h 45m').exists, true);
    expect($('goal 8h').exists, true);
    expect($('97%').exists, true);
    expect($('Edit').exists, true);
  });

  patrolTest('editing sleep REPLACES the night rather than merging it',
      ($) async {
    await openToday($);
    final c = Get.find<LifestyleController>();
    await c.setSleep(7.75,
        start: DateTime(2026, 8, 1, 22, 45),
        end: DateTime(2026, 8, 2, 6, 30),
        replacing: true);
    await $.pumpAndSettle();
    expect($('7h 45m').exists, true);

    await c.setSleep(7,
        start: DateTime(2026, 8, 1, 23, 30),
        end: DateTime(2026, 8, 2, 6, 30),
        replacing: true);
    await $.pumpAndSettle();

    expect($('7h 0m').exists || $('7h').exists, true);
    expect(c.sleepHours, closeTo(7.0, 0.01),
        reason: 'the union bug would leave this at 7.75');
    expect(store.events.values.where((e) => e.deleted).length, 1,
        reason: 'append-only: the original is withdrawn, never erased');
  });

  // ══ SUPPLEMENTS ══════════════════════════════════════════════════════════

  patrolTest('supplements complete and count down', ($) async {
    await openToday($);
    await $('SUPPLEMENTS').scrollTo();
    expect($('0 completed · 2 remaining').exists, true);

    await $('Creatine · 5 g').tap();
    await $.pumpAndSettle();
    expect($('1 completed · 1 remaining').exists, true);

    await $('Vitamin D3').tap();
    await $.pumpAndSettle();
    expect($('All 2 completed').exists, true);
    expect(Get.find<LifestyleController>().supplementCompletion, 1.0);
  });

  // ══ HISTORY ══════════════════════════════════════════════════════════════

  patrolTest('History shows today, with the coach\'s goals applied', ($) async {
    // Today, as the SERVER would derive and roll it up from these events.
    await openToday($);
    for (var i = 0; i < 10; i++) {
      await $.tester.tap(find.bySemanticsLabel('Add a glass of water'));
      await $.pumpAndSettle();
    }
    final c = Get.find<LifestyleController>();
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);

    Get.put(LifestyleHistoryController(
      rollups: _Rollups([
        RollupDay(date: day, waterMl: c.waterMl.toDouble()),
      ]),
      clientDoc: clientDoc,
      now: today,
    ));
    await $.pumpWidgetAndSettle(
      GetMaterialApp(
        theme: AppTheme.dark,
        home: const LifestyleHistoryScreen(),
      ),
    );

    expect($('Your history').exists, true);
    expect($('Water').exists, true);
    // 2 500 ml against a 2 500 ml goal — a hit, so today is a streak of one
    // and the goal-hit rate is 100%. Both were dead before the targets
    // reached this screen.
    expect($('2.5L').exists, true);
    expect($('100%').exists, true);
    expect($('1').exists, true);
  });

  patrolTest('sleep reaches History as HOURS, from the server\'s minutes',
      ($) async {
    // 🔴 The parser read `metrics.sleepHours`, a key the backend never writes
    // (`deriveLifestyleMetrics` emits `sleepMinutes`), so a member's sleep
    // history was permanently empty while their coach saw it correctly.
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final parsed = MemberRollupService.daysFrom({
      'tracks': {
        'lifestyle': {
          'days': {
            dayKey(day): {
              'metrics': {'sleepMinutes': 465},
            },
          },
        },
      },
    });
    expect(parsed.single.sleepHours, closeTo(7.75, 0.001));

    Get.reset();
    Get.put(LifestyleHistoryController(
      rollups: _Rollups(parsed),
      clientDoc: clientDoc,
      now: today,
    ));
    await $.pumpWidgetAndSettle(
      GetMaterialApp(
        theme: AppTheme.dark,
        home: const LifestyleHistoryScreen(),
      ),
    );
    await $.tester.tap(find.text('Sleep'));
    await $.pumpAndSettle();
    expect($('7.8h').exists, true, reason: 'not "No sleep history yet"');
  });

  // ══ ADVERSARIAL ══════════════════════════════════════════════════════════

  patrolTest('RAPID tapping records every glass and loses none', ($) async {
    await openToday($);
    final c = Get.find<LifestyleController>();
    // Fire the taps WITHOUT settling between them — on a device these land
    // inside one frame. With the goal cap gone (LS-03) the invariant is no
    // longer "never overshoots"; it is that a burst of N taps is N drinks,
    // which is what the per-action event id guarantees.
    final add = find.bySemanticsLabel('Add a glass of water');
    for (var i = 0; i < 6; i++) {
      await $.tester.tap(add);
    }
    await $.pumpAndSettle();
    expect(c.waterGlasses, 6, reason: 'six taps are six glasses');
    expect(c.waterGlasses, store.live.length,
        reason: 'the count and the record agree exactly');

    // And the same burst downward.
    final remove = find.bySemanticsLabel('Remove a glass of water');
    for (var i = 0; i < 20; i++) {
      await $.tester.tap(remove);
    }
    await $.pumpAndSettle();
    expect(c.waterGlasses, 0, reason: 'floors at zero, never negative');
    expect(c.waterMl, 0);
  });

  patrolTest('the SAME flow repeated many times stays exact', ($) async {
    await openToday($);
    final c = Get.find<LifestyleController>();
    for (var cycle = 0; cycle < 5; cycle++) {
      for (var i = 0; i < 3; i++) {
        await $.tester.tap(find.bySemanticsLabel('Add a glass of water'));
        await $.pumpAndSettle();
      }
      for (var i = 0; i < 3; i++) {
        await $.tester.tap(find.bySemanticsLabel('Remove a glass of water'));
        await $.pumpAndSettle();
      }
      expect(c.waterGlasses, 0, reason: 'cycle $cycle left residue');
    }
    // Append-only: 15 drinks recorded, 15 withdrawn, nothing erased.
    expect(store.events.length, 15);
    expect(store.live, isEmpty);
  });

  patrolTest('a REJECTED write is reported and changes nothing', ($) async {
    await openToday($);
    final c = Get.find<LifestyleController>();
    await $.tester.tap(find.bySemanticsLabel('Add a glass of water'));
    await $.pumpAndSettle();
    expect(c.waterGlasses, 1);

    c.hasError.value = true;
    await $.pumpAndSettle();
    expect($(RegExp("That didn't save")).exists, true);
    expect(c.waterGlasses, 1, reason: 'a failure never invents or loses water');
  });

  patrolTest('a QUEUED (offline) write says saved-on-device, not failed',
      ($) async {
    await openToday($);
    final c = Get.find<LifestyleController>();
    c.isOffline.value = true;
    await $.pumpAndSettle();
    expect($(RegExp('Saved on this device')).exists, true);
    expect($(RegExp("That didn't save")).exists, false,
        reason: 'queued is not a failure');
  });

  patrolTest('a coach target change lands live, with the screen open',
      ($) async {
    await openToday($);
    final c = Get.find<LifestyleController>();
    expect($('of 10 glasses').exists, true);

    Get.find<MemberController>().client.value = {
      'lifestyleTargets': {
        'waterTargetMl': 3000,
        'glassSizeMl': 500,
        'stepsTarget': 12000,
        'sleepHoursTarget': 7,
      },
      'supplementPlan': stack,
    };
    await $.pumpAndSettle();

    expect($('of 6 glasses').exists, true, reason: '3 000 ml at 500 ml a glass');
    expect($('0 ml / 3,000 ml').exists, true);
    expect(c.glassSizeMl, 500);
  });

  patrolTest('a coach REMOVING the stack empties the checklist live', ($) async {
    await openToday($);
    await $('SUPPLEMENTS').scrollTo();
    expect($('Creatine · 5 g').exists, true);

    Get.find<MemberController>().client.value = {
      'lifestyleTargets': {'waterTargetMl': 2500, 'glassSizeMl': 250},
      'supplementPlan': const <Map<String, dynamic>>[],
    };
    await $.pumpAndSettle();
    await $('SUPPLEMENTS').scrollTo();

    expect($('Creatine · 5 g').exists, false);
    expect($("Your coach hasn't added supplements yet.").exists, true);
  });

  // ══ PERSISTENCE ══════════════════════════════════════════════════════════

  patrolTest('a RESTART reads back everything that was logged', ($) async {
    await openToday($);
    for (var i = 0; i < 4; i++) {
      await $.tester.tap(find.bySemanticsLabel('Add a glass of water'));
      await $.pumpAndSettle();
    }
    await $.tester.enterText(find.byType(TextField), '8200');
    await $.pumpAndSettle();
    await $.tester.tap(find.bySemanticsLabel('Save').first);
    await $.pumpAndSettle();
    await Get.find<LifestyleController>().setSleep(7.5,
        start: DateTime(2026, 8, 1, 23),
        end: DateTime(2026, 8, 2, 6, 30),
        replacing: true);
    await $('Creatine · 5 g').scrollTo();
    await $('Creatine · 5 g').tap();
    await $.pumpAndSettle();

    // Tear the whole app down and build it again over the same store.
    await $.pumpWidgetAndSettle(const SizedBox.shrink());
    await openToday($);

    expect($('1,000 ml / 2,500 ml').exists, true);
    await $('8,200').scrollTo();
    expect($('8,200').exists, true);
    await $('7h 30m').scrollTo();
    expect($('7h 30m').exists, true);
    await $('1 completed · 1 remaining').scrollTo();
    expect($('1 completed · 1 remaining').exists, true);

    final c = Get.find<LifestyleController>();
    expect(c.waterGlasses, 4);
    expect(c.steps, 8200);
    expect(c.sleepHours, closeTo(7.5, 0.01));
    expect(c.supplementCompletion, 0.5);
  });
}
