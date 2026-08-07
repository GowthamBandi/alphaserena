# MY PLANS — REDESIGN REPORT (FOUNDATION DELIVERY)

**Date:** 2026-08-03 · **Device:** `emulator-5554`, Android 17 · **Backend:** unchanged, `trainershq-f5ded`
**Scope agreed:** unbacked fields omitted + coach-facing gap list · foundation this session, remainder next.

---

## 1. ARCHITECTURE SUMMARY

The old screen was **one 1436-line `StatefulWidget`** with 21 private builders, **zero tests**, and a
tab axis that answered the wrong question (*Current Plans / Previous Plans*, where "Previous" was a
hardcoded empty state no data could ever fill).

Replaced by **three files, 0 new controllers, 0 new listeners, 0 new backend calls**:

```
lib/screens/dashboard/plans/
  plan_segmented_control.dart   the two-tab control + PlanTab enum + per-tab accent
  plan_hero_card.dart           the shared "my coach assigned this" card + PlanFact
  my_plans_screen.dart          the shell: header · control · workout tab · diet tab
```

**Controller reuse is structural, not incidental.** Every accessor is
`Get.isRegistered<X>() ? Get.find<X>() : Get.put(X())` — `Get.find` first, so this screen can never
become a second owner of a stream the dashboard already owns. Data comes from `MemberController`,
`TrainingController`, `FoodLogController`, `HomeController`, `MembershipController` — all already live.

**Single source of truth with Home is structural too.** The Diet tab renders the *literal*
`NutritionProgressCard` + `DailyMetric` + `nutritionCardSubtitle` that Home renders, fed by the same
`FoodLogController` and the same `resolveNutritionTarget`. It is not a lookalike card, so the two
screens *cannot* drift. Proven on device: Home and this tab both read **1005 / 2000 kcal**.

`AnimatedSwitcher` + `KeyedSubtree` rather than `IndexedStack`, so only the visible tab is built and
the hidden discipline keeps no `Obx` subscriptions alive.

---

## 2. BEFORE vs AFTER

| | Before | After |
|---|---|---|
| Tab axis | Current / **Previous** (permanently empty) | **Workout / Diet** — the two things a coach assigns |
| Tab control | 2px underline under text; text-sized tap target | 56dp glass segmented control, spring slider, icons, half-width targets |
| Tab identity | one accent for both | **red = workout, green = diet** — the colour language Home already uses |
| Plan card | generic list rows | one hero card per discipline, "ASSIGNED BY YOUR COACH" |
| `Duration` | **`'Ongoing'` — hardcoded string** | **removed** (not served) |
| Plan image | **bundled stock asset shown as the member's plan** | **removed** (not served) |
| `Daily Calories` | plan item sum + hardcoded 2000 fallback | fixed earlier this session; now the canonical target |
| Nutrition card | bespoke re-implementation | **the same widget Home uses** |
| Routes to Diet | "Open Diet" **and** a "Log Food" pill | **one** CTA; card body still tappable |
| Calendar button | **dead `Container`, no gesture at all** | real button with semantics |
| Tests | **0** | **16** widget tests, all passing |

---

## 3. EVERY REUSED BACKEND FIELD

**Workout tab** — `workout.name` · `workout.items[].{name, sets, reps, muscleGroup, equipment,
thumbnailUrl}` · `workout.restDay` · `workout.weekly.days[]` · `workout.nextDay.{day, planName}` ·
`coach.name` · `MemberController.gymName` / `trainerName`.

