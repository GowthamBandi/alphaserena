# MY PLANS — CTO PRODUCTION COMPLETION REPORT

**Module:** My Plans (AlphaSerena member app) · **Date:** 2026-08-03 (final polish pass)
**Device:** `emulator-5554` — Pixel 9 Pro AVD, Android 17, live member session, degraded network
**Member:** client `EkNg2Yux4lPAQtSpQjds` · "Workout Plan 11" / "Test Diet Plan"
**Backend:** `trainershq-f5ded` — **unchanged this pass** (no function, rule, index or schema edit)

---

## 1. UI IMPROVEMENTS

### Today's Workout — ranked, not dumped

The section rendered every exercise with every set permanently open. On the one-exercise plan it was
built against, that read fine; on a real 8-exercise session it is a 40-row wall in which the one thing
a returning member needs — *where do I continue* — is indistinguishable from everything else.

Rebuilt as a collapsing list:

- one card per exercise: status, name, **muscle group · equipment**, `2/3`, chevron, and a progress
  bar that stays visible **while collapsed**
- the exercise holding the **next set opens itself**; finished and skipped ones stay shut because
  they are answered
- the next exercise carries an accent border, and the next **set** is highlighted inside it
- `AnimatedSize` expansion, `AnimatedRotation` chevron, `TweenAnimationBuilder` bars that animate
  from where they were, so logging a set *advances* the bar rather than snapping it

Nothing is hidden — it is ranked. Every card is tappable and stays open once the member opens it.

### Fields the backend served and this section dropped

| Field | Where it lives | Status |
|---|---|---|
| **Muscle group · equipment** | served `workout.items[]` | now on every exercise card, matched by `exerciseId` |
| **Prescribed rest** | `setRows[].rest` | now on every set row |

The rest label also had a unit bug: `setRows[].rest` is free text and is usually a bare `"90"`, so it
rendered as **"rest 90"** — ninety of what. Rest is seconds everywhere in this app (the rest overlay
counts it in seconds; `workout_session_screen` prints `rest ${digits}s`). Now matched exactly:
**"rest 90s"**. Not inventing a unit — stating the one the timer already uses.

### After the workout — it celebrates

A completed session now carries a green border and a `verified` badge on the summary card, and the
hero CTA is a green statement rather than a button. Verified on device after finishing a real
session: **100% · Sets 3/3 · Exercises 1/1 · Duration 2h 7m · On target 100% · Volume 360 kg.**

### Diet — the coach's plan answers "what do I still need?"

| Added | Source |
|---|---|
| Per-meal **macros** (`13g P · 6g C · 13g F`) | served plan items, summed — previously summed nowhere |
| **"1 of 2 logged"** per meal | factual `foodId` match against today's log |
| A green check on each prescribed food already logged | same match |
| A green border on a fully-logged meal | same |

**It is a factual match, never an adherence score.** A marked food means "you logged this food
today"; it makes no claim about the AMOUNT, because the coach's portion and the member's are two
different numbers and equating them would invent compliance. Empty by default, so the Diet screen is
unchanged.

Verified live: **BREAKFAST · 189 kcal · 13g P · 6g C · 13g F · 1 of 2 logged**, with Boiled Egg
checked and Whole Cow Milk not — matched against the real member's real log.

---

## 2. UX + NAVIGATION IMPROVEMENTS

### Two dead ends removed

The blockers named a remedy and offered nothing to do it with:

- *"Renew your membership to see the plans your coach assigned"* — **no renew button**
- *"Once you join a coach, the plans they build for you appear here"* — **no way to join**

Both now carry a real action (**Renew membership** → `MembershipScreen`, **Find a coach** →
`JoinCoachScreen`), tinted to the active tab.

### Navigation audit — full walk

Every control on the module now reaches a real destination and nothing reaches it twice: segmented
control · history button (tab-aware) · hero CTA (Start / Resume / Review / a non-tappable complete
statement) · Add Food · per-meal Log · swipe-delete · Undo · food row → edit sheet · exercise
expand/collapse · pull-to-refresh · plan-notification deep link (selects the **tab**, never stacks a
second copy) · back from every pushed route. No duplicate destination survives: one CTA per action,
one statement of the day's totals, one implementation of the coach's plan and of the food log.

---

## 3. PREMIUM DESIGN — the segmented control

Third audit of this control. Its geometry was fixed in the previous pass (the pill sat **1px outside
its own track** on the Diet tab). This pass adds what was still missing: **a pressed state**.

Selection animated the pill and the icon, but until the finger lifted nothing acknowledged the touch
except an ink ripple — and on dark glass an ink ripple is nearly invisible. Each half is now its own
`StatefulWidget` with a 3% press-scale, and the **selected** half deliberately does not respond,
because tapping it does nothing and it must not pretend otherwise.

Still verified: 9 geometry tests at 284 / 354 / 604 / 988 dp (both halves identical size, mirrored
about the centre, never painting outside the track), one-tab-only `isSelected` semantics, 56dp
half-width hit targets, ellipsis rather than overflow at 2.0× text, light theme, tablet, landscape.

