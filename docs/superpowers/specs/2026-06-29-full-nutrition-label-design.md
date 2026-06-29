# Full nutrition label — trainer maintains fiber / sugar / saturated fat (design)

> 2026-06-29. Cross-app, cross-repo feature. Adds three new nutrition fields —
> **fiber, sugar, saturated fat** (all grams) — so the trainer (trainersHQ)
> maintains the complete nutrition label, and the data flows to the member app
> (alphaserena) via the existing `getMyTraining` Cloud Function.

## Goal
Today the platform stores only **calories, protein, carbs, fat**. The member
home already *renders* a fiber macro but has no data source, and there is no
sugar / saturated-fat anywhere. Let the trainer enter the full label on a food
and a diet plan; surface it to the member.

New fields (all grams, default `0`):
- `fiber` — dietary fiber.
- `sugar` — "of which sugars" (subset of carbs, informational).
- `saturatedFat` — "of which saturated fat" (subset of fat, informational).

Sodium and other micros are explicitly **out of scope**.

## Approach
**Mirror the existing macro pattern exactly.** Add `fiber`, `sugar`,
`saturatedFat` as siblings of `fat` everywhere `fat` appears — same defensive
`_toDouble` parsing, same gram-scaling, same `toMap`/`fromMap`. All three are
optional with `0` defaults, so **every existing food / diet plan keeps working
untouched** (legacy data reads `0`). No migration. No new collections/indexes.

Rejected alternative: a generic `micros: Map<String,double>` bag — more
extensible but breaks the named-field convention and complicates the UI + Cloud
Function; overkill for three fixed fields.

## Field placement decision
- **Food + DietItem (item-level):** all three (`fiber`, `sugar`, `saturatedFat`).
- **Plan-level daily target:** **`targetFiber` only.** Fiber is a primary macro
  shown on the member home, so it gets a target like cal/protein/carbs/fat.
  Sugar & saturated fat are "of which" details — value + totals only, **no daily
  target** (YAGNI line, confirmed with founder).
- **Member home:** unchanged code — shows the 5 macros; `fiber` lights up with
  real data once the CF sends it.
- **Member Diet screen:** shows fiber in totals and sugar + saturated fat as
  "of which" detail.

---

## Part A — trainersHQ (Dart authoring + storage)

### A1. `lib/core/models/food_item_model.dart`
Add to `FoodItemModel` (per-100 g): `final double fiber, sugar, saturatedFat;`
(default `0`). Parse in `fromMap` with the existing `_toDouble`
(`fiber: _toDouble(map['fiber'])`, etc.). Constructor params default `0`.

### A2. `lib/features/food/controllers/food_controller.dart`
`saveFood(...)` gains `double fiber = 0, sugar = 0, saturatedFat = 0` params and
writes them into the food map (next to `'fat': fat`).

### A3. `lib/features/food/screens/create_food_screen.dart`
- Three new `TextEditingController`s (`_fiber`, `_sugar`, `_satFat`); init from
  `existing`, dispose with the others.
- In the **NUTRITION · PER 100 g** card, add a second row under the P/C/F row:
  `Fiber (g)`, `Sugar (g)`, `Sat. fat (g)` (same 3-column layout, number
  keyboards).
- Pass them to `c.saveFood(... fiber: _d(_fiber), sugar: _d(_sugar),
  saturatedFat: _d(_satFat))`.

### A4. `lib/core/utils/diet_math.dart`
- `NutritionTotals` gains `fiber`, `sugar`, `saturatedFat` (default `0`, in the
  const ctor + `zero`).
- `scaleByGrams` scales the three by the same `f = grams/100` factor.
- `planTotals` sums the three across items.
- (`macroSplit` unchanged — split stays P/C/F by energy.)

### A5. `lib/core/models/diet_plan_model.dart`
- `DietItem` gains `fiber`, `sugar`, `saturatedFat` (default `0`) in the ctor,
  `fromMap` (`_toDouble`), and `toMap` (always written, like the existing
  macros).
- `DietPlanModel` gains `targetFiber` (`double?`, parsed with
  `_toDoubleOrNull`); include it in `hasTarget` (`|| targetFiber != null`).

### A6. `lib/features/diet_plans/screens/create_diet_plan_screen.dart`
- The food-quantity sheet (`_FoodQuantitySheet`) builds its `base`
  `NutritionTotals` from the food's per-100 g values **including the three new
  fields**, both for a library food and for the per-100/per-serving prefill on
  edit (the `it.fiber / g * 100` style reconstruction).
