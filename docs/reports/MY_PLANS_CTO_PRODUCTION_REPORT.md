# MY PLANS — CTO PRODUCTION REPORT

**Module:** My Plans (AlphaSerena member app) · **Date:** 2026-08-03
**Device:** `emulator-5554` — Pixel 9 Pro AVD, Android 17 (API 37)
**Backend:** `trainershq-f5ded` — the live production project
**Live member used:** client `EkNg2Yux4lPAQtSpQjds`, coach "ORG Name", plan "Workout Plan 11" / "Test Diet Plan"

> Every claim below is either backed by a command output, a device screenshot, or a file:line in this
> repo. Claims I could **not** prove are marked **UNPROVEN** and are excluded from the pass column.

---

## 1. PRODUCT DEFINITION APPLIED

Home answers *"what should I do right now"*. My Plans answers two different questions:

1. **What has my trainer assigned me?**
2. **What have I completed today?**

Before this pass the screen answered **(1) partially and (2) not at all**. On the live device the
Workout tab rendered a plan card, one exercise row, and then ~55% empty screen. Everything below was
scoped by whether it serves one of those two questions.

---

## 2. ARCHITECTURE VERIFICATION ✅

| Property | Verified how | Result |
|---|---|---|
| No new controller | file read | ✅ 0 added |
| No new Firestore listener | file read | ✅ 0 added |
| No new backend call | file read | ✅ 0 added |
| No second stream owner | every accessor is `Get.isRegistered<X>() ? Get.find<X>() : Get.put(X())` | ✅ |
| Analyzer | `flutter analyze` | ✅ **0 issues** |

My Plans reads **six already-registered controllers**: `MemberController`, `TrainingController`,
`FoodLogController`, `StreakController`, `HomeController`, `MembershipController`.

**Single source of truth is structural, not a promise.** Three surfaces on this screen are the
*literal* widgets other screens render, fed by the same controllers, so they cannot drift:

- `NutritionProgressCard` + `DailyMetric` — Home's own card.
- `FoodLogSection` — the Diet screen's own section (so edit, swipe-delete, undo, the queued-write
  indicator and the honest error state arrived already correct).
- `todayWorkoutPresentation` — the **same decision function Home uses** for rest/excused/paused/
  flexible/dormant days.

New file: `lib/screens/dashboard/plans/today_workout_section.dart` — renders today's session and
computes nothing; `SessionStats` is passed in from the one engine (`computeSessionStats`).

---

## 3. BACKEND VERIFICATION ✅ (read from source; **no backend behaviour changed**)

`trainershq-backend/functions/src/members.ts`:

- `getMyTraining` (L501) serves `{workout, diet, nutritionTargets, coach, expectation, prescriptionData}`.
- **Only ACTIVE assignments are served** (L559: `if (status === "paused" || status === "ended") continue;`).
  A paused/removed plan therefore arrives as `null` — indistinguishable from never having had one.
- `buildTrackPrescriptionData` (L737) returns **`{versions, excusedDays}`** — there is **no `slices`
  key and no `status` field**. A plan-status chip is therefore *unknowable* from the member app, which
  is why this screen renders none.
- Membership is gated server-side (L521, `memberEntitled`).
- `buildWorkout` can return **`dayPlanUnavailable: true`** (L296) when a weekly day-plan was deleted.

**Cloud Functions test suite:** `cd functions && npm test` → **1027 / 1027 pass, 0 fail.** No function
source was modified in this pass.

---

## 4. FIRESTORE + RULES VERIFICATION ✅ (one real defect found and fixed)

### 🔴 F-1 — `client_workout_sessions` denied reads of a session that does not exist yet

**Found on the device, against the live backend**, in the first logcat capture of the session:

```
W Firestore: Listen for Query(client_workout_sessions/ws_EkNg2Yux4lPAQtSpQjds_2026-08-03 …)
  failed: Status{code=PERMISSION_DENIED, description=Missing or insufficient permissions.}
```

