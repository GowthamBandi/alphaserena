import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena/controllers/food_log_controller.dart';
import 'package:alphaserena/controllers/member_controller.dart';
import 'package:alphaserena/core/domain/food_portion_math.dart';
import 'package:alphaserena/core/models/member_food.dart';
import 'package:alphaserena/core/models/nutrition_day_model.dart';
import 'package:alphaserena/core/services/member_food_service.dart';
import 'package:alphaserena/core/services/nutrition_day_service.dart';

/// A DEAD LISTENER MUST NOT OUTLIVE A SUCCESSFUL WRITE.
///
/// Firestore TERMINATES a listener on error and never retries it. The food log
/// rebound in exactly two places — a date rollover, and the manual "Try again"
/// button — so once the day's listener failed, the screen was stuck.
///
/// That is not theoretical. It is the documented behaviour of the production
/// blocker in `NUTRITION_PRODUCTION_FREEZE_REPORT.md`: a nutrition day starts as
/// a NON-EXISTENT document, the deployed rule denies reads of a missing
/// document, and the listener dies. The WRITE path is unaffected (`create`
/// never dereferences `resource`), so the member could log food successfully
/// and go on reading *"Couldn't load today's food"* — with the food already
/// stored. The escape hatch was "log blind, then tap Try again".
///
/// A successful write proves the member is reachable AND that the document now
/// exists, which makes it the exact moment a rebind can succeed. These tests
/// pin that, and pin that a healthy subscription is never churned.
class _FakeMember extends MemberController {
  @override
  String? get linkedClientId => 'c1';

  @override
  // ignore: must_call_super
  void onInit() {}
}

class _FakeService extends NutritionDayService {
  _FakeService();

  /// How many live subscriptions have been opened.
  int binds = 0;

  /// The next subscription errors instead of delivering — the dead-listener
  /// case, reproduced exactly.
  bool failNextRead = false;

  /// Writes succeed regardless of the read failure — the asymmetry that let
  /// this defect hide.
  DietSaveResult writeResult = DietSaveResult.synced;

  StreamController<NutritionDayModel?>? _current;

  @override
  bool get canLog => true;

  @override
  Stream<NutritionDayModel?> watchDay(String dateKey) {
    binds++;
    final c = StreamController<NutritionDayModel?>();
    _current = c;
    if (failNextRead) {
      c.addError(Exception('permission-denied'));
    } else {
      c.add(null);
    }
    return c.stream;
  }

  void emit(NutritionDayModel? d) => _current?.add(d);

  @override
  Future<DietSaveResult> addEntry({
    required String dateKey,
    required FoodEntry entry,
    String? existingAdminId,
  }) async =>
      writeResult;

  @override
  Future<DietSaveResult> writeEntry({
    required String dateKey,
    required String entryId,
    required Map<String, dynamic> patch,
    String? existingAdminId,
  }) async =>
      writeResult;

  @override
  Future<DietSaveResult> softDelete({
    required String dateKey,
    required String entryId,
    String? existingAdminId,
  }) async =>
      writeResult;

  @override
  Future<DietSaveResult> restore({
    required String dateKey,
    required String entryId,
    String? existingAdminId,
  }) async =>
      writeResult;
}

class _FakeFoods extends MemberFoodService {
  @override
  Future<void> remember(MemberFood food) async {}
}

final _food = MemberFood(
  foodId: 'f1',
  name: 'Boiled Egg',
  tier: MemberFoodTier.global,
  per100: const {'calories': 155, 'protein': 13},
  portions: const [],
);

int _ids = 0;

FoodLogController _controller(_FakeService s) => FoodLogController(
      service: s,
      foods: _FakeFoods(),
      member: _FakeMember(),
      // The real generator asks Firestore for a collision-free id, which needs
      // a live Firebase app. Injected here so the WRITE path is reachable from
      // a plain unit test at all.
      idFactory: () => 'e${++_ids}',
    );

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  test('a successful log REBINDS a listener that had died', () async {
    final service = _FakeService()..failNextRead = true;
    final c = _controller(service);
    c.onInit();
    await _settle();

    // The listener errored: an honest error, and NOT the empty state.
    expect(c.loadError.value, isTrue);
    expect(service.binds, 1);

    // The write path still works — this is precisely the asymmetry that made
    // the stuck state so misleading.
    service.failNextRead = false;
    final result = await c.logFood(
      food: _food,
      mealSlot: 'breakfast',
      selection: PortionSelection.grams(100),
    );
    await _settle();

    expect(result, isNot(DietSaveResult.failed));
    expect(service.binds, 2, reason: 'the dead listener must be reopened');
    expect(
      c.loadError.value,
      isFalse,
      reason: 'the member must not be told the load failed after it succeeded',
    );
  });

  test('a FAILED write does not rebind — nothing changed to retry for',
      () async {
    final service = _FakeService()
      ..failNextRead = true
      ..writeResult = DietSaveResult.failed;
    final c = _controller(service);
    c.onInit();
    await _settle();
    expect(service.binds, 1);

    await c.logFood(
      food: _food,
      mealSlot: 'breakfast',
      selection: PortionSelection.grams(100),
    );
    await _settle();

    expect(service.binds, 1);
    expect(c.loadError.value, isTrue);
  });

  test('a QUEUED (offline) write still rebinds — queued is success', () async {
    final service = _FakeService()
      ..failNextRead = true
      ..writeResult = DietSaveResult.queued;
    final c = _controller(service);
    c.onInit();
    await _settle();
    expect(service.binds, 1);

    service.failNextRead = false;
    await c.logFood(
      food: _food,
      mealSlot: 'breakfast',
      selection: PortionSelection.grams(100),
    );
    await _settle();

    expect(service.binds, 2);
    expect(c.loadError.value, isFalse);
  });

  test('a HEALTHY listener is never torn down by a write', () async {
    // The guard matters: rebinding on every save would drop and reopen a
    // Firestore listener on each logged food, for no reason at all.
    final service = _FakeService();
    final c = _controller(service);
    c.onInit();
    await _settle();
    expect(c.loadError.value, isFalse);
    expect(service.binds, 1);

    for (var i = 0; i < 3; i++) {
      await c.logFood(
        food: _food,
        mealSlot: 'lunch',
        selection: PortionSelection.grams(100),
      );
    }
    await _settle();

    expect(service.binds, 1, reason: 'one healthy subscription, start to end');
  });

  test('edit, delete and undo recover a dead listener too', () async {
    for (final action in ['edit', 'delete', 'undo']) {
      final service = _FakeService()..failNextRead = true;
      final c = _controller(service);
      c.onInit();
      await _settle();
      expect(c.loadError.value, isTrue, reason: action);
      service.failNextRead = false;

      final entry = FoodEntry(
        entryId: 'e1',
        foodName: 'Boiled Egg',
        mealSlot: 'breakfast',
        quantity: 1,
        unit: 'g',
        grams: 100,
        consumed: const ConsumedSnapshot(calories: 155),
      );

      switch (action) {
        case 'edit':
          await c.editEntry(
            entry: entry,
            per100: const {'calories': 155},
            selection: PortionSelection.grams(120),
          );
        case 'delete':
          await c.removeEntry(entry);
        case 'undo':
          await c.restoreEntry(entry);
      }
      await _settle();

      expect(service.binds, 2, reason: '$action must recover the listener');
      expect(c.loadError.value, isFalse, reason: action);
    }
  });
}
