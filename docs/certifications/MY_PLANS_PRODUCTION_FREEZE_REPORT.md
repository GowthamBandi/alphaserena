# MY PLANS — CTO PRODUCTION FREEZE REPORT

**Module:** My Plans (AlphaSerena member app) · **Date:** 2026-08-03 (final freeze pass)
**Device:** `emulator-5554` — Pixel 9 Pro AVD, Android 17 (API 37), degraded network (~50% loss)
**Backend:** `trainershq-f5ded` — the live production project
**Live member:** client `EkNg2Yux4lPAQtSpQjds`, coach "ORG Name", "Workout Plan 11" / "Test Diet Plan"

> Per Rule 1, nothing from the previous pass was taken on trust. Every conclusion below was
> re-derived from source or from the running app. Where this contradicts the earlier report, **this
> one supersedes it** — including one place where the earlier report was wrong.

---

## 1. WHAT THIS PASS FOUND THAT THE LAST ONE MISSED

The previous report certified the module as complete pending a rules deploy. Re-auditing from zero
found **eight further defects**, four of them member-visible. That is the value of not trusting the
prior certification.

| # | Defect | How found |
|---|---|---|
| F-1 | The segmented control's pill sat **1px outside its own track** on the Diet tab | geometry test written from the UX audit |
| F-2 | **No coach plan change ever reached an open app** — not assign, replace, pause or remove | read TrainerHQ's `AssignmentService` |
| F-3 | The app **receives a plan-change push and ignores it** | live notification centre on device |
| F-4 | Plan notifications **pushed a rootless second copy** of My Plans over the shell | read the deep-link router |
| F-5 | The Diet tab showed the coach's plan as **two number chips**, never the foods | UX audit against the mission |
| F-6 | The coach's **workout description** is served and rendered nowhere | diffed `buildWorkout` against the UI |
| F-7 | A finished session **stated no duration** until the next app restart | manual device journey |
| F-8 | A **red action button inside the green Diet tab** | device screenshot after F-5's fix |

---

## 2. UI / UX + PREMIUM DESIGN

### F-1 🔴 — The segmented control was asymmetric, and only on the second tab

The control is `Container(padding: 5, border: 1px)` wrapping a `Stack`, so the slider's coordinate
space is inset **6px**. Its geometry was computed from the control's **outer** width
(`half = maxWidth / 2`, `width: half - 5`). Measured at 354dp, before the fix:

```
workout pill   left inset  =  6.0   ✓  (correct by luck)
diet pill      right inset = -1.0   ✗  one pixel PAST the outer edge
```

So on the Diet tab the 6px frame that surrounds the pill everywhere else vanished and the pill
painted over — and beyond — the track's own border. **Asymmetric by construction: flawless on the
first tab, wrong on the second**, which is exactly why it survived a 16-test suite and a review.

Compounding it, `Curves.easeOutBack` overshoots its target by ~10% of the travel (~17px here),
throwing the pill outside the track mid-animation. It cannot be clipped away either — clipping
would also cut the pill's glow, which is drawn deliberately outside its bounds.

**Fixed at the root:** the `LayoutBuilder` moved *inside* the padding, so both numbers derive from
the box the slider actually lives in and there is no outer measurement left to drift from. The travel
curve became `easeOutCubic`; the spring moved to the icon's scale, where it cannot escape.
**9 new geometry tests** measure rendered rectangles (not arithmetic) at 284/354/604/988dp.

### F-5 🔴 — "What has my trainer assigned me?" was answered with two numbers

My Plans exists to answer that question. On the Diet tab it answered with `Plan items 2 · Meals 1`
while the foods the coach actually prescribed lived on a screen the member had to go and find. The
member could see everything they had eaten and nothing they were asked to.

**Fixed** by extracting the Diet screen's section into a shared `CoachRecommendedMeals` and rendering
it on both. One implementation, not a copy — the coach's own words are the last thing that should be
phrased two ways. Verified on device: **BREAKFAST · 189 kcal · Boiled Egg 1.5 egg (75 g) · Whole Cow
Milk 100 g.**

### F-6 🟠 — A field the coach wrote, served, and rendered nowhere

`buildWorkout` has served plan-level `description` since Workout Plans V1 — the backend's own comment
calls it *"the one field a coach wrote that disappeared entirely between the two apps."* The Diet tab
rendered its equivalent; the Workout tab dropped it. Now rendered as a quotation, and only when the
coach wrote one.