**Root cause.** Session identity is deterministic (`ws_{clientId}_{yyyy-MM-dd}`), so
`StreakController._loadTodayStats` reads today's session **by id on every cold open** — before the
member's first set, that document does not exist. On a missing document `resource` is null, so every
ownership clause dereferences `resource.data` and **errors** instead of returning false; no clause can
return true and the read is **denied**.

This is the **identical defect shape** already fixed on `client_nutrition_days` and
`client_diet_logs`. It was never fixed here because that sweep was scoped **by collection name rather
than by defect shape** — the same mistake, one collection further along.

**Blast radius today:** contained. `WorkoutLogService.fetchSession` falls back to cache and returns
null, which happens to equal the truth ("no session yet"), so there is no member-visible symptom
*today*. It is fixed anyway: the containment is an accident of the fallback, not of the rule, and any
surface putting a **listener** on that document would inherit the dead-listener failure mode.

**Fix:** `firestore.rules` — added `(resource == null && signedIn())` to the read rule. It grants no
data (a null resource has no fields).

**Proved both ways on a real Firestore emulator:**

| Rule shape | `an unlogged workout session is readable` | `a LISTENER … is not denied` |
|---|---|---|
| pre-fix (clause stripped) | ❌ DENIED | ❌ DENIED |
| repo (fixed) | ✅ ok | ✅ ok |

Three new tests in `tests/rules/nutrition_food_log_write.mjs`, including
`the empty session stays PRIVATE once it exists` — proving the grant buys availability, never exposure.

### Rules suite result

Run per file (see §11 for why the multi-file invocation is not usable):

```
firestore_rules.test.mjs .................. 268 / 268
lifestyle_read_path_validation.mjs .........  20 /  20
lifestyle_targets_validation.mjs ...........  18 /  18
member_profile_editor_write.mjs ............  17 /  17
member_role_gate_reads.mjs .................  15 /  15
member_rollup_read.mjs .....................   5 /   5
n17_cross_tenant_food_write.mjs ............   5 /   5
nutrition_food_log_write.mjs ...............  23 /  23   (+3 new)
                                            ───────────
                                             371 / 371   0 failures
```

**Indexes:** none required. Every My Plans read is a document read by deterministic id, or the
existing single-field `authorId ==` query. No `.where()` + `orderBy` combination was added.

---

## 5. TRAINERHQ SYNCHRONISATION VERIFICATION ✅ (source-certified) / ⚠️ (not exercised on a coach device)

Verified by reading the consumer, not by assuming:

| Member action | Coach path | Realtime? | Verified |
|---|---|---|---|
| Logs food | `ClientLogsService.watchNutritionDays` → `.snapshots()` | ✅ live | ✅ source |
| Edits food | same listener; `consumed` snapshot rewritten | ✅ live | ✅ source |
| Deletes food | writes `{deleted: true}`; `ClientNutritionDayModel.fromMap` **skips `deleted == true`** | ✅ live | ✅ source + device |
| Undo | clears the flag; the entry reappears | ✅ live | ✅ device |
| Workout sets | `watchWorkoutSessions` → `.snapshots()` | ✅ live | ✅ source |

**Totals cannot disagree.** Both sides sum the member's **frozen `consumed` snapshots** over live
entries — `FoodLogController.totals` (`sumMacros`) and `consumedForNutritionDay` are the same
operation over the same values, and the server's `computeDayTotals` is a third copy of it. A food
re-costed or archived later cannot move a past day.

⚠️ **UNPROVEN:** the coach-side TrainerHQ app was **not run**. No coach session exists on this
machine. Synchronisation is certified from the producer's wire shape and the consumer's parser — not
from watching a coach's screen update.

---

## 6. BUGS DISCOVERED, ROOT CAUSES, FIXES

### 🔴 M-1 — The Workout tab's primary CTA was a dead end (**verified on device**)

