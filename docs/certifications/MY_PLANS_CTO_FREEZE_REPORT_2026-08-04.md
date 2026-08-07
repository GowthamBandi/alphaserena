# MY PLANS — CTO FREEZE REPORT
**Date:** 2026-08-04 · **App:** alphaserena (member app) · **Device:** emulator-5554 (Android 17)
**Scope:** completion pass over the already-built My Plans redesign — finish tests, fix what they
find, challenge the result, verify on hardware and across apps.

**DECISION: 🟢 GO** — with three known items listed at the end, none of which block release.

---

## 1. HEADLINE NUMBERS

| Gate | Result |
|---|---|
| `flutter analyze` | **0 issues** |
| `flutter test` | **1323 passed / 14 failed** — all 14 are pre-existing golden-image failures, proven below |
| Patrol (`my_plans_patrol_test`, emulator-5554) | **34 / 34 real tests pass**; 1 harness artifact (diagnosed, §6) |
| New tests written this pass | **+32** (1291 → 1323) |
| Manual drive as a real member | **Completed end-to-end on a live signed-in account** |
| Cross-app (TrainerHQ) sync | **Verified from source, by contract test, and on device** |

### The 14 golden failures are NOT from this work — proven, not asserted
They were failing in the baseline run **before a single edit**. To remove all doubt the entire
working tree was stashed (`git stash push -- lib/ test/`) and the goldens re-run: the diff
percentages came back **byte-identical** (`consistency_pair_dark` 4.55%/3334px,
`workout_card_ready_dark` 4.61%/5796px, and so on for all eight). Cards with no duration text at
all (`ready`, `rest`) fail by the same margin as ones with it, which is the signature of host font
substitution, not content. This matches the standing note in `CLAUDE.md`.

Breakdown: `home_cards_golden_test` 8 · `home_header_test` 4 · `serena_foundation_test` 1 ·
`log_transformation_screen_test` 1 = **14**, exactly the documented baseline.

---

## 2. DEFECTS FOUND AND FIXED

### 🔴 P1 — A crash on every loading skeleton, for reduce-motion members
`_SerenaSkeletonState._c` was `late final`, so it initialised on **first access**. Under reduced
motion `build` returns the static box and never touches it — making `dispose()` the first access,
which constructed an `AnimationController` (and a `Ticker`) against an already-deactivated element:

```
Looking up a deactivated widget's ancestor is unsafe.
  #10 _SerenaSkeletonState.dispose (premium_states.dart:86)
```

Reachable on **nine screens** — Home, My Plans, Diet, Add Food, Food History, Workout History,
Workout Log Editor and two more — every time a first-load placeholder left the tree, on the single
code path selected by an OS accessibility preference. Found by a test that did not exist before this
pass. Fixed by making the controller nullable and creating it in `build`, so `dispose` can only
release something already constructed; the ticker is also stopped if the setting is turned on
mid-sweep.

### 🔴 P1 — The finished-workout card flattered the member
`WorkoutCompleteCard` showed Duration, Volume and Calories but **not `On target`** — the adherence
figure. The in-progress header has always shown it, and so does the History day view. So a member
who completed every prescribed set at *under* the prescribed reps saw a green tick, "Workout
Complete", and no indication they had hit 50% of their targets. Completion and adherence are
different questions, and the one state that most needed the counterweight was the only one without
it. `On target` now renders on the card whenever `targetHitPct` is non-null (null when nothing was
completed — 0% would read as failure rather than absence). Verified live on device: the card now
reads **On target 100%**.

### 🔴 P1 — "Edit Workout Log" on Home opened the training flow
Home's secondary CTA called `openSession()` → `WorkoutBriefingScreen`, the guided one-exercise-at-a-
time player. That is the exact dead end `WorkoutLogEditorScreen` was built to replace: to fix a
mistyped rep count the member had to navigate a screen designed for *training* and decline its offer
to start a second session. My Plans and Workout History both already routed the same label to the
editor — so one label did two different things depending on which card was tapped. It survived
because the widget tests drive `HomeWorkoutCardWidget` with injected callbacks and never exercised
the screen's routing. Now branches on card mode: completed/closed → editor, rest day → briefing.
**Confirmed on device**: tapping it from Home now lands directly in the editor.

### 🟠 P2 — The calendar strip clipped itself at large text sizes
`_timelineStrip` was a flat `height: 92` while the two glyphs inside scale with the OS text setting.
At 2.0x the day cell wanted 95dp and got 90, so **every one of ~30 cells** painted an overflow
stripe across the screen's only navigation surface. Clamping the scaler would have "fixed" it by
shrinking type for exactly the members who asked for larger type; instead the height is now derived
from the same two styles the cell renders and floored at the original 92 — the 1.0x design is
untouched and the strip can only grow.

