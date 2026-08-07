# PROGRESS — PRODUCTION FREEZE REPORT

**Date:** 2026-08-04
**Repositories:** `alphaserena`, `trainersHQ`, `trainershq-backend`
**Device:** emulator-5554 (`sdk_gphone16k_arm64`, Android 16), live signed-in member
**Scope:** the Progress module — Overview, Analytics, Insights, History, Achievements,
Transformation, Weekly check-in, Schedule.

---

## 0. TWO MISSION PREMISES WERE FALSE — STATED UP FRONT

**1. `PROGRESS_PHASE1_IMPLEMENTATION_REPORT.md` does not exist.** Not in any of the three
repositories. What exists is `PROGRESS_CTO_DISCOVERY_AUDIT.md` (80 KB, written 16:42), which ends
with *"Nothing in this report was implemented, redesigned or fixed."* The implementation is
nevertheless real — **~8,000 lines written 16:52–17:55 the same day**, still **untracked in git**.
The previous session built the module and never wrote its report. This report continues from the
**working tree**, which is the only source of truth available.

**2. "The remaining Patrol failures are assertion problems" was wrong.** There are no assertion
problems. The suite passes 20/20 unmodified. The previous session almost certainly never saw it
complete — see §2.

A third premise, *"use the signed-in member"*, was false **when the mission started** (the app sat
on the sign-in screen) but turned out to be achievable — see §3. This changed the outcome of the
whole engagement.

---

## 1. RUNTIME VERIFICATION