Tapping **Start Workout** raised `Get.snackbar('Start Workout', 'Open it from Home → Start Workout.')`.
The primary action of this screen's primary tab was a **sign pointing at another screen**.
Screenshot captured before the fix.

**Root cause:** the previous pass shipped the shell before wiring the destinations.
**Fix:** real navigation to `WorkoutBriefingScreen` (the same entry point Home uses), with the label
resolved by state — `Start Full Workout` / `Resume Workout` / `Review Workout` / a non-tappable
`Workout complete`.

### 🔴 M-2 — The header calendar button was the same dead end

Raised *"Open it from Home → View Workout Calendar."* (and on the original screen before that, it was
a bare `Container` with **no gesture detector at all**).
**Fix:** opens `ConsistencyDetailScreen`, **tab-aware** — workout history from the Workout tab,
nutrition history from the Diet tab.

### 🔴 M-3 — My Plans contradicted Home about what today is

My Plans knew only `training.isWeeklyRestDay`. It **ignored the served expectation entirely** — so on
an excused day, a paused block, a flexible week, or a not-yet-started plan, Home correctly said
*"Today is excused"* / *"Coaching paused"* while My Plans said **"Start Workout · 3 exercises"**.
Two screens, one served fact, opposite answers.

**Fix:** My Plans now calls `todayWorkoutPresentation(...)` — the same function Home calls, with the
same inputs. **Proven on device:** both screens now show *"No schedule set — showing your plan
daily."*, both show *33%*, both name *set 2 of 3*.

### 🔴 M-4 — The Diet tab reported a network failure as "your coach assigned nothing"

`_dietTab` had **no error branch at all**. A failed `getMyTraining` left `diet == null`, which rendered
*"No diet plan right now — your coach will assign one soon."* The Workout tab already drew this
distinction; the Diet screen already drew it; this tab did not.
**Fix:** `loadFailed` branch → *"Couldn't load your plans — this is a connection problem"* + Try again.

### 🔴 M-5 — Nothing on the screen said what the member had done today

The module's second reason to exist was missing. `StreakController` already held today's
`SessionStats`, `NextUp` and duration; nothing rendered them, and the per-exercise detail was thrown
away after being parsed.
**Fix:** `StreakController` now also holds `todayExercises` (day-guarded exactly like the stats,
carried on the **same** `markWorkoutToday` call so the aggregate and the detail can never describe
different sessions). New `TodayWorkoutSection` renders progress, sets, skips, duration, adherence,
volume, the resume point, and every set as *prescribed → actual*.

### 🔴 M-6 — A dead listener outlived a successful write (`FoodLogController`)

Firestore **terminates** a listener on error and never retries. The food log rebound in exactly two
places: a date rollover, and the manual *Try again*. The **write** path is unaffected. So a member
could log food successfully and go on reading *"Couldn't load today's food"* with the food already
stored — the documented escape hatch being *"log blind, then tap Try again"*.
**Fix:** `_recoverIfErrored(result)` on log / edit / delete / undo — rebinds **only** when
`loadError` is set, so a healthy subscription is never churned. 5 new tests, including the
never-churn guard.

### 🟠 M-7 — The Diet tab stated the coach's five macro targets twice

The hero card carried `Calories 2000 · Protein 33 · Carbs 22 · Fat 12 · Fiber 32`; the nutrition card
a few hundred pixels below stated **all five again, against what the member had actually eaten** —
strictly more information. **Fix:** the five chips are deleted; `Plan items` and `Meals` remain
(neither is stated elsewhere).

### 🟠 M-8 — *A duplication this rebuild introduced, and caught on device*

Reusing `FoodLogSection` wholesale brought its **"Logged today" totals card** onto a screen whose
nutrition ring states the same four macros immediately above it. Caught in a device screenshot.
**Fix:** `showTotals` flag (default `true`, so the Diet screen is unchanged); My Plans passes `false`.
The **"Syncing"** offline indicator, which lived on that card, is preserved separately — hiding the
card must not hide the member's assurance that food logged offline is safe. Pinned by 5 tests.

