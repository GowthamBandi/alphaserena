# CTO FORENSIC AUDIT — HOME + MY PLANS
**Date:** 2026-08-04 · **Auditor:** independent re-verification · **Trust basis:** nothing inherited

This audit assumed nothing works. No previous report, certification, Patrol result, comment or doc
was accepted as evidence. Every claim below is backed by a command I ran, a file I read, or a
screenshot I took on the running emulator against the live production backend (`trainershq-f5ded`).

> **Three sessions, one document.** Session 1 ran the architecture, runtime, backend and TrainerHQ
> passes and stopped mid-Patrol. Session 2 finished Patrol, completed the runtime pass on a live
> member session, re-adjudicated every prior finding, found four more defects and fixed them.
> Session 3 — this closure pass — removed both remaining blockers, deployed, and re-certified.
> Where the sessions disagree, the later one says so and shows the evidence.

---

## 0. DECISION

# ✅ GO — Home and My Plans are production-ready and are hereby frozen.

Both named blockers are closed, **deployed**, and proven at runtime. Every certification criterion
is met. The one remaining limitation (§6, F3) is a missing backend feature in the plan-authoring
pipeline, not a defect in either audited module — it is documented below with its exact fix and its
owner, and it is explicitly *not* being downgraded quietly: it is stated so you can overrule me.

| Blocker | Status |
|---|---|
| **BL-1** — `chats/{clientId}` denied the member's own thread read | ✅ **Fixed, deployed to `trainershq-f5ded`, verified at runtime** — 0 denials on a signed-in cold start where it was reliably 1 |
| **BL-2** — Duration was wall clock, and the clamp only bounded the extreme | ✅ **Fixed properly** — active training time is now the single source of truth across calories, duration, summary, history, Home, My Plans **and TrainerHQ** |

**Recommendation: move development to the Progress module.**

---

## 1. FINAL CERTIFICATION GATES

| Gate | Result |
|---|---|
| `flutter analyze` | **0 issues** — re-run after every single edit across all three sessions |
| `flutter test` | **1394 passed / 14 failed** (was 1352/14 at session 1) |
| Failing-test identity | **Exactly** the 14 documented baseline goldens, nothing else: `home_cards_golden` 8 · `home_header` 4 · `log_transformation` 1 · `serena_foundation` 1 |
| Backend functions (`npm test`) | **1027 / 1027**, tsc clean |
| Firestore rules (real emulator) | **399 tests, 392 pass** — all Firestore rules green incl. 5 new; the 7 failures are Storage **upload** tests, byte-identical before and after every change |
| Patrol | see §7 |
| Deployed rules | ✅ released to `trainershq-f5ded`, then **verified at runtime** |
| Emulator clock skew | none — host == device, `auto_time=1`; ruled out first, per the prior incident |
| Live runtime pass | Home + My Plans (both tabs) + both History screens + editor + chat, on `emulator-5554` against production, real member account |
| Closure-build runtime re-verification | signed-in cold start · offline takeover · reconnect (auto-dismiss, data intact) · restart (identical state, no re-auth) — **0 PERMISSION_DENIED across the whole cycle** |

---

## 2. BL-1 — CLOSED

### The defect
`chats/{clientId}` is created **only** by the `onMessageCreated` trigger (`functions/src/chat.ts`),
so it does not exist until the first message is ever sent — the state every newly joined member is
in. The read rule dereferenced `resource.data.memberUid`, which on a null resource **errors** rather
than returning false. No clause could return true; the read was denied.

**The fifth instance of one shape.** `client_workout_sessions`, `client_nutrition_days`,
`client_diet_logs` and `client_lifestyle_days` each already carry a `(resource == null &&
signedIn())` clause and a comment noting the previous sweep was *"scoped by collection name rather
than by defect shape"*. This collection is what that scoping missed again.

### Runtime proof, before
logcat, signed-in cold open, live member `EkNg2Yux4lPAQtSpQjds`:
```
W Firestore: Listen for Query(chats/EkNg2Yux4lPAQtSpQjds order by __name__)
  failed: Status{code=PERMISSION_DENIED, description=Missing or insufficient permissions.}
```
Reproduced on two independent cold starts. Firestore **terminates** a listener on permission-denied,
so `ChatService.watchConversation` — which drives Home's unread badge and message preview — was dead
for the rest of the session. The app swallows the error and renders an empty conversation, which is
exactly why it had never been noticed.

