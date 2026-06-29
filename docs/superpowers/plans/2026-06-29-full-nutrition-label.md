# Full Nutrition Label Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the trainer (trainersHQ) maintain fiber, sugar, and saturated fat on foods + diet plans, and surface them to the member app (alphaserena) via `getMyTraining`.

**Architecture:** Mirror the existing calories/protein/carbs/fat pattern — add `fiber`, `sugar`, `saturatedFat` (grams, default `0`) as siblings of `fat` through the food model, diet math, diet-plan model, authoring screens, and the Cloud Function. Fiber additionally gets a plan-level daily target (`targetFiber`); sugar/sat-fat are value+totals only. All fields default `0`, so legacy data needs no migration.

**Tech Stack:** Flutter/Dart + GetX (both apps), Firebase Cloud Functions (TypeScript), Firestore. Tests: `flutter test` (pure logic/model tests, matching the repo pattern); `tsc` for functions.

## Global Constraints

- New fields are **grams**, type `double`, **default `0`**, parsed defensively (`_toDouble` in Dart, `num()` in TS). Verbatim field names: `fiber`, `sugar`, `saturatedFat`, plan target `targetFiber`.
- **No migration / no back-fill.** Legacy foods/plans read `0`.
- Out of scope: sodium/trans-fat/cholesterol; sugar & sat-fat daily targets; seed-catalog back-fill; member-side diet logging.
- Two repos = **two commits**. trainersHQ: `D:\flutter works\trainersHQ`. alphaserena: `D:\flutter works\alphaserena`.
- trainersHQ Dart package name in imports: `package:trainers_hq/...`.
- A **Cloud Functions deploy is required and is the user's responsibility** (`firebase deploy --only functions:getMyTraining,functions:getFoodServings`); the member app won't see new data until then.
- Run `flutter analyze` (zero issues) after each Dart task; `npm run build` (tsc) clean after each functions task.

---

## File structure

**trainersHQ (Dart):**
- `lib/core/utils/diet_math.dart` — `NutritionTotals` + scaling/sum gain the 3 fields. *(Task 1)*
- `lib/core/models/food_item_model.dart` — per-100g 3 fields. *(Task 2)*
- `lib/core/models/diet_plan_model.dart` — `DietItem` 3 fields + `DietPlanModel.targetFiber`. *(Task 3)*
- `lib/features/food/controllers/food_controller.dart` + `lib/features/food/screens/create_food_screen.dart` — input + save. *(Task 4)*
- `lib/features/diet_plans/screens/create_diet_plan_screen.dart` — builder wiring + fiber target + summary. *(Task 5)*
- `lib/features/diet_plans/screens/diet_plan_detail_screen.dart` — read-only display. *(Task 6)*
- `lib/core/services/cloud_functions_service.dart` — `FoodApiServings` carries the 3 (USDA lookup). *(Task 7)*

**trainersHQ (TypeScript):**
- `functions/src/food.ts` — `getFoodServings` reads USDA fiber/sugar/satfat. *(Task 8)*
- `functions/src/members.ts` — `buildDiet` returns the 3 + `targetFiber`. *(Task 9)*

**trainersHQ tests:**
- `test/diet_math_test.dart` *(Task 1)*, `test/food_item_model_label_test.dart` *(Task 2, new)*, `test/diet_plan_label_test.dart` *(Task 3, new)*.

**alphaserena (Dart):**
- `lib/screens/dashboard/client_diet_screen.dart` — fiber in totals + "of which" + per-food macro line. *(Task 10)*
- `lib/controllers/home_controller.dart` — **no change** (verified: `_sumDietField('fiber')` already exists).

---

### Task 1: Diet math — add fiber/sugar/saturatedFat to NutritionTotals, scaleByGrams, planTotals

**Files:**
- Modify: `D:\flutter works\trainersHQ\lib\core\utils\diet_math.dart`
- Test: `D:\flutter works\trainersHQ\test\diet_math_test.dart`

**Interfaces:**
- Produces: `NutritionTotals({double calories, protein, carbs, fat, fiber, sugar, saturatedFat})` all defaulting `0`; `scaleByGrams` and `planTotals` carry the 3 new fields.

- [ ] **Step 1: Write the failing tests** — append inside `main()` in `test/diet_math_test.dart`:

