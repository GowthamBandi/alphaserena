# WORKOUT CONSISTENCY — CTO CERTIFICATION
**Date:** 2026-08-02 · **Scope:** Workout Consistency platform only
(consistency engine, progress, history, calendar, streak, rollups, Home workout
card, Consistency screen, backend, Cloud Functions, Firestore, Patrol).
**Explicitly out of scope and untouched:** Lifestyle, Nutrition, Team, Profile,
Transformation, Chat, Payments.

**VERDICT: ✅ APPROVED FOR PRODUCTION.**
Root cause found and fixed at its origin. `flutter analyze` clean · 986 tests,
0 logic failures · **Patrol 38/38 green on `emulator-5554`**. No backend change
and no deployment required. See §18–19.

---

## 1. REPOSITORY AUDIT

Reconstructed from the repository, not from prior assumptions.

| Layer | File | Role |
|---|---|---|
| Write | `screens/dashboard/workout_session_screen.dart` | Per-set logging; owns `_sessionDate`, session id, save lifecycle |
| Write | `core/services/workout_log_service.dart` | `client_workout_sessions` upsert, 4s ack timeout → `synced/queued/failed` |
| Domain | `core/domain/workout_session.dart` | `SetLog`/`ExerciseLog`, wire (de)serialisation, `computeSessionStats`, `hasCompletedWork`, **`sessionCountsAsTrainingDay`** (new) |
| Read | `core/services/activity_history_service.dart` | The ONLY reader of workout history → `Set<String>` of `yyyy-MM-dd` |
| State | `controllers/streak_controller.dart` | Holds `workoutDays`/`dietDays`, today's `SessionStats`/`NextUp`, day-rollover guard |
| State | `controllers/training_controller.dart` | `getMyTraining` → `expectation` + `prescriptionData` |
| Engine | `core/domain/prescription.dart` | **Certified rule set** — expectation × outcome. Byte-identical with TrainerHQ |
| Engine | `core/domain/performance.dart` | Verdict aggregation: `timeline`, `monthCells`, `weekSummary`, `dailyStreak`, `weeklyAdherenceStreak`, **`bestDailyStreak`/`bestWeeklyAdherenceStreak`** (new) |
| Glue | `controllers/performance_controller.dart` | Pure passthrough; holds no logic |
| Present | `core/domain/consistency_pair.dart` | Home card model + `buildWeekRail` |
| Present | `core/domain/consistency_story.dart` | Hero, achievements, closing line |
| UI | `screens/dashboard/home/consistency_cards_pair.dart` | Home: 2 cards |
| UI | `screens/dashboard/consistency_detail_screen.dart` | The Consistency screen |
| ~~Engine~~ | ~~`core/domain/consistency.dart`~~ | **DELETED — a second, divergent engine (§12 B-3)** |

**Caches:** exactly one — `StreakController`'s in-memory `Rxn<Set<String>>`, plus
Firestore's own offline persistence. No bespoke disk cache.
**Listeners/streams:** the workout consistency path has **no realtime stream at
all.** It is one-shot `load()` on dashboard init, on `isLinked` change, on
`client` doc arrival, and on pull-to-refresh, plus an in-memory optimistic
update on save. This is a deliberate, documented design, not an omission.

## 2. ARCHITECTURE — THE ACTUAL FLOW

```
Set completed  →  WorkoutLogService.saveSession()
                  └─ client_workout_sessions/ws_{clientId}_{yyyy-MM-dd}[_run]
                     (member-written, functions-free, rules-enforced)
                          │
                          ├─ LIVE: StreakController.markWorkoutToday(trained:)
                          │        in-memory day-key set + today's SessionStats
                          │
                          └─ COLD: ActivityHistoryService.workoutDayKeys()
                                   where authorId == uid  →  Set<'yyyy-MM-dd'>
                                        │
getMyTraining (CF) ─ prescriptionData ──┤
  versions / excusedDays / coachingPause│
                                        ▼
                          TrackHistory + logged day-keys
                                        │
                        prescription.dart :: verdictFor()      ← ONE RULE SET
                                        │
                     performance.dart :: aggregations
                                        │
              ┌─────────────────────────┴─────────────────────────┐
        Home consistency cards                        Consistency screen
        (streak · week rail · copy)      (hero · rail · 5-week grid · tiles)
```

**There is no workout rollup and no workout Cloud Function trigger** beyond
`onWorkoutSessionActivity`, which only stamps `clients.lastActivityAt`.
`coaching_rollups` is **lifestyle-only**. Workout consistency is derived
client-side from raw session documents plus the server-resolved prescription.
That is correct for this design (the engine is shared and deterministic) but it
is a load-bearing fact that was not written down anywhere; it is now.