### The fix, and how it was verified
`firestore.rules` gains the null-resource clause. Pinned by new
`tests/rules/member_chat_thread_read.mjs` — **5/5 on a real Firestore emulator**, and proven
non-vacuous by reverting the rule and re-running (the regression case fails on the old rule, passes
on the new). Three of the five are security guards: an *existing* stranger thread stays denied, a
signed-out caller stays denied, the org owner keeps access.

**Deployed** — `firebase deploy --only firestore:rules --project trainershq-f5ded`, released
successfully.

### Runtime proof, after
| Check | Result |
|---|---|
| Signed-in cold start, logcat cleared first | **0 PERMISSION_DENIED** (was 1, deterministically) |
| Any other Firestore error | **none** — which also proves the deploy reverted no production hotfix |
| Home header | renders, chat + bell live, membership line intact |
| Chat screen | opens, correct "Start the conversation" empty state, composer live |
| Listener | attaches and holds an empty snapshot — the direct converse of the failure mode, which was denial→termination |

⚠️ **Two invalid measurements I caught and discarded, recorded so nobody trusts them.**
1. A "0 denials" reading taken after an APK reinstall had silently signed the member out. A
   signed-out app never reads `chats` at all, so it proved nothing.
2. A second "0 denials" reading where the app on the device was **Patrol's instrumented test-bundle
   APK**, not the app: `patrol test` writes its build to the same
   `build/app/outputs/flutter-apk/app-debug.apk` path, so installing that artifact after a Patrol
   run installs the harness. It hung on the splash trying to reach an automator that was not
   running — which is what exposed the mistake.

Both were re-done properly. The result in the table above is from the **closure build, signed in,
with Home fully loaded and live production data on screen** — and it was reproduced across a full
offline → reconnect → restart cycle, still 0.

### A second, smaller defect found while verifying BL-1
Opening the chat screen produced `Write failed at chats/{id}: PERMISSION_DENIED`. Cause: the same
missing-document shape on the **update** rule. `ChatService.markReadMember` anticipated this and
caught `not-found` — but a rules rejection on a missing document is reported as **permission-denied,
never not-found**, so that handler could never fire and the method rethrew on every chat open for a
member who has never messaged their coach.

**No member-visible impact** — the sole caller wraps it in `catchError` and the screen renders
correctly — so this is an INFO-grade finding, not a blocker. Fixed on the client (both codes mean
"there is no thread to mark read", and `allow create: if false` guarantees the member must never
create one), with the dead `not-found` branch replaced by an accurate explanation.

---

## 3. BL-2 — CLOSED PROPERLY

### What was wrong, and why the previous fix was not enough
`sessionDurationSeconds` was `finishedAt - startedAt` — pure wall clock, with no pause control
anywhere in the session screens. Session 2 applied the mitigation you chose at the time: clamp the
calorie model's input at three hours. That bounded the catastrophic case (9 h: 3308 → 1103 kcal) and
**did not touch the realistic one**. The proof was in this member's own production data:

```
Workout History · Monday 3 August 2026
Workout Plan 11 · 5:13 PM – 7:21 PM · Duration 2h 7m
Sets 3/3 · Volume 360 kg · Dumbbell Chest Press — 3 × (10 reps × 12 kg), rest 90s
```

Two hours seven minutes for three sets of a 12 kg press — under the three-hour clamp, so untouched,
and rendered to the coach as **"127 min"**.

A duration-only clamp *cannot* separate a long real session from a short one left open, because from
duration alone the two are identical. Only active time closes it.

### The architecture decision, investigated not guessed

**Source of truth.** There is no sensor and no pause control to appeal to — but the session already
contains a reliable presence signal: every completed set, skip, un-skip and correction is a moment
the member was demonstrably there. Active time is the sum of the intervals **between** those marks,
with any single interval capped at `kMaxIdleGapSeconds` = **5 minutes**.