### 🟠 P2 — Five duration formatters, disagreeing
The same function existed five times (Home results, consistency story, Today section, completion
card, History day log). Four printed `${s}s` under a minute and the fifth printed `<1m` — one
session length rendered two ways depending on which card showed it. All five printed **"1h 0m"** for
an exact hour. Consolidated into one `formatWorkoutDuration` with the sub-minute wording as its only
parameter; an exact hour now reads **"1h"**.

### 🟠 P2 — The set editor showed placeholders its own keyboard forbids
The reps/weight fields open a decimal pad, but the hints echoed the coach's prescription verbatim —
so a bodyweight exercise showed a hint of **"bodyweight"** and a range showed **"8-12"**, neither of
which that keyboard can type. Worse, the full prescription is already stated one line above ("coach
asked for 8-12 reps × bodyweight"), so the one piece of in-field guidance was spent repeating it.
Hints are now the prescription's leading number when there is one ("8-12" → "8") and a plain unit
otherwise. The source comment claiming members "must be able to answer in the coach's vocabulary"
was wrong about code that has never permitted it, and is corrected.

### 🟠 P2 — "Saved offline" told online members they were offline
`queued` means only that the server did not acknowledge within the 4s `ackTimeout`. Nothing on that
path checks connectivity. **Observed live on a fully-connected emulator**: during cold start, App
Check token retries pushed the first write past 4s and the member was told "Saved offline" — the
very next write acked in under a second. Now **"Saved on this device"**, which is true in both cases
and is the phrase Lifestyle already uses for this exact state.

### 🟡 P3 — Dead code owning a second definition of "done"
`TodayWorkoutSection._header` still carried a congratulatory branch — a green border, a verified tick
and the words "Workout complete" — that became unreachable the moment `WorkoutCompleteCard` landed
(`build` routes `finished || isComplete` away before `_header` is called). Two widgets owning one
state's presentation, one of them invisible. Deleted.

### 🟡 P3 — The skeleton promised a layout it did not hand over
The loaded History screen pads `(0,4,0,32)` and runs the timeline full-bleed; the skeleton padded
`(18,8,18,28)` uniformly with a hardcoded 92. So when data arrived the page slid up 4dp and the
timeline grew 36dp wider. The skeleton now mirrors the real layout exactly, including the
text-scale-aware strip height.

---

## 3. TESTS WRITTEN (+32)

| File | Tests | What it pins |
|---|---|---|
| `test/premium_states_test.dart` *(new)* | 20 | The five state primitives that had **no test at all** — skeleton, sync whisper, stale banner, empty state, state swap. These are the only things a member sees on a cold start, a dropped connection, or a plan their coach hasn't sent. This file found the P1 crash. |
| `test/workout_trainerhq_parity_test.dart` *(new)* | 11 | Cross-app contract (§4). Diet and Lifestyle had parity tests; workouts — the one collection the member app can now **rewrite** — had none. |
| `test/workout_log_editor_test.dart` | +1 | Hints must be enterable on the keyboard they open. |

Six previously-failing tests were also repaired. Two (`today_workout_section_test`) were **stale**,
asserting the pre-redesign header; they now pin the new design *and* the restored `On target`
figure. Four (`workout_history_screen_test`) split into two stale-casing assertions, one genuine
formatter defect ("1h 0m") and one genuine layout defect (the overflow above).

---

## 4. TRAINERHQ SYNCHRONISATION — VERIFIED, NOT ASSUMED

**a) Field-by-field parity, read from both sources.** `buildSessionEntries` (alphaserena) against
`SessionSet.fromMap` / `SessionEntry.fromMap` (trainersHQ
`lib/core/models/client_workout_session_model.dart`):

- Set level — `setNumber`, `prescribedReps`, `prescribedWeight`, `prescribedRest`, `actualReps`,
  `actualWeight`, `completed`, `skipped`, `edited` — **all 9 written, all 9 read.**
- Exercise level — `exerciseName`, `exerciseId`, `sets`, `note`, `skipped`, `skipReason` — **all 6
  written, all 6 read.**

**b) The merge-write hazard is closed.** `saveEditedEntries` writes `{entries, updatedAt}` with
`SetOptions(merge: true)`, and a merge write replaces an **array wholesale** — so any field the
member app fails to write back is deleted from the coach's copy the first time a member corrects a
set. `ExerciseLog.note` is round-tripped for exactly this reason, and the new contract test pins it,
plus a full parse→edit→write→re-parse cycle asserting byte-identical output.