### 🟠 M-9 — `dayPlanUnavailable` was served by the backend and read by nobody

When a coach deletes the plan mapped to today in a weekly split, `buildWorkout` says so explicitly.
The member saw *"This plan has no exercises yet"* — about a plan with plenty.
**Fix:** *"Today's session isn't available right now — your coach is updating this day of the plan."*

### 🟠 M-10 — The Diet CTA led where the member already was

Once the whole log lives on this tab, a button labelled **"Open Diet"** showed the member the same
thing again. **Fix:** the CTA is **"Add Food"** — the one action this tab cannot perform inline. The
nutrition card's tap-through was removed for the same reason (three controls, one destination).

### 🟠 M-11 — Midnight rollover on a never-backgrounded phone

My Plans lives in the dashboard's `IndexedStack` and stays mounted all session. The dashboard
re-anchors the daily controllers on **resume**; a phone left on this tab across midnight was never
backgrounded. **Fix:** a post-frame `ensureFreshDay()` on the food log, streak and training
controllers (all three are already guarded no-ops).

### 🟡 M-12 — `logFood` was unreachable from any test

`newEntryId()` called `FirebaseFirestore.instance` directly, so **no unit test could call `logFood` at
all** — which is exactly why M-6 survived. **Fix:** an injectable `idFactory`, matching the
house pattern already used for every other collaborator on this controller.

### ⚪ A dead parameter, now live

`PlanHeroCard.completedToday` existed and was **never passed** by either tab — exercised only by
tests. It is now driven by `stats.isComplete`, so a finished session renders as a **statement, not a
button**.

---

## 7. UX / UI CHANGES MADE

| Change | Why |
|---|---|
| **Today's workout** section added | The module's second question had no answer. |
| **Today's meals** added (the literal `FoodLogSection`) | Same — and it brings edit / delete / undo / realtime already correct. |
| Prescription list **replaced** by the session view once a session exists | The session view already states every prescribed set beside its result; showing both is the same facts twice. |
| Five macro chips deleted · totals card suppressed · "Open Diet" → "Add Food" · card tap-through removed | Four separate duplications removed (M-7, M-8, M-10). |
| Header subtitle → *"Assigned by your coach · logged by you."* | Names the screen's two jobs instead of marketing copy. |
| Disclosure line surfaced | Home showed *"No schedule set"*; this screen hid it. |
| Rest/excused/paused body text surfaced | Consequence of adopting the shared presentation. |

**Still deliberately NOT shown** — plan difficulty, duration, frequency, start date, cover image,
badge, plan status. `getMyTraining` serves none of them at plan level. A Patrol journey
(`NO fabricated plan fields`) fails if any reappears.

---

## 8. TEST + PATROL RESULTS

```
flutter analyze ......................... 0 issues
flutter test ............................ 1165 pass / 14 fail      (baseline 1139 / 14)
                                          +26 new, 0 regressions
                                          all 14 are the SAME pre-existing matchesGoldenFile
                                          failures (home_cards_golden, home_header,
                                          log_transformation, serena_foundation) — none in
                                          any file this pass touched
functions (backend) ..................... 1027 / 1027
firestore rules (real emulator) ......... 371 / 371   (+3 new, A/B proved)
patrol my_plans_patrol_test ............. 22 / 22 substantive journeys on emulator-5554
```

**New test files**
`test/today_workout_section_test.dart` (16) — pending sets state no result · 17/18 reads 94% not 100%
· skipped sets count against completion · no clock → no Duration · bodyweight → no "0 kg" volume ·
nothing completed → no adherence · 320dp @2.0× · light theme.
`test/food_log_error_recovery_test.dart` (5) — the dead-listener recovery, in all four mutations, plus
the never-churn guard.
`test/food_log_section_totals_test.dart` (5) — the de-duplication, and that "Syncing" survives it.
`integration_test/my_plans_patrol_test.dart` (22) — the two product questions, no dead ends, the
expectation agreement, honest failure, tablet / landscape / 320dp@2.0× / light.