Five minutes is derived, not picked: the longest rest any coach on this platform prescribes is about
three minutes and performing a set is under two, so it covers every genuine gap with room to spare.
A longer gap is not training, and is credited at the cap — so an interruption can cost the total at
most five minutes however long it really ran.

**Why every surface agrees automatically.** The wire field is `durationSeconds` on
`client_workout_sessions`. Verified from source: TrainerHQ's `ClientWorkoutSessionModel.durationLabel`
reads **`durationSeconds` and nothing else** — the coach app parses `startedAt`/`finishedAt` into
fields but no surface anywhere derives a duration from them. So writing active time into that one
field makes Home, My Plans, the completion card, the history calendar, the calorie model **and the
coach's app** agree structurally, with zero coach-side change.

**What was deliberately NOT changed.** `startedAt` and `finishedAt` are still written, and
`sessionDurationSeconds` still exists — the elapsed window is a real fact and remains recoverable.
It is simply no longer the answer to "how long did I train for". The three-hour calorie clamp is
kept as a second line of defence against a bad stored value.

### Where the clock ticks
`_tickActivity()` is called from exactly one place — `_persist()`, which every affirmative action
routes through (complete, skip set, reopen, skip exercise, un-skip) — plus `_finish()`, which does
not. Ticking centrally is what makes it impossible to add a sixth action that silently stops
counting. It is **not** called on keystrokes: typing is not evidence a set was performed.

The total rides the draft (`WorkoutDraft.activeMillis`, schema v2, and a v1 draft reads as 0 rather
than failing to load), so it survives leaving the screen, backgrounding, a locked phone and a killed
process. On restore the tick is deliberately reset to null — the clock restarts at the next real
activity, never at the resume, so time spent away is never charged.

### Verified
| Scenario | Covered by |
|---|---|
| pause / interruption / background / foreground / phone lock | the idle cap — a gap the app did not observe is credited at most 5 min |
| restart / killed process | draft round-trip, `activeMillis` v2 + v1 fallback |
| resume | on-device Patrol: the total is restored, not restarted, and time away is not credited |
| finish | `_finish` ticks, so the interval before pressing Finish is banked |
| backwards device clock | never subtracts time already earned |
| **TrainerHQ shows the identical duration** | structural — one field, one reader; pinned by 3 new cross-app parity tests |

**Numbers.** The real 3 August session, reconstructed exactly (7620 s wall clock):

```
reported duration   2h 7m  →  9m         (127 min → 9 min in the coach's app)
calories (70 kg)    778    →  54
a genuine 45-min session                 →  unchanged, 45m, on both sides
a session with nothing accrued           →  no duration stated, never "0m", on both sides
```

**Test coverage added:** `test/workout_active_time_test.dart` (14 tests — the cap, the boundary, the
backwards clock, the real 3 August reconstruction, the draft round-trip, the null rules),
3 cross-app duration parity tests, and **2 on-device Patrol tests**.

### One deliberate behaviour change worth naming
An in-progress session now carries a non-null `durationSeconds`, where it previously had none until
finished. So "Today's workout" shows a live-accruing Duration mid-session, and an **abandoned**
session now records the active time it earned rather than nothing at all. Both are honest and follow
directly from the mandated fix.

---

## 4. DEFECTS FIXED IN THE EARLIER SESSIONS (all still green)

| # | Defect | Evidence |
|---|---|---|
| **D1** | The History timeline **never** auto-centred, on either screen, ever | Measured: cold offset `0.0` vs `1506.0` centred. Worse than first thought — GetX disposes the route-scoped controller on pop (proven twice on device: select the 3rd, back, re-enter, panel is on today), so **every** entry is a cold entry. Survived because the test group named *"the timeline centres the day the member came to see"* only ever asserted the selection, never the scroll offset. Now pinned by widget tests **and** an on-device Patrol test |
| **D3** | Workout History's pull-to-refresh **blanked the month to a shimmer** | Session 1 §6 claimed this distinction was "correctly drawn in both modules" — it was wrong for Workout History. Fixed with the `isLoading`/`isRefreshing` split + `SyncWhisper`; a failed background re-read no longer destroys good days. **Confirmed on device**: mid-refresh, the whole month stays on screen with an "Updating" whisper |
| **D4** | 18 dp skeleton→content reflow on both history screens | Both skeletons now derive the gap from `SyncWhisper.height` |
| **D5** | A member **could not retract a note**, and was told "try again" at an impossible action | `saveMemberNote` refused an empty string, borrowing a guard meant for a destructive case. Now an empty note clears the field and the editor says "Note removed." |
| **D2** | *Collapsed under runtime evidence* — see §5 |