**c) The coach cannot be writing into it.** TrainerHQ holds exactly one reference to the collection —
`ClientLogsService.watchWorkoutSessions`, a `snapshots()` listener. There is no `.set`/`.update`/
`.add` anywhere in the coach app, and `firestore.rules` allows update only where
`resource.data.authorId == request.auth.uid`, with `delete: if false`. So there is no coach-authored
field for an edit to destroy, and because the coach's view is a **live listener**, an edit propagates
without a refresh.

**d) Adherence agrees on both sides.** The contract test computes adherence with TrainerHQ's own
`hit` / `_lowerBound` / `_num` logic and asserts it equals `computeSessionStats` — including a range
prescription ("8-12" lower-bounds to 8), a bodyweight set with no numeric target, and the null case.
It also proves a correction *moves* the coach's adherence (1.0 → 0.0), because the coach derives it
on read.

**e) On the device, with real data.** Two edits were made to today's live session (set 1 → 15 kg,
set 2 → 14 kg). Both were written, both gained the **`edited`** flag, the workout stayed `completed`
at 3/3, and volume recomputed 470 → 500 → 510 kg (verified by hand: 10×15 + 10×14 + 10×22 = 510).
The second write returned **"✓ Saved"** — a server acknowledgement — and because `saveEditedEntries`
rewrites the whole `entries` array, that acked write carried set 1's correction with it. The edits
then appeared through a **different read path** (Workout History's own query) and survived a full
process kill and cold restart.

> **Limit of this verification, stated plainly:** the coach-side *screen* was not opened. TrainerHQ
> was verified by reading its parser, its only accessor and the security rules, and by executing its
> parsing and adherence logic against this app's real output in a twinned test. What was not done is
> launching TrainerHQ, signing in as this member's coach, and looking at the session. That requires a
> coach session on this machine and is the one step between "provably correct contract" and "seen
> with eyes".

---

## 5. MANUAL VERIFICATION ON emulator-5554

Driven as a real member on a live Google-authenticated account with real coach data
(Workout Plan 11 · Dumbbell Chest Press · Test Diet Plan). Every item from the brief:

| # | Item | Result |
|---|---|---|
| 1 | Workout tab | ✅ hero, coach, facts, session breakdown |
| 2 | Diet tab | ✅ pill travels to green identity, coach's plan, meals, macros, Add Food |
| 3 | Workout completion | ✅ 100%, 3/3, `Completed at 10:27 AM` |
| 4 | Edit Workout Log | ✅ opens the **editor** from Home, My Plans and History (Home was broken — §2) |
| 5 | Editing reps | ✅ field accepts, saves, recomputes |
| 6 | Editing weights | ✅ 12→15, 13→14; volume 470→510 kg |
| 7 | Editing completed sets | ✅ Completed / Skipped / Not done picker; empty-completed blocked |
| 8 | Workout History | ✅ month rollup (3 sessions · 7 sets · 990 kg) |
| 9 | Month selector | ✅ 12-cell grid, future months **disabled and visible**, July loads (1 · 3 · 360 kg) |
| 10 | Year selector | ✅ offers only 2026 — the years that actually have history |
| 11 | Calendar scrolling | ✅ horizontal strip, full-bleed, state marks are shapes not just colours |
| 12 | Current day centered | ✅ 4 August selected and centred on open |
| 13 | Previous workouts | ✅ 31 July session with its own plan name, note and sets |
| 14 | Navigation | ✅ all routes and back stacks correct |
| 15 | Empty states | ✅ legend renders only states present; no legend in an empty month |
| 16 | Loading states | ✅ skeletons mirror the real layout (fixed this pass) |
| 17 | Offline behaviour | ✅ app-wide gate takes over, auto-dismisses on reconnect **restoring the exact prior tab** |
| 18 | Resume after restart | ✅ session persists, no re-login, edits intact (510 kg, On target 100%) |

Read-only history is correctly enforced: the 31 July session shows **no** Edit button; today's does.

---

## 6. PATROL

`patrol test --target integration_test/my_plans_patrol_test.dart -d emulator-5554` — run three times
during this pass (9m28s each). **34 / 34 real tests pass**, including the runs that exercised every
`lib/` change made here.

One test fails: the deliberate `warm-up — the screen mounts`, which exists to absorb first-test
harness cost. Its recorded cause was stale ("a null-messaged AssertionError"); the real Dart-side
assertion was read off logcat and is:

```
A SemanticsHandle was active at the end of the test.
WidgetTester._verifySemanticsHandlesWereDisposed
```

It fires **after the body has already passed** — Patrol's own tearDown logs the test as `success`,
and only the post-body verification throws. Patrol ships a workaround for the same family of bug in
this exact code path, citing [leancodepl/patrol#1474](https://github.com/leancodepl/patrol/issues/1474).

**Two candidate causes were tested and refuted rather than assumed:**
1. The emulator's `accessibility_enabled` secure setting — toggled to 0, whole suite re-run, failure
   reproduced identically. (Setting restored afterwards.)
2. `semanticsEnabled: false` on the test, which controls whether `testWidgets` itself holds a
   handle — also reproduced identically, proving the handle is held by the `PatrolBinding`, not the
   test.

It is an upstream harness artifact with no app-side fix. The comment in the test now records the
real diagnosis and both refuted hypotheses.

---

## 7. REMAINING KNOWN ISSUES

**1. "Workout complete" still appears twice on a completed My Plans screen.** 🟡 *cosmetic*
It appeared **three** times before this pass — the hero's subtitle chip, the hero's CTA-slot
statement, and the completion card's title, two of them inside one card, all three wearing a green
tick. The subtitle was the clearest duplication (it repeated its own CTA verbatim) and now reads
**"All 3 sets done"**, which spends the slot on information the member does not already have.

The remaining two are the hero's CTA statement and the card's title. Removing the hero statement is
defensible on hierarchy grounds — the card below says the same thing *and* carries the figures and
the action — but that statement is a **deliberate, separately-tested** design decision
(`plan_segmented_control_test`: "completed today replaces the CTA with a statement", so the card does
not end abruptly), and it is asserted by name in the Patrol suite. Re-litigating a tested component
contract is redesign rather than completion, so it is **flagged for your decision, not changed**.

**2. The offline gate hides cached plans.** 🟡 *product decision, pre-existing*
The app-wide takeover (Section 6.4) means a member with no signal cannot see today's workout **even
though it is cached locally** — relevant for a gym basement. This was an explicit product choice
("app-wide + always-when-offline + full-screen takeover") recorded in `CLAUDE.md`, so it is reported
rather than altered. A per-screen stale banner (the pattern `StaleDataBanner` already implements)
would be the alternative if you want to revisit it.

**3. The Nutrition Progress card renders in brand red inside the green Diet tab.** 🟡 *cosmetic*
The segmented control teaches "Workout = red, Diet = green" and then the nutrition ring below it is
red. The card is shared with Home, where red is correct, so changing it is a cross-surface decision
outside this module's scope.

**Also unchanged and pre-existing:** the 14 golden-image failures (host font substitution — they need
regenerating on a machine with the right faces, which would otherwise bake this machine's rendering
into the repo); a `PERMISSION_DENIED` on the `chats/{clientId}` listener seen in logcat, which
belongs to the chat module, not this one; and App Check 403s, which are known harmless noise on this
emulator.

---

## 8. FILES CHANGED

**Library (9)**
`core/domain/workout_session.dart` (shared `formatWorkoutDuration`) ·
`core/domain/home_workout_card.dart` · `core/domain/consistency_story.dart` ·
`core/widgets/serena/premium_states.dart` (P1 crash) ·
`screens/dashboard/home/client_home_screen.dart` (P1 routing) ·
`screens/dashboard/plans/workout_complete_card.dart` (P1 adherence) ·
`screens/dashboard/plans/workout_history_screen.dart` (overflow + skeleton) ·
`screens/dashboard/plans/today_workout_section.dart` (dead code) ·
`screens/dashboard/plans/workout_set_edit_sheet.dart` (hints) ·
`screens/dashboard/plans/workout_log_editor_screen.dart` (save wording) ·
`screens/dashboard/plans/my_plans_screen.dart` (subtitle duplication)

**Tests (6)**
`test/premium_states_test.dart` *(new)* · `test/workout_trainerhq_parity_test.dart` *(new)* ·
`test/today_workout_section_test.dart` · `test/workout_history_screen_test.dart` ·
`test/workout_history_test.dart` · `test/workout_log_editor_test.dart` ·
`integration_test/my_plans_patrol_test.dart` (diagnosis comment only)

---

## 9. VERDICT

**🟢 GO for production.**

Three P1 defects were found and fixed in this pass, and none of them would have been caught by the
suite as it stood: a crash reachable on nine screens for accessibility users, a headline card that
congratulated members while withholding the figure that qualified the congratulation, and a primary
action whose label and destination disagreed. Two of the three were found by tests that did not
exist before this pass — which is the real argument for the +32.

The module now analyses clean, passes 1323 tests with no logic failures, passes 34/34 on real
hardware, and was driven end to end by hand on a live account with a real coach's plan. The
cross-app contract with TrainerHQ is verified at the field level, at the rules level, by a twinned
contract test, and by observing a server-acknowledged edit survive a cold restart.

The three remaining items are cosmetic or previously-decided product choices, each documented above
with the reasoning for leaving it to you rather than changing it unilaterally.
