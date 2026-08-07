# NUTRITION HISTORY — CTO FREEZE REPORT
**Date:** 2026-08-04 · **App:** alphaserena · **Device:** emulator-5554 (Android 17)
**Mission:** build the Diet tab's history to mirror Workout History exactly.

**DECISION: 🟡 GO — with ONE required backend deploy.** The module is complete, tested and
verified on device. A **pre-existing, undeployed Firestore rule** (not introduced by this work)
prevents it from rendering a month in which the member logged nothing. Details in §5. Everything
else is done.

---

## 1. HEADLINE NUMBERS

| Gate | Result |
|---|---|
| `flutter analyze` | **0 issues** |
| `flutter test` | **1366 passed / 14 failed** — the same 14 pre-existing goldens, unchanged |
| Patrol (`diet_journey_patrol_test`, emulator-5554) | **17 / 17** |
| New tests | **+60** (1306 → 1366) |
| Manual device verification | **Completed on a live signed-in member with real coach data** |
| Cross-app (TrainerHQ) | **Verified from source and by twinned contract test** |

---

## 2. WHAT WAS BUILT

The flow the mission asked for, in the order it asked for it:

> **Coach Assigned Diet → Today's Nutrition → Nutrition History →**

`History →` now sits on the **TODAY'S NUTRITION** heading of the Diet tab, in exactly the position
and style the Workout tab puts it on TODAY'S WORKOUT. A member who has learned one has learned both.

**Four new files, all mirroring their workout twin:**

| New | Mirrors |
|---|---|
| `core/domain/nutrition_history.dart` — pure, I/O-free, unit-tested | `workout_history.dart` |
| `controllers/nutrition_history_controller.dart` | `workout_history_controller.dart` |
| `screens/…/nutrition_history_screen.dart` | `workout_history_screen.dart` |
| `screens/…/nutrition_day_log_view.dart` | `workout_day_log_view.dart` |

**Every requirement, delivered:** premium calendar timeline · month selector (12-cell grid, future
months **disabled not hidden**) · year selector (only years with history) · current day auto-centred
· selected day highlighted **in its own state's colour** · smooth month transitions · four states
plus `today` (§3) · full day log with calories, protein, carbs, fat, fiber · meal timeline with
foods, quantity, calories, meal total and meal time · today editable, past days read-only · a
premium empty state, never a blank list.

### The production model, unchanged
Reads `client_nutrition_days/{clientId}_{yyyy-MM-dd}` through the existing `NutritionDayService`
and `NutritionDayModel.fromMap` — the same documents the Food Log writes and TrainerHQ reads.
**No new collection, no new model, no new writer.** The one mutating affordance ("Edit Food Log",
today only) navigates to the existing `DietScreen`, whose `FoodLogController` remains the sole
writer. The module is a second *reader* of one store, which is what "no duplicate storage, no
parallel models" means in practice — and it is pinned by a test.

### Meal vocabulary — your names, mapped to the stored slugs
The mission named the meals Breakfast / Snack / Lunch / Evening Snack / Dinner / Late Snack. The
platform's canonical taxonomy (`kMealSlots`, twinned with the backend's `MEAL_SLOTS`) is the same
six slots under stored slugs: `breakfast`, **`mid_morning`** ("Mid-Morning Snack"), `lunch`,
`evening_snack`, `dinner`, **`bedtime`**. I used the **canonical** slugs and labels rather than
introducing new ones — renaming a label is a display change there, while a new slug would have been
a data migration. Your "Snack" is `mid_morning`; your "Late Snack" is `bedtime`. Say the word and
the two display labels can be changed in one map without touching a document.

### The list screen it replaces
`FoodHistoryScreen` (a reverse-chronological list) is **deleted**, with its controller and unit
test, and its 5 Patrol tests rewritten against the calendar. Leaving it would have recreated this
repo's own documented incident — a retired nutrition screen kept alive only by Patrol, which then
appeared on a device during a run. `entryAmountLabel` moved out of that screen into
`nutrition_day_model.dart`, where it belongs (two other screens were importing a formatter out of a
screen, which is what kept the file alive). Sign-out teardown now deletes
`NutritionHistoryController` in its place — same shared-device hazard, same fix.

---

## 3. THE ONE RULE THE DOMAIN IS BUILT AROUND

> **A past day is never judged against today's target.**

This is the nutrition twin of the trap `workout_history.dart` documents: resolving "rest" from a
plan's *current* schedule repaints history every time a coach changes the split. Scoring March
against the calorie target set in August would silently relabel months of a member's record every
time their coach adjusted their goal.

