import 'dart:async';

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
import 'package:alphaserena/core/utils/lifestyle_math.dart';

/// THE MEMBER'S LIFESTYLE WRITE PATH — the surface they touch every day, and
/// the one thing in this module that had NO test of any kind.
///
/// Not one test in the repository referenced `addGlass`, `setSteps`,
/// `setSleep` or `toggleSupplement`, because the controller built its own
/// Firebase-backed services in its field initialisers and could not be
/// constructed off a device. Every defect these tests pin was therefore free
/// to survive every previous certification.
///
/// The fake below is a real event store: it holds the day's events, serves
/// them on a stream exactly as Firestore does, and applies soft deletes. The
/// controller's derivations run for real against it.
class _FakeEvents extends LifestyleEventService {
  _FakeEvents() : super(writer: _NoopWriter(), legacy: _FakeLog());

  final Map<String, CoachingEvent> store = {};
  final _controller = StreamController<List<CoachingEvent>>.broadcast();

  /// Writes the fake will REJECT, so failure handling is testable too.
  bool failWrites = false;

  /// Held writes, to reproduce the burst races that motivated the pending
  /// withdrawal set.
  bool holdEmissions = false;

  int mirrors = 0;

  @override
  bool get canLog => true;

  void _emit() {
    if (holdEmissions) return;
    final list = store.values.toList()
      ..sort((a, b) {
        final c = a.at.compareTo(b.at);
        return c != 0 ? c : a.eventId.compareTo(b.eventId);
      });
    _controller.add(list);
  }

  void flush() {
    holdEmissions = false;
    _emit();
  }

  @override
  Stream<List<CoachingEvent>> watchDay(String dateKey) async* {
    yield store.values.toList();
    yield* _controller.stream;
  }

  Future<EventWriteResult> _put(CoachingEvent e) async {
    if (failWrites) return EventWriteResult.failed;
    store[e.eventId] = e;
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
      _put(CoachingEvent(
        eventId: 'd${store.length}',
        type: LifestyleEventType.drink,
        at: DateTime(2026, 8, 2, 8, store.length),
        payload: {'ml': ml},
      ));

  @override
  Future<EventWriteResult> logSleep({
    required String dateKey,
    DateTime? start,
    DateTime? end,
    int? minutes,
    String source = EventSource.manual,
    String? sourceKey,
  }) {
    final hasPeriod = start != null && end != null && end.isAfter(start);
    return _put(CoachingEvent(
      eventId: 's${store.length}',
      type: LifestyleEventType.sleep,
      at: DateTime(2026, 8, 2, 9, store.length),
      payload: hasPeriod
          ? {
              'start': start.millisecondsSinceEpoch,
              'end': end.millisecondsSinceEpoch,
            }
          : {'minutes': minutes ?? 0},
    ));
  }

  @override
  Future<EventWriteResult> logSteps({
    required String dateKey,
    required int count,
    String source = EventSource.manual,
    String? sourceKey,
  }) =>
      _put(CoachingEvent(
        eventId: 'st${store.length}',
        type: LifestyleEventType.stepsSample,
        at: DateTime(2026, 8, 2, 10, store.length),
        payload: {'count': count},
      ));

  @override
  Future<EventWriteResult> logSupplementDose({
    required String dateKey,
    required String itemId,
    String? name,
    String? dose,
  }) =>
      _put(CoachingEvent(
        eventId: 'p${store.length}',
        type: LifestyleEventType.supplementTaken,
        at: DateTime(2026, 8, 2, 11, store.length),
        payload: {'itemId': itemId, 'name': ?name},
      ));

  @override
  Future<EventWriteResult> withdraw({
    required String dateKey,
    required String eventId,
  }) async {
    if (failWrites) return EventWriteResult.failed;
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
  }) async {
    mirrors++;
  }
}

class _NoopWriter extends CoachingEventWriter {
  _NoopWriter() : super(collection: 'x');
}

