import 'package:alphaserena/core/domain/nutrition_targets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Daily nutrition targets — one rule for Home, My Plans and the Diet screen.
///
/// The backend (`buildDiet`) serves the coach's goal from
/// `clients/{id}.dietTargets`, never from the plan. The plan's item SUM is a
/// different quantity and must never be presented as a coach goal.
void main() {
  List<Map<String, dynamic>> items(List<num> calories) => [
    for (final c in calories) {'calories': c, 'protein': 10},
  ];

  group('coach goal wins', () {
    test('served target is used even when items sum to something else', () {
      final t = resolveNutritionTarget(
        diet: {'targetCalories': 2000},
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: items([500, 600, 650]), // sums to 1750
      );
      expect(t.value, 2000);
      expect(t.source, NutritionTargetSource.coach);
      expect(t.isCoachGoal, isTrue);
    });

    test('a string-encoded target is honoured', () {
      final t = resolveNutritionTarget(
        diet: {'targetCalories': '1800'},
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: items([500]),
      );
      expect(t.value, 1800);
      expect(t.isCoachGoal, isTrue);
    });
  });

  group('prescription fallback', () {
    test('no served target → sum of items, flagged as NOT a coach goal', () {
      final t = resolveNutritionTarget(
        diet: {'targetCalories': null},
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: items([500, 600, 650]),
      );
      expect(t.value, 1750);
      expect(t.source, NutritionTargetSource.prescription);
      // The critical assertion: a sum must never masquerade as a goal, or the
      // UI burns it down as "kcal left".
      expect(t.isCoachGoal, isFalse);
    });

    test('a stored zero is treated as unset, not as a goal of zero', () {
      final t = resolveNutritionTarget(
        diet: {'targetCalories': 0},
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: items([400]),
      );
      expect(t.value, 400);
      expect(t.source, NutritionTargetSource.prescription);
    });

    test('a missing diet map still sums whatever items were passed', () {
      final t = resolveNutritionTarget(
        diet: null,
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: items([300, 200]),
      );
      expect(t.value, 500);
      expect(t.source, NutritionTargetSource.prescription);
    });
  });

  group('nothing to claim', () {
    test('no target and no items → empty, never a fabricated number', () {
      final t = resolveNutritionTarget(
        diet: const {},
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: const [],
      );
      expect(t.value, 0);
      expect(t.source, NutritionTargetSource.none);
      expect(t.hasValue, isFalse);
    });

    test('items present but this macro absent everywhere', () {
      final t = resolveNutritionTarget(
        diet: const {},
        targetKey: 'targetFiber',
        itemKey: 'fiber',
        items: items([500, 600]), // carry calories/protein only
      );
      expect(t.hasValue, isFalse);
      expect(t.source, NutritionTargetSource.none);
    });
  });

  group('per-macro independence', () {
    test('a coach may set calories only; protein falls back to the sum', () {
      const diet = {'targetCalories': 2000, 'targetProtein': null};
      final cal = resolveNutritionTarget(
        diet: diet,
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: items([500, 600]),
      );
      final pro = resolveNutritionTarget(
        diet: diet,
        targetKey: 'targetProtein',
        itemKey: 'protein',
        items: items([500, 600]),
      );
      expect(cal.isCoachGoal, isTrue);
      expect(pro.isCoachGoal, isFalse);
      expect(pro.value, 20); // 10 per item
    });
  });

  group('NIP Phase A — the served targets map wins when present', () {
    const servedTargets = {
      'calories': 2000,
      'protein': 150,
      'carbs': null,
      'fat': null,
      'fiber': null,
      'waterMl': 3000,
      'micros': {'iron': 18},
      'note': 'High-protein cut',
      'version': 4,
      'source': 'nutritionTargets',
    };

    test('map value wins and is a coach goal, extras ride along', () {
      final t = resolveNutritionTarget(
        diet: {
          'targetCalories': 2000, // backend serves identical flat value
          'targets': servedTargets,
        },
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: items([500, 600]),
      );
      expect(t.value, 2000);
      expect(t.source, NutritionTargetSource.coach);
      expect(t.isCoachGoal, isTrue);
      expect(t.waterMl, 3000);
      expect(t.note, 'High-protein cut');
      expect(t.version, 4);
    });

    test('same number as the flat path — no visible change by construction', () {
      final flat = resolveNutritionTarget(
        diet: const {'targetCalories': 2000},
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: items([500, 600]),
      );
      final mapped = resolveNutritionTarget(
        diet: const {'targetCalories': 2000, 'targets': servedTargets},
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: items([500, 600]),
      );
      expect(mapped.value, flat.value);
      expect(mapped.source, flat.source);
    });

    test('a macro absent from the map falls back per-macro (carbs → sum)', () {
      final t = resolveNutritionTarget(
        diet: const {'targets': servedTargets},
        targetKey: 'targetCarbs',
        itemKey: 'carbs',
        items: [
          {'carbs': 120},
          {'carbs': 80},
        ],
      );
      expect(t.value, 200);
      expect(t.source, NutritionTargetSource.prescription);
      // Extras belong to the coach contract, not to a derived sum.
      expect(t.waterMl, isNull);
      expect(t.note, isNull);
      expect(t.version, isNull);
    });

    test("source 'none' is ignored entirely — legacy resolution unchanged", () {
      final t = resolveNutritionTarget(
        diet: const {
          'targets': {'calories': null, 'source': 'none'},
        },
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: items([400]),
      );
      expect(t.value, 400);
      expect(t.source, NutritionTargetSource.prescription);
    });

    test("legacy 'dietTargets' provenance is still a coach goal", () {
      final t = resolveNutritionTarget(
        diet: const {
          'targets': {'calories': 1800, 'source': 'dietTargets'},
        },
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: items([500]),
      );
      expect(t.value, 1800);
      expect(t.isCoachGoal, isTrue);
      expect(t.version, isNull); // legacy storage carries no version
    });

    test('an old backend (no targets key) resolves exactly as before', () {
      final t = resolveNutritionTarget(
        diet: const {'targetCalories': 2200},
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: items([500]),
      );
      expect(t.value, 2200);
      expect(t.isCoachGoal, isTrue);
      expect(t.waterMl, isNull);
    });

    test('a malformed targets map cannot crash resolution', () {
      final t = resolveNutritionTarget(
        diet: const {
          'targetCalories': 1900,
          'targets': {'calories': 'junk', 'source': 'nutritionTargets'},
        },
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: items([500]),
      );
      // Junk map value → falls through to the flat field.
      expect(t.value, 1900);
      expect(t.isCoachGoal, isTrue);
    });
  });

  group('targets survive having no diet plan', () {
    // THE DEFECT: a member's daily goal lives on `clients/{id}` and belongs to
    // the MEMBER, not to any plan. But the backend resolved it only inside
    // `buildDiet`, which runs solely when an ACTIVE diet assignment exists — so
    // a coach who set targets and assigned no diet plan (or paused, ended or
    // soft-deleted one) served `diet: null`, and every target went with it.
    // The member's calorie ring and all four macro goals read as "no goal set"
    // while the numbers sat correctly on their client document.
    //
    // `getMyTraining` now serves them top-level as `nutritionTargets`, and
    // `diet` still goes null with no active plan — so the "no active plan"
    // state is untouched while the goal survives it.
    final served = {
      'calories': 2000.0,
      'protein': 150.0,
      'waterMl': 3000.0,
      'note': 'cut',
      'version': 4.0,
      'source': 'nutritionTargets',
    };

    test('a coach goal is served with NO diet plan at all', () {
      final t = resolveNutritionTarget(
        servedTargets: served,
        diet: null, // no active assignment — this is the paused/ended member
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: const [],
      );
      expect(t.value, 2000);
      expect(t.source, NutritionTargetSource.coach);
      expect(t.isCoachGoal, isTrue);
      expect(t.waterMl, 3000);
      expect(t.version, 4);
      expect(t.note, 'cut');
    });

    test('a macro the coach left unset stays honestly empty', () {
      // Only calories and protein are prescribed above. Carbs must not be
      // fabricated, and with no plan there is no item sum to fall back to.
      final t = resolveNutritionTarget(
        servedTargets: served,
        diet: null,
        targetKey: 'targetCarbs',
        itemKey: 'carbs',
        items: const [],
      );
      expect(t.hasValue, isFalse);
      expect(t.source, NutritionTargetSource.none);
    });

    test('a cleared prescription claims no goal', () {
      final t = resolveNutritionTarget(
        servedTargets: const {'source': 'none'},
        diet: null,
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: const [],
      );
      expect(t.hasValue, isFalse);
      expect(t.source, NutritionTargetSource.none);
    });

    test('the top-level goal outranks a stale plan-embedded copy', () {
      // Both are produced by the same backend mapper, so they agree in
      // practice; if they ever disagree the member-scoped one is canonical.
      final t = resolveNutritionTarget(
        servedTargets: served,
        diet: {'targetCalories': 1750, 'targets': {
          'calories': 1750.0, 'source': 'dietTargets'}},
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: items([500, 600, 650]),
      );
      expect(t.value, 2000);
      expect(t.source, NutritionTargetSource.coach);
    });

    test('an old backend with no top-level key still resolves as before', () {
      // Zero-migration guarantee: nothing about the legacy path may move.
      final t = resolveNutritionTarget(
        servedTargets: null,
        diet: {'targetCalories': 1800},
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: items([500, 600]),
      );
      expect(t.value, 1800);
      expect(t.source, NutritionTargetSource.coach);
    });

    test('with no plan and no coach goal, nothing is claimed', () {
      final t = resolveNutritionTarget(
        servedTargets: null,
        diet: null,
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: const [],
      );
      expect(t.hasValue, isFalse);
      expect(t.source, NutritionTargetSource.none);
    });
  });

  group('malformed data does not throw', () {
    test('non-numeric junk is ignored rather than crashing', () {
      final t = resolveNutritionTarget(
        diet: {'targetCalories': 'not-a-number'},
        targetKey: 'targetCalories',
        itemKey: 'calories',
        items: [
          {'calories': 'abc'},
          {'calories': 250},
          {'calories': null},
        ],
      );
      expect(t.value, 250);
      expect(t.source, NutritionTargetSource.prescription);
    });
  });
}