So **Partial** is derived only from `computed.targetAdherence['calories']` — which the **backend**
writes onto the day document at the time (`rollupDaySummary` → `computeTargetAdherence`, itself
`clamp01(consumed / target)`). It is frozen historical truth for that date. When it is absent — no
targets were set then, or the day predates the server summary — a day with food in it is **Logged**,
never "partial", because there is nothing it fell short *of*.

**Two consequences, both deliberate and both tested:**
- **`today` is a fifth state.** A daily total cannot be behind before the day is over; marking a
  member "partial" at breakfast would be the calendar scolding them for not having eaten dinner yet.
  Today with food is Logged; today with none is `today` ("Nothing logged yet today"), not `empty`.
  The workout twin draws the same distinction for the same reason.
- **An emptied day is empty.** A document whose entries are all soft-deleted has no day behind it,
  so the cell is not openable — a cell that responds with an empty panel is worse than one that does
  not respond.

**Verified on real data:** 3 August rendered **Partial** (amber ring) from its own frozen adherence,
beside 4 August **Logged** (green dot). The backend really does write the figure, and the rule
really does resolve against it.

---

## 4. DEFECTS FOUND AND FIXED DURING THE BUILD

Five, of which **two were invisible to the test suite and only appeared on the device**:

### 🔴 The error state trapped the member on the month that failed *(device)*
The error replaced the **whole body, selectors and all** — so a member who landed on a month that
failed to load had two options: retry the same failing month, or leave. The one thing they wanted,
"show me a different month", was exactly what the error state had removed. The selectors now stay;
only the content below them becomes the apology.

### 🔴 The error followed the member to a month that was fine *(device)*
`loadError` describes a **month**, but a cache hit returned early without clearing it. So after July
failed, going back to the August they had just been reading showed August's month and year in the
selectors above an apology about a month they had left — and **no amount of "Try again" could clear
it**, because the cache hit returned before anything was retried. A month is cached only *because*
it read successfully, so returning to one now clears the flag.

### 🟠 Re-opening History showed a stale month
The controller outlives the screen (`Get.put` keeps one per session) and `onInit` runs only for a
fresh one — so a member who opened History, went and logged lunch, and came back would see the month
as it stood *before* lunch: their own food missing from their own record. The screen now re-reads on
mount.

### 🟠 …and that refresh would have flashed a skeleton over their data
Fixing the above naively would have replaced days the member was already reading with a shimmer.
`isLoading` (first load → skeleton) and `isRefreshing` (a re-read → a quiet `SyncWhisper`) are now
separate, which is the rule `premium_states.dart` states and the workout module already follows.

### 🟠 History → Diet → History → Diet, without limit
"Edit Food Log" pushes `DietScreen`, which carries its own history action — so the member could
stack duplicate routes and then need four back-taps to leave. `DietScreen` now takes
`showHistoryAction`, false when History itself opened it. (The workout twin never had this to solve:
its editor is a dedicated screen with no history of its own.)

**Also fixed:** `_sectionTitle`'s accessibility label was hardcoded to `'$actionLabel, workout'` —
correct while only the Workout tab had a history, and a lie the moment the Diet tab gained one. It
now takes the subject, so a screen reader hears "History, nutrition".

---

## 5. ⚠️ REQUIRED DEPLOY — a month with nothing logged cannot be read

**This is not a defect in the new code, and it is not fixable from the client.**

Switching to July on a live member produced "Couldn't load your history". logcat gives the cause
directly:

```
Listen for Query(client_nutrition_days/EkNg2Yux4lPAQtSpQjds_2026-07-31)
  failed: Status{code=PERMISSION_DENIED, ...}
```

Every **missing** day is denied. `firestore.rules` in `trainershq-backend` **already contains the
fix** — `allow read: if (resource == null && signedIn()) || …`, with a long comment explaining that
"THE MISSING DAY MUST BE READABLE" — so the rule in the repo is correct and **has simply not been
deployed**. A member's own by-id read of a document that does not exist is denied in production
today.

**The precise consequence:** `NutritionDayService.fetchDays` throws only when *every* day in the
window is unreadable (`windowUnreadable` = `unreadable == requested`), which is deliberate —
degrading is right for a bad day and a lie for a bad window. So:

- a month with **at least one** logged day renders correctly (August did, throughout);
- a month with **zero** logged days shows the honest error state.

**The fix is one deploy, from `trainershq-backend`:**

```bash
firebase deploy --only firestore:rules
```

Until then the client behaves correctly given what the server tells it, and the two error-state
fixes above mean the member can always navigate to a month that does load. I did not run the deploy:
it is an outward-facing production change affecting all three apps, and it is yours to make.

---

## 6. TRAINERHQ SYNCHRONISATION