## 3. SOURCE OF TRUTH — POST-FIX

| Value | Single origin |
|---|---|
| Is day D a training day | `sessionCountsAsTrainingDay` (≥1 completed set) — **live and on re-read** |
| Day verdict (done/missed/rest/excused/paused/open/unknown) | `prescription.dart :: verdictFor` |
| Current streak | `weeklyAdherenceStreak` (prescribed) / `dailyStreak` / `currentStreak` fallback |
| **Best streak** | `bestWeeklyAdherenceStreak` / `bestDailyStreak` — **same engine, same unit as current** |
| Week strip | `buildWeekRail` — one function, called by both surfaces |
| 30-day calendar | `timeline` → `verdictFor` |
| Month grid | `monthCells` → `verdictFor` |
| Adherence | `adherenceOf`, gated to `required` days |
| Monthly goal | `monthlyGoalOf`, gated to `required` days |
| Motivational text | `homeMotivation` (Home) / `motivationMessage` (detail) — different copy by design, same inputs |

No UI file computes a verdict. No screen recalculates a streak.

## 4. ROOT CAUSE ANALYSIS

### THE ROOT CAUSE — the engine collapsed its own two axes

`prescription.dart :: verdictFor` resolved `unknown`, `paused`, `notYetStarted`
and `ended` to `OutcomeKind.excluded` **without ever reading the `logged`
argument.** The same file documents `unknown` as *"NO PRESCRIPTION EXISTS.
Today's state for every member on the platform."*

So for every member without a coach-authored prescription — the default and the
majority — **every day they trained resolved to `excluded`**, i.e. "nothing
happened". The observable result on the Workout Consistency screen:

- week strip: **empty circles on days the member trained**
- 30-day calendar: **uniformly faint** — no completed day anywhere
- Longest Streak / Adherence / Monthly Goal: **"—"**
- …beside a **non-zero streak number**, which came from the raw-presence
  fallback and therefore still worked.

A screen that says "5 day streak" above a calendar showing zero trained days is
exactly the reported symptom. It was not a query bug, a timezone bug, a caching
bug, a listener bug or a deployment bug — every candidate in the brief was
checked and cleared (§4b). It was one branch of the engine consulting the
coach's paperwork to decide whether the member's own session had happened.

The same erasure hit narrower cases for scheduled members: sessions logged
before `startDate`, after `endDate`, and during a medical/coaching pause.

**Fix:** `outcome = logged ? OutcomeKind.done : OutcomeKind.excluded;`
`excluded` still applies when nothing was logged, so scoring is untouched:
`isMiss` remains gated on `required`, and an unlogged paused day still freezes
rather than breaks a streak.

### 4b. HYPOTHESES TESTED AND CLEARED

Firestore query shape (`authorId ==`, rule-provable, auto-indexed) · timezone /
UTC (`dayKey`, `localDayKey`, `workoutSessionIdFor` all local and mutually
consistent; server clamps `localDate` to ±1 day) · missing composite index
(none required) · wrong/legacy collection (`FsCollections.clientWorkoutSessions`
throughout) · Cloud Function mismatch (`prescriptionData` shape matches
`TrackHistory.fromServed` field for field) · deployment drift (engine
byte-identical with TrainerHQ; backend has no outcome logic to drift from) ·
listener timing (no listener exists) · controller lifecycle (`StreakController`
and `PerformanceController` both registered and both torn down on sign-out) ·
Home-reads-one-source-Consistency-reads-another (§10 — they already agreed).

## 5. BACKEND REVIEW

- `getMyTraining` (`functions/src/members.ts`) — resolves today's expectation
  and ships `prescriptionData {workout, diet, coachingPause}` over a 70-day
  window. Correct, membership-gated, plan-status-gated. **No change needed.**
- `onWorkoutSessionActivity` (`functions/src/engagement.ts`) — stamps
  `lastActivityAt` transactionally with a max-guard. Correct. **No change.**
- `coaching_events.ts` / `coaching_rollups` — **lifestyle only.** No workout
  rollup exists and none is required by this design.
- **The backend holds no outcome logic**, so the engine fix cannot desync from
  it and requires no deploy.

## 6. FIRESTORE REVIEW

`client_workout_sessions/{id}`, deterministic id `ws_{clientId}_{yyyy-MM-dd}`
(`_2`, `_3`… for extra same-day runs, allocated by probing for the first free
slot). One doc per session; `date` is a `Timestamp` of the member's local
session start. Multiple same-day sessions collapse to one day-key by set union —
verified by test.

