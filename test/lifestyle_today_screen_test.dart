import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena/controllers/lifestyle_controller.dart';
import 'package:alphaserena/controllers/member_controller.dart';
import 'package:alphaserena/core/domain/coaching_event.dart';
import 'package:alphaserena/core/models/lifestyle_log_model.dart';
import 'package:alphaserena/core/models/lifestyle_targets.dart';
import 'package:alphaserena/core/services/coaching_event_writer.dart';
import 'package:alphaserena/core/services/lifestyle_event_service.dart';
import 'package:alphaserena/core/services/lifestyle_log_service.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/lifestyle_today_screen.dart';

/// TODAY'S TARGETS, rendered against a REAL controller over a fake event
/// store — so a tap goes through the same derivation the device runs and the
/// screen re-renders from the stream, exactly as it does in production.
///
/// The previous screen had no widget test at all.
class _Member extends MemberController {
  /// A NULL doc is the real unlinked shape: first login, a claim still in
  /// flight, or a failed client-doc read.
  _Member(Map<String, dynamic>? doc) {
    client.value = doc;
  }

  // Deliberately does NOT call super: the real onInit starts the auth and
  // Firestore listeners this fixture exists to avoid.
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Writer extends CoachingEventWriter {
  _Writer() : super(collection: 'x');
}

class _Log extends LifestyleLogService {
  /// Mutable so a test can land linkage mid-session, which is what the member
  /// actually experiences while `claimClientAccount` resolves.
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

class _Events extends LifestyleEventService {
  _Events([List<CoachingEvent> seed = const []])
      : super(writer: _Writer(), legacy: _Log()) {
    for (final e in seed) {
      store[e.eventId] = e;
    }
  }

  final Map<String, CoachingEvent> store = {};
  final _stream = StreamController<List<CoachingEvent>>.broadcast();
  int seq = 0;

  @override
  bool get canLog => true;

  void _emit() => _stream.add(store.values.toList());

  @override
  Stream<List<CoachingEvent>> watchDay(String dateKey) async* {
    yield store.values.toList();
    yield* _stream.stream;
  }

  Future<EventWriteResult> _put(String type, Map<String, dynamic> payload) async {
    final id = '${type}_${seq++}';
    store[id] = CoachingEvent(
        eventId: id,
        type: type,
        at: DateTime(2026, 8, 2, 12).add(Duration(minutes: seq)),
        payload: payload);
    _emit();
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
    final e = store[eventId];
    if (e != null) store[eventId] = e.copyWith(deleted: true);
    _emit();
    return EventWriteResult.synced;
  }

