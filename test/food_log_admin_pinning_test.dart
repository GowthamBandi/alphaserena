import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena/controllers/food_log_controller.dart';
import 'package:alphaserena/controllers/member_controller.dart';
import 'package:alphaserena/core/domain/food_portion_math.dart';
import 'package:alphaserena/core/models/member_food.dart';
import 'package:alphaserena/core/models/nutrition_day_model.dart';
import 'package:alphaserena/core/services/nutrition_day_service.dart';

/// THE ORG A DAY WAS OPENED UNDER.
///
/// The Firestore rules pin `adminId` IMMUTABLE on update, so every write after
/// the first must resend the org the day document was CREATED under. The
/// controller carried a detailed comment promising exactly that — and then
/// sourced the value from `MemberController.adminId`, the member's CURRENT
/// org, because `NutritionDayModel` did not parse `adminId` at all.
///
/// The failure needs a restart to show itself, which is why it survived: while
/// the app stays open the value is captured before the transfer, so it happens
/// to be right. After a relaunch the existing day arrives with nothing
/// remembered, the current (NEW) org is adopted, and every further write that
/// day is DENIED — the member simply cannot log food until midnight.
///
/// A rules test already pinned the RULE ('the day keeps the org it was opened
/// under'). Nothing pinned the client that has to satisfy it, so the two sides
/// were free to disagree, and did.
class _FakeMember extends MemberController {
  _FakeMember(String adminId) {
    client.value = {'adminId': adminId, 'id': 'client-1'};
  }

  @override
  // ignore: must_call_super
  void onInit() {}
}

class _FakeService extends NutritionDayService {
  _FakeService(this._day);

  final NutritionDayModel? _day;
  final _controller = StreamController<NutritionDayModel?>.broadcast();

  /// Every `adminId` the controller asked to be written, in order.
  final List<String?> sentAdminIds = [];

  @override
  bool get canLog => true;

  @override
  Stream<NutritionDayModel?> watchDay(String dateKey) {
    scheduleMicrotask(() => _controller.add(_day));
    return _controller.stream;
  }

  @override
  Future<DietSaveResult> addEntry({
    required String dateKey,
    required FoodEntry entry,
    String? existingAdminId,
  }) async {
    sentAdminIds.add(existingAdminId);
    return DietSaveResult.synced;
  }
}

/// Only `newEntryId` is stubbed: it mints its id from `FirebaseFirestore
/// .instance`, which needs a live Firebase app. Everything under test — the
/// org resolution and what reaches the service — is the real controller's.
class _TestLog extends FoodLogController {
  _TestLog({required super.service, required super.member});

  var _n = 0;

  @override
  String newEntryId() => 'e${_n++}';
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  const food = MemberFood(
    foodId: 'food-1',
    name: 'Paneer Tikka',
    tier: MemberFoodTier.org,
    per100: {'calories': 250, 'protein': 18},
  );

  const oneKatori = PortionSelection(
    mode: PortionMode.portion,
    quantity: 1,
    portionLabel: 'katori',
    gramsPerPortion: 150,
  );

  NutritionDayModel dayUnder(String adminId) => NutritionDayModel(
        id: 'client-1_2026-08-01',
        dateKey: '2026-08-01',
        adminId: adminId,
        entries: const {},
      );

  test('a day opened under the OLD org keeps writing that org', () async {
    // The member transferred: their client doc now says orgB, but the day
    // document on the wire was created under orgA.
    final service = _FakeService(dayUnder('orgA'));
    final c = _TestLog(
      service: service,
      member: _FakeMember('orgB'),
    );
    c.onInit();
    await Future<void>.delayed(Duration.zero);

    await c.logFood(food: food, mealSlot: 'lunch', selection: oneKatori);

    expect(service.sentAdminIds.single, 'orgA',
        reason: 'the rules pin adminId immutable; sending orgB is denied');
  });

  test('the org is read from the DOCUMENT, not from a captured first sight',
      () async {
    // Same state a RESTART produces: nothing was observed before the transfer,
    // so there is no in-memory memory to fall back on. Reading the document is
    // the only thing that survives a relaunch.
    final service = _FakeService(dayUnder('orgA'));
    final c = _TestLog(
      service: service,
      member: _FakeMember('orgB'),
    );
    c.onInit();
    await Future<void>.delayed(Duration.zero);

    expect(c.day.value?.adminId, 'orgA');
  });

  test('with no day document yet, nothing is pinned', () async {
    // The first write of the day CREATES the document, and create is the one
    // moment the member's current org is the right answer. The service fills
    // it in when none is supplied.
    final service = _FakeService(null);
    final c = _TestLog(
      service: service,
      member: _FakeMember('orgB'),
    );
    c.onInit();
    await Future<void>.delayed(Duration.zero);

    await c.logFood(food: food, mealSlot: 'lunch', selection: oneKatori);

    expect(service.sentAdminIds.single, isNull);
  });

  test('a legacy day with no adminId does not pin an empty org', () async {
    // Defensive: an empty string must never be sent as an org, or the identity
    // block would carry a blank adminId and fail the rules for a different
    // reason than the one being fixed.
    final service = _FakeService(dayUnder(''));
    final c = _TestLog(
      service: service,
      member: _FakeMember('orgB'),
    );
    c.onInit();
    await Future<void>.delayed(Duration.zero);

    await c.logFood(food: food, mealSlot: 'lunch', selection: oneKatori);

    expect(service.sentAdminIds.single, isNull);
  });
}