---

## 5. WHAT I TRIED TO BREAK AND COULD NOT

- **D2, "Workout History shows a stale month on re-entry"** — my own finding, **collapsed**. The
  controller does not survive the route pop, so every entry is already a cold load. I kept a one-line
  guard on both screens and rewrote both comments to state the measured truth, including correcting
  the nutrition screen's pre-existing and false *"the controller outlives this screen"*.
- **Patrol's `warm-up` failure** — the test file diagnoses it as an upstream `SemanticsHandle`
  artifact. I did not take that on trust. `my_plans` is one of only **two** suites using
  `patrolWidgetTest`; I ran the other, `membership_lifecycle`, as a decisive cross-check: **it also
  fails on its first test and passes all the rest**. Identical pattern, independent suite. The
  diagnosis is confirmed by experiment.
- **"The Home header shows the org name where the coach's name belongs."** The resolution chain is
  correct; the coach record in production is *literally named* "ORG Name". Data, not code — see §8.
- **"My Plans says Meals 1, Nutrition History says 2 meals."** Different subjects: the coach's plan
  structure vs the member's log. Both correct.
- **"The workout draft leaks between members on a shared device."** Cleared on sign-out.
- **"A failed `saveEditedEntries` leaves an unsaved value on screen."** It does, but the caller
  re-reads on return.
- Home ↔ My Plans nutrition parity — re-verified live, twice: **236 / 2000 kcal, P 39/33, F 5/12,
  C 5.2/22, Fib 8.6/32**, identical on both surfaces and in Nutrition History.
- Arithmetic — 165 + 71 = 236; coach's BREAKFAST 189 = 116 + 73, macros coherent.
- A member's log becoming invisible to their coach — impossible; both write guards stamp the fields
  TrainerHQ queries on.
- Missing composite indexes — none; every in-scope query is single-field equality.

---

## 6. REMAINING NON-BLOCKING FINDINGS

### F3 — In-place plan-content edits reach the member only on a poll · **stated, not downgraded**
`planAssignmentNotifications` emits `plan_updated_<type>` only on reactivation or a planId swap, and
`functions/src/programs.ts:18` says so in the source: *"there is NO Firestore trigger on
`workoutPlans`, `dietPlans` or `weeklyWorkoutPlans`."* A coach editing the exercises or foods
**inside** the assigned plan emits nothing.

**Why this does not block the freeze, stated so you can overrule me:** the member is never shown
*wrong* data, only *old* data, and only until app resume, a My Plans tab re-entry, or a
pull-to-refresh. Every plan **assignment** change — assign, replace, pause, remove, all six kinds —
does push in realtime, and both modules correctly consume every event the backend emits. The gap is
a missing trigger in the plan-authoring pipeline, i.e. a backend feature, not a defect in Home or My
Plans. **Fix:** a Firestore trigger on the plan collections that emits `plan_updated_<type>` to the
assigned members. Owner: backend.

### F4 — Unbounded Firestore reads on the Home critical path · MEDIUM-HIGH at scale
`workoutDayKeys` / `dietDayKeys` / `fetchSessionHistory` issue `.where(authorId == uid).get()` with
no `.limit()`; the window cutoff is client-side. Reads grow linearly with member tenure. A 4 s
timeout means a slow network degrades honestly, but the cost cliff arrives as the member base ages.

### F5 — "Offline" copy on screens that only render while the app believes it is online
**Verified at runtime**: the takeover covers Home whenever `isOnline` is false, and auto-dismissed on
reconnect with data intact. So the two "Offline —" strings are unreachable in the state they claim;
they fire on a server-side fault and send the member to check a connection that is fine.

### F6 / F7 / F8 — LOW
Dead `HeaderView.orgLogo` (confirmed visually — no logo tile renders) · repo/production index drift
(69 deployed vs 68 declared, `client_review_events`) · an identical-arm `ctaIcon` ternary at
`my_plans_screen.dart:344`. *Half of F8 collapsed:* `coldLoad` is used, not dead.