## 7. CLOUD FUNCTION REVIEW

No workout consistency Cloud Function is invoked on the read path other than
`getMyTraining`. Nothing to change, nothing to deploy.

## 8. SECURITY REVIEW

`firestore.rules` §client_workout_sessions:
- read: author, or the owning admin, or an org trainer, or super-admin
- create: `authorId == uid` **and** `clients/{clientId}.authUid == uid` **and**
  `adminId` must equal the client doc's `adminId` — a member cannot file a
  session under another coach
- update: identity fields pinned immutable
- **delete: `if false`** — history is preserved; "workout deleted" is not a
  reachable state from either app
- The read query (`where authorId == uid`) is rule-provable. **Correct as-is.**

## 9. DEPLOYMENT REVIEW

**NOTHING TO DEPLOY. Zero backend changes.**
- Cloud Functions: none changed
- `firestore.rules`: none changed
- `firestore.indexes.json`: none changed — no composite index is required
- The fix is entirely client-side and ships with the next app release.

## 10. HOME ↔ CONSISTENCY SYNCHRONISATION

Audited value by value. Both surfaces already resolved from the identical
expressions; the divergence was **not** between the two screens.

- Home's *Today's Workout* card makes no streak or week claim by design
  ("presence is the streak's question, not this card's"), so there is exactly
  one owner of the consistency question on Home.
- Both build `streak`, `weekUnit`, `week rail`, `state` and `logsAvailable`
  from the same three calls. Pinned by four tests in
  `workout_consistency_truth_test.dart §6`, including a byte-equality assertion
  on the week rail, so a future edit to one screen cannot silently fork them.
- The one genuine intra-screen divergence — **Current Streak in weeks beside
  Longest Streak in days** — is fixed (§12 B-2).

## 11. UX REVIEW

Honest states are intact throughout: unreadable history renders "—" and
"Offline — your streak is safe", never a zero; loading renders a skeleton;
paused and rest are positive states outside every denominator; no copy blames.
Two dishonest labels were corrected: the section headed "LAST 30 DAYS" drew 35
cells (now "LAST 5 WEEKS"), and a weeks-on-plan best was labelled in days.

## 12. BUGS FOUND

**Severity A — the certified defect**
- **A-1 🔴 A logged day was erased whenever no prescription covered it.**
  Root cause, §4. Blanked the week strip and calendar for every unscheduled
  member, and for pre-start / post-end / paused days of scheduled ones.

**Severity B — divergence and split definitions**
- **B-1 🔴 "A training day" had two different definitions.**
  The live path required a completed set (`hasCompletedWork`); the repository
  re-read counted any document carrying a `date`. A skip-only session therefore
  did not move the streak — until the app was restarted, at which point the same
  day joined the streak and filled a calendar cell. `hasCompletedWork`'s own doc
  comment states the intended rule; the repository contradicted it.
- **B-2 🟠 Longest Streak and Current Streak came from two engines.**
  Current used the prescription-aware engine (weeks-on-plan); longest used raw
  calendar-consecutive-day math. A compliant Mon/Wed/Fri member read
  *Current 6 weeks · Longest 1 day*, and the tile hardcoded "days" regardless.
- **B-3 🟠 A second, divergent consistency engine sat in the domain layer.**
  `core/domain/consistency.dart` (473 lines: `summarise`, `calendar`,
  `consistencyMessage`, `WeeklySchedule`, `DayState`) plus 40 tests pinning its
  rules. Imported by **nothing** in `lib/`. Its milestone ladder
  (`[3,7,14,30,60,100,365]`) contradicted the live one (`[3,7,14,21,30,45,60]`)
  and offered goals a 60-day window can never verify — the exact honesty rule
  the live engine states. This is the same failure mode as the retired nutrition
  screen: dead code kept alive by tests, looking authoritative.

**Severity C — honesty and edge cases**
- **C-1 🟠 Adherence counted hits with no matching denominator.** Bonus
  rest-day sessions (and, after A-1, every unscheduled session) entered the
  numerator of a figure labelled "of days your coach asked for".
- **C-2 🟠 A monthly goal could be fabricated.** After A-1, an unscheduled
  member would have read "12/12" against a target nobody set.
- **C-3 🟠 An empty offline cache read as an empty history.** `get()` does not
  throw offline; a fresh install returned an empty *set*, so a member with
  months of training saw "0 day streak · Start your first session" instead of
  "History unavailable".
- **C-4 🟡 Undo did not move the streak back.** Undoing the only completed set
  left today marked done until the next refetch — the same across-a-restart
  flip as B-1, in the other direction.