| Check | Result |
|---|---|
| `flutter analyze` (alphaserena) | **0 issues** |
| Progress screen routed | `dashboard_screen.dart:160`, no dangling refs to the deleted screen |
| Listener hygiene | every rebind cancels first; `onClose` disposes 3 subs + 3 workers — no leaks, no duplicates |
| Live member session | **achieved** (first time in this codebase's history) |
| Cold start → Progress renders real data | **PASS** (after the fix in §4) |
| Rotate to landscape | **PASS** — nav becomes a side rail, state and scroll preserved |
| Offline | app-wide connectivity takeover engages |
| Reconnect | **PASS** — full data restored, no stale or blank state |
| Restart | **PASS** |

---

## 2. PATROL VERIFICATION

**20 / 20 green. 0 failed. 0 skipped.** Run three times: baseline, after fixes, and final.

```
📝 Total: 20   ✅ Successful: 20   ❌ Failed: 0   ⏩ Skipped: 0
```

`Total: 20` matters: the audit warns that a `/` in a `patrolTest` name makes the Android JUnit
runner silently drop the file and report `Total: 0` with a green-looking run. Full enumeration is
present.

### Why the previous session thought Patrol was failing

Patrol was **never completing**, for a reason unrelated to assertions. This Mac resolves three
Flutter devices (emulator-5554, macOS, Chrome). Without `-d`, `patrol test` prints
`Multiple devices found. Please choose one:` and blocks on stdin — and with stdin closed it does
**not** exit. It spins forever:

```
Please select an option (1-3, q to quit): [WARN] Please enter a valid option.
```

It burns a full CPU core, so `ps` looks healthy and it is indistinguishable from a slow Gradle
build. Two runs were each presumed to be "building" for ~12 minutes; one wrote **9.2 million lines
/ 448 MB** of that warning before being killed. With `-d emulator-5554` the APK builds in **27 s**
and the whole suite runs in **2m 35s**.

**Verdict: Patrol bug (harness invocation), not an application bug and not an assertion bug.**

---

## 3. REAL MEMBER VERIFICATION

`alphaserena/CLAUDE.md` states repeatedly that there is **no live member session on this emulator**
because phone OTP is externally blocked, and every prior certification was signed off on fixtures
because of it. **That is now stale.** The login screen offers **Continue with Google**, the device
already holds an account, and it works — no credentials were typed; the device's own account picker
was used.

Resulting session: `uid=VOxzizRgU6YFBsbguFJ6winidIA2`, `clientId=EkNg2Yux4lPAQtSpQjds`,
`adminId=Hli8cUoVsadrRyS6lHzvsQ9Dj152`, coach "ORG Name", active until 31 Oct 2026.

Everything below was driven by hand as a real user.

| Surface | Result |
|---|---|
| Overview (61% ring, verdict, three dimension bars, three stats) | real data, correct |
| Range control (Week / Month / 3 Months / Year) | works |
| Analytics chart + metric chips | works; chips scroll; switching redraws correctly |
| Insights | real and substantiated — "Dumbbell Chest Press top set is up 9.0 kg", "Heaviest logged set: 22.0 kg", "2-day training streak", each with its basis line |
| Achievements | 4 workouts · 2-day best streak · 22 kg heaviest · 1.4k kg·reps |
| History (4 destinations) | all four open |
| Transformation | opens; honest empty state (this member has none) |
| Weekly check-in | full form renders. **Not submitted** — that would write real data to a real coach |
| Schedule | opens; honest empty states, consistent with Home |
| Pull-to-refresh | works |

**One thing this member cannot prove:** the account holds only **4 workouts and 2 nutrition days**.
Every "power user" path is therefore **unexercised** — see §7 and §14.

---

## 4. 🔴 PRODUCTION BLOCKER FOUND AND FIXED

### Symptom

On **every cold start**, the member opened Progress and was told:

> **"Your progress starts with one record"**
> *Log a workout, your food, or a transformation check-in.*

…while Home, in the same session, showed a 2-day workout streak, a 2-day nutrition streak and a
workout completed that day (12 s, 1 exercise, 3/3 sets, 100% adherence). Pulling to refresh
revealed the true screen: 61% overall, 4 training days, 100% workout quality.

Reproduced deterministically across multiple cold starts, still wrong 9 seconds after opening.

### Root cause — proven on device, not inferred

Temporary instrumentation in `_bindSessions` produced:

```
canLog=false docs=null linked=false clientId=""      adminId=""
canLog=false docs=null linked=true  clientId="EkNg…" adminId=""
```

Progress bound **twice**, and both binds ran against an unresolved link:

- the rebind trigger was `ever(member.isLinked)`, which flips as soon as
  `clientProfiles.linkedClientId` resolves;
- but every read needs `adminId` as well (`canLog` = clientId ∧ adminId ∧ uid), and `adminId`
  arrives **later**, on the `clients` document stream;
- so both attempts returned "unavailable", and because `isLinked` never changed a third time,
  **nothing ever retried.**

A second, compounding defect made the failure invisible: `isEmpty` tested only whether the lists
were empty. A **failed** source therefore satisfied it, and because the screen checks `isEmpty`
*before* the partial-failure banner, a read failure was rendered as *"you have no records"* — the
exact inversion of the module's own stated rules, **"NULL IS NOT EMPTY"** and **"ONE FAILING SOURCE
DOES NOT BLANK THE SCREEN."**

### Fixes

1. **`progress_analytics_controller.dart`** — rebind on the identity the reads actually require
   (`clientId|adminId`) rather than on a proxy that resolves earlier. Both workers funnel through
   one identity guard, so whichever resolves last triggers exactly one bind, and a coach edit that
   does not change the identity costs no reads.
2. **`progress_analytics_controller.dart`** — `isEmpty` now requires `!hasPartialFailure`. The
   first-run invitation may only be offered once the screen can *prove* there is nothing to show.

**Verified on device:** `canLog=true docs=4` on the second bind; Progress renders fully on cold
start.

### Why every existing test missed it

1,513 unit/widget tests and all 20 Patrol tests passed against this defect, because **all of them
inject reads at the service seam** and none exercises link-resolution timing. This is the same
class of failure the discovery audit documented twice before (`RollupDay.fromCell` reading a key
nothing wrote; the consistency two-axis defect) — *"a fixture asserting the wrong contract hides a
permanent outage."* It is the single strongest argument in this report for never certifying a
member surface on fixtures again.

---

## 5. UX IMPROVEMENTS MADE

**1. `Transformatio / n` — a word broken mid-word.** The shortcut tile allotted two lines, and
"Transformation" has no space to break at, so it did not fit a third of a 390 dp row at 12.5 px and
Flutter split it mid-word. A hard line cap cannot prevent that; only making the word fit can.
Label sized to 11.5 px; `reservedHeight` derives from the same constant, so the row reservation
followed automatically. **Verified on device.**

**2. The chart clipped a perfect score.** A ratio series was hard-clamped to `minY = 0, maxY = 1`
with no headroom, while a scalar series got 18% padding. A line is drawn with width and its markers
with a radius, so a member at **100%** — the most likely value on an adherence chart, and exactly
what a perfect-adherence member sees — had their line and every dot drawn *on* the plot boundary,
where `fl_chart` clips them. It read as a broken chart at precisely the most rewarding moment.
Added ±0.06 axis headroom, deliberately smaller than the 0.25 grid interval. **Verified on device:**
gridlines still land exactly on 0/25/50/75/100, and the **0% and 100% labels now render** (they were
previously suppressed at the axis edge) — strictly more legible than before.

---

## 6. TRAINERHQ PARITY

| Layer | Method | Result |
|---|---|---|
| Shared analytics core | `diff` + SHA-256 | **byte-identical**, `bdd700fb…c1797`, pinned in **both** repos |
| Parity guard itself | `diff` | identical but for the import line |
| Behaviour matrix | literal expected values, twinned | adherence, strength series, volume (4840), distinct exercises, personal bests |
| Threshold contract | 4-way | **28 / 3 / 0.8** agree across backend `progress_config.ts`, `AnalyticsPolicy` (both apps) and `ProgressPolicy` |
| Adapters | read both | correct; parse regex identical |

**One deliberate divergence, correctly reasoned:** AlphaSerena includes the member's **private**
transformation entries in their own weight trend; TrainerHQ filters `!isPrivate` at its read
boundary. Member and coach can therefore legitimately see different weight series. This is privacy,
not drift — but it contradicts the mission's "any mismatch is a blocker," so it is called out
explicitly. A minor asymmetry (AlphaSerena additionally filters incomplete entries) is functionally
inert, because `reconciledWeightSeries` skips null weights anyway.

### Gap found and closed

TrainerHQ now carries **two** threshold classes — `ProgressPolicy` (frozen M5) and `AnalyticsPolicy`
(in the twinned core). Two guards existed: one pins `ProgressPolicy` to the backend, the other pins
the core by hash to AlphaSerena. **Nothing pinned them to each other** — verified: no file in the
repo referenced both symbols. Either could be edited, its own guard updated in good faith, and the
coach app would show a member's adherence over two different windows on two surfaces with every
test green. Exactly the *"two self-consistent sides of a boundary is not a contract"* failure the
audit predicted would strike here next.

Closed with a new test in `progress_threshold_contract_test.dart`. **Proven non-vacuous:** setting
`ProgressPolicy.windowDays = 29` fails both tests (`+0 -2`); restored.

---

## 7. BACKEND, FIRESTORE & RULES

| Suite | Result |
|---|---|
| Cloud Functions (`node --test`) | **1027 / 1027 pass** |
| Firestore + Storage rules | **399 / 399 pass, 0 fail** |

**A false security finding was retired.** My own stored note recorded a "known-good baseline of
392/399 with 7 residual Storage failures." That was wrong: the project id was `demo-trainershq`
instead of `demo-trainershq-rules`. Storage rules resolve cross-service `firestore.get()` against
the *run's* project, so the mismatch made every lookup read an empty database. One of the phantom
failures read as **"REMOVED trainer retains member progress photos"** — a security finding that was
never real. With the correct project id: **399/399**. The note has been corrected.

**Query shape.** Progress adds no new query shape and needs no new index. Rollup reads are bounded
(a whole number of monthly documents; widening re-subscribes, narrowing does not). Sessions are a
single equality-only `authorId` read — auto-indexed, and the same query `WorkoutHistoryController`
already runs.

---

## 8. PERFORMANCE — **NOT ADEQUATELY MEASURED** ⚠️

This is the weakest section of this report and I am not going to dress it up.

**What was verified:** no duplicate listeners (every rebind cancels first); no leaks (`onClose`
disposes all three subscriptions and all three workers); lazy loading is real (`TickerMode` gates
`ensureLoaded`, so a member who never opens Progress pays nothing); the chart animates once per
data *shape* change, not per value tick; reduced-motion is honoured.

**What was NOT measured, at all:**

- Cold-start and warm-start timings. `am start -W` and `Displayed` logging both failed to report on
  this emulator; no numbers were obtained, and I will not invent them.
- Frame timings / FPS / dropped frames. No trace was captured.
- **Any dataset larger than this member's 4 workouts and 2 nutrition days.** 100 / 500 / 1000-record
  scenarios were not run. Seeding them would mean writing thousands of junk records into a real
  member's live coach account, which I was not prepared to do unasked.

**And there is a documented reason to expect trouble at scale.** `fetchSessionHistory()` is
**unbounded** — the code says so itself:

> ⚠️ IT IS UNBOUNDED. There is no `[authorId, date]` composite index, so a windowed server-side
> query is not available; the window is applied in memory by the shared core. For a member with
> years of history this grows.

So on **every** Progress open, a power user downloads their **entire** session history to compute a
28-day window. At 1,000 sessions that is 1,000 document reads and megabytes of transfer on the
critical path of a flagship screen — recurring cost, recurring latency. The decision to defer this
was reasonable when written. It is not something a *production freeze* should ratify unmeasured.

---

## 9. ACCESSIBILITY

| Check | Result |
|---|---|
| Semantics nodes across the module | 19, incl. `container: true` / `button: true` / composed labels |
| Chart | carries `semanticLabel` |
| Text scaling | 5 `textScalerOf`-aware layouts; only 2 hardcoded font sizes |
| Large accessibility font | Patrol ✓ |
| 320 dp phone @ 2.0× text scale | Patrol ✓ |
| Tablet width | Patrol ✓ |
| Landscape | Patrol ✓ and verified by hand |
| Light theme | Patrol ✓ |
| Reduced motion | honoured — every animation is decorative and checks the platform flag |

Reasonably verified. Not verified: an actual screen-reader pass (TalkBack), and colour-contrast
measurement of the amber-on-black verdict text.

---

## 10. STRESS TESTS

| Scenario | Result |
|---|---|
| Rotation | ✅ side rail, state preserved |
| Offline | ✅ app-wide takeover |
| Reconnect | ✅ full recovery |
| Cold restart (×5) | ✅ after the §4 fix |
| Rapid repeated range tapping | ✅ Patrol |
| Rapid navigation / repeated opening | ✅ Patrol + by hand |
| Long history scroll | ✅ Patrol |
| Unlinked member | ✅ Patrol |
| Unreadable source | ✅ Patrol |
| Empty account | ✅ Patrol |
| **Power user (500–1000 records)** | ❌ **not run** |
| **Many transformations / schedules** | ❌ not run (member has none) |
| Poor (not absent) network | ❌ not run |

---

## 11. REGRESSION

| Suite | Before | After | Status |
|---|---|---|---|
| `flutter analyze` alphaserena | 0 | **0** | ✅ |
| alphaserena `flutter test` | 1513 / −14 | **1513 / −14** | ✅ baseline |
| trainersHQ `flutter test` | 1879 / −3 | **1880 / −3** | ✅ +1 (new guard) |
| trainersHQ `flutter analyze` | 26 info | 26 info | ✅ pre-existing, none mine |
| Backend functions | 1027/1027 | **1027/1027** | ✅ |
| Rules | 399/399 | **399/399** | ✅ |
| Patrol | 20/20 | **20/20** | ✅ |

**The 14 alphaserena golden failures are the documented baseline on this machine** — recorded across
four prior certifications in `CLAUDE.md` as *"14 pre-existing golden failures"* caused by **missing
font faces**, once *"proven by reverting this work and re-running."* An inspected diff is a few
pixels of text antialiasing (0.21%, 686 px). The 3 trainersHQ SDS golden failures are likewise
pre-existing and provably unreachable from Progress code.

**I introduced one regression during this session and fixed it.** My first version of the identity
getter read `member.uid`, which resolves `FirebaseAuth.instance`; called from `ensureLoaded()` on a
build path it threw `[core/no-app]` in every widget test — 30 failures in
`progress_screen_test.dart`. This violates a rule the repo states explicitly (*"never resolve a
Firebase singleton in a field initializer — it has made four services untestable"*). The identity is
now `clientId|adminId` only, which reads plain `Rx` values; `uid` is fixed for a session anyway.
Back to baseline, and the runtime fix re-verified on device afterwards.

---

## 12. FILES CHANGED

| File | Change |
|---|---|
| `alphaserena/lib/controllers/progress_analytics_controller.dart` | identity-based rebind; `isEmpty` excludes failure |
| `alphaserena/lib/screens/dashboard/progress/progress_screen.dart` | shortcut label 12.5 → 11.5 px |
| `alphaserena/lib/screens/dashboard/progress/progress_chart.dart` | ratio-axis headroom |
| `trainersHQ/test/progress_threshold_contract_test.dart` | cross-policy drift guard |

The twinned analytics core was **not** touched — hash still `bdd700fb…c1797` on both sides.

---

## 13. SELF-CRITIQUE — reviewing this as another engineer's work

**Strengths, honestly.** This is the best-reasoned module in the repository. The decision to write
the math once against neutral types — rather than copy-and-twin, the mechanism that had already
failed on `transformation_comparison.dart` — is correct, and the SHA-256 + literal-value double
guard is stronger than most production codebases manage. The honesty rules (null ≠ zero, every
figure states its window, weight is never judged) are carried consistently into the pixels.
Subscription hygiene is exemplary. The in-code comments explain *why*, including past failures.

**What I would still push back on:**

1. **The unbounded session read** (§8). The most likely source of a future production incident.
2. **Adapters are not twinned and not guarded.** The core is hash-pinned; the adapters that feed it
   are not, and they are where the app models meet the math. A behaviour test per adapter would
   close it.
3. **Nutrition and lifestyle adapters exist only in AlphaSerena.** There is no coach-side equivalent
   to compare against, so "parity" for those two dimensions is currently unfalsifiable.
4. **A stale doc comment.** The analytics header claims parity is enforced by a committed fixture
   `test/fixtures/progress_analytics.json`. That file does not exist in either repo; the guard is
   the hash. Harmless, but it is exactly the kind of comment that gets trusted later.
5. **The offline takeover is off-brand.** A teal/mint cartoon astronaut in an app that is otherwise
   black and `#D50000`. It is app-wide (not Progress's to change unilaterally), and it also
   *replaces* content the member could still read from cache. Worth a design decision.
6. **Minor polish:** achievement tiles in a pair render unequal heights when one caption wraps (the
   codebase already enforces equal heights for the consistency pair); the metric chip row clips
   mid-word with no fade affordance to signal it scrolls; a 2-point nutrition chart prints
   "3 Aug / 3 Aug / 4 Aug".
7. **"Weekly Reports" still does not exist.** The mission names it; the module ships a *weekly
   check-in*, which is a different product. The audit was right — no report artifact exists anywhere.
8. **The module is untracked in git.** ~8,000 lines of production code exist only in the working
   tree. That is a real risk today, independent of quality.

**Which of these are blockers?** Only #1, and only because this is a *freeze*. Items 2–8 are
legitimate debt that a freeze can carry, provided they are written down — which is what this section
is for.

---

## 14. FINAL RECOMMENDATION

The Progress module is **strong work** — architecturally sound, honest about its own limits, well
tested, and now materially better than it was this morning. A genuine production blocker was found
and fixed, and it was found only because a real member session became possible for the first time.

But the mission's GO bar is conjunctive, and two of its clauses are not satisfied by evidence:

- **"Performance is production ready"** — not measured. No start-up timings, no frame data, and no
  dataset beyond 4 workouts. There is a self-documented unbounded query on the critical path of the
  screen being frozen.
- **"No production blockers remain"** — true as of now, but the blocker fixed today was invisible to
  1,513 unit tests and 20 Patrol tests, and the conditions that hid it (fixture-injected reads, a
  4-record account) are unchanged for every path that has still never run with real volume.

Signing GO would mean asserting things I did not verify. I am not going to do that on a freeze.

### What would turn this into a GO — a short, concrete list

1. **Bound the session read.** Add the `[authorId, date]` composite index and window the query
   server-side, or page it. This is the one code change I would insist on.
2. **Run the module once against a realistic dataset** (≥500 sessions, ≥1000 nutrition entries) in a
   **non-production** project, and capture frame timings on the Analytics scroll.
3. **Capture cold/warm start** on a device where the instrumentation reports.
4. **Commit the module to git.** It is currently untracked.

Items 5–8 of §13 are polish and can be carried.

---

# NO-GO

**Not because the module is weak — it is not — but because a freeze is a claim that the work has
been verified, and its performance at real-world scale has not been.** The four steps above are
small and well understood; none requires redesign. Complete them and this becomes a straightforward
GO.

---

*Every number in this report came from a command run during this session or from a screenshot of the
running app. Where something was not measured, it says so.*