```dart
  group('new label fields', () {
    test('scaleByGrams scales fiber/sugar/saturatedFat', () {
      const per100 = NutritionTotals(
          calories: 200, fiber: 10, sugar: 8, saturatedFat: 4);
      final r = scaleByGrams(per100, 50);
      expect(r.fiber, closeTo(5, 0.001));
      expect(r.sugar, closeTo(4, 0.001));
      expect(r.saturatedFat, closeTo(2, 0.001));
    });

    test('planTotals sums fiber/sugar/saturatedFat', () {
      final t = planTotals([
        const DietItem(
            foodName: 'A', quantity: '1', fiber: 3, sugar: 2, saturatedFat: 1),
        const DietItem(
            foodName: 'B', quantity: '1', fiber: 4, sugar: 5, saturatedFat: 2),
      ]);
      expect(t.fiber, 7);
      expect(t.sugar, 7);
      expect(t.saturatedFat, 3);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "D:\flutter works\trainersHQ" && flutter test test/diet_math_test.dart`
Expected: FAIL — `NutritionTotals`/`DietItem` have no `fiber`/`sugar`/`saturatedFat` named params (compile error).

- [ ] **Step 3: Add fields to `NutritionTotals`** — in `diet_math.dart`, replace the class body fields + ctor:

```dart
class NutritionTotals {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final double sugar;
  final double saturatedFat;

  const NutritionTotals({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fiber = 0,
    this.sugar = 0,
    this.saturatedFat = 0,
  });

  static const NutritionTotals zero = NutritionTotals();
}
```

- [ ] **Step 4: Scale the new fields in `scaleByGrams`** — replace the return:

```dart
NutritionTotals scaleByGrams(NutritionTotals per100, double grams) {
  final f = grams / 100.0;
  return NutritionTotals(
    calories: per100.calories * f,
    protein: per100.protein * f,
    carbs: per100.carbs * f,
    fat: per100.fat * f,
    fiber: per100.fiber * f,
    sugar: per100.sugar * f,
    saturatedFat: per100.saturatedFat * f,
  );
}
```

- [ ] **Step 5: Sum the new fields in `planTotals`** — replace its body:

```dart
NutritionTotals planTotals(List<DietItem> items) {
  double c = 0, p = 0, cb = 0, f = 0, fb = 0, sg = 0, sf = 0;
  for (final it in items) {
    c += it.calories;
    p += it.protein;
    cb += it.carbs;
    f += it.fat;
    fb += it.fiber;
    sg += it.sugar;
    sf += it.saturatedFat;
  }
  return NutritionTotals(
      calories: c, protein: p, carbs: cb, fat: f,
      fiber: fb, sugar: sg, saturatedFat: sf);
}
```

> Note: `DietItem.fiber/sugar/saturatedFat` are added in Task 3. This task’s test only compiles after Task 3. **Execute Task 3 before re-running Step 6** (or run Steps 2/6 of Tasks 1 & 3 together). The tasks are split for review clarity but share one compile unit.

- [ ] **Step 6: Run tests to verify they pass** (after Task 3 is implemented)

Run: `cd "D:\flutter works\trainersHQ" && flutter test test/diet_math_test.dart`
Expected: PASS (all groups, including the new one).

- [ ] **Step 7: Commit** (commit together with Tasks 2–3 — see Task 3 Step 7).

---

### Task 2: FoodItemModel — per-100g fiber/sugar/saturatedFat

**Files:**
- Modify: `D:\flutter works\trainersHQ\lib\core\models\food_item_model.dart`
- Test: `D:\flutter works\trainersHQ\test\food_item_model_label_test.dart` (create)

**Interfaces:**
- Produces: `FoodItemModel.fiber/sugar/saturatedFat` (double, default 0), parsed in `fromMap`.

- [ ] **Step 1: Write the failing test** — create `test/food_item_model_label_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:trainers_hq/core/models/food_item_model.dart';

void main() {
  test('fromMap reads fiber/sugar/saturatedFat (default 0 when absent)', () {
    final withVals = FoodItemModel.fromMap({
      'name': 'Oats', 'adminId': 'a', 'calories': 380,
      'fiber': 10, 'sugar': 1, 'saturatedFat': 1.5,
    }, 'f1');
    expect(withVals.fiber, 10);
    expect(withVals.sugar, 1);
    expect(withVals.saturatedFat, 1.5);

    final legacy = FoodItemModel.fromMap(
        {'name': 'Rice', 'adminId': 'a', 'calories': 130}, 'f2');
    expect(legacy.fiber, 0);
    expect(legacy.sugar, 0);
    expect(legacy.saturatedFat, 0);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd "D:\flutter works\trainersHQ" && flutter test test/food_item_model_label_test.dart`