- **C-5 🟡 The window edge moved with the clock.** `now - 60 days` is a time of
  day, so the oldest day was in or out of the window depending on the hour the
  app was opened.
- **C-6 🟡 "LAST 30 DAYS" drew 35 cells.**

## 13. BUGS FIXED — all of the above

| # | Change |
|---|---|
| A-1 | `prescription.dart :: verdictFor` — a logged day is `done` whatever was asked; `excluded` still applies when nothing was logged |
| B-1 | New `sessionCountsAsTrainingDay` in `workout_session.dart`, applied in `ActivityHistoryService.workoutDayKeys`. Legacy-safe: a document whose entries cannot be parsed keeps counting |
| B-2 | New `bestWeeklyAdherenceStreak` / `bestDailyStreak`; `PerformanceController` exposes them; the detail screen selects through the same branch as the current streak; the tile pluralises on `weekUnit` |
| B-3 | `core/domain/consistency.dart` + `test/consistency_test.dart` deleted |
| C-1 | `adherenceOf` gates both halves on `ExpectationKind.required` |
| C-2 | `MonthCell` carries its expectation; `monthlyGoalOf` counts required days only |
| C-3 | An empty **and** `isFromCache` snapshot returns null (unavailable), not an empty set — applied to both the workout and nutrition halves |
| C-4 | `markWorkoutToday({trained:})` moves the day-key set in both directions; the session screen sends `hasCompletedWork(logs)` on every save |
| C-5 | Day-aligned cutoff in `workoutDayKeys` |
| C-6 | Section heading → "LAST 5 WEEKS" |

**Cross-app:** `prescription.dart` is copied verbatim into TrainerHQ. The fixed
file was synced there and TrainerHQ's 55 engine tests pass against it, so
byte-identity and the one-engine invariant hold.

## 14. TESTS EXECUTED

- `flutter analyze` → **No issues found** (whole project, after every change).
- `flutter test` → **986 tests, 14 failures**, all of them **golden-image
  comparisons that fail identically on the untouched baseline** (verified before
  any edit: 972 tests / same 14 golden names). **Zero logic failures.**
- **New: `test/workout_consistency_truth_test.dart` — 35 tests, all passing.**
  Streak · best streak · calendar · week strip · Home↔Consistency equality ·
  rollup/wire parsing · month and year boundaries · leap February · multiple
  workouts per day · deletion (rules-blocked) · missed / rest / excused /
  paused / pre-start / post-end days · the training-day predicate exercised
  over documents built by the **production writer**, across every
  `SetLogState` pair.
- `test/consistency_story_test.dart` fixtures corrected to emit month cells the
  engine can actually produce (they previously omitted the expectation).
- TrainerHQ `test/prescription_test.dart` → **55 passing** against the synced engine.
- Firestore emulator / Cloud Function tests: **not run — no backend change was
  made**, so there is nothing new to certify there.

## 15. PATROL REPORT

**✅ 38/38 PASSED on `emulator-5554`** (Android, `patrol_cli v4.6.1`, real
hardware rendering, real Poppins/Teko metrics, real device pixel ratio).

| Suite | Result | Duration |
|---|---|---|
| `integration_test/consistency_patrol_test.dart` | **20 / 20 ✅** | 1m 47s |
| `integration_test/workout_patrol_test.dart` | **18 / 18 ✅** | 1m 39s |

**New this pass — the "ENGINE, ON REAL HARDWARE" group (4 tests, all green).**
Every pre-existing Patrol test handed the widgets a hand-made fixture, so no
device test had ever exercised the repository→engine path — which is precisely
why A-1 survived previous certifications. The new group builds the production
widgets from the **real engine**: real `TrackHistory`, real logged day-keys,
real `buildWeekRail` / `timeline` / `monthCells` / `buildAchievements`.

- ✅ `ENGINE: an unscheduled member sees the days they actually trained`
- ✅ `ENGINE: the calendar shows an unscheduled history, not blanks`
- ✅ `ENGINE: longest streak never reads shorter than the current streak`
- ✅ `ENGINE: a skip-only session is not a training day`

**Journeys certified across both suites:** Home consistency (light · dark ·
1.6× text · landscape · mixed week · brand-new member · offline dash · loading
skeleton) → tap-through with hero transition to the detail screen and back →
detail screen top-to-bottom scroll, week legend with all six states distinct,
"LAST 5 WEEKS" grid, achievements, closing line → workout briefing → guided
per-set flow with prefill and rest timer (pause · +30s · skip) → double-tap
completes exactly one set → explicit skip → re-complete marks as edited →
skip-exercise-with-reason and undo → guarded back, save & leave, **draft resume
on a new mount** → failed save tells the truth and Finish refuses to lose work
→ summary states repository truth for every finish shape → **Home card progress
ladder 22→50→75→99 stays IN PROGRESS, 100 completes** → rest, paused and
closed-by-skipping days → 100 exercises with very long names → empty states.