**a) One store, one writer.** Nutrition History adds no service, no document and no write path.
Verified structurally and pinned by a test.

**b) Both apps read the same day the same way.** New
`test/nutrition_trainerhq_parity_test.dart` (9 tests) carries a **verbatim transcription** of
TrainerHQ's `client_nutrition_day_model.dart` — `fromMap`, its live-entry filter, its seven-nutrient
key list and `consumedForNutritionDay` — and runs the *same* wire document through both sides.
Agreement is asserted on: every macro, entry count, soft-delete exclusion, an emptied day, a document
with no `entries` map at all, and string-encoded numbers.

**c) The fields only the member renders still come off the wire** — meal slug, food name, amount and
eaten-time, including a free-text slug (`"Tea Time"` → `evening_snack`) being canonicalised rather
than lost. TrainerHQ parses none of these because it needs only day totals.

**d) ⚠️ ONE KNOWN DIVERGENCE, pinned deliberately.** For a nutrient **no entry recorded**, TrainerHQ
keeps it absent (its UI can say "unknown") while the member app's `ConsumedSnapshot.fromMap` coerces
every missing macro to `0` at parse time. So a day whose foods carry no fiber figure reads
**"Fiber 0.0 g"** here and "unknown" on the coach's screen. **Observed live** — 3 August shows
`Fiber 0.0 g`.

This is **app-wide and long predates this module** (Home, the Diet screen and My Plans all share the
model), and every macro that *was* recorded agrees exactly. Fixing it properly means making
`ConsumedSnapshot`'s fields nullable, which is a model change touching three other surfaces — so it
is documented and tested rather than half-done inside one screen.

---

## 7. DEVICE VERIFICATION (live member, real coach data)

| Item | Result |
|---|---|
| Month switching | ✅ August ⇄ July; future months disabled, not hidden |
| Year switching | ✅ offers only 2026 — the years with history |
| Calendar auto-centering | ✅ 4 August centred on open |
| Selected day highlighted | ✅ and **in its own state colour** — green for Logged, amber for Partial |
| Editing today's log | ✅ "Edit Food Log" → Diet screen (no history action, no loop) |
| Read-only previous days | ✅ 3 August shows the full log and **no** edit button |
| Day detail | ✅ 236 kcal · 2 items · 2 meals · P39 / C5.2 / F5.0 / Fib8.6 |
| Meal timeline | ✅ Breakfast 9:11 AM 165 kcal · Mid-Morning Snack 10:04 AM 71 kcal, with foods and amounts ("1 piece", "100 g") |
| Empty day | ✅ premium state — 🍽 "No food logged", member-centred copy, no button |
| Today before first meal | ✅ "Nothing logged yet today" **with** a Log Food action |
| Loading states | ✅ skeleton mirrors the real layout exactly |
| Offline behaviour | ✅ app-wide gate, auto-dismisses on reconnect — identical to Workout History |
| Restart persistence | ✅ survived force-stop, relaunch and a full reinstall |
| Cross-surface totals | ✅ "236 kcal" matches the My Plans card exactly |

Arithmetic checked by hand against the screen: 3 August meal totals 271 + 162 + 571 = **1005 kcal**,
matching the day header.

---

## 8. REMAINING KNOWN ITEMS

1. **The undeployed rule (§5)** — the only blocking item. One command.
2. **The unrecorded-nutrient divergence (§6d)** — bounded, documented, tested, pre-existing.
3. **Meals sort by canonical slot, not by clock.** On 3 August the Mid-Morning Snack is stamped
   10:48 AM and Breakfast 10:50 AM, so the timeline shows Breakfast first despite the later time.
   This is the ordering the mission specified (Breakfast → Snack → Lunch → …) and the order the live
   Food Log already uses; the times are simply what the member entered. Flagged because it looks odd
   on that particular day, not because it is wrong.
4. **Pre-existing and unchanged:** the 14 golden-image failures (host font substitution — byte-
   identical diffs with this work stashed), and the `chats/{clientId}` PERMISSION_DENIED belonging
   to the chat module.

---

## 9. VERDICT

**🟡 GO, pending one deploy.**

Nutrition History mirrors Workout History in structure, gesture, vocabulary and honesty rules, and
it reaches the same production bar: 0 analyze issues, 1366 tests, 17/17 Patrol, and a full manual
pass on a live member's real data. It introduces no second store and no second writer — a property
now pinned by a test rather than promised in a comment.

Two defects were caught only because the screen was driven by hand on a device, and both were the
same class: an error state that described the *screen* when it was really describing a *month*.
Neither was reachable from the test suite as written, and both are now covered.

The one thing standing between this and unconditional GO is a rules deploy that was already written,
already reviewed and already committed — just never shipped.