### F-8 🟠 — A red button in a green tab (introduced by F-5's fix, caught on device)

Reusing the section wholesale brought the brand-red "Log" action onto the green Diet tab — a third
accent competing with the tab's identity, the same reason Home's red pill was kept off it. The action
now takes the tab's accent. Caught in a screenshot **after** the fix that introduced it.

### Deliberately NOT changed

The nutrition ring stays red→orange on the green tab. It is the *literal* card Home renders and the
gradient is a **calorie** semantic, not a tab semantic; forking it per-tab would create the second
nutrition card this module spent two passes eliminating.

---

## 3. REALTIME — the mission's hardest question, answered honestly

### F-2 🔴 — No coach plan change reached an open app. At all.

Traced end to end rather than assumed:

- `getMyTraining` is a **one-shot callable**, not a stream.
- TrainerHQ's `AssignmentService` writes **only** to `client_plan_assignments` — a collection the
  member app cannot read (plan resolution is deliberately server-side) and which **never touches the
  `clients` document the member does stream**.
- `HomeController`'s reload worker is gated on `!hasPlan`, so it can only help a member with no plan.

| Coach action, member watching | Before | After |
|---|---|---|
| Assigns a first plan | invisible | ✅ push-driven, immediate |
| Replaces / edits a plan | invisible | ✅ push-driven, immediate |
| Pauses / removes a plan | invisible — member could still **start a withdrawn workout** | ✅ push-driven, immediate |
| Member backgrounds and returns | stale | ✅ refreshed on resume |
| Member enters the My Plans tab | stale | ✅ refreshed on entry |

### F-3 🔴 — The push channel existed; the app ignored it

The notification centre on the live device held three real plan notifications
(*"Your coach assigned you a new diet plan"*). The backend emits six kinds
(`plan_{assigned,updated,removed}_{workout,diet}`) and the client **already routed all six on tap** —
but in the foreground the handler raised a snackbar and touched no data. A member watching My Plans
was told *"Check it out!"* over a screen still showing the old plan.

**Fixed:** the foreground handler now forces a `load()` on those six kinds — a forced load, not the
throttled one, because a push is authoritative evidence that the plan moved. One shared
`_planChangeKinds` set now drives both the refresh and the deep link, so they cannot drift.

**Plus `refreshIfStale`** (45s window, stamped only on success) on app resume and on entering the tab,
for changes that happen while push is unavailable. 4 tests pin: fresh is not re-fetched, stale is,
a **failed** load never counts as fresh, and a load in flight is never doubled.

### F-4 🟠 — The deep link stacked a second copy of the screen

`Get.to(() => const MyPlansScreen())` **pushes** a rootless My Plans over the shell: no bottom
navigation, no route to Home but the back gesture, and two live instances of the screen in the tree.
A tab is not a page you push. Replaced with `openMyPlansTab()`, which selects the tab and pops back to
the shell; the request is sticky so a notification tapped from a **cold start** still lands correctly.

### Still not covered, and not pretended away

A coach changing a plan while the member sits on the screen **with push undelivered** (permission
denied, FCM unreachable — this emulator cannot get an FCM token at all). The only complete fix is a
member-readable assignment stream, which needs a rules change and a deliberate architectural
decision. **Documented, not hidden.**

---

## 4. WORKOUT VERIFICATION

Full journey performed by hand on the live account, across two app restarts:

1. My Plans → **Start Full Workout** → briefing → **Begin Workout**
2. Set 1: 10 reps × 12 kg → rest timer → **Save & leave**
3. **App killed and relaunched** → session resumed at **Set 2 of 3**, Set 1 intact ✓
4. Sets 2 and 3 completed → **Finish** → summary: **2h 8m · 3/3 · 360 kg · 100% on target**
5. My Plans: hero shows *"Workout complete · every set done"*, the CTA is a **green statement, not a
   button**; Today's Workout shows **100%**, Sets 3/3, Exercises 1/1, On target 100%, Volume 360 kg,
   and every set as `10 reps → 10 reps × 12 kg ✓`
6. Home shows **identical** figures — 2h 7m, 1 exercise, 3/3, 100%

### F-7 🟠 — the defect this journey caught