  @override
  Future<void> mirrorLegacyTotals({
    required String dateKey,
    required List<CoachingEvent> events,
    List<SupplementPlanItem> stack = const [],
  }) async {}
}

void main() {
  late _Events events;
  late LifestyleController controller;

  CoachingEvent ev(String id, String type, Map<String, dynamic> payload) =>
      CoachingEvent(
          eventId: id, type: type, at: DateTime(2026, 8, 2, 7), payload: payload);

  Future<void> open(
    WidgetTester tester, {
    List<CoachingEvent> seed = const [],
    List<Map<String, dynamic>> stack = const [],
    double? waterTargetMl = 2500,
    double glassSizeMl = 250,
    int? stepsTarget = 10000,
    double? sleepHoursTarget = 8,
    Size size = const Size(390, 1800),
    double textScale = 1.0,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    events = _Events(seed);
    final member = _Member({
      'lifestyleTargets': {
        'waterTargetMl': ?waterTargetMl,
        'glassSizeMl': glassSizeMl,
        'stepsTarget': ?stepsTarget,
        'sleepHoursTarget': ?sleepHoursTarget,
      },
      'supplementPlan': stack,
    });
    Get.put<MemberController>(member);
    controller = Get.put(LifestyleController(
      service: _Log(),
      events: events,
      member: member,
    ));

    await tester.pumpWidget(MaterialApp(
      theme: theme ?? AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const LifestyleTodayScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    // Past the controller's projection debounce, so the initial emission
    // never leaves a timer pending at the end of the test.
    await tester.pump(const Duration(seconds: 1));
  }

  /// Pumps animations to rest AND past the controller's legacy-projection
  /// debounce, so no timer outlives the test.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
  }

  tearDown(Get.reset);

  // ══ THE SCREEN ═══════════════════════════════════════════════════════════

  group('the screen', () {
    testWidgets('is titled Today\'s Targets and offers History', (tester) async {
      await open(tester);
      expect(find.text("Today's Targets"), findsOneWidget);
      expect(find.text('Today'), findsNothing);
      expect(find.text('History'), findsOneWidget);
    });

    testWidgets('shows every metric section', (tester) async {
      await open(tester);
      for (final label in ['WATER', 'STEPS', 'SLEEP', 'SUPPLEMENTS']) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });

  // ══ LINKAGE ══════════════════════════════════════════════════════════════
  //
  // LS-01. The body is one `Obx`, and its FIRST statement branches on
  // `canLog`. That guard used to reach `MemberController.linkedClientId` — a
  // plain, non-reactive field — and `&&` short-circuits, so for an unlinked
  // member the closure read no observable at all and GetX threw by design.
  // The member got a framework error where the join prompt should be, and no
  // rebuild ever came when their linkage landed.
  //
  // Every other fake in this file hardcodes `canLog => true`, which is exactly
  // why the false branch had never once been executed.
  group('an unlinked member', () {
    late _Log log;

    Future<_Member> openUnlinked(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      log = _Log()..linked = false;
      final member = _Member(null);
      Get.put<MemberController>(member);
      Get.put(LifestyleController(
        service: log,
        events: _Events(),
        member: member,
      ));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: const LifestyleTodayScreen(),
      ));
      await tester.pump();
      return member;
    }

    testWidgets('sees the join prompt, not a framework error', (tester) async {
      await openUnlinked(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Join a coach'), findsOneWidget);
    });

    testWidgets('the prompt is replaced the moment linkage lands',
        (tester) async {
      final member = await openUnlinked(tester);
      expect(find.textContaining('Join a coach'), findsOneWidget);

      // `claimClientAccount` resolves: the member is linked and their client
      // doc arrives. The screen must rebuild off that alone — which it can
      // only do if the guard subscribed the Obx while it was still false.
      log.linked = true;
      member.client.value = {
        'lifestyleTargets': {'glassSizeMl': 250, 'waterTargetMl': 2500},
        'supplementPlan': const [],
      };
      member.isLinked.value = true;
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Join a coach'), findsNothing);
      expect(find.text('WATER'), findsOneWidget);
    });
  });

  // ══ WATER ════════════════════════════════════════════════════════════════

  group('water', () {
    testWidgets('+ adds exactly one glass and the ring follows', (tester) async {
      await open(tester);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('of 10 glasses'), findsOneWidget);
      expect(find.text('0 ml / 2,500 ml'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Add a glass of water'));
      await settle(tester);

      expect(find.text('1'), findsOneWidget);
      expect(find.text('250 ml / 2,500 ml'), findsOneWidget);
      expect(controller.waterCompletion, closeTo(0.1, 0.001));
    });

    testWidgets('− removes exactly one glass', (tester) async {
      await open(tester);
      final add = find.bySemanticsLabel('Add a glass of water');
      await tester.tap(add);
      await settle(tester);
      await tester.tap(add);
      await settle(tester);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Remove a glass of water'));
      await settle(tester);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('250 ml / 2,500 ml'), findsOneWidget);
    });

    testWidgets('the millilitres use the COACH\'S glass size', (tester) async {
      await open(tester, glassSizeMl: 400, waterTargetMl: 2000);
      expect(find.text('of 5 glasses'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Add a glass of water'));
      await settle(tester);
      expect(find.text('400 ml / 2,000 ml'), findsOneWidget);
    });

    testWidgets('reaching the goal says so, and does NOT stop the counter',
        (tester) async {
      // LS-03. This test used to assert the opposite — that a third tap
      // "changes nothing, the counter is a goal not a tally" — and so it
      // certified the defect: a member who drank past their goal could not
      // record it, in their own history or their coach's.
      await open(tester, waterTargetMl: 500);
      final add = find.bySemanticsLabel('Add a glass of water');
      await tester.tap(add);
      await settle(tester);
      await tester.tap(add);
      await settle(tester);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Goal reached — nice work.'), findsOneWidget);

      // A third glass is still a glass the member drank.
      await tester.tap(add);
      await settle(tester);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('of 2 glasses'), findsOneWidget);
      expect(events.store.length, 3);
      // Reaching the goal is still celebrated; it just is not a wall.
      expect(find.text('Goal reached — nice work.'), findsOneWidget);
    });

    testWidgets('− is inert on an empty day', (tester) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('Remove a glass of water'));
      await settle(tester);
      expect(find.text('0'), findsOneWidget);
      expect(events.store, isEmpty);
    });
  });

  // ══ STEPS ════════════════════════════════════════════════════════════════

  group('steps', () {
    testWidgets('Save records the entry, then the action becomes Edit',
        (tester) async {
      await open(tester);
      expect(find.text('Save'), findsWidgets);
      await tester.enterText(find.byType(TextField), '6500');
      await tester.tap(find.bySemanticsLabel('Save').first);
      await settle(tester);

      expect(find.text('6,500'), findsOneWidget);
      expect(find.text('65%'), findsWidgets,
          reason: 'the card and the day summary both show it');
      expect(find.bySemanticsLabel('Edit'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('Edit reloads the previous value and updates the same day',
        (tester) async {
      await open(tester, seed: [
        ev('s1', LifestyleEventType.stepsSample, {'count': 6500}),
      ]);
      expect(find.text('6,500'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Edit'));
      await settle(tester);
      // The field opens carrying what was saved — never blank.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '6500',
      );

      await tester.enterText(find.byType(TextField), '9000');
      await tester.tap(find.bySemanticsLabel('Save').first);
      await settle(tester);

      expect(find.text('9,000'), findsOneWidget);
      expect(controller.steps, 9000, reason: 'a correction, never 15 500');
    });

    testWidgets('an impossible entry is refused with a reason', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), '500000');
      await tester.tap(find.bySemanticsLabel('Save').first);
      await settle(tester);
      expect(find.textContaining('too high'), findsOneWidget);
      expect(controller.steps, isNull);
    });

    testWidgets('an empty save asks for a value rather than doing nothing',
        (tester) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('Save').first);
      await settle(tester);
      expect(find.text('Enter your step count.'), findsOneWidget);
    });
  });

  // ══ SLEEP ════════════════════════════════════════════════════════════════

  group('sleep', () {
    testWidgets('two times derive the duration', (tester) async {
      await open(tester);
      expect(find.text('Sleep'), findsOneWidget);
      expect(find.text('Wake'), findsOneWidget);
      expect(find.text('Set time'), findsNWidgets(2));
      expect(
        find.text('Pick both times to see your sleep duration.'),
        findsOneWidget,
      );
    });

    testWidgets('a saved night shows its duration, its period and Edit',
        (tester) async {
      await open(tester, seed: [
        ev('sl', LifestyleEventType.sleep, {
          'start': DateTime(2026, 8, 1, 22, 45).millisecondsSinceEpoch,
          'end': DateTime(2026, 8, 2, 6, 30).millisecondsSinceEpoch,
        }),
      ]);
      expect(find.text('7h 45m'), findsOneWidget);
      expect(find.text('goal 8h'), findsOneWidget);
      expect(find.text('97%'), findsWidgets);
      expect(find.textContaining('→'), findsOneWidget);
      expect(find.bySemanticsLabel('Edit'), findsOneWidget);
    });

    testWidgets('Edit reloads the saved times into the pickers', (tester) async {
      await open(tester, seed: [
        ev('sl', LifestyleEventType.sleep, {
          'start': DateTime(2026, 8, 1, 22, 45).millisecondsSinceEpoch,
          'end': DateTime(2026, 8, 2, 6, 30).millisecondsSinceEpoch,
        }),
      ]);
      await tester.tap(find.bySemanticsLabel('Edit'));
      await settle(tester);
      expect(find.textContaining('10:45'), findsOneWidget);
      expect(find.textContaining('6:30'), findsOneWidget);
      expect(find.text('Duration 7h 45m'), findsOneWidget);
      expect(find.text('Set time'), findsNothing);
    });

    testWidgets('two EQUAL times are refused, never saved as a 24-hour night',
        (tester) async {
      // LS-04. `_minutes` computed `w > b ? w - b : 1440 - b + w`, which for
      // w == b yields 1440 — never 0. So the `span == 0` guard and the message
      // it protected were UNREACHABLE, and two equal times silently recorded a
      // TWENTY-FOUR HOUR night: accepted by validation (24 <= 24), derived by
      // the server (1440 is not > 1440), rolled up, and shown to the coach.
      //
      // The seed here IS that corrupt state — a 24 h period, whose two
      // instants share a time of day — so Edit reloads two equal times and
      // this proves the member can no longer re-commit it.
      await open(tester, seed: [
        ev('sl', LifestyleEventType.sleep, {
          'start': DateTime(2026, 8, 1, 22, 30).millisecondsSinceEpoch,
          'end': DateTime(2026, 8, 2, 22, 30).millisecondsSinceEpoch,
        }),
      ]);
      await tester.tap(find.bySemanticsLabel('Edit'));
      await settle(tester);
      // Both pickers now hold 10:30 PM.
      expect(find.textContaining('10:30'), findsNWidgets(2));

      await tester.tap(find.bySemanticsLabel('Save').last);
      await settle(tester);

      expect(find.textContaining("can't be the same"), findsOneWidget);
      expect(events.store.length, 1,
          reason: 'the refused save must write nothing at all');
      expect(events.store.values.single.deleted, isFalse,
          reason: 'and must not withdraw what was already there');
    });

    testWidgets('saving with only one time set asks for the other',
        (tester) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('Save').last);
      await settle(tester);
      expect(
        find.text('Set both a sleep time and a wake time.'),
        findsOneWidget,
      );
    });
  });

  // ══ SUPPLEMENTS ══════════════════════════════════════════════════════════

  group('supplements', () {
    const stack = [
      {'id': 'a', 'name': 'Creatine', 'dose': '5 g'},
      {'id': 'b', 'name': 'Vitamin D3'},
      {'id': 'c', 'name': 'Omega 3'},
    ];

    testWidgets('shows the coach\'s stack with completed and remaining',
        (tester) async {
      await open(tester, stack: stack);
      expect(find.text('Creatine · 5 g'), findsOneWidget);
      expect(find.text('0 completed · 3 remaining'), findsOneWidget);
      expect(find.text('0/3'), findsOneWidget);
    });

    testWidgets('marking one complete updates the counts', (tester) async {
      await open(tester, stack: stack);
      await tester.tap(find.bySemanticsLabel('Creatine · 5 g'));
      await settle(tester);
      expect(find.text('1 completed · 2 remaining'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
    });

    testWidgets('completing every item says so', (tester) async {
      await open(tester, stack: stack);
      for (final label in ['Creatine · 5 g', 'Vitamin D3', 'Omega 3']) {
        await tester.tap(find.bySemanticsLabel(label));
        await settle(tester);
      }
      expect(find.text('All 3 completed'), findsOneWidget);
    });

    testWidgets('no prescribed stack shows the existing empty state',
        (tester) async {
      await open(tester);
      expect(find.text("Your coach hasn't added supplements yet."),
          findsOneWidget);
      expect(find.text('0/3'), findsNothing);
    });
  });

  // ══ HONEST STATES ════════════════════════════════════════════════════════

  group('honest states', () {
    testWidgets('an unlogged metric shows a dash, never a zero',
        (tester) async {
      await open(tester);
      // Steps, sleep AND the day summary: nothing logged is never 0%.
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('0%'), findsNothing);
    });

    testWidgets('a percentage is never shown against an unstated goal',
        (tester) async {
      // Completion falls back to the platform default, so the goal it scores
      // against has to be named — "no goal set" beside a live percentage was
      // the card contradicting itself.
      await open(tester, stepsTarget: null, sleepHoursTarget: null);
      expect(find.text('no goal set'), findsNothing);
      expect(find.text('goal 8,000 · suggested'), findsOneWidget);
      expect(find.text('goal 8h · suggested'), findsOneWidget);
    });

    testWidgets('a suggested water goal is labelled as suggested',
        (tester) async {
      await open(tester, waterTargetMl: null);
      expect(find.text('suggested goal'), findsOneWidget);
      expect(find.text('of 10 glasses'), findsOneWidget);
    });

    testWidgets('a failed write surfaces the banner', (tester) async {
      await open(tester);
      controller.hasError.value = true;
      await settle(tester);
      expect(find.textContaining("That didn't save"), findsOneWidget);
    });
  });

  // ══ RESPONSIVE ═══════════════════════════════════════════════════════════

  group('responsive + themes', () {
    testWidgets('320dp at 1.8x accessibility text does not overflow',
        (tester) async {
      await open(tester,
          stack: const [
            {'id': 'a', 'name': 'Creatine'},
          ],
          size: const Size(320, 3400),
          textScale: 1.8);
      expect(tester.takeException(), isNull);
      expect(find.text('WATER'), findsOneWidget);
      // The action moves to its own row rather than crushing the field.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('tablet, landscape and light mode render cleanly',
        (tester) async {
      await open(tester, size: const Size(1024, 1600));
      expect(tester.takeException(), isNull);
      await open(tester, size: const Size(900, 500));
      expect(tester.takeException(), isNull);
      await open(tester, theme: AppTheme.light);
      expect(tester.takeException(), isNull);
      expect(find.text('WATER'), findsOneWidget);
    });
  });
}