---

## 7. PATROL

Final run, against the finished tree, on `emulator-5554`. Tallies counted from the run logs, not
from Patrol's own summary block (which reports `Total: 0` for a suite whose first test fails):

| Suite | Result |
|---|---|
| `workout_patrol_test` | **21 / 21** — up from 18; all three new device tests pass |
| `my_plans_patrol_test` | 33 / 34 — the one failure is the documented harness artifact |
| `home_lifestyle_patrol_test` | 15 / 15 |
| `consistency_patrol_test` | 20 / 20 |
| `diet_journey_patrol_test` | 17 / 17 |
| **Total** | **106 / 107** |

New device coverage added this mission:
- `active time accrues from real intervals between sets` — real wall-clock intervals, real
  SharedPreferences, asserts the first mark banks nothing and the second banks a bounded interval.
- `the accumulated total SURVIVES leaving and resuming the session` — the path a killed process, a
  locked phone and a backgrounded app all take; asserts the total is restored, only grows, and that
  time spent **away** is not credited.
- `workout history centres the selected day on a cold open` — reads the real ScrollController offset
  on real hardware; measured at `0.0` before the fix.

The `warm-up` failure is the documented upstream `SemanticsHandle` artifact
([patrol#1474](https://github.com/leancodepl/patrol/issues/1474)), confirmed this mission by the
independent `membership_lifecycle` cross-check. It fires *after* the body passes, on the first
`patrolWidgetTest` in a bundle only, and is excluded by your own certification rule.

---

## 8. TRAINERHQ CROSS-APP VERIFICATION

Verified **from source on both sides**: collection names, field names, query shapes, write guards,
all six notification kinds, and the shared `durationSeconds` / `memberNote` / `entries` wire shapes.
Verified **on device**: Home, My Plans and both History screens agree to the decimal.

**The BL-2 cross-app defect is closed and pinned.** TrainerHQ reads duration from exactly one field,
which the member app now fills with active time — so parity is a property of the wiring, not a
promise. Three new parity tests hold it: the same session that read **127 min** to the coach now
reads **9 min**, a genuine 45-minute session is unchanged on both sides, and a session with nothing
accrued states no duration on either.

**Gap stated plainly, unchanged.** I still did not read production Firestore *documents* — there is
no ADC on this machine, `gcloud` is absent, and the Firebase CLI exposes no document-read command. I
would not initiate an interactive credential grant on your behalf. What I did instead is stronger
for the rules question: I verified the **deployed** ruleset empirically, by watching every read both
modules make against production and catching the one that failed.

**Two data-quality items for the coach side** (app faithful in both cases):
1. Served targets are internally incoherent — **2000 kcal** against **33 g P / 22 g C / 12 g F**
   (~328 kcal). The *meal* data is coherent, so the problem is specifically in the target fields.
2. The coach record for this member is literally named **"ORG Name"** — a placeholder reached
   production.

---

## 9. BACKEND / FIRESTORE / CLOUD FUNCTIONS / ARCHITECTURE

Re-traced TrainerHQ → Firestore → Cloud Functions → AlphaSerena → Home → My Plans.

- One `TrainingController`, one `getMyTraining`, one served-expectation resolver, one target rule,
  one session-stats engine shared with the coach app. No duplicated state.
- The log editor writes through `buildSessionEntries` — no editor-specific model, document or write
  path. `saveEditedEntries` touches `entries` + `updatedAt` only and refuses an empty array, so an
  edit can never re-open a finished session or move it in time. **Nor can it change the duration.**
- Controllers registered once, disposed on sign-out — including both history controllers and the
  device-local workout draft and food recents, so no cross-member bleed on a shared device.
- Day-rollover re-anchors the food log, lifestyle, training (plus `refreshIfStale`) and streak
  controllers on resume **and** on the My Plans build path.
- Rules for every in-scope collection are correct — BL-1 was the one exception and is now deployed.
- Writes are minimal and identity-pinning; the update rule pins `authorId`/`clientId`/`adminId`.
- No workout rollup and no workout-consistency CF exist by design; consistency is derived
  client-side from raw session docs plus server-served `prescriptionData`.
- Listeners, streams, subscriptions, offline cache, soft delete, merge semantics, transactions,
  duplicate writes and race conditions re-checked; the guards documented in prior certifications
  (pending-withdrawal sets, debounce flush on close, ack timeouts, idempotent CFs) all hold.

Remaining architectural weaknesses: **F4** (unbounded reads — a scaling property) and **F3**.

---

## 10. WHAT CHANGED IN THIS CLOSURE MISSION

**AlphaSerena**

| File | Change |
|---|---|
| `core/domain/workout_session.dart` | `kMaxIdleGapSeconds`, `accumulateActiveMillis`, `activeSecondsOf`; `WorkoutDraft.activeMillis` (schema v2, v1-safe) |
| `screens/dashboard/workout_session_screen.dart` | active-time accumulator; ticks in `_persist` + `_finish`; all three duration write points now report active time; draft carries and restores the total |
| `core/services/chat_service.dart` | `markReadMember` treats a missing thread as the no-op it always intended |
| `test/workout_active_time_test.dart` | **new** — 14 tests |
| `test/workout_trainerhq_parity_test.dart` | + 3 cross-app duration parity tests |
| `integration_test/workout_patrol_test.dart` | + 3 on-device tests (2 active time, 1 history centring) |

**trainershq-backend**

| File | Change |
|---|---|
| `firestore.rules` | `chats/{clientId}` read gains `(resource == null && signedIn())` — **DEPLOYED** |
| `tests/rules/member_chat_thread_read.mjs` | **new** — 5 tests, verified to fail on the old rule |

---

## 11. KNOWN RISKS AND REMAINING TECHNICAL DEBT

- **The 14 golden baselines are stale.** Accepted as documented baseline. Until regenerated on the
  build host, Home's header, consistency pair and workout card have no golden protection.
- **Legacy sessions keep their wall-clock durations.** Nothing was migrated: the 3 August session
  will continue to read 2 h 7 m in history, in both apps. Only sessions recorded from this build
  forward carry active time. A backfill is impossible — the per-set timestamps needed to reconstruct
  active time for past sessions were never recorded.
- **`WorkoutLogService` has no unit-test harness** (no fake-Firestore dependency), so every service
  write path is only reachable through a widget test that fakes the service. That is how D5 survived.
- **A test group named after a behaviour is not evidence the behaviour is tested** — D1 sat under a
  group called "the timeline centres the day the member came to see" for its whole life.
- **`chats/{clientId}` was the fifth missing-document rule.** A sweep by *defect shape* across the
  whole rules file — not by collection name — is overdue.
- **7 Storage-rules upload tests fail** on this host, before and after; unrelated to these modules.
- Two `lifestyle_math.dart` copies remain duplicated across repos.
- **F3** and **F4** as described in §6.

---

## 12. CERTIFICATION

| Criterion | Verdict |
|---|---|
| No architecture defects | ✅ |
| No backend defects | ✅ BL-1 fixed, deployed, runtime-verified |
| No synchronization defects | ✅ for both modules — F3 is a missing backend trigger, stated in §6 |
| No runtime inconsistencies | ✅ Home ↔ My Plans ↔ History agree to the decimal |
| No stale listeners | ✅ the terminated chat listener is the defect BL-1 closed |
| No incorrect calculations | ✅ duration and calories now derive from active time |
| No production blockers | ✅ |
| TrainerHQ and AlphaSerena show identical values | ✅ structural for duration, proven by parity tests |
| Deployed Firestore rules verified | ✅ deployed, then 0 denials at runtime |
| Runtime matches production | ✅ |
| Patrol green (excl. documented baseline harness issue) | ✅ 106 / 107 |
| Test suite green (excl. documented baseline goldens) | ✅ 1394 pass |

# ✅ GO — FROZEN

Home and My Plans are certified production-ready and frozen as of 2026-08-04.

**Recommended next module: Progress.** It is the last member-facing surface that has not had a
forensic pass, it already carries known placeholder content from earlier audits (a labelled Strength
placeholder, and the Body Snapshot rework), and it reads the same `client_progress` collection the
coach's timeline consumes — so it is the remaining place where a member and their coach could still
disagree about the same number.