---

## 4. LOADING IMPROVEMENTS — a regression I introduced, and fixed

The realtime work from the previous pass re-pulls the plan on app resume, on entering the tab and on
a coach's plan-change push. **Every one of those flips `isLoading`, which was rendering the loading
SKELETON straight over content the member already had.** A background refresh that greys out the plan
you are reading is worse than no refresh at all — it looks like the data was lost.

Now:

- the **skeleton is for a cold load only** — nothing held yet
- an existing plan **stays on screen**, with a slim centred spinner reading
  **"Checking for updates from your coach"**
- the indicator sits in an `AnimatedSize` that occupies the same 18px gap when idle, so nothing
  under it jumps when it appears

---

## 5. EMPTY STATES — every one, audited

| State | Treatment |
|---|---|
| No coach linked | icon · reason · **Find a coach** |
| Membership inactive | icon · reason · **Renew membership** |
| No workout / diet plan | calm, and explicitly says a plan "can also be paused between blocks" — the app genuinely cannot distinguish removed from paused, and does not pretend to |
| Coach removed / changed the assignment | collapses to the above **honestly**, and now refreshes into it on push/resume/tab-entry |
| Rest day | positive statement from the shared expectation engine |
| Day-plan unavailable | *"your coach is updating this day of the plan"* — reads the served `dayPlanUnavailable` |
| Nothing logged today | `FoodLogSection`'s empty state, with its own CTA |
| Workout completed | celebratory, not an empty list |
| Load failure | *"Couldn't load your plans — this is a connection problem"* + **Try again**, on **both** tabs |
| Offline | the app's global connectivity takeover, plus the food log's own honest error |

No empty state is a blank area, and none reports a network failure as a coach doing nothing.

---

## 6. STRESS TEST RESULTS

New `test/my_plans_stress_test.dart` — every section of My Plans renders inside **one** `ListView`
item, so none of them gets lazy building for free.

| Case | Result |
|---|---|
| **100 exercises × 4 sets** (400 prescribed sets) | ✅ renders; the collapse design means the 400-row wall is **never built** |
| 100 exercises × 100 served items (the `_servedFor` lookup at scale) | ✅ no quadratic blow-up |
| **200 logged foods** across four meals | ✅ |
| **100 prescribed meals**, half already logged | ✅ |
| A 60-item plan **and** a 120-food day on screen together | ✅ |

Whole file runs in ~1s. The budgets are loose on purpose: they are tripwires for an accidental O(n²),
not performance targets.

---

## 7. BACKEND · FIRESTORE · CLOUD FUNCTIONS · RULES

**No backend change was made in this pass.** Re-verified as current:

```
functions (npm test) ........... 1027 / 1027   (re-run this pass)
firestore rules ................ 371 / 371     (previous pass; rules untouched since)
```

⚠️ The working tree carries **uncommitted backend edits from earlier sessions**
(`functions/src/coaching_events.ts`, `functions/src/lib/coaching_events.ts`) that are **not mine** and
were not reviewed here.

---

## 8. REALTIME + TRAINERHQ SYNCHRONISATION

Unchanged from the previous pass and re-stated for completeness: coach plan changes reach an open app
through the platform's own push channel (six `plan_*` kinds, forced reload), plus `refreshIfStale` on
resume and tab entry. Member → coach is live in both directions via `.snapshots()`, with soft deletes
honoured by `{deleted: true}` and totals summed from the same frozen `consumed` snapshots on both
sides.

⚠️ **Still UNPROVEN:** TrainerHQ's coach app was **not run** in any pass — no coach session exists on
this machine. Cross-app sync is certified from the producer's wire shape and the consumer's parser,
**not** from watching a coach's screen update. The mission asked for live cross-app verification;
this is the one item I could not deliver, and I am not going to claim it.

---

## 9. PATROL RESULTS

```
patrol test --target integration_test/my_plans_patrol_test.dart -d emulator-5554
→ 34 journeys · 33 PASS · 1 fail
```

The single failure is the **warm-up slot**, proven in the previous pass to be a harness artifact: the
first `patrolWidgetTest` in a bundle aborts in ~0.5s *before the widget tree is built*, and moving a
trivial test into first position moves the failure with it. All 33 real journeys pass.

**7 new journeys this pass:** a finished exercise stays collapsed · the next exercise opens itself ·
any card can be opened by hand · prescribed rest reaches the member · a logged prescribed food is
marked · no markers when nothing is logged · per-meal macros are summed. Plus the two blocker
journeys now assert their **action buttons** exist.

---

## 10. MANUAL EMULATOR VERIFICATION

On the live member session, on the polished build:

1. My Plans → Workout: completed session shows the **verified badge, green border, 100%**, and
   `Duration 2h 7m` — matching Home exactly.