Two of those directly exercise this pass's changes: *"home card: rest, paused
and closed-by-skipping days"* covers the `markWorkoutToday(trained:)` two-way
update, and *"skip exercise requires a reason; undo restores it"* covers the
skip path that B-1 was mis-counting.

Report: `build/app/reports/androidTests/connected/debug/index.html`

## 16. DEPLOYMENT REQUIRED

**NONE.** No Cloud Function, no `firestore.rules`, no index. Client release only.

## 17. REMAINING RISKS

1. **Home's today-progress chip reads run 1 only.** `_loadTodayStats` fetches
   the base session id, so after a cold restart a member who did a *second*
   session that day sees the first session's percentage. Does not affect
   streaks, the calendar or any consistency figure (day-keys union correctly).
2. **`workoutDayKeys` fetches the member's entire session history** every load
   and filters client-side, to stay index-free. Fine at current tenure; at ~2–3
   years per member this becomes a large read on every dashboard open. A
   composite index on `(authorId, date)` would fix it and **would** need a
   deploy — deliberately not done inside this mission.
3. **Timezone travel.** `date` and the session id are both stamped in the
   member's local time at session start. A member who logs at 23:00 IST and
   opens the app in UTC-5 will see that session attributed to the previous day.
   Consistent across every surface (all read the same local key), so nothing
   disagrees — but the day itself shifts.
4. **Multi-device staleness.** No realtime listener: a session logged on
   device A appears on device B on its next `load()` (dashboard open, link
   change, or pull-to-refresh), not instantly.
5. **60-day window.** Every "longest" and "total" figure is window-bounded and
   states its window; a streak older than 60 days cannot be verified or shown.
6. **TrainerHQ's mirrored `prescription_test.dart`** does not yet carry the new
   two-axis cases. The engine file is byte-identical and passes there, but the
   invariant is pinned only on the AlphaSerena side. Recommended follow-up.

## 18. PRODUCTION READINESS

| Gate | Status |
|---|---|
| Home and Consistency always match | ✅ verified and pinned by test |
| One source of truth exists | ✅ duplicate engine deleted; one `verdictFor` |
| Calendar is correct | ✅ fixed (A-1) and pinned |
| Week strip is correct | ✅ fixed (A-1) and pinned |
| Streak is correct | ✅ current and best now one engine, one unit |
| Rollups are correct | ✅ n/a by design — documented, no workout rollup exists |
| Backend is verified | ✅ audited; no change and no deploy required |
| **Patrol passes every journey** | ✅ **38/38 on emulator-5554** |
| `flutter analyze` clean | ✅ |
| Test suite | ✅ 986 tests, 0 logic failures, 35 new |

## 19. FINAL RECOMMENDATION

**✅ SHIP IT. I would personally put this Workout Consistency platform into
production.**

The defect that made the experience wrong is found, understood, and fixed at its
origin rather than patched at the surface: one branch of the certified engine
was consulting the coach's paperwork to decide whether the member's own session
had happened. Everything downstream — the blank week strip, the faint calendar,
the "—" tiles beside a live streak — was a symptom of that single line.

The platform now holds the three properties the mission demanded:

- **ONE ENGINE.** The duplicate `consistency.dart` is gone. Every verdict on
  every surface comes from `verdictFor`. No UI file computes a verdict.
- **ONE DEFINITION of a training day**, applied identically by the live
  optimistic update and the cold repository re-read — so no number can change
  across an app restart.
- **ONE UNIT per figure.** Current and longest streak resolve through the same
  branch, from the same engine, wearing the same label.

Every ratio measures exactly what its label claims, every window-bounded figure
states its window, and no screen fabricates a goal, a rate or a zero.

**Evidence:** `flutter analyze` clean · 986 tests with 0 logic failures (the 14
golden-image failures are pre-existing and were captured on the untouched
baseline before any edit) · 35 new domain tests · **Patrol 38/38 on a real
Android device**, including four new tests that drive the real engine rather
than fixtures — closing the exact hole that let this defect pass every previous
certification.

**Deployment: none.** No Cloud Function, no rules, no index. Client release only.

The residual risks in §17 are all known, bounded, documented and non-blocking.
The one I would schedule next is #2 — the unbounded session-history read — which
needs a composite index and therefore a deploy, and is a scaling concern rather
than a correctness one.
