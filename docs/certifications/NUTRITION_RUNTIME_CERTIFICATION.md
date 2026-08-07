# ALPHASERENA — NUTRITION MODULE
# LIVE RUNTIME VALIDATION · CTO CERTIFICATION

**Date:** 2026-08-03
**Method:** the real application, driven as a real member, on emulator-5554,
against a real backend (real security rules, real Cloud Functions, real
Firestore, real signed-in session). No fixtures, no mocked controllers, no
faked repositories.

---

## 1. EXECUTIVE SUMMARY

**A member-facing BLOCKER was found that no test, no audit and no Patrol run had
ever seen — and it was found within ten minutes of using the app as a member.**

The member logged a food. The write landed in Firestore. The Cloud Function
computed it. The rollup was written. And the app told them
**"Nothing logged yet today"** — through a full restart. Their own food was
permanently invisible on every nutrition surface.

That is the whole case for this mission. Every prior pass certified this module
green: 1 097 Flutter tests, 1 027 backend tests, 386 rules tests, 52 Patrol
tests on real hardware. All of them passed while this was live, because every
one of them constructs a member who is **already fully linked**, and the defect
lives in the moment *before* that is true.

### The runtime session, end to end

| Step | Result |
|---|---|
| Coach sets targets via the real `setNutritionTargets` callable | ✅ versioned map + legacy mirror written |
| Member signs in (real OTP, real session) | ✅ `member-uid-1` |
| `getMyTraining` with **no diet plan** | ✅ `diet: null`, `nutritionTargets: 2000 kcal` — **H2 fix proven live** |
| Diet screen on an **unlogged day** | ✅ honest empty state, not a permission denial — **N1 fix proven live** |
| Two-tier food search (org + global) | ✅ org first, correct macros and tiers |
| Log 1 katori Paneer Tikka | ✅ 375 kcal / 27P / 9C / 27F / 1.5 fiber — exact |
| **Rapid double-tap on submit** | ✅ exactly **1** entry |
| Cloud Function `computed` | ✅ exact match to UI; adherence 0.188 = 375/2000, 0.45 = 27/60 |
| `nutrition_rollups` month cell | ✅ written with totals + adherence |
| **Food visible in the app** | ❌ **BLOCKER — see N15** |
| After N15 fix, same journey | ✅ Home, My Plans, Diet, Firestore, CF all agree |
| History across a **45-day gap** | ✅ 19 Jun reached — **H3 fix proven live** |
| Coach assigns diet plan | ✅ served, macros hydrated from the food library |

---

## 2. ARCHITECTURE (as exercised, not as documented)

```
TrainerHQ ──setNutritionTargets (callable, coach-authed)──► clients/{id}.nutritionTargets  (v1)
                                                        └► clients/{id}.dietTargets  (legacy mirror)
          ──client_plan_assignments (planType:'diet', status)──► dietPlans/{id}

getMyTraining (member-authed)
   ├─ memberEntitled gate
   ├─ assignment scan → ACTIVE diet only → buildDiet → items hydrated from foodDatabase
   ├─ diet.targets       ┐
   └─ nutritionTargets   ┴── ONE producer: servedTargetsWire()  ← proven identical at runtime

searchMemberFoods ──► foodDatabase: org tier (adminId, + legacy fallback scan)
                                    global tier (scope=='global', published, prefix tokens)

Member write ──set(merge)──► client_nutrition_days/{clientId}_{yyyy-MM-dd}
                                   │
                  onNutritionDayWritten (trigger)
                                   ├──► day.computed        (totals + targetAdherence)
                                   └──► nutrition_rollups/{clientId}_{YYYY-MM}

Member read  ──snapshots()──► FoodLogController ──► Home card · My Plans ring · Diet screen
History      ──31 deterministic gets per window, horizon 366d──► FoodHistoryController
```

**The one structural fact this mission established:** the read path binds on
`canLog`, and `canLog` depends on **two independent Firestore streams**
(`clientProfiles` for `clientId`, `clients` for `adminId`). Nothing in the
module had ever accounted for their arrival order.

---

## 3. DEFECTS FOUND AT RUNTIME

### 🔴 N15 — BLOCKER · The food log never bound, so logged food was invisible

- **Layer:** `food_log_controller.dart` (binding) + `nutrition_day_service.dart:74`
- **Symptom, observed:** member logs food → write succeeds → CF computes it →
  Home ring stays at 2000 kcal left, My Plans says "Nothing logged yet today",
  Diet screen offers "Add your first food". **Survives a full app restart.**