**Diet tab** — `diet.name` · `diet.items[]` (count) · `nutritionTargets` / `diet.targets` /
`diet.target{Calories,Protein,Carbs,Fat,Fiber}` via `resolveNutritionTarget` (**provenance-gated:
only `isCoachGoal` becomes a target chip — a plan's item sum is never captioned as a goal**) ·
`FoodLogController.{entryCount, loggedCalories, loggedProtein, loggedCarbs, loggedFat, loggedFiber,
isLoading, loadError}`.

**Shell** — `MemberController.isLinked` · `MembershipController.isActive` · `TrainingController.{isLoading, error}`.

---

## 4. EVERY REMOVED UI ELEMENT, AND WHY

| Removed | Why |
|---|---|
| **"Previous Plans" tab** | Rendered a hardcoded empty state. No data source existed; nothing could ever appear. |
| **`Duration: 'Ongoing'`** | A hardcoded string presented as plan data. `buildWorkout` serves no duration. |
| **Workout plan image** | A **bundled asset** rendered as the member's own plan image. No plan image is served. |
| **Plan status chip** | I built one, then **deleted it after proving it could never work** — see §6. |
| **"Log Food" pill (this screen only)** | Duplicated the hero "Open Diet" CTA directly above it, and was brand-red inside a green tab. Kept on Home, where it is the only route. |
| **`_partnerCard`, `_weeklyRestCard`, `_planStat`, `_detail`, `_emptyPlans`** | Folded into the hero card / blockers; each was a second way to say something the card now says once. |

---

## 5. EVERY NEW INTERACTION

1. **Segmented control** — tap either half; spring slider travels; icon scales; label weight animates.
   Re-tapping the *selected* half fires nothing (no pointless rebuild + animation restart).
2. **Tab transition** — 260ms fade + 3% upward slide.
3. **Hero CTA** — `Start Workout` / `Open Diet`; **disabled** on a rest day; becomes a **green
   statement, not a button**, when today is complete (nothing left to tap).
4. **Calendar button** — now actually a button, with a semantics label.
5. **Nutrition card body** — tappable to the Diet screen.
6. **Pull-to-refresh** — re-claims the member and reloads training.

---

## 6. A BUG I SHIPPED AND THEN CAUGHT

I built a plan **status chip** reading `prescriptionData.workout.slices[].status`. It rendered
nothing on device. Rather than leave it, I checked the backend: `buildTrackPrescriptionData` returns
**`{versions, excusedDays}`** — there is **no `slices` key and no `status` field**. My chip was reading
a path that does not exist and failing silently.

Further, `getMyTraining` serves **only active assignments** — a paused or ended plan arrives as `null`,
indistinguishable from never having had one. So plan status is genuinely **not knowable** by the member
app, and a chip could only ever have said "Active", which is not information.

**Chip deleted; a test now pins that no status label is ever rendered.** This is exactly the failure
mode the field inventory exists to prevent, and it slipped through anyway — which is why the inventory
is now a checked-in document rather than a one-off analysis.

---

## 7. TESTS ADDED

`test/plan_segmented_control_test.dart` — **16 tests, all passing**:

*Control (8)* — both tabs labelled · **only one announces `isSelected`** (real semantics assertion) ·
tapping the unselected half reports the new tab · **tapping the selected half fires nothing** ·
56dp height + two half-width `InkWell`s · the two tabs carry **different** accents · 2.0× text at
320dp · light theme.

*Hero card (8)* — **with no facts, no chips at all** (explicitly asserts `Duration` / `Ongoing` /
`Not set` are absent) · only supplied facts render · plan/coach/org all appear · **no status chip is
ever rendered** · completed-today replaces the CTA with a statement and removes the button · a null
CTA disables rather than hides · today's line renders · **2.0× at 320dp without overflow**.

⚠️ **That last test found a real defect in my own card** — a `RenderFlex overflowed by 29 pixels` in
the fact chips at 320dp/2.0×. Fixed by making both halves of a chip `Flexible` (a `Wrap` hands its
child the line width as a *max*, so `Flexible` resolves to `min(content, available)`).

**Patrol: none added this session.** The Patrol work belongs with the tab bodies that are not built
yet; adding device tests for a foundation I am about to extend would pin the wrong contract.

---

## 8. REGRESSION

```
flutter analyze .................... 0 issues
flutter test ....................... 1139 pass / 14 fail   (was 1123 — +16 new, 0 regressions)
                                     all 14 are the SAME pre-existing matchesGoldenFile tests
                                     (home_cards_golden 8, home_header 4, log_transformation 1,
                                      serena_foundation 1) — none in files this work touched
debug APK ......................... builds, installs, runs
emulator .......................... both tabs verified live against production data
```

**Screenshots:** `shots/40_myplans_workout.png` (Workout tab) · `shots/43_diet_final.png` (Diet tab).

---

## 9. COACH-FACING GAP LIST — what TrainerHQ would need to author

Backend changes are out of scope; this is the spec for a future pass. Full detail in
`MY_PLANS_FIELD_INVENTORY.md`.

**Plan-level (workout + diet assignment docs)** — `difficulty` · `durationWeeks` · `frequencyPerWeek` ·
`startDate` (coach-authored, distinct from `createdAt`) · `coverImageUrl` · `badge`/`tag` ·
`planGoal` (today only the *member's* goal exists, which is not the plan's).

**Diet plan** — `mealNotes{}` per meal slot · `instructions` · `warnings` · `tips`
(today there is exactly **one** free-text `description`, plan-level).

**Workout session wire** — a per-exercise member `note` field · `caloriesBurned`
(not derivable: no MET, no bodyweight-at-time, no per-exercise duration).

**Assignment lifecycle** — `completed` and `archived` statuses (today: `active | paused | ended`), and
`getMyTraining` would need to **serve non-active assignments** for a plan-history timeline to exist at
all — today they are filtered out server-side and arrive as `null`.

---

## 10. WHAT IS NOT BUILT YET — CONTINUATION PLAN

Delivered: segmented control · hero card · shell · workout tab (plan + today's exercises) · diet tab
(plan + targets + the shared nutrition card).

**Not built, in the order I would take them next:**

1. **Today's Meals timeline** (Diet) — per-meal completion badge, calories, macros, time, food count,
   expand/chevron, and expanded food rows with edit + delete. All data exists in
   `FoodLogController.entriesByMeal`; the edit sheet and swipe-delete already work on the Diet screen
   and should be lifted into a shared widget rather than reimplemented.
2. **Exercise timeline expansion** (Workout) — per-set prescribed vs actual from `SetLog`, completed
   sets, rest, duration, completion badge, expand animation.
3. **Previous Workout + Weekly Consistency** — reuse the existing consistency engine and
   `StreakController`; **volume only where `weight` parses numerically** (it is a free-text String).
4. **Plan History timeline** — blocked: needs the backend to serve non-active assignments (§9).
5. **Coach Instructions** — only the plan-level `description` is renderable today.
6. **Patrol suite** + goldens + tablet/landscape/offline/realtime device verification.

---

## 11. CERTIFICATION

❌ **NOT certified production-ready — this is a foundation delivery, by agreement, not a finished module.**

What I *do* certify, with evidence: the three delivered files are analyze-clean, covered by 16 passing
tests including accessibility and 2.0×/320dp layout, verified live on the emulator against production
data on both tabs, introduce **no new controller, listener or backend call**, and render **no field the
backend does not serve** — the two fabrications the old screen shipped (`Duration: 'Ongoing'`, a
bundled stock plan image) are gone, and a third I introduced myself (the status chip) was caught and
removed before it could mislead anyone.

⚠️ **Unchanged and still blocking the wider module:** the undeployed Firestore rule documented in
`NUTRITION_PRODUCTION_FREEZE_REPORT.md`. A member who has not logged today cannot load the nutrition
data this Diet tab depends on. **My Plans cannot be certified while that is true, regardless of the UI.**