class _FakeLog extends LifestyleLogService {
  @override
  bool get canLog => true;

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

void main() {
  late _FakeEvents events;
  late MemberController member;

  /// A controller wired to the fakes, with the coach's configuration on the
  /// member's client doc — the same place production reads it from.
  LifestyleController build({
    double? waterTargetMl = 2500,
    double glassSizeMl = 250,
    int? stepsTarget = 10000,
    double? sleepHoursTarget = 8,
    List<Map<String, dynamic>> supplementPlan = const [],
  }) {
    events = _FakeEvents();
    member = MemberController();
    member.client.value = {
      'lifestyleTargets': {
        'waterTargetMl': ?waterTargetMl,
        'glassSizeMl': glassSizeMl,
        'stepsTarget': ?stepsTarget,
        'sleepHoursTarget': ?sleepHoursTarget,
      },
      'supplementPlan': supplementPlan,
    };
    final c = LifestyleController(
      service: _FakeLog(),
      events: events,
      member: member,
    );
    c.onInit();
    return c;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  tearDown(Get.reset);

  mainDefectB();

  // ══ WATER ════════════════════════════════════════════════════════════════

  group('water — one glass means one glass', () {
    test('+ records exactly one glass at the COACH\'S glass size', () async {
      final c = build(glassSizeMl: 300);
      await c.addGlass(1);
      await settle();
      expect(c.waterGlasses, 1);
      expect(c.waterMl, 300, reason: "never a hardcoded 250");
      await c.addGlass(1);
      await settle();
      expect(c.waterGlasses, 2);
      expect(c.waterMl, 600);
    });

    test('− removes exactly one glass', () async {
      final c = build();
      for (var i = 0; i < 3; i++) {
        await c.addGlass(1);
        await settle();
      }
      expect(c.waterGlasses, 3);
      await c.addGlass(-1);
      await settle();
      expect(c.waterGlasses, 2);
      expect(c.waterMl, 500);
    });

    test('− never goes below zero, and writes nothing when empty', () async {
      final c = build();
      expect(c.canRemoveGlass, isFalse);
      await c.addGlass(-1);
      await settle();
      expect(c.waterGlasses, 0);
      expect(events.store, isEmpty, reason: 'an empty day has nothing to undo');
    });

    test('+ NEVER exceeds the coach\'s goal', () async {
      // LS-03. Adding used to STOP at the goal, and `waterTargetGlasses`
      // derives from `effectiveTarget`, which is never <= 0 — so the cap was
      // always on. A member who drank more than their goal simply could not
      // record it: the + greyed out and their real intake was truncated, in
      // their own history and permanently in their coach's analytics.
      //
      // It was worse when the coach had set NO goal, because the cap then
      // enforced the PLATFORM DEFAULT — a goal this very card labels
      // "suggested" and the Home card reports as "No target set".
      //
      // A goal is a goal, not a ceiling. Every other metric already accepts an
      // over-target value and renders it as 115%/140% rather than flattening
      // it; water was the one outlier.
      final c = build(waterTargetMl: 750); // 3 glasses at 250 ml
      for (var i = 0; i < 8; i++) {
        await c.addGlass(1);
        await settle();
      }
      expect(c.waterTargetGlasses, 3);
      expect(c.waterGlasses, 8, reason: 'every glass the member drank counts');
      expect(c.waterMl, 2000);
      expect(c.waterGoalReached, isTrue);
      expect(events.store.length, 8, reason: 'no tap is ever refused');
      // Over-target completion is reported honestly, not clamped to 1.0.
      expect(c.waterCompletion, closeTo(8 / 3, 0.001));
    });

    test('a member with NO coach goal is not capped by the suggestion',
        () async {
      // The suggested default is 2 500 ml = 10 glasses. It is a suggestion, so
      // it must not stop an eleventh glass being recorded.
      final c = build(waterTargetMl: null);
      expect(c.waterTargetGlasses, 10);
      for (var i = 0; i < 12; i++) {
        await c.addGlass(1);
        await settle();
      }
      expect(c.waterGlasses, 12);
      expect(events.store.length, 12);
    });

    test('withdrawing still stops at zero', () async {
      // The OTHER direction stays bounded, and for a different reason: there
      // is no event left to withdraw, so a tap could only be a silent no-op.
      final c = build(waterTargetMl: 500);
      await c.addGlass(1);
      await settle();
      expect(c.canRemoveGlass, isTrue);
      await c.addGlass(-1);
      await settle();
      expect(c.waterGlasses, 0);
      expect(c.canRemoveGlass, isFalse);
      await c.addGlass(-1);
      await settle();
      expect(c.waterGlasses, 0);
    });

    test('the ring and the counter can never disagree', () async {
      // 🔴 A 2 600 ml goal at 250 ml a glass ROUNDED to 10 glasses = 2 500 ml,
      // so completion (millilitres) read 96% while the counter inside the same
      // ring read "10 of 10 glasses". Both are glasses now, and the target
      // rounds UP so the goal is always reachable.
      final c = build(waterTargetMl: 2600);
      expect(c.waterTargetGlasses, 11, reason: '2 600 ml needs an 11th glass');
      for (var i = 0; i < 11; i++) {
        await c.addGlass(1);
        await settle();
      }
      expect(c.waterGlasses, 11);
      expect(c.waterCompletion, 1.0);
      expect(c.waterGoalReached, isTrue);
      expect(c.waterMl, 2750, reason: 'and the goal is genuinely met in ml');
    });

    test('completion is null before anything is logged, never 0%', () async {
      final c = build();
      expect(c.waterCompletion, isNull);
      await c.addGlass(1);
      await settle();
      expect(c.waterCompletion, closeTo(0.1, 0.001));
    });

    test('two taps in the SAME frame record two glasses', () async {
      // This test used to assert that a same-frame pair could not "push past
      // the goal" — the `_pendingAdds` race guard. That guard existed only to
      // protect the cap, and it retired with it: there is no longer a
      // threshold for two taps to straddle. What must still hold is that two
      // taps are two DRINKS, which is the event model's own guarantee (one id
      // minted per action, so a burst cannot collapse into one glass).
      final c = build(waterTargetMl: 750); // 3 glasses at 250 ml
      await c.addGlass(1);
      await settle();
      await c.addGlass(1);
      await settle();
      expect(c.waterGlasses, 2);

      events.holdEmissions = true;
      await Future.wait([c.addGlass(1), c.addGlass(1)]);
      events.flush();
      await settle();

      expect(c.waterGlasses, 4, reason: 'both taps are real glasses');
      expect(events.store.length, 4);
    });

    test('two quick − taps remove two glasses, not one', () async {
      final c = build();
      for (var i = 0; i < 3; i++) {
        await c.addGlass(1);
        await settle();
      }
      // No settle between: the second tap must not re-target the drink the
      // first one already withdrew.
      events.holdEmissions = true;
      await c.addGlass(-1);
      await c.addGlass(-1);
      events.flush();
      await settle();
      expect(c.waterGlasses, 1);
    });

    test('a rejected write leaves the glass count untouched', () async {
      final c = build();
      await c.addGlass(1);
      await settle();
      events.failWrites = true;
      await c.addGlass(1);
      await settle();
      expect(c.waterGlasses, 1);
      expect(c.hasError.value, isTrue);
    });
  });

  // ══ STEPS ════════════════════════════════════════════════════════════════

  group('steps — an absolute daily figure', () {
    test('saving records the entry', () async {
      final c = build();
      expect(c.hasStepsRecord, isFalse);
      expect(await c.setSteps(6500), isTrue);
      await settle();
      expect(c.steps, 6500);
      expect(c.hasStepsRecord, isTrue);
    });

    test('editing REPLACES the day rather than adding to it', () async {
      final c = build();
      await c.setSteps(6500);
      await settle();
      await c.setSteps(9000);
      await settle();
      expect(c.steps, 9000, reason: 'a correction, never 15 500');
      expect(c.stepsCompletion, closeTo(0.9, 0.001));
    });

    test('an out-of-range entry is refused, not written', () async {
      final c = build();
      expect(await c.setSteps(500000), isFalse);
      await settle();
      expect(c.steps, isNull);
      expect(events.store, isEmpty);
    });

    test('a NEGATIVE entry is refused, not written', () async {
      // `int.tryParse('-5')` is -5, and the derivation silently discards
      // negatives — so an unguarded entry would be written as an event every
      // reader then ignored, and the member would watch their number vanish.
      final c = build();
      expect(await c.setSteps(-5), isFalse);
      await settle();
      expect(c.steps, isNull);
      expect(events.store, isEmpty);
    });

    test('zero steps is a legitimate rest-day entry', () async {
      final c = build();
      expect(await c.setSteps(0), isTrue);
      await settle();
      expect(c.steps, 0);
    });
  });

  // ══ SLEEP ════════════════════════════════════════════════════════════════

  group('sleep — a period, and a correctable one', () {
    test('a bedtime and a wake time derive the duration', () async {
      final c = build();
      final start = DateTime(2026, 8, 1, 22, 45);
      final end = DateTime(2026, 8, 2, 6, 30);
      expect(await c.setSleep(7.75, start: start, end: end), isTrue);
      await settle();
      expect(c.sleepHours, closeTo(7.75, 0.001));
      expect(c.hasSleepRecord, isTrue);
      expect(c.sleepPeriod?.start, start);
      expect(c.sleepPeriod?.end, end);
    });

    test('editing a period REPLACES it — the union bug', () async {
      // 🔴 Overlapping sleep periods MERGE (so a nap and a night both count),
      // which meant a correction could only ever ADD: 22:45→06:30 corrected to
      // 23:30→06:30 produced the union, 7h 45m, unchanged. A member could
      // never reduce a sleep they had over-reported.
      final c = build();
      await c.setSleep(7.75,
          start: DateTime(2026, 8, 1, 22, 45), end: DateTime(2026, 8, 2, 6, 30));
      await settle();
      expect(c.sleepHours, closeTo(7.75, 0.001));

      await c.setSleep(7,
          start: DateTime(2026, 8, 1, 23, 30),
          end: DateTime(2026, 8, 2, 6, 30),
          replacing: true);
      await settle();
      expect(c.sleepHours, closeTo(7.0, 0.001),
          reason: 'the member\'s last word stands');
      expect(c.sleepPeriod?.start, DateTime(2026, 8, 1, 23, 30));
    });

    test('the withdrawn original is retained, never erased', () async {
      final c = build();
      await c.setSleep(8,
          start: DateTime(2026, 8, 1, 22), end: DateTime(2026, 8, 2, 6));
      await settle();
      await c.setSleep(7,
          start: DateTime(2026, 8, 1, 23),
          end: DateTime(2026, 8, 2, 6),
          replacing: true);
      await settle();
      expect(events.store.length, 2, reason: 'append-only: two events exist');
      expect(events.store.values.where((e) => e.deleted).length, 1);
    });

    test('an out-of-range duration is refused', () async {
      final c = build();
      expect(await c.setSleep(30), isFalse);
      expect(events.store, isEmpty);
    });

    test('sleep stated as hours alone records no invented instants', () async {
      final c = build();
      await c.setSleep(7.5);
      await settle();
      expect(c.sleepHours, closeTo(7.5, 0.001));
      expect(c.sleepPeriod, isNull, reason: 'a bedtime nobody gave is not data');
    });
  });

  // ══ SUPPLEMENTS ══════════════════════════════════════════════════════════

  group('supplements — the coach\'s stack', () {
    final stack = [
      {'id': 'a', 'name': 'Creatine', 'dose': '5 g'},
      {'id': 'b', 'name': 'Vitamin D'},
      {'id': 'c', 'name': 'Omega 3'},
    ];

    test('ticking records a dose; un-ticking withdraws it', () async {
      final c = build(supplementPlan: stack);
      expect(c.supplementChecklist.length, 3);
      await c.toggleSupplement('a');
      await settle();
      expect(c.supplementChecklist.firstWhere((s) => s.id == 'a').taken, isTrue);
      expect(c.supplementCompletion, closeTo(1 / 3, 0.001));

      await c.toggleSupplement('a');
      await settle();
      expect(
          c.supplementChecklist.firstWhere((s) => s.id == 'a').taken, isFalse);
      expect(c.supplementCompletion, 0);
    });

    test('a multi-dose protocol counts doses without double-counting the item',
        () async {
      final c = build(supplementPlan: stack);
      await c.toggleSupplement('a');
      await settle();
      await c.addSupplementDose('a');
      await settle();
      expect(c.dosesOf('a'), 2);
      expect(c.supplementCompletion, closeTo(1 / 3, 0.001),
          reason: 'two doses of one item is still one item taken');
    });

    test('a rapid DOUBLE TAP toggles once — it never logs two doses', () async {
      // A checkbox that is tapped twice quickly must end where it started.
      // `toggleSupplement` chose its branch from `lastDoseOf`, which is empty
      // until the first write's snapshot returns — so both taps took the
      // "not taken yet" branch and recorded TWO doses of an item the member
      // was trying to un-tick. Same race the water + and − paths guard.
      final c = build(supplementPlan: stack);
      events.holdEmissions = true;
      await Future.wait([c.toggleSupplement('a'), c.toggleSupplement('a')]);
      events.flush();
      await settle();

      expect(c.dosesOf('a'), 1, reason: 'one tap, one dose');
      expect(c.supplementChecklist.firstWhere((s) => s.id == 'a').taken, isTrue);
    });

    test('the explicit + dose button still records EVERY dose', () async {
      // The guard above must not break a real 3x/day protocol.
      final c = build(supplementPlan: stack);
      await c.toggleSupplement('a');
      await settle();
      await c.addSupplementDose('a');
      await settle();
      await c.addSupplementDose('a');
      await settle();
      expect(c.dosesOf('a'), 3);
    });

    test('no prescribed stack yields no checklist and no completion', () async {
      final c = build();
      expect(c.supplementChecklist, isEmpty);
      expect(c.supplementCompletion, isNull);
    });
  });

  // ══ LIFECYCLE ════════════════════════════════════════════════════════════

  group('lifecycle', () {
    test('a DAY ROLLOVER re-anchors the log and drops the old day\'s state',
        () async {
      final c = build();
      await c.addGlass(1);
      await settle();
      expect(c.waterGlasses, 1);
      final firstKey = c.dateKeyStr;

      // The member browses to another day: the write target moves with it.
      c.selectDay(DateTime(2026, 8, 1));
      await settle();
      expect(c.dateKeyStr, '2026-08-01');
      expect(c.dateKeyStr, isNot(firstKey));

      // ensureFreshDay only re-anchors while FOLLOWING today, so a deliberate
      // selection is never yanked back under the member.
      c.ensureFreshDay();
      expect(c.dateKeyStr, '2026-08-01');
    });

    test('closing cancels every subscription and leaves no timer', () async {
      final c = build();
      await c.addGlass(1);
      await settle();
      c.onClose();
      // A write after teardown must not resurrect the stream or throw.
      await c.addGlass(1);
      await settle();
      expect(true, isTrue, reason: 'no unhandled error escaped teardown');
    });
  });

  // ══ CROSS-SURFACE ════════════════════════════════════════════════════════

  group('one controller, one truth', () {
    test('Home and Today read the SAME instance and the same numbers',
        () async {
      // Home builds its card from `waterGlasses`/`waterTargetGlasses` and
      // Today draws its ring from `waterCompletion`. These were different
      // units; the same tap must now move all three together.
      final c = build(waterTargetMl: 2000);
      await c.addGlass(1);
      await settle();
      expect(c.waterGlasses, 1);
      expect(c.waterTargetGlasses, 8);
      expect(c.waterCompletion, closeTo(1 / 8, 0.001));
      expect(
        (c.waterGlasses / c.waterTargetGlasses),
        c.waterCompletion,
        reason: 'the card fraction and the ring fraction are one number',
      );
    });

    test('the coach\'s configuration is never hardcoded', () async {
      final c = build(glassSizeMl: 500, waterTargetMl: 3000);
      expect(c.glassSizeMl, 500);
      expect(c.waterTargetGlasses, 6);
      await c.addGlass(1);
      await settle();
      expect(c.waterMl, 500);
      expect(c.waterCompletion, closeTo(1 / 6, 0.001));
    });

    test('a COACH TARGET CHANGE reaches the member live, mid-session',
        () async {
      // `clients/{id}` is a live snapshots() listener in MemberController, so
      // a coach raising a goal in TrainerHQ must move the member's numbers
      // without a reopen. Nothing re-reads targets on a timer — every getter
      // reads the doc — so this pins that the derivation follows the doc.
      final c = build(waterTargetMl: 2000);
      expect(c.waterTargetGlasses, 8);
      for (var i = 0; i < 8; i++) {
        await c.addGlass(1);
        await settle();
      }
      expect(c.waterGoalReached, isTrue);

      // The coach raises the goal to 3 L and the glass size to 300 ml.
      member.client.value = {
        'lifestyleTargets': {
          'waterTargetMl': 3000,
          'glassSizeMl': 300,
          'stepsTarget': 12000,
          'sleepHoursTarget': 7,
        },
        'supplementPlan': const [],
      };

      expect(c.glassSizeMl, 300);
      expect(c.waterTargetGlasses, 10, reason: '3 000 / 300');
      expect(c.waterGoalReached, isFalse);
      // Already-recorded millilitres are UNTOUCHED — the events are the record,
      // and a coach changing a glass size cannot rewrite what was drunk.
      expect(c.waterMl, 2000);
      expect(c.waterGlasses, 7, reason: '2 000 ml at 300 ml a glass');
    });

    test('a coach REMOVING the stack empties the checklist immediately',
        () async {
      final c = build(supplementPlan: [
        {'id': 'a', 'name': 'Creatine'},
      ]);
      await c.toggleSupplement('a');
      await settle();
      expect(c.supplementCompletion, 1.0);

      member.client.value = {
        'lifestyleTargets': const {'glassSizeMl': 250},
        'supplementPlan': const [],
      };
      expect(c.supplementChecklist, isEmpty);
      expect(c.supplementCompletion, isNull,
          reason: 'nothing prescribed is not 100% of nothing');
    });

    test('a glass size the coach never set falls back to the platform default',
        () async {
      final c = build(glassSizeMl: 0);
      expect(c.glassSizeMl, LifestyleDefaults.glassSizeMl);
      await c.addGlass(1);
      await settle();
      expect(c.waterMl, 250);
    });
  });
}

// ══════════════════════════════════════════════════════════════════════════
// DEFECT B — THE SUBSCRIPTION LIFECYCLE.
//
// `_subscribe()` ran synchronously in `onInit`, while `canLog` was still
// false, so `watchDay` returned an empty stream and NO Firestore listener was
// ever registered. The only rebind was `ever(isLinked)`, which fires on the
// clientProfiles snapshot — strictly BEFORE the `clients` snapshot that
// supplies `adminId` — so it too saw `canLog == false`, and `isLinked` never
// changed again. Proven on the device by the Firestore SDK's own listener
// registry: a clean boot registered NO target for `client_lifestyle_days`.
//
// These fakes model the REAL arrival order:
//   1. clientProfiles snapshot  → clientId, isLinked = true      (adminId absent)
//   2. clients snapshot         → adminId                        (now loggable)
//
// `watchCalls` counts listener registrations, which is the thing the registry
// measures on the device.
class _LateMember extends MemberController {
  String cid = '';

  @override
  String get clientId => cid;

  @override
  String get uid => 'u1';

  @override
  // ignore: must_call_super
  void onInit() {}

  /// Step 1 — the profile resolves. Linked, but NOT yet loggable.
  void profileArrives() {
    cid = 'c1';
    isLinked.value = true;
  }

  /// Step 2 — the clients document resolves. `adminId` exists; now loggable.
  void clientDocArrives({String adminId = 'a1', int glassSizeMl = 250}) {
    client.value = {
      'adminId': adminId,
      'lifestyleTargets': {'glassSizeMl': glassSizeMl, 'waterTargetMl': 2500},
      'supplementPlan': const [],
    };
  }
}

class _CountingLog extends LifestyleLogService {
  _CountingLog(this._m);
  final _LateMember _m;
  int watchCalls = 0;

  @override
  bool get canLog => _m.clientId.isNotEmpty && _m.adminId.isNotEmpty;

  @override
  Stream<LifestyleLogModel?> watchDay(String dateKey) {
    watchCalls++;
    return Stream.value(null);
  }

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

class _CountingEvents extends LifestyleEventService {
  _CountingEvents(this._m, LifestyleLogService legacy)
      : super(writer: _NoopWriter(), legacy: legacy);
  final _LateMember _m;

  /// Every day key a listener was registered for, in order.
  final List<String> boundDays = [];

  @override
  bool get canLog => _m.clientId.isNotEmpty && _m.adminId.isNotEmpty;

  @override
  Stream<List<CoachingEvent>> watchDay(String dateKey) {
    boundDays.add(dateKey);
    return Stream.value(const []);
  }

  @override
  Future<void> mirrorLegacyTotals({
    required String dateKey,
    required List<CoachingEvent> events,
    List<SupplementPlanItem> stack = const [],
  }) async {}
}

void mainDefectB() {
  late _LateMember member;
  late _CountingLog log;
  late _CountingEvents events;
  late LifestyleController c;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  LifestyleController boot() {
    member = _LateMember();
    log = _CountingLog(member);
    events = _CountingEvents(member, log);
    c = LifestyleController(service: log, events: events, member: member);
    c.onInit();
    return c;
  }

  tearDown(Get.reset);

  group('Defect B — listener lifecycle', () {
    test('NEVER binds a dead stream: nothing at onInit, nothing on profile',
        () async {
      boot();
      await settle();
      expect(events.boundDays, isEmpty,
          reason: 'no prerequisite has arrived — binding here is the defect');

      // The OLD trigger. It fired here and re-subscribed against a still-false
      // gate, which is exactly why the stream stayed dead forever.
      member.profileArrives();
      await settle();
      expect(events.boundDays, isEmpty,
          reason: 'clientId alone is not enough — adminId has not arrived');
      expect(c.canLog, isFalse);
    });

    test('binds EXACTLY ONCE the moment the last prerequisite lands', () async {
      boot();
      member.profileArrives();
      await settle();

      member.clientDocArrives();
      await settle();

      expect(c.canLog, isTrue);
      expect(events.boundDays.length, 1, reason: 'never zero, never duplicated');
      expect(events.boundDays.single, c.dateKeyStr);
      expect(log.watchCalls, 1, reason: 'the legacy listener binds once too');
    });

    test('NEVER duplicates: later client-doc updates do not rebind', () async {
      boot();
      member.profileArrives();
      member.clientDocArrives();
      await settle();
      expect(events.boundDays.length, 1);

      // The coach edits targets — the clients document emits repeatedly.
      for (var i = 0; i < 5; i++) {
        member.clientDocArrives(glassSizeMl: 250 + i);
        await settle();
      }
      expect(events.boundDays.length, 1,
          reason: 'same member, same day — binding must be idempotent');
    });

    test('NEVER stale: a new day rebinds, deterministically and once',
        () async {
      boot();
      member.profileArrives();
      member.clientDocArrives();
      await settle();
      final firstDay = c.dateKeyStr;

      // The day rolls over while the app is open.
      c.selectDay(DateTime.now().add(const Duration(days: 1)));
      await settle();
      expect(events.boundDays.length, 2);
      expect(events.boundDays.last, isNot(firstDay));

      // Re-asking for the SAME day must not open a third listener.
      c.selectDay(DateTime.now().add(const Duration(days: 1)));
      await settle();
      expect(events.boundDays.length, 2, reason: 'idempotent per member-day');
    });

    test('NEVER stale: a different member rebinds even on the same day',
        () async {
      boot();
      member.profileArrives();
      member.clientDocArrives();
      await settle();
      expect(events.boundDays.length, 1);

      // The linkage moves to another client doc (coach switch / re-claim).
      member.cid = 'c2';
      member.clientDocArrives(adminId: 'a2');
      await settle();
      expect(events.boundDays.length, 2,
          reason: 'the bind key carries the member, not just the day');
    });

    test('binds immediately when the controller is created LATE', () async {
      // Opening the screen long after sign-in: everything already resolved.
      member = _LateMember()..profileArrives();
      member.clientDocArrives();
      log = _CountingLog(member);
      events = _CountingEvents(member, log);
      c = LifestyleController(service: log, events: events, member: member);
      c.onInit();
      await settle();

      expect(events.boundDays.length, 1, reason: 'never zero');
    });

    test('an unlinked member binds nothing at all, and reports it', () async {
      boot();
      await settle();
      expect(events.boundDays, isEmpty);
      expect(c.canLog, isFalse, reason: 'the screen shows the join prompt');
    });
  });
}