- **Root cause:** the rebind was `ever(_member.isLinked, …)`. `isLinked` flips
  true when the *profile* resolves, which is typically **before** the `clients`
  document lands — so `_bind()` re-ran while `adminId` was still empty, took the
  `!canLog` branch and subscribed to nothing. When `adminId` finally arrived,
  `isLinked` did not change again, so **nothing ever rebound**. `ever` fires on
  CHANGE, and the controller was watching the wrong fact.
  `watchDay` compounds it by returning `Stream.value(null)` — a single-value,
  immediately-completing stream — on the not-loggable path.
- **Why writes still worked:** `addEntry` re-evaluates `canLog` at call time, by
  which point it is true. **Writes worked while reads were dead** — which is
  precisely the shape that invites a member to log the same food again.
- **Why every test missed it:** all of them build a controller whose member is
  already fully linked. The defect only exists in the arrival-order window.
- **Fix:** rebind on what `canLog` actually depends on —
  `everAll([isLinked, client])` — guarded by a `_liveBound` flag so an
  established listener is never torn down and reopened on a coach edit.
- **Verified:** failing test first (`food_log_rebind_test.dart`, 3 cases), then
  the identical member journey on device: ring **1625 / 2000**, Protein
  **27/150**, Carbs **9/200**, Fat **27/60**, Fiber **2/30**, "1 item across 1
  meal · 375 kcal".

### 🟠 N14 — Home hides a real coach prescription when no plan is assigned

- **Layer:** `client_home_screen.dart:121` + `home_controller.dart:153`
- **Observed:** with targets set and **no** diet plan, My Plans showed the full
  ring (2000 kcal, all four macros) while **Home rendered no nutrition card at
  all** — it showed "Getting Started · Complete your onboarding" instead.
- **Cause:** `hasPlan = workout != null || diet != null`. With no plan,
  `stage != ready`, and the whole dashboard body — including
  `_nutritionProgress` — is replaced by the lifecycle guide.
- **Why it matters now:** before the H2 repair this was harmless, because a
  member with no plan genuinely had no targets. H2 made targets
  plan-independent, so this state now hides a **real prescription** the coach
  set, on the member's primary surface, while another screen displays it. One
  fact, two screens, two answers.