Expected: FAIL — no `fiber`/`sugar`/`saturatedFat` getters (compile error).

- [ ] **Step 3: Add fields + ctor params** — in `food_item_model.dart`, after the `final double fat;` line add:

```dart
  final double fiber;
  final double sugar;
  final double saturatedFat;
```

In the const constructor, after `this.fat = 0,` add:

```dart
    this.fiber = 0,
    this.sugar = 0,
    this.saturatedFat = 0,
```

- [ ] **Step 4: Parse in `fromMap`** — after `fat: _toDouble(map['fat']),` add:

```dart
      fiber: _toDouble(map['fiber']),
      sugar: _toDouble(map['sugar']),
      saturatedFat: _toDouble(map['saturatedFat']),
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd "D:\flutter works\trainersHQ" && flutter test test/food_item_model_label_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit** (with Task 3 — see Task 3 Step 7).

---

### Task 3: DietItem fields + DietPlanModel.targetFiber

**Files:**
- Modify: `D:\flutter works\trainersHQ\lib\core\models\diet_plan_model.dart`
- Test: `D:\flutter works\trainersHQ\test\diet_plan_label_test.dart` (create)

**Interfaces:**
- Produces: `DietItem.fiber/sugar/saturatedFat` (double, default 0, in ctor/`fromMap`/`toMap`); `DietPlanModel.targetFiber` (double?, in ctor/`fromMap`, counted in `hasTarget`).

- [ ] **Step 1: Write the failing test** — create `test/diet_plan_label_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:trainers_hq/core/models/diet_plan_model.dart';