At step 5 the **Duration was missing**, seconds after the summary screen had displayed *2h 8m*.
`markWorkoutToday` carried stats, resume point and per-exercise detail but **not the clock**, so a
finished session stated no duration until the next app restart re-read the document. Home had the
same hole. Fixed on the same call; null is never written back, so an in-progress re-save cannot erase
a recorded duration. Verified on device afterwards: **2h 7m on both screens.**

Finding it required a testable controller — `StreakController` built `FirebaseFirestore.instance` in
a **field initializer**, so it could not be constructed in a unit test at all, which is precisely why
none of its live-update behaviour was covered. Now resolved lazily (the house pattern), with 5 new
tests including the midnight-rollover guard across all four views.

---

## 5. NUTRITION VERIFICATION

Verified on the live account: meals grouped with times, per-food source chips, swipe-delete
(**1005 → 843 kcal**, the emptied meal group disappearing, Undo offered), and Undo restoring the
*same* entry to its original meal at its original 10:48 AM slot.

- **Totals stated once.** The food log's "Logged today" card is suppressed on My Plans, where the
  nutrition ring already states all four macros *against the coach's targets*.
- **"Syncing" survives that suppression** — hiding the card must not hide the member's assurance that
  food logged offline is safe. Pinned by test.
- **Canonical meal order and bucketing.** Coach free-text labels ("Snacks", "Mid-morning") land in the
  same buckets the log uses, so one meal can never appear under two headings on one screen.
- **One CTA.** "Add Food" — the one action the tab cannot perform inline.

---

## 6. BACKEND · FIRESTORE · FUNCTIONS · RULES

**No Cloud Function, index, or document shape was changed in either pass.**

```
functions (npm test) ............ 1027 / 1027
firestore rules (real emulator) .. 371 / 371, per file, deterministic
```

The rules fix from the previous pass stands and was re-proved both ways: with the
`resource == null && signedIn()` clause stripped, `an unlogged workout session is readable` and
`a LISTENER … is not denied` both FAIL; with the repo's rules they pass.

⚠️ **Re-confirmed this pass:** running `tests/rules/*.mjs` in a **single** `node --test` invocation
shares one emulator and yields 26–35 varying failures across identical runs. Per file it is a
deterministic 371/371. Any CI job using the glob form is reporting noise.

---

## 7. TRAINERHQ SYNCHRONISATION

Certified from the producer's wire shape and the consumer's parser:
`watchNutritionDays` / `watchWorkoutSessions` are `.snapshots()` (live); the member's soft delete
writes `{deleted: true}`, which `ClientNutritionDayModel.fromMap` skips; and both sides sum the same
frozen `consumed` snapshots, so totals cannot disagree.

⚠️ **UNPROVEN:** TrainerHQ's coach app was **not run** — no coach session exists on this machine.

---

## 8. TEST + PATROL RESULTS

```
flutter analyze ................. 0 issues
flutter test .................... 1194 pass / 14 fail   (was 1139 at the start of this work)
                                  +55 tests, 0 regressions; the 14 are the SAME pre-existing
                                  matchesGoldenFile failures, none in any file touched
patrol my_plans_patrol_test ..... 27 journeys, 26 PASS
functions ....................... 1027 / 1027
firestore rules ................. 371 / 371
```

**New this pass:** `plan_segmented_control_geometry_test` (9) · `training_freshness_test` (4) ·
`streak_today_session_test` (5) · `coach_recommended_meals_test` (11) · 4 new Patrol journeys.

⚠️ **The 1 Patrol failure is a harness artifact, proven so.** The **first** `patrolWidgetTest` in a
bundle aborts in ~0.5s — *before the widget tree is built* — with a null-messaged `AssertionError`
from the JUnit runner. Proved to follow the **slot**, not the content: a deliberately trivial
*warm-up* test was placed first and it took the failure while all 26 real journeys passed.

---

## 9. PERFORMANCE · ACCESSIBILITY · RESPONSIVE

- **Reads per open unchanged.** No listener, query or callable added. The new refreshes are
  rate-limited (`refreshIfStale`, 45s) or push-triggered (one authoritative event).
- **Accessibility:** every control is its own semantics node; only one tab announces `isSelected`;
  the history button carries a tab-aware label. Verified at **320dp @ 2.0× text** on both tabs, in
  Patrol and in unit tests, with no overflow.
- **Responsive:** tablet, landscape and light theme all pass in Patrol; the segmented control's
  geometry is pinned at four widths from 284dp to 988dp.