⚠️ **Patrol: 1 of 23 slots fails — a harness artifact, not a screen defect.** The **first**
`patrolWidgetTest` in the bundle aborts in ~0.5 s, *before the widget tree is built*, with a
null-messaged `AssertionError` from the JUnit runner. Proved to follow the slot rather than the
content: a deliberately trivial *warm-up* test was inserted first and **it** then took the failure
while all 22 real journeys passed. The same assertions pass in the tests below it, and the screen was
verified by hand on this same device.

---

## 9. EMULATOR VALIDATION — the member journey, actually performed

Live account, live backend, screenshots retained:

1. Home → My Plans (Workout) — plan, coach, exercise render.
2. **Start Full Workout** → `WorkoutBriefingScreen` (previously: a snackbar).
3. **Begin Workout** → session → entered 12 kg → **Complete Set 1** → rest timer → **Skip**.
4. Back → *"Leave workout? Your progress is saved"* → **Save & leave**.
5. Back to My Plans → **"1 of 3 sets done" · Resume Workout · In progress 33% · Sets 1/3 ·
   Exercises 0/1 · On target 100% · Volume 120 kg · Next: Dumbbell Chest Press · set 2 of 3 · 10 reps**,
   and per set: `Set 1  10 reps → 10 reps × 12 kg ✓` / `Set 2  10 reps ○` / `Set 3  10 reps ○`.
   **Pending sets state their target and no result** — exactly as the unit tests pin.
6. Diet tab — plan, ring (1005 / 2000 kcal), meals grouped with times, **no duplicated totals**.
7. **Swipe-delete "Almonds"** → total 1005 → **843**, macros recomputed, the now-empty
   MID-MORNING SNACK group disappears, **Undo** offered.
8. **Undo** → the *same* entry restored to its original meal at its original time (10:48 AM);
   total back to **1005**.
9. Home → **33% · Next exercise Dumbbell Chest Press · Set 2 of 3 · 10 reps · Resume Workout ·
   "No schedule set — showing your plan daily."** — identical to My Plans. Workout streak 0 → 1.
10. `logcat` after the flow: **zero** `PERMISSION_DENIED`, zero `E/flutter`, zero exceptions.

---

## 10. PERFORMANCE VALIDATION

- **Reads per open: unchanged.** No listener, no callable and no query was added. Today's session is
  the single `get()` `StreakController` already performed.
- `AnimatedSwitcher` + `KeyedSubtree` (not `IndexedStack`) — only the visible tab is built, so the
  hidden discipline keeps no `Obx` subscriptions alive.
- **Large plans:** the session view is O(exercises × sets) `Text` rows inside the page's single
  `ListView`. At 50 exercises × 5 sets that is ~250 rows built eagerly inside one list item.
  It renders, but see R-4.
- **100 foods:** `FoodLogSection` is the Diet screen's shipped implementation, unchanged.
- **Double taps / rapid edits:** unchanged paths — `pendingIds` on the food log, the session screen's
  own `_finishing` guard. `_recoverIfErrored` is idempotent and gated on `loadError`.

---

## 11. REMAINING RISKS