- The built `DietItem` carries the three (from the gram-scaled `totals`).
- Plan totals display: add **Fiber** to the totals/preview alongside
  protein/carbs/fat; show sugar & sat-fat as a small "of which" sub-line under
  the macro row.
- Plan target editor: add an optional **Fiber target** input next to the
  existing cal/protein/carbs/fat targets; persist as `targetFiber`.

### A7. `lib/features/diet_plans/screens/diet_plan_detail_screen.dart`
Show fiber in the plan/food breakdown and the "of which sugar / sat fat" detail
(mirrors the create-screen presentation). Read-only.

### A8. `lib/core/widgets/diet_visuals.dart` (if it renders a macro set)
If it renders the P/C/F macro chips/bars, add a fiber chip; leave the energy
split logic (P/C/F) unchanged. Confirm during implementation; no change if it
only handles the energy split.

> Note: `lib/core/services/indian_food_catalog.dart` seed foods are **left at
> `0`** for the new fields (no back-fill) — out of scope, safe via defaults.

---

## Part B — trainersHQ Cloud Functions (the data bridge) — **DEPLOY REQUIRED**

### B1. `functions/src/members.ts` → `buildDiet`
- For each item, read `fiber`, `sugar`, `saturatedFat` (via the existing `num()`
  helper). Extend the existing "macros all zero → pull from `foodDatabase`"
  fallback to also pull the three from the linked food doc.
- Add the three to the returned per-item object (next to `calories/protein/
  carbs/fat`).
- Add `targetFiber: plan.targetFiber != null ? num(plan.targetFiber) : null` to
  the returned plan targets.

### B2. `functions/src/food.ts` → `getFoodServings`
Add USDA nutrient ids so a looked-up food pre-fills the new fields:
`N_FIBER = 1079`, `N_SUGAR = 2000` (fallback `1063` "Sugars, total incl. NLEA"
if `2000` is `0`), `N_SATFAT = 1258`. Include `fiber/sugar/saturatedFat` in the
returned `per100`. (`searchFood` summary line may stay kcal/P/C/F.)

### Deploy
`firebase deploy --only functions:getMyTraining,functions:getFoodServings` from
`trainersHQ/`. The new fields do not reach the member app until this runs.
trainersHQ `functions` must `tsc` clean first.

---

## Part C — alphaserena (member app)

### C1. `lib/screens/dashboard/client_diet_screen.dart`
- `_totals`: add **FIBER** as a 5th `_macro` column (kcal / protein / carbs /
  fat / fiber). Under the gradient totals row, add a small "of which" line:
  `Sugar {sum}g · Sat. fat {sum}g` (uses the existing `_sum(items, key)`).
- `_foodCard`: add a compact macro line under the name/qty
  (`P{..} · C{..} · F{..} · Fiber{..}`) now that the data exists. Keep the kcal
  on the right.

### C2. `lib/controllers/home_controller.dart`
**No change required.** `_sumDietField('fiber')` already sums item-level
`fiber`; it returns real values once the CF sends them. (`targetSugar` /
`targetSaturatedFat` are not used on home.) The member home nutrition card's
`targetFiber` getter already exists and works off the item sum.

---

## Data flow
Trainer enters per-100 g values on a **Food** (or imports from USDA) → builds a
**Diet plan** (values gram-scale per item; plan totals + optional fiber target)
→ stored in `foodDatabase` / `dietPlans` → `getMyTraining` resolves per-item
fiber/sugar/saturatedFat + `targetFiber` → member **Home** shows real fiber,
member **Diet screen** shows the full label.

## Backward compatibility & errors
- All new fields default `0`, parsed defensively (`_toDouble` / `num()`).
- Legacy foods/plans without the fields read `0` everywhere — no breakage, no
  migration.
- The CF zero-macros fallback is extended to the new fields, so an old diet
  item linked to a (newly) enriched food still resolves them.

## Out of scope
- Sodium, trans fat, cholesterol, other micros.
- Sugar / saturated-fat daily targets.
- Back-filling existing foods (seed catalog or admin-entered) with the new
  values.
- Member-side diet *logging* of these fields (separate designed feature).

## Verification
- trainersHQ: `flutter analyze` clean; `functions` `tsc`/lint clean.
- alphaserena: `flutter analyze` clean.
- Manual end-to-end: create a food with fiber/sugar/sat-fat → add to a diet plan
  (verify gram-scaling on quantity change) → set a fiber target → assign to a
  member → deploy functions → member Home shows real fiber, Diet screen shows
  fiber in totals + the "of which" sugar/sat-fat line.
- Two commits (trainersHQ + alphaserena).