void main() {
  test('DietItem round-trips fiber/sugar/saturatedFat', () {
    const item = DietItem(
        foodName: 'Oats', quantity: '50 g',
        fiber: 5, sugar: 1, saturatedFat: 0.5);
    final map = item.toMap();
    expect(map['fiber'], 5);
    expect(map['sugar'], 1);
    expect(map['saturatedFat'], 0.5);
    final back = DietItem.fromMap(map);
    expect(back.fiber, 5);
    expect(back.sugar, 1);
    expect(back.saturatedFat, 0.5);
  });

  test('DietItem legacy map → fields default 0', () {
    final back = DietItem.fromMap({'foodName': 'Rice', 'quantity': '1'});
    expect(back.fiber, 0);
    expect(back.sugar, 0);
    expect(back.saturatedFat, 0);
  });

  test('DietPlanModel targetFiber parsed + counts in hasTarget', () {
    final plan = DietPlanModel.fromMap(
        {'name': 'Cut', 'adminId': 'a', 'targetFiber': 30}, 'p1');
    expect(plan.targetFiber, 30);
    expect(plan.hasTarget, isTrue);

    final none = DietPlanModel.fromMap({'name': 'X', 'adminId': 'a'}, 'p2');
    expect(none.targetFiber, isNull);
    expect(none.hasTarget, isFalse);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd "D:\flutter works\trainersHQ" && flutter test test/diet_plan_label_test.dart`
Expected: FAIL — missing `fiber`/`sugar`/`saturatedFat`/`targetFiber` (compile error).

- [ ] **Step 3: Add `DietItem` fields** — after `final double fat;` in `DietItem` add:

```dart
  final double fiber;
  final double sugar;
  final double saturatedFat;
```

In the `DietItem` const ctor, after `this.fat = 0,` add:

```dart
    this.fiber = 0,
    this.sugar = 0,
    this.saturatedFat = 0,
```

In `DietItem.fromMap`, after `fat: _toDouble(m['fat']),` add:

```dart
        fiber: _toDouble(m['fiber']),
        sugar: _toDouble(m['sugar']),
        saturatedFat: _toDouble(m['saturatedFat']),
```

In `DietItem.toMap`, after `'fat': fat,` add:

```dart
        'fiber': fiber,
        'sugar': sugar,
        'saturatedFat': saturatedFat,
```

- [ ] **Step 4: Add `DietPlanModel.targetFiber`** — after `final double? targetFat;` add:

```dart
  final double? targetFiber;
```

In the `DietPlanModel` const ctor, after `this.targetFat,` add:

```dart
    this.targetFiber,
```

In `hasTarget`, change the expression to include fiber:

```dart
  bool get hasTarget =>
      targetCalories != null ||
      targetProtein != null ||
      targetCarbs != null ||
      targetFat != null ||
      targetFiber != null;
```

In `fromMap`, after `targetFat: _toDoubleOrNull(map['targetFat']),` add:

```dart
      targetFiber: _toDoubleOrNull(map['targetFiber']),
```

- [ ] **Step 5: Run to verify it passes (all three model/math test files)**

Run: `cd "D:\flutter works\trainersHQ" && flutter test test/diet_plan_label_test.dart test/diet_math_test.dart test/food_item_model_label_test.dart`
Expected: PASS (this also closes Task 1 Step 6 and Task 2).

- [ ] **Step 6: Analyze**

Run: `cd "D:\flutter works\trainersHQ" && flutter analyze lib/core/utils/diet_math.dart lib/core/models/food_item_model.dart lib/core/models/diet_plan_model.dart`
Expected: `No issues found!`

- [ ] **Step 7: Commit Tasks 1–3 together** (shared compile unit)

```bash
cd "D:\flutter works\trainersHQ"
git add lib/core/utils/diet_math.dart lib/core/models/food_item_model.dart lib/core/models/diet_plan_model.dart test/diet_math_test.dart test/food_item_model_label_test.dart test/diet_plan_label_test.dart
git commit -m "feat(diet): add fiber/sugar/saturatedFat to nutrition model + math"
```

---

### Task 4: Food authoring — input + save the 3 fields

**Files:**
- Modify: `D:\flutter works\trainersHQ\lib\features\food\controllers\food_controller.dart`
- Modify: `D:\flutter works\trainersHQ\lib\features\food\screens\create_food_screen.dart`

**Interfaces:**
- Consumes: `FoodItemModel.fiber/sugar/saturatedFat` (Task 2).
- Produces: `FoodController.saveFood({... double fiber = 0, sugar = 0, saturatedFat = 0})` persisting them.

- [ ] **Step 1: Add params to `saveFood`** — in `food_controller.dart`, in the `saveFood({...})` signature after `double fat = 0,` add:

```dart
    double fiber = 0,
    double sugar = 0,
    double saturatedFat = 0,
```

In the `data` map after `'fat': fat,` add:

```dart
      'fiber': fiber,
      'sugar': sugar,
      'saturatedFat': saturatedFat,
```

- [ ] **Step 2: Add controllers + prefill + dispose** — in `create_food_screen.dart`:

After `final _fat = TextEditingController();` add:

```dart
  final _fiber = TextEditingController();
  final _sugar = TextEditingController();
  final _satFat = TextEditingController();
```

In `initState`, inside `if (e != null) {` after `_fat.text = e.fat.toStringAsFixed(0);` add:

```dart
      _fiber.text = e.fiber.toStringAsFixed(0);
      _sugar.text = e.sugar.toStringAsFixed(0);
      _satFat.text = e.saturatedFat.toStringAsFixed(0);
```

In `dispose`, change the list to include the new controllers:

```dart
    for (final x in [_name, _serving, _calories, _protein, _carbs, _fat, _fiber, _sugar, _satFat]) {
      x.dispose();
    }
```

- [ ] **Step 3: Add the input row** — in the NUTRITION card, immediately after the closing `),` of the existing `Row(children: [Protein, Carbs, Fat])` (the `Expanded` for `_fat`), add a spacer + second row:

```dart
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _fiber,
                        label: 'Fiber (g)',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppTextField(
                        controller: _sugar,
                        label: 'Sugar (g)',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppTextField(
                        controller: _satFat,
                        label: 'Sat. fat (g)',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
```

- [ ] **Step 4: Pass to `saveFood`** — in `_submit`, in the `c.saveFood(...)` call after `fat: _d(_fat),` add:

```dart
      fiber: _d(_fiber),
      sugar: _d(_sugar),
      saturatedFat: _d(_satFat),
```

- [ ] **Step 5: Analyze**

Run: `cd "D:\flutter works\trainersHQ" && flutter analyze lib/features/food/`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd "D:\flutter works\trainersHQ"
git add lib/features/food/controllers/food_controller.dart lib/features/food/screens/create_food_screen.dart
git commit -m "feat(food): trainer enters fiber/sugar/saturated fat per 100 g"
```

---

### Task 5: Diet plan builder — thread the 3 fields + fiber target

**Files:**
- Modify: `D:\flutter works\trainersHQ\lib\features\diet_plans\screens\create_diet_plan_screen.dart`
- Modify: `D:\flutter works\trainersHQ\lib\features\diet_plans\controllers\diet_plan_controller.dart`

**Interfaces:**
- Consumes: `NutritionTotals.fiber/sugar/saturatedFat` (Task 1), `FoodItemModel.*` (Task 2), `DietItem.*`/`DietPlanModel.targetFiber` (Task 3).
- Produces: `DietPlanController.savePlan({... double? targetFiber})`.

- [ ] **Step 1: Carry the 3 fields through every `NutritionTotals(...)` construction** — in `create_diet_plan_screen.dart` there are NutritionTotals built from a source object. For EACH, add the 3 fields reading from the same source:

  - In `_prefillForEdit` (per-100g reconstruction, the `it.x / g * 100` block) after `fat: it.fat / g * 100,` add:
    ```dart
        fiber: it.fiber / g * 100,
        sugar: it.sugar / g * 100,
        saturatedFat: it.saturatedFat / g * 100,
    ```
  - In `_prefillForEdit` (per-serving block, `NutritionTotals(calories: it.calories, ...)`) after `fat: it.fat),` insert before the `)`:
    ```dart
        // becomes: ..., fat: it.fat, fiber: it.fiber, sugar: it.sugar, saturatedFat: it.saturatedFat),
    ```
    i.e. replace `fat: it.fat)` with `fat: it.fat, fiber: it.fiber, sugar: it.sugar, saturatedFat: it.saturatedFat)`.
  - In `_fromLibrary` (both `NutritionTotals(calories: f.calories, ... fat: f.fat)` sites) replace `fat: f.fat)` with `fat: f.fat, fiber: f.fiber, sugar: f.sugar, saturatedFat: f.saturatedFat)`.
  - In `_chooseOnline` (`NutritionTotals(calories: s.calories, ... fat: s.fat)`) replace `fat: s.fat)` with `fat: s.fat, fiber: s.fiber, sugar: s.sugar, saturatedFat: s.saturatedFat)`. (`s.fiber` etc. come from Task 7.)

- [ ] **Step 2: Write the 3 fields into the cached library food** — in the `createReturning({...})` map (caching a bundled/online food), after `'fat': t.base.fat,` add:

```dart
          'fiber': t.base.fiber,
          'sugar': t.base.sugar,
          'saturatedFat': t.base.saturatedFat,
```

- [ ] **Step 3: Put the 3 fields on the built `DietItem`** — in the `final item = DietItem(...)` build, after `fat: r.fat,` add:

```dart
      fiber: r.fiber,
      sugar: r.sugar,
      saturatedFat: r.saturatedFat,
```

- [ ] **Step 4: Add the fiber target controller + prefill + dispose + save** — in `create_diet_plan_screen.dart`:

After `final _tF = TextEditingController();` add:

```dart
  final _tFiber = TextEditingController();
```

In the edit-prefill block, after `if (e.targetFat != null) _tF.text = e.targetFat!.toStringAsFixed(0);` add:

```dart
      if (e.targetFiber != null) {
        _tFiber.text = e.targetFiber!.toStringAsFixed(0);
      }
```

In `dispose`, add `_tFiber` to the controller list: `for (final t in [_name, _desc, _tCal, _tP, _tC, _tF, _tFiber]) {`.

In the `c.savePlan(...)` call, after `targetFat: _showTargets ? _parseTarget(_tF) : null,` add:

```dart
      targetFiber: _showTargets ? _parseTarget(_tFiber) : null,
```

- [ ] **Step 5: Add the fiber target input field** — in the `if (_showTargets) ...[` target editor, after the Row containing `_targetField(_tF, 'Fat', 'g')` add:

```dart
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _targetField(_tFiber, 'Fiber', 'g')),
                const Spacer(),
              ],
            ),
```

- [ ] **Step 6: Show fiber + "of which" in the summary card** — in `_summaryCard`, after `final tF = _showTargets ? _parseTarget(_tF) : null;` add:

```dart
    final tFiber = _showTargets ? _parseTarget(_tFiber) : null;
```

Change `anyTarget` to include it:

```dart
    final anyTarget =
        tCal != null || tP != null || tC != null || tF != null || tFiber != null;
```

After the `if (tF != null) ...[` VsTargetBar block (inside `if (anyTarget)`), add:

```dart
            if (tFiber != null) ...[
              const SizedBox(height: 10),
              VsTargetBar(
                  label: 'Fiber', value: totals.fiber, target: tFiber, unit: 'g'),
            ],
```

After the top `Row(...MacroDonut + MacroLegend...)` closes (before `if (anyTarget)`), add an always-on "of which / fiber" detail line:

```dart
          const SizedBox(height: 10),
          Text(
            'Fiber ${totals.fiber.toStringAsFixed(0)} g  ·  '
            'of which sugar ${totals.sugar.toStringAsFixed(0)} g  ·  '
            'sat. fat ${totals.saturatedFat.toStringAsFixed(0)} g',
            style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
          ),
```

- [ ] **Step 7: Add `targetFiber` to `savePlan`** — in `diet_plan_controller.dart`, in the `savePlan({...})` signature after `double? targetFat,` add:

```dart
    double? targetFiber,
```

In the `data` map after `'targetFat': targetFat,` add:

```dart
      'targetFiber': targetFiber,
```

- [ ] **Step 8: Analyze**

Run: `cd "D:\flutter works\trainersHQ" && flutter analyze lib/features/diet_plans/`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
cd "D:\flutter works\trainersHQ"
git add lib/features/diet_plans/screens/create_diet_plan_screen.dart lib/features/diet_plans/controllers/diet_plan_controller.dart
git commit -m "feat(diet): builder carries fiber/sugar/sat-fat + optional fiber target"
```

---

### Task 6: Diet plan detail — read-only display of the 3 fields

**Files:**
- Modify: `D:\flutter works\trainersHQ\lib\features\diet_plans\screens\diet_plan_detail_screen.dart`

**Interfaces:**
- Consumes: `DietItem.fiber/sugar/saturatedFat`, `planTotals` (now includes them).

- [ ] **Step 1: Read the totals/summary region**

Run: `cd "D:\flutter works\trainersHQ" && sed -n '90,130p;275,330p' lib/features/diet_plans/screens/diet_plan_detail_screen.dart`
Note where `planTotals`/`MacroLegend`/the kcal totals render (around lines 100–115 and 280–320 per the earlier grep).

- [ ] **Step 2: Add a fiber + "of which" detail line under the macro summary** — directly beneath the existing macro donut/legend or totals row (mirror the create-screen wording), insert:

```dart
          const SizedBox(height: 10),
          Text(
            'Fiber ${totals.fiber.toStringAsFixed(0)} g  ·  '
            'of which sugar ${totals.sugar.toStringAsFixed(0)} g  ·  '
            'sat. fat ${totals.saturatedFat.toStringAsFixed(0)} g',
            style: AppText.body(size: 11.5).copyWith(color: context.palette.textMuted),
          ),
```

> Use the local totals variable already in scope (the file computes `planTotals(items)` / a `totals` for the donut at ~line 100). If the totals are computed inline as `kcal` only, add `final totals = planTotals(items);` just above the insertion. Confirm the exact variable name from Step 1 and match it.

- [ ] **Step 3: Analyze**

Run: `cd "D:\flutter works\trainersHQ" && flutter analyze lib/features/diet_plans/screens/diet_plan_detail_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd "D:\flutter works\trainersHQ"
git add lib/features/diet_plans/screens/diet_plan_detail_screen.dart
git commit -m "feat(diet): show fiber + of-which sugar/sat-fat on plan detail"
```

---

### Task 7: USDA lookup wrapper — FoodApiServings carries the 3 fields

**Files:**
- Modify: `D:\flutter works\trainersHQ\lib\core\services\cloud_functions_service.dart`

**Interfaces:**
- Produces: `FoodApiServings.fiber/sugar/saturatedFat` (double, default 0), parsed from the CF `per100` map.

- [ ] **Step 1: Add fields to `FoodApiServings`** — after `final double fat;` add:

```dart
  final double fiber;
  final double sugar;
  final double saturatedFat;
```

In the const ctor after `this.fat = 0,` add:

```dart
    this.fiber = 0,
    this.sugar = 0,
    this.saturatedFat = 0,
```

- [ ] **Step 2: Parse them in `getFoodServings`** — in the `return FoodApiServings(...)` (where `calories: _toDouble(per['calories'])` is built), after `fat: _toDouble(per['fat']),` add:

```dart
      fiber: _toDouble(per['fiber']),
      sugar: _toDouble(per['sugar']),
      saturatedFat: _toDouble(per['saturatedFat']),
```

- [ ] **Step 3: Analyze**

Run: `cd "D:\flutter works\trainersHQ" && flutter analyze lib/core/services/cloud_functions_service.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd "D:\flutter works\trainersHQ"
git add lib/core/services/cloud_functions_service.dart
git commit -m "feat(food): USDA lookup result carries fiber/sugar/saturated fat"
```

---

### Task 8: Cloud Function `getFoodServings` — read USDA fiber/sugar/saturated fat

**Files:**
- Modify: `D:\flutter works\trainersHQ\functions\src\food.ts`

**Interfaces:**
- Produces: `getFoodServings` `per100` includes `fiber`, `sugar`, `saturatedFat`.

- [ ] **Step 1: Add USDA nutrient ids** — after `const N_FAT = 1004;` add:

```ts
const N_FIBER = 1079; // Fiber, total dietary
const N_SUGAR = 2000; // Total Sugars (fallback 1063 below)
const N_SUGAR_ALT = 1063; // Sugars, total including NLEA (legacy SR foods)
const N_SATFAT = 1258; // Fatty acids, total saturated
```

- [ ] **Step 2: Include them in the per-100g object** — in `getFoodServings`, replace the `per100` object with:

```ts
  const sugar = detailNut(food, N_SUGAR) || detailNut(food, N_SUGAR_ALT);
  const per100 = {
    calories: detailNut(food, N_ENERGY),
    protein: detailNut(food, N_PROTEIN),
    carbs: detailNut(food, N_CARBS),
    fat: detailNut(food, N_FAT),
    fiber: detailNut(food, N_FIBER),
    sugar,
    saturatedFat: detailNut(food, N_SATFAT),
  };
```

- [ ] **Step 3: Build (tsc)**

Run: `cd "D:\flutter works\trainersHQ\functions" && npm run build`
Expected: tsc completes with no errors.

- [ ] **Step 4: Commit**

```bash
cd "D:\flutter works\trainersHQ"
git add functions/src/food.ts
git commit -m "feat(functions): getFoodServings returns USDA fiber/sugar/saturated fat"
```

---

### Task 9: Cloud Function `getMyTraining` (buildDiet) — emit the 3 fields + targetFiber

**Files:**
- Modify: `D:\flutter works\trainersHQ\functions\src\members.ts`

**Interfaces:**
- Produces: per-item `fiber/sugar/saturatedFat` and plan `targetFiber` in the `getMyTraining` diet payload.

- [ ] **Step 1: Read + fallback the 3 fields per item** — in `buildDiet`, the loop currently reads `protein/carbs/fat` and falls back to `foodDatabase` when all are 0. After the `let fat = num(it.fat);` line add:

```ts
    let fiber = num(it.fiber);
    let sugar = num(it.sugar);
    let saturatedFat = num(it.saturatedFat);
```

Inside the existing `if (foodId && protein === 0 && carbs === 0 && fat === 0) {` fallback block, after the `fat = num(f.fat);` line add:

```ts
        fiber = num(f.fiber);
        sugar = num(f.sugar);
        saturatedFat = num(f.saturatedFat);
```

- [ ] **Step 2: Emit them on the item** — in the returned item object, after `fat,` add:

```ts
      fiber,
      sugar,
      saturatedFat,
```

- [ ] **Step 3: Emit the plan target** — in the returned plan object, after `targetFat: plan.targetFat != null ? num(plan.targetFat) : null,` add:

```ts
    targetFiber: plan.targetFiber != null ? num(plan.targetFiber) : null,
```

- [ ] **Step 4: Build (tsc)**

Run: `cd "D:\flutter works\trainersHQ\functions" && npm run build`
Expected: tsc completes with no errors.

- [ ] **Step 5: Commit**

```bash
cd "D:\flutter works\trainersHQ"
git add functions/src/members.ts
git commit -m "feat(functions): getMyTraining emits fiber/sugar/sat-fat + targetFiber"
```

---

### Task 10: Member Diet screen — fiber in totals + "of which" + per-food macros

**Files:**
- Modify: `D:\flutter works\alphaserena\lib\screens\dashboard\client_diet_screen.dart`

**Interfaces:**
- Consumes: `getMyTraining` diet items now carrying `fiber/sugar/saturatedFat` (Task 9). `home_controller.dart` needs **no change** (its `_sumDietField('fiber')` already exists).

- [ ] **Step 1: Add fiber to the totals row + "of which" line** — replace `_totals(...)` body with:

```dart
  Widget _totals(AppPalette p, List<Map<String, dynamic>> items) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: AppRadii.lgR,
        gradient: const LinearGradient(
          colors: BrandColors.selectedGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _macro('KCAL', _sum(items, 'calories')),
              _macro('PROTEIN', _sum(items, 'protein')),
              _macro('CARBS', _sum(items, 'carbs')),
              _macro('FAT', _sum(items, 'fat')),
              _macro('FIBER', _sum(items, 'fiber')),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'of which sugar ${_sum(items, 'sugar').round()} g  ·  '
            'sat. fat ${_sum(items, 'saturatedFat').round()} g',
            style: AppText.body(size: 11)
                .copyWith(color: Colors.white70, letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 2: Add a per-food macro line** — in `_foodCard`, after the `if (qty.isNotEmpty) Text(qty, ...)` widget (still inside the name/qty `Column`'s `children`), add:

```dart
                Builder(builder: (_) {
                  final pr = (f['protein'] is num) ? (f['protein'] as num).round() : 0;
                  final cb = (f['carbs'] is num) ? (f['carbs'] as num).round() : 0;
                  final ft = (f['fat'] is num) ? (f['fat'] as num).round() : 0;
                  final fb = (f['fiber'] is num) ? (f['fiber'] as num).round() : 0;
                  return Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('P$pr · C$cb · F$ft · Fiber$fb',
                        style: AppText.body(size: 11).copyWith(color: p.textMuted)),
                  );
                }),
```

- [ ] **Step 3: Analyze**

Run: `cd "D:\flutter works\alphaserena" && flutter analyze lib/screens/dashboard/client_diet_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd "D:\flutter works\alphaserena"
git add lib/screens/dashboard/client_diet_screen.dart
git commit -m "feat(diet): member sees fiber in totals + of-which sugar/sat-fat + per-food macros"
```

---

### Task 11: Whole-repo verification + deploy handoff

**Files:** none (verification).

- [ ] **Step 1: trainersHQ full analyze + test**

Run: `cd "D:\flutter works\trainersHQ" && flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass.

- [ ] **Step 2: trainersHQ functions build**

Run: `cd "D:\flutter works\trainersHQ\functions" && npm run build`
Expected: tsc clean.

- [ ] **Step 3: alphaserena full analyze**

Run: `cd "D:\flutter works\alphaserena" && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Deploy handoff (USER ACTION)** — tell the user to run, from `D:\flutter works\trainersHQ`:

```bash
firebase deploy --only functions:getMyTraining,functions:getFoodServings
```

The member app will not show fiber/sugar/sat-fat until this completes.

- [ ] **Step 5: Manual end-to-end checklist** (after deploy)
  - trainersHQ: add a food with fiber/sugar/sat-fat → values persist on reopen (edit screen).
  - trainersHQ: add that food to a diet plan; change grams → fiber/sugar/sat-fat scale; summary shows the "of which" line; set a Fiber target → vs-target bar appears.
  - Assign the plan to a member.
  - alphaserena: member Home nutrition card shows real fiber; Diet screen totals show FIBER + the "of which" line; each food card shows the macro line.

---

## Self-review notes
- **Spec coverage:** food fields (T2,T4), diet item + targetFiber (T3,T5), diet math (T1), builder + detail (T5,T6), USDA lookup (T7,T8), getMyTraining (T9), member diet screen (T10), home unchanged (verified, T10 interface note). All spec parts covered.
- **Type consistency:** field names `fiber`/`sugar`/`saturatedFat` and `targetFiber` used identically across Dart + TS + tests.
- **Ordering caveat:** Tasks 1–3 share one Dart compile unit; their tests only pass once all three are implemented — committed together in Task 3 Step 7 (called out in Task 1 Step 5 note).