| # | Risk | Severity | Status |
|---|---|---|---|
| **R-1** | **The `client_nutrition_days` missing-day rule (N-1) deployment state is UNVERIFIED.** `NUTRITION_PRODUCTION_FREEZE_REPORT.md` proved it undeployed earlier today; I could not re-observe it, because the live member had already logged food so today's document existed. If still undeployed, every member's Diet surfaces — including this tab — fail on the first open of every day. | 🔴 **Gating** | Repo rule is correct; **deploy + verify required** |
| **R-2** | **F-1's fix is not deployed.** The repo rule is correct and proved; production still carries the pre-fix shape (observed denying on device today). | 🟠 | Deploy with R-1 |
| **R-3** | **On a degraded network the splash can stall for minutes with no feedback.** Observed directly: with ~50% packet loss the app sat on the brand screen ~7 minutes before resolving. `splash_screen.dart:_decide()` awaits `authStateChanges().first` with **no timeout, no progress indication and no escape**. Outside the My Plans module; **not changed in this pass** — auth routing is not something to alter inside a My Plans certification. | 🟠 | Reported, not fixed |
| **R-4** | Today's session builds every set row eagerly inside one `ListView` item. Fine at observed sizes; a 50-exercise plan deserves a lazy or collapsed-by-default treatment. | 🟡 | Reported |
| **R-5** | TrainerHQ's coach screens were **not run**. Sync is certified from the wire shape and the consumer's parser, not from a coach's screen. | 🟡 | UNPROVEN |
| **R-6** | `tests/rules/*.mjs` run in **one** `node --test` invocation share a single emulator and interfere (395 tests: 26–35 failures, varying between identical runs; per-file: **371/371, deterministic**). Any CI job using the glob form is reporting noise. | 🟡 | **New finding** |
| **R-7** | Plan **history** (paused/ended/previous plans) remains impossible: `getMyTraining` filters non-active assignments server-side and `prescriptionData` carries no status. Needs a backend change, not a UI one. | 🟡 | Documented gap |
| **R-8** | The workout streak's `chats/{clientId}` listener was also denied on device today. Unrelated to My Plans; **not investigated**. | 🟡 | Reported |

---

## 12. PRODUCTION READINESS DECISION

### ⚠️ **CONDITIONAL GO — the module is complete and verified; one rules deploy gates release.**

**What I certify, with evidence:** My Plans now answers both of its questions from live data; it
shares Home's decision function so the two cannot contradict each other; it contains no field the
backend does not serve; every control reaches a real destination; a network failure is never reported
as a coach doing nothing; and food logged, edited, deleted or restored from this screen reaches the
coach live. Analyzer clean, 1165 app tests, 1027 backend tests, 371 rules tests, 22 device journeys,
and a full member journey performed by hand on the live production backend.

**What blocks release** is not this module's code — it is **one deploy** carrying two rule fixes:

```bash
cd /Users/bandigowtham/flutter_works/trainershq-backend && firebase deploy --only firestore:rules
```

That single deploy ships **R-1** (`client_nutrition_days`, previously proved undeployed and
member-blocking) and **R-2** (`client_workout_sessions`, F-1, found today). Both are additive
`resource == null && signedIn()` clauses that grant no data, and both are proved by emulator tests
that fail against the pre-fix shape.

**I have not run that deploy** — backend deploys are operator-gated by
`trainershq-backend/CLAUDE.md`, and this is an outward-facing production change.

**After the deploy, one verification closes R-1 and R-2:** open the app as a member who has **not yet
logged food or trained today**, and confirm `logcat` shows no `PERMISSION_DENIED` on
`client_nutrition_days/{clientId}_{today}` or `client_workout_sessions/ws_{clientId}_{today}`.
With that observation, My Plans is **GO**.

---

### Files changed

**alphaserena** — `controllers/food_log_controller.dart` · `controllers/streak_controller.dart` ·
`screens/dashboard/plans/my_plans_screen.dart` · `screens/dashboard/plans/today_workout_section.dart`
*(new)* · `screens/dashboard/nutrition/food_log_section.dart` ·
`screens/dashboard/workout_session_screen.dart` · 3 new `test/` files · 1 new `integration_test/` file.

**trainershq-backend** — `firestore.rules` (`client_workout_sessions` read clause) ·
`tests/rules/nutrition_food_log_write.mjs` (+3 tests).

**No Cloud Function, no index, and no Firestore document shape was changed.**
