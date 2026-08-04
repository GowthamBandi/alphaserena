import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena/controllers/food_log_controller.dart';
import 'package:alphaserena/controllers/member_controller.dart';
import 'package:alphaserena/core/models/nutrition_day_model.dart';
import 'package:alphaserena/core/services/nutrition_day_service.dart';

/// THE FOOD LOG MUST BIND WHEN THE MEMBER ACTUALLY BECOMES LOGGABLE.
///
/// Found on a real device, with a real signed-in member, against real rules:
/// the member logged a food, the write landed in Firestore, the Cloud Function
/// computed it — and the Diet screen said "Nothing logged yet today", through
/// a full app restart. Their own food was permanently invisible, which invites
/// them to log it again.
///
/// `canLog` needs THREE facts, and they arrive from TWO different streams:
///   • clientId  — `clientProfiles.linkedClientId`
///   • adminId   — the `clients` document
///   • uid       — Firebase Auth
///
/// The rebind was `ever(_member.isLinked)`. `isLinked` flips true when the
/// profile resolves, which is typically BEFORE the clients document lands — so
/// `_bind()` re-ran while `adminId` was still empty, took the `!canLog` branch
/// and subscribed to nothing. When `adminId` finally arrived, `isLinked` did
/// not change again, so nothing ever rebound. `ever` fires on CHANGE, and the
/// controller was watching the wrong fact.
///
/// The write path never noticed, because `addEntry` re-evaluates `canLog` at
/// call time — by then it is true. Writes worked; reads were dead. That
/// asymmetry is exactly why no test caught it: every existing test constructs
/// a controller whose member is ALREADY fully linked.
class _FakeMember extends MemberController {
  _FakeMember();

  String? _linked;

  /// `linkedClientId` is backed by a private Rx on the real controller; the
  /// facts under test are the two PUBLIC streams (`isLinked`, `client`).
  @override
  String? get linkedClientId => _linked;

  void linkTo(String id) => _linked = id;

  @override
  // ignore: must_call_super
  void onInit() {}
}

class _FakeService extends NutritionDayService {
  _FakeService(this._member);

  final _FakeMember _member;
  final _controller = StreamController<NutritionDayModel?>.broadcast();

  /// How many times a LIVE subscription was opened.
  int liveBinds = 0;

  /// Mirrors the real service: all three identity facts, from two streams.
  @override
  bool get canLog =>
      (_member.linkedClientId ?? '').isNotEmpty &&
      (_member.client.value?['adminId'] ?? '').toString().isNotEmpty;

  @override
  Stream<NutritionDayModel?> watchDay(String dateKey) {
    // The real service returns a single-value, immediately-completing stream
    // here — nothing can ever arrive on it later.
    if (!canLog) return Stream<NutritionDayModel?>.value(null);
    liveBinds++;
    return _controller.stream;
  }

  void emit(NutritionDayModel? d) => _controller.add(d);
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  final today = NutritionDayModel(
    id: 'c1_2026-08-03',
    dateKey: '2026-08-03',
    adminId: 'orgA',
    entries: {
      'e1': FoodEntry(
        entryId: 'e1',
        foodName: 'Paneer Tikka',
        mealSlot: 'lunch',
        quantity: 1,
        unit: 'katori',
        grams: 150,
        loggedAt: 1000,
        consumed: ConsumedSnapshot(calories: 375, protein: 27),
      ),
    },
  );

  test('binds when adminId arrives AFTER isLinked already flipped', () async {
    final member = _FakeMember();
    final service = _FakeService(member);
    final c = FoodLogController(service: service, member: member);
    c.onInit();
    await Future<void>.delayed(Duration.zero);
    expect(service.liveBinds, 0, reason: 'nothing is loggable yet');

    // The profile resolves first: linked, but the clients doc has NOT landed,
    // so adminId is still empty and canLog is still false.
    member.linkTo('c1');
    member.isLinked.value = true;
    await Future<void>.delayed(Duration.zero);
    expect(service.liveBinds, 0, reason: 'still missing adminId');

    // The clients document arrives. `isLinked` does NOT change — this is the
    // moment the old code could never react to.
    member.client.value = {'adminId': 'orgA'};
    await Future<void>.delayed(Duration.zero);
    expect(service.liveBinds, 1,
        reason: 'the member became loggable; the log must bind');

    service.emit(today);
    await Future<void>.delayed(Duration.zero);
    expect(c.entryCount, 1);
    expect(c.loggedCalories, 375);
  });

  test('a live binding is not torn down and rebuilt on every snapshot',
      () async {
    // The clients document restreams on any coach edit. Rebinding on each one
    // would drop and reopen a Firestore listener for no reason.
    final member = _FakeMember();
    final service = _FakeService(member);
    final c = FoodLogController(service: service, member: member);
    c.onInit();
    member.linkTo('c1');
    member.client.value = {'adminId': 'orgA'};
    member.isLinked.value = true;
    await Future<void>.delayed(Duration.zero);
    expect(service.liveBinds, 1);

    member.client.value = {'adminId': 'orgA', 'name': 'edited by coach'};
    member.client.value = {'adminId': 'orgA', 'goal': 'cut'};
    await Future<void>.delayed(Duration.zero);
    expect(service.liveBinds, 1, reason: 'already live — do not re-subscribe');
  });

  test('an already-linked member binds immediately', () async {
    // The ordinary case must not regress: everything resolved before onInit.
    final member = _FakeMember();
    member.linkTo('c1');
    member.client.value = {'adminId': 'orgA'};
    member.isLinked.value = true;
    final service = _FakeService(member);
    final c = FoodLogController(service: service, member: member);
    c.onInit();
    await Future<void>.delayed(Duration.zero);
    expect(service.liveBinds, 1);
    service.emit(today);
    await Future<void>.delayed(Duration.zero);
    expect(c.entryCount, 1);
  });
}