2. The exercise card is **collapsed**, showing `Chest · Dumbbell` and a full green bar.
3. Tapped it → **expanded**, chevron rotated, all three sets as `10 reps → 10 reps × 12 kg` with
   `rest 90s` and green ticks.
4. Diet tab: **"YOUR COACH'S PLAN"** with macros and **"1 of 2 logged"**, Boiled Egg checked from a
   real `foodId` match against the member's real log.
5. `logcat`: **zero** `PERMISSION_DENIED`, zero `E/flutter`.

Earlier in the same session (previous pass, same module): start → log a set → **kill the app** →
resume at set 2 of 3 → finish → summary → completed state; and swipe-delete a food (1005 → 843 kcal)
→ **Undo** restoring the same entry to its original 10:48 AM slot.

⚠️ I stopped driving the emulator at the end: it is now in **interactive use** (it returned to the
launcher between my commands). All polish verification above was completed *before* that, and Patrol
ran after it on a clean relaunch.

---

## 11. FULL VERIFICATION SUMMARY

```
flutter analyze ................. 0 issues
flutter test .................... 1206 pass / 14 fail
                                  (1139 at the start of this module's work → +67 tests, 0 regressions;
                                   the 14 are the SAME pre-existing matchesGoldenFile failures,
                                   none in any file touched)
patrol .......................... 34 journeys, 33 pass
functions ....................... 1027 / 1027
firestore rules ................. 371 / 371
```

---

## 12. REMAINING RISKS

| # | Risk | Severity |
|---|---|---|
| **R-1** | **`client_nutrition_days` missing-day rule (N-1) deployment state remains UNVERIFIED.** Proved undeployed earlier today; never re-observable because the live member had already logged. If still undeployed, every member's Diet surfaces fail on the first open of each day. | 🔴 **Gating** |
| **R-2** | The `client_workout_sessions` rule fix is correct in the repo and **not deployed**. Ships with R-1. | 🟠 |
| **R-3** | **Splash stalls with no timeout or feedback on a degraded network** — observed again this pass: 200s on the brand screen before resolving. `_decide()` awaits `authStateChanges().first` with no timeout, no progress, no escape. Outside this module; deliberately not changed in a My Plans pass. | 🟠 |
| **R-4** | TrainerHQ coach app never run (§8). | 🟡 |
| **R-5** | Plan **history** (paused/ended) still impossible — `getMyTraining` filters non-active assignments server-side. Backend change required. | 🟡 |
| **R-6** | Realtime gap when push is undelivered (permission denied / FCM unreachable — this emulator cannot obtain an FCM token at all). Resume and tab-entry pulls cover most of it; a member sitting on the screen is still stale. | 🟡 |
| **R-7** | Uncommitted third-party backend edits in the working tree (§7). | 🟡 |
| **R-8** | `chats/{clientId}` listener denied on device. Unrelated to My Plans; not investigated. | 🟡 |
| **R-9** | Outside the module, seen while driving it: the session screen shows **two "Finish Workout" buttons** at once, and the briefing says "Begin Workout" when **resuming**. | 🟡 |

---

## 13. PRODUCTION READINESS DECISION

### ⚠️ **CONDITIONAL GO — the module is complete and feels like a flagship screen; one rules deploy gates release.**

My Plans now states, from live data: what the coach assigned (both disciplines, down to the
prescribed foods, macros, equipment and rest), what the member has completed today (set by set, with
progress, duration, volume and adherence), and what they still need (which prescribed foods are
already logged). It ranks rather than dumps, celebrates completion rather than ending flat, refreshes
without blanking, offers an action in every state that names one, and stays in lockstep with Home
through a shared decision function — verified on a real device with a real member, against production.

**What blocks release is not this module's code.** It is one operator-gated deploy carrying two
additive `resource == null && signedIn()` rule clauses, both proved by emulator tests that fail
against the pre-fix shape:

```bash
cd /Users/bandigowtham/flutter_works/trainershq-backend && firebase deploy --only firestore:rules
```

**One verification closes R-1 and R-2:** open the app as a member who has **not yet logged food or
trained today** and confirm no `PERMISSION_DENIED` on `client_nutrition_days/{clientId}_{today}` or
`client_workout_sessions/ws_{clientId}_{today}`. With that observation, My Plans is **GO**.

---

### Files changed in this polish pass

`plans/today_workout_section.dart` (rebuilt) · `plans/plan_segmented_control.dart` ·
`plans/my_plans_screen.dart` · `nutrition/coach_recommended_meals.dart` ·
`test/my_plans_stress_test.dart` *(new)* · `test/today_workout_section_test.dart` (+7) ·
`integration_test/my_plans_patrol_test.dart` (+7 journeys). **No backend file touched.**

---

### A note on what polish actually caught

Two of this pass's fixes were **defects, not preferences**: the loading skeleton blanking live content
was a regression introduced by my own realtime work one pass earlier, and "rest 90" was an ambiguous
unit that every other surface in the app qualifies. Neither was visible in a code diff. Both appeared
by looking at the running screen and asking whether a paying member would understand it.