- **Large plans:** today's session builds every set row eagerly inside one list item. Fine at
  observed sizes; a 50×5 plan deserves lazy or collapsed rendering (**R-4**).

---

## 10. REMAINING RISKS

| # | Risk | Severity |
|---|---|---|
| **R-1** | **`client_nutrition_days` missing-day rule (N-1) deployment state remains UNVERIFIED.** Proved undeployed earlier today; I could not re-observe it, because the live member had already logged food so today's document existed. If still undeployed, every member's Diet surfaces fail on the first open of each day. | 🔴 **Gating** |
| **R-2** | The `client_workout_sessions` fix is correct in the repo and **not deployed** (observed denying on device). Ships with R-1. | 🟠 |
| **R-3** | **Splash can stall for minutes with no feedback on a degraded network** — observed ~7 minutes at ~50% packet loss. `_decide()` awaits `authStateChanges().first` with no timeout, no progress and no escape. Outside this module; **not changed** in a My Plans pass. | 🟠 |
| **R-4** | Eager set-row rendering for very large plans. | 🟡 |
| **R-5** | TrainerHQ coach app not run; sync certified from wire shape + parser. | 🟡 |
| **R-6** | The rules glob-run interference (§6) — a CI hazard, not a product one. | 🟡 |
| **R-7** | Plan **history** (paused/ended) is still impossible: `getMyTraining` filters non-active assignments server-side. Needs a backend change. | 🟡 |
| **R-8** | `chats/{clientId}` listener denied on device (3× this run). Unrelated to My Plans; **not investigated**. | 🟡 |
| **R-9** | Push-less realtime gap (§3) — coach edits mid-screen with FCM unavailable. | 🟡 |
| **R-10** | Outside the module, observed while driving it: the workout session screen shows **two "Finish Workout" buttons** at once, and the briefing says "Begin Workout" for a session being **resumed**. | 🟡 |

---

## 11. PRODUCTION READINESS DECISION

### ⚠️ **CONDITIONAL GO — the module is frozen and certified; one rules deploy gates release.**

**Certified, with evidence:** My Plans answers both of its questions from live data and now shows the
coach's actual prescribed foods and notes, not counts. It shares Home's decision function, so the two
cannot contradict each other — proved on device down to identical percentages, next-set text and
duration. Its segmented control is geometrically symmetric at four widths. A coach's plan change now
reaches an open app through the platform's own push channel, plus resume and tab-entry pulls. Every
control reaches a real destination and the plan deep link selects a tab instead of stacking a second
screen. Food logged, edited, deleted or restored reaches the coach live. Nothing is rendered that the
backend does not serve.

**What blocks release is not this module's code** — it is **one deploy** carrying two additive
`resource == null && signedIn()` rule clauses, both proved by emulator tests that fail against the
pre-fix shape:

```bash
cd /Users/bandigowtham/flutter_works/trainershq-backend && firebase deploy --only firestore:rules
```

**I have not run it** — backend deploys are operator-gated by `trainershq-backend/CLAUDE.md`, and this
is an outward-facing production change.

**One verification closes R-1 and R-2:** open the app as a member who has **not yet logged food or
trained today** and confirm no `PERMISSION_DENIED` on `client_nutrition_days/{clientId}_{today}` or
`client_workout_sessions/ws_{clientId}_{today}`. With that observation, My Plans is **GO**.

---

### Files changed in this freeze pass

**alphaserena** — `plans/plan_segmented_control.dart` · `plans/my_plans_screen.dart` ·
`nutrition/coach_recommended_meals.dart` *(new)* · `nutrition/diet_screen.dart` ·
`controllers/training_controller.dart` · `controllers/streak_controller.dart` ·
`core/services/member_push_service.dart` · `dashboard_screen.dart` ·
`workout_session_screen.dart` · 4 new `test/` files · Patrol suite extended.

**trainershq-backend** — unchanged this pass (the rules fix and its 3 tests landed in the previous one).

---

### A note on method

The emulator was treated as the source of truth throughout, and it earned that status: **F-3, F-7 and
F-8 were invisible in the code and only appeared by using the app** — a notification centre holding
plan alerts that had never moved any data, a duration that vanished between two screens, and a red
button in a green tab. F-8 in particular was introduced by the fix for F-5 and caught one screenshot
later. The live member session was protected until the end and Patrol was run last, after all manual
verification, because the previous pass showed Patrol can cost the session.