- **NOT FIXED — deliberately.** The gate is a considered product decision
  ("guide them through onboarding → coach → plan instead of showing
  empty/placeholder plan content"), and the mission forbids UI redesign. The
  minimal fix is one condition: treat "has coach targets" as sufficient to
  render the nutrition card. **This is a product call, not mine.**

### 🟡 Observations (not defects, recorded)

- **A plan assigned mid-session does not reach an open app.** `getMyTraining` is
  a callable fetched on open / Home reload / pull-to-refresh, not a listener.
  Correct by design; worth knowing when a coach expects instant propagation.
- **Global-tier foods have no legacy fallback.** The org tier has an explicit
  `ORG_FALLBACK_SCAN` for libraries predating `searchTokens`; the global tier
  has none, so a global food with missing/stale tokens is invisible to every
  member with no recovery path. Safe today because `upsertGlobalFood` always
  writes tokens — but it is an asymmetry with no guard.
- **Google Sign-In could not complete** on this emulator: `google_sign_in`
  returns a null `idToken` without a configured `serverClientId`, so the app
  bails with "Please try again in a moment." Production auth is Google-only
  (`_showPhoneAuthentication = false`). **This path remains unvalidated.**

### 🔬 Hypotheses I raised and then DISPROVED (my own errors, recorded)

The mission requires destroying my own hypotheses. Three "defects" I suspected
turned out to be my seed data, not the product:

- ✗ *"Food search returns 0 kcal."* — I seeded a nested `per100` map; the schema
  stores **flat** macros (`doc.calories`). Backend was right.
- ✗ *"Global foods are unreachable."* — I hand-wrote `searchTokens`; the platform
  stores **prefix-expanded** tokens from `buildSearchTokens` (`ri`,`ric`,`rice`).
  Once seeded correctly, both tiers returned correctly.
- ✗ *"An active diet assignment is ignored."* — I wrote `type`; the field is
  **`planType`**, and ordering uses `createdAt`. Corrected, the plan served.

---

## 4–8. BACKEND · FIRESTORE · CLOUD FUNCTION · SECURITY VERIFICATION

- **Cloud Functions:** 120 loaded; `getMyTraining`, `setNutritionTargets`,
  `searchMemberFoods`, `onNutritionDayWritten` all exercised live.
- **Trigger chain:** `computed` totals matched the UI to the decimal;
  `targetAdherence` exact against the coach's targets
  (0.188 = 375/2000 · 0.18 = 27/150 · 0.045 = 9/200 · 0.45 = 27/60 · 0.05 = 1.5/30);
  `nutrition_rollups` month cell written with `origin: v1`. `targetsVersion: 1`
  matched the `setNutritionTargets` version.
- **Identity:** the day document carried `adminId: coach-uid-1`,
  `authorUid: member-uid-1` — created under real rules, so the create rule's
  ownership `get()` and id pinning both passed live.
- **Targets parity:** `diet.targets` and top-level `nutritionTargets` were
  **byte-identical** at runtime — the shared `servedTargetsWire` producer works.
- **Rules suite:** **386 / 386** on a real emulator.
- **Backend suite:** **1 027 / 1 027** (tsc + node:test).

## 9–16. FOOD DATABASE · TARGETS · HOME · LOGGING · HISTORY

- **Two-tier search:** `""` → org then global; `rice`/`basmati` → global only;
  `paneer` → org only. Correct macros and tier badges ("Your coach's").
- **Portion math:** 1 katori (150 g) of a 250 kcal/100 g food → **375 kcal,
  27 P, 9 C, 27 F, 1.5 fiber**. Exact.
- **Meal slot:** auto-selected Lunch at 12:29; entry stored `slot=lunch`.
- **Rapid double-tap:** exactly **1** entry — the `_submitting` guard holds
  under real input.
- **Home card:** ring 375 / 2000 with all four macros and proportional bars,
  subtitle "Today's nutrition".
- **History:** reached a log **45 days back across an empty 31-day window** —
  "Days logged 1 · Average day 1800 kcal · Fri, 19 Jun". Pre-H3 this was
  permanently unreachable.
- **Plan serving:** coach's two items hydrated from the food library
  (Paneer 375 / Rice 195 for 150 g each).

## 17–18. PERFORMANCE · PATROL

- One `FoodLogController` instance serves Home, My Plans and Diet; the N15 fix
  adds a `_liveBound` guard so a live listener is **not** re-subscribed on every
  `clients` snapshot (pinned by a regression test).
- **Flutter:** `analyze` clean · **1 100 tests, 14 failures** — all in
  `home_cards_golden_test.dart`, the documented pre-existing font/golden
  baseline, unchanged in file and count.
- **Patrol:** unchanged from the previous pass (52/52). ⚠️ **Patrol did not and
  could not catch N15** — its fixtures inject already-linked controllers. The
  new `food_log_rebind_test.dart` is the permanent guard.

---

## 19. REMAINING RISKS

### Resolved and proven at runtime
N1 (empty-day read) · H2 (targets without a plan) · H3 (history across a gap) ·
N15 (log binding) · portion math · duplicate-tap guard · trigger chain · rollups.

### Confirmed, NOT fixed — product decision required
- **N14** — Home hides the nutrition card when targets exist but no plan does.
  One-condition fix; deliberately left to you.

### Not exercised this pass — stated, not implied
- **Offline / reconnect / queued writes** — not driven on device.
- **Midnight rollover, multi-device, background/foreground** — not driven.
- **Edit / delete / undo / replace** of a logged entry — not driven.
- **Google Sign-In**, the actual production auth path — cannot complete on this
  emulator (see §3).
- **The TrainerHQ Flutter app itself** — the coach side was driven through the
  real callables and real documents, not through the coach UI.
- **TrainerHQ analytics surface** — `nutrition_rollups` is written correctly and
  still has **no reader** in any app (the prior audit's N6 stands).

### Carried forward, unchanged
N6 (write-only rollup pipeline) · N7 (dead legacy code + stale docs) ·
N8 (unbounded streak query) · N10 · N12 · N13.

---

## 20. PRODUCTION READINESS

**NOT FROZEN. One blocker was found and fixed today; the module is materially
stronger, and the remaining gap is deployment plus a short list of undriven
scenarios.**

What changed today is not a test result — it is that the member-facing loop was
**actually used** and produced a blocker that four green suites could not see.
That is the honest argument for one more short pass rather than a freeze.

**Blocking before freeze:**
1. **Deploy.** Nothing above reaches a member until this runs:
   ```bash
   firebase deploy --only firestore:rules,functions:getMyTraining
   ```
   Until then **N1 is still live in production** and H2 is still unserved.
   Answer **NO** to any prompt offering to delete indexes.
2. **Decide N14** — one condition, your call.
3. **Drive the undriven:** offline/reconnect, delete/edit/undo, midnight
   rollover, and Google Sign-In. Each is a real member behaviour; N15 is proof
   that "the tests cover it" is not the same as "someone did it".

**Test infrastructure added (debug-only, no release impact):**
- `lib/core/firebase_emulators.dart` — opt-in via
  `--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2`; unreachable in release
  (`kReleaseMode` short-circuit), data endpoints redirected before anything that
  can throw.
- `main.dart` — one call.
- `android/app/src/debug/` — network security config permitting cleartext to
  `10.0.2.2`/localhost **only**, in the debug source set alone.

`_showPhoneAuthentication` was flipped to `true` to obtain a member session and
**has been reverted to `false`**.
