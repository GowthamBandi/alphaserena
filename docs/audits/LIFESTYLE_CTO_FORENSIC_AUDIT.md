# LIFESTYLE MODULE — CTO FORENSIC AUDIT

**Date:** 2026-08-03 · **Mode:** investigation only — nothing was fixed, redesigned or refactored.
**Scope:** the Lifestyle module across all three repositories
(`alphaserena` member app · `trainersHQ` coach app · `trainershq-backend`).

**Verdict: NOT PRODUCTION READY. 2 blockers, 3 high, 5 medium.**

The module is architecturally sound and unusually well documented. Every defect below is a
**correctness** defect inside that architecture, not an architectural failure. Two of them
(LS-01, LS-02) are member-visible today and are not caught by any of the 228 passing tests.

---

## 0. What was actually executed (evidence basis)

| Method | Done | Result |
|---|---|---|
| Source forensics, 3 repos, full module | ✅ | ~6,600 LOC app + CF core + rules read end to end |
| Dart runtime probes against real controllers/screens | ✅ | 5 probes (A–E), 3 defects confirmed, **1 hypothesis refuted** |
| **Compiled backend executed** (`lib/lib/coaching_events.js`, node) | ✅ | LS-02 / LS-07 / LS-04 proven **server-side** |
| Existing suites re-run | ✅ | alphaserena **139/139**, trainersHQ **89/89** — all green, all blind to these defects |
| Patrol suite enumerated + fixtures inspected | ✅ | 44 device tests read; fixture defect LS-17 found |
| **Live device E2E with the real CF trigger firing** | ❌ | Not run — requires emulator boot + seeded member auth |
| **Rules emulator suite** | ❌ | Not run — rules read statically instead |
| Multi-device concurrency / real network degradation | ❌ | Reasoned from code, not executed |

The two ❌ rows are the honest limit of this audit. Everything asserted below as **CONFIRMED**
was produced by executing code, not by reading it.

---

## 1. Architecture map (reconstructed)

```
TrainerHQ  LifestyleTargetsSheet
   └─ LifestyleTargetService.setTargetsAndStack()      ── the ONLY target write path
        └─ clients/{clientId}.lifestyleTargets + .supplementPlan
             (rules: validLifestyleTargets + validSupplementPlan; member CANNOT write)
                              │
                              ▼  live snapshots()
AlphaSerena  MemberController.client ──► LifestyleController.targets / .stack
                              │
   member taps ──► LifestyleController ──► LifestyleEventService ──► CoachingEventWriter
                              │                                          │
                              │                        client_lifestyle_days/{clientId}_{date}
                              │                          events: { eventId: {...} }   ← MAP, append-only
                              │                                          │
                              │                              onLifestyleDayWritten (CF)
                              │                                          │
                              │                          deriveLifestyleMetrics()
                              │                            ├─► doc.computed  (server-owned)
                              │                            └─► coaching_rollups/{clientId}_{yyyy-MM}
                              │                                   tracks.lifestyle.days.{date}
                              │                                          │
                              │                          ┌───────────────┴───────────────┐
                              │                          ▼                               ▼
                              │              MemberRollupService              CoachingRollupService
                              │              (member History)                (coach review)
                              │                                                        │
                              └─► mirrorLegacyTotals ──► client_lifestyle_logs ◄── legacy fallback
                                   (compatibility bridge, best-effort)
```

**Two write paths, deliberately:** the event document is the record; the legacy log is a
compatibility projection derived from the same events. **One read model** (`coaching_rollups`)
serves both apps — which is why a defect in the derivation hits member and coach identically.

**Firestore document map**

| Collection | Id | Writer | Readers | Delete |
|---|---|---|---|---|
| `clients/{id}` | client id | coach app (rules-validated) | both apps | admin only |
| `client_lifestyle_days` | `{clientId}_{yyyy-MM-dd}` | member (events only) | member, org | `if false` |
| `coaching_rollups` | `{clientId}_{yyyy-MM}` | **CF only** | member, org | `if false` |
| `client_lifestyle_logs` | `{clientId}_{yyyy-MM-dd}` | member (bridge) | org | `if false` |
| `coaching_reviews` | `{clientId}_{yyyy-MM-dd}` | **CF only** | org + member if `visibility=='member'` | `if false` |

**Cloud Functions:** `onLifestyleDayWritten` (trigger) · `rebuildCoachingRollups` (replay,
super-admin) · `getCoachingMetrics` (callable) · `reviewCoachingDay` · `compareCoachingParity`.
All five exported from `index.ts`.

**Indexes:** none required, and none present. Every lifestyle read is a document read by
deterministic id. The single query is the legacy fallback's two equality filters
(`adminId`, `clientId`) — single-field indexes only. **Confirmed correct.**

**Listeners per member session:** 2 from `LifestyleController` (day doc + events doc) +
3 from `LifestyleHistoryController` (one per month) = 5. See LS-08.

---

## 2. Product intent vs. implementation (Phase 1)

Traced from the design spec (`2026-07-01-daily-lifestyle-tracker-design.md`) and from backend
behaviour, not assumed:

| Question | Intended | Actual |
|---|---|---|
| Water accumulates? | Yes — sum of drink events | ✅ correct |
| Steps overwrite? | Yes — manual is absolute, latest wins | ✅ correct |
| Sleep replaces? | Periods merge; an edit must replace | ✅ correct (`replacing:`) |
| Supplements append? | One event per dose | ✅ correct |
| Edits create events? | Yes — soft delete, never erase | ✅ correct |
| Coach sees events or totals? | Totals, derived server-side | ✅ correct |
| Home shows totals? | Yes | ✅ correct |
| History shows rollups? | Yes | ✅ correct |
| **Absent ≠ zero?** | **Spec §4.1: "Any metric may be absent. Absent ≠ zero."** | ❌ **violated — LS-02** |
| **Member can edit prior days?** | **Spec §6: day strip, today default, future disabled** | ❌ **never built — LS-05** |

---

## 3. BUG CATALOG

### 🔴 BLOCKERS

---

#### **LS-01 — "Today's Targets" renders a framework error instead of the join prompt**

- **Severity:** Blocker · **Category:** correctness / crash · **Layer:** Controller ↔ Widget
- **Screen:** `lifestyle_today_screen.dart:56–86`

**Reproduction**
1. Sign in as a member whose `clients` doc has not yet resolved (first login, claim in flight,
   membership lapsed, or a failed client-doc read).
2. Open Today's Targets.

**Expected:** the "Join a coach to start tracking your day." prompt (`_joinPrompt`, which exists).
**Actual:** GetX throws `ObxError`; the body renders an error box. The prompt renders **zero times**.

**Root cause.** The body is an `Obx`. Its first statement is `if (!c.canLog)`, and `canLog`
short-circuits on `_member.clientId` — which reads `MemberController.linkedClientId`, a
**plain non-reactive `String?`** (`member_controller.dart:38`). When it is empty, `adminId`
(the only reactive read, via `client.value`) is never evaluated, so the `Obx` closure observes
**no `Rx` at all** and GetX throws by design.

**Evidence — PROBE A, executed:**
```
PROBE A exception:  [Get] the improper use of a GetX has been detected. ...
PROBE A join prompt found: 0
```

**Why it survived:** all four test fakes in both `lifestyle_controller_test.dart` and
`lifestyle_today_screen_test.dart` hardcode `bool get canLog => true`. The false branch has
**never been executed by any test.**

**Affected files:** `lifestyle_today_screen.dart:57` · `member_controller.dart:38,237`
**Risk:** every member sees a broken screen on the first render after login until the claim
resolves; a member whose linkage fails sees it permanently.
**Recommended fix (not applied):** read a reactive value before the guard, or make
`linkedClientId` an `Rx`. The latter also fixes the silent-rebind class.

---

#### **LS-02 — "Did not log" is recorded as "logged zero" for water and supplements**

- **Severity:** Blocker · **Category:** data integrity · **Layer:** Cloud Function → both apps
- **Backend:** `functions/src/lib/coaching_events.ts :: deriveLifestyleMetrics`

**Reproduction**
1. On any day, log **only** steps (or only sleep, or only a supplement) — do not drink water.
2. Open the member's History → Water. Open the coach's Lifestyle review.

**Expected:** that day is **absent** from water history. Spec §4.1 and the code comments in
`RollupDay.fromCell` and `LifestyleHabitStats` all state this rule explicitly.
**Actual:** the day is present with the value **0 ml** — counted as a logged day that missed the goal.

**Root cause.** `deriveLifestyleMetrics` returns `null` for `sleepMinutes` and `steps` when
unrecorded, but `totalWaterMl` returns `0` and `supplementAdherence` returns `{taken:0, itemsTaken:0}`.
**Three of five metrics cannot express absence.** Every downstream reader treats presence as
"logged", so a 0 becomes a miss.

**Evidence — compiled backend executed directly:**
```
STEPS-ONLY DAY      -> {"waterMl":0,"sleepMinutes":null,"steps":9000,"supplementDoses":0,"supplementItems":0}
SLEEP-ONLY DAY      -> {"waterMl":0,"sleepMinutes":480,"steps":null,"supplementDoses":0,"supplementItems":0}
SUPPLEMENT-ONLY DAY -> {"waterMl":0,"sleepMinutes":null,"steps":null,"supplementDoses":1,"supplementItems":1}
```

**Evidence — member app, PROBE D (3 days: 2 500 ml, steps-only, 2 500 ml):**
```
water: dayValues={08-01: 0.0, 07-31: 2500.0, 08-02: 2500.0}
       avg7=1666.67   hitRate=0.667   streak=1   best=1
       worstDay=MapEntry(2026-08-01: 0.0)
supplements: dayValues={08-01: 0.0, 07-31: 2.0, 08-02: 2.0}  hitRate=0.667  streak=1
```
Truth: 2 logged water days, both hits — **100% hit rate, 2 500 ml average, 3-day streak.**
Shown: 67%, 1 667 ml, **streak broken**, and the member is told 1 Aug was their *worst water day*
— a day about which they claimed nothing.

**Evidence — coach app, PROBE E (same cell through `lifestyleDaysFromRollup`):**
```
2026-08-01: water=0.0 steps=9000.0 sleep=null itemsTaken=0 doses=0
```
Identical corruption reaches `statsFor` → `hitRate7`, `currentStreak`, `consecutiveMisses`,
`worstDay`, and the hero `LifestyleScore`. `supplementStats` scores the day `0/stack` = a miss.

**Blast radius:** water and supplement **averages, hit rates, streaks, best/worst day, trend,
calendar colour and the coach's headline score** — in **both** apps, for **every** member who
does not log all four metrics every single day.

**Why it survived:** every fixture in every suite hand-builds cells containing only the metric
under test (see LS-17). No test has ever fed either app the shape the server actually emits.

**Affected files:** `coaching_events.ts:278,388,401` · `member_rollup_service.dart:43–60` ·
`coaching_rollup_service.dart:141–182` · `lifestyle_history_controller.dart:244–299` ·
`lifestyle_review_controller.dart:333–420`
**Recommended fix (not applied):** make the derivation return `null` when no event of that type
exists — one change at the source, rather than teaching four readers to special-case 0. Note this
is a **read-model semantic change**: existing rollups need `rebuildCoachingRollups`, and
`compareCoachingParity` will legitimately report diffs during the transition.

---

### 🟠 HIGH

#### **LS-03 — Water above the goal cannot be recorded; the cap also applies to a merely *suggested* goal**

- **Layer:** Controller · `lifestyle_controller.dart:279–281`

```dart
bool get canAddGlass =>
    waterTargetGlasses <= 0 || waterGlasses + _pendingAdds < waterTargetGlasses;
```

`waterTargetGlasses` derives from `waterTargetMl`, which is `effectiveTarget(coachTarget, 2500)` —
**it is never ≤ 0**. So the cap is *always* active. Two consequences:

1. A member who drinks more than their goal **cannot record it.** The + button greys out. Their
   real intake is truncated in the coach's analytics, permanently and silently.
2. When the coach set **no** water target, the cap is enforced against the **platform default**.
   The card itself labels that goal "suggested" — and the Home card says **"No target set"** —
   yet the member is blocked at 10 glasses by it.

Every other metric accepts over-target values (steps and sleep are unbounded to their limits, and
the module elsewhere deliberately renders 115%/200% rather than flattening). Water is the outlier.

**Aggravating:** Patrol test `'the + stops at the coach\'s goal'` **certifies this as intended
behaviour**, so the defect is currently protected by the test suite.

---

#### **LS-04 — Setting bedtime equal to wake time silently records a 24-hour night**

- **Layer:** Widget · `lifestyle_today_screen.dart:1005–1014, 1050–1059`

```dart
final span = w > b ? w - b : (24 * 60) - b + w;
return span == 0 ? null : span;
```

When `w == b`, the first branch is false and the second yields `1440 - b + b` = **1440**.
`span` is **mathematically incapable of being 0**, so the `span == 0` guard and the error message
`"Sleep and wake time can't be the same."` are **unreachable dead code**.

**Evidence — PROBE B, executed:**
```
PROBE B _minutes for bed==wake(22:30) = 1440
PROBE B setSleep accepted: true   derived sleepHours: 24.0
```
Confirmed server-side too: `BED==WAKE (24h span) -> {"sleepMinutes":1440, ...}`.
`validateSleepEntry` passes (24 ≤ 24) and `sleepMinutes` accepts it (1440 ≯ 1440), so a 24-hour
sleep is written, derived, rolled up and shown to the coach.

The 2026-08-02 certification entry records this as *fixed* ("Now names the actual problem").
The change replaced a confusing message with **silent data corruption**.

---

#### **LS-05 — The member can only ever log today; the day strip was never built**

- **Layer:** Screen (missing) · `lifestyle_controller.dart:235`

`selectDay()` has **zero production callers** — verified by grep across `lib/`. Its only caller
anywhere is one unit test. The whole selected-day machinery (`selectedDay`, `_followToday`,
`ensureFreshDay`'s follow logic) is dead in production.

Design spec §6 required: *"A light day strip to view/edit prior days; today selected by default;
future days disabled."* It was not built, and no certification entry records the omission.

**Consequence:** a member who forgets to log last night's sleep before midnight can never record
it. There is no correction path for any missed day.

---

### 🟡 MEDIUM

#### **LS-06 — Midnight rollover only fires on app resume**
`ensureFreshDay()` is wired to `didChangeAppLifecycleState == resumed`
(`dashboard_screen.dart:76`) and to pull-to-refresh. A member with the app **in the foreground**
across midnight — logging a last glass of water at 00:01 — writes to **yesterday's** document.
No timer, no `Ticker`, no date-change listener. (Pull-to-refresh is also a no-op unless the date
actually changed, so the visible refresh gesture does nothing on the common path.)

#### **LS-07 — The 200-event cap discards the NEWEST events, and the client has no cap at all**
`onLifestyleDayWritten` does `allEvents.slice(0, MAX_EVENTS_PER_DAY)` over a list sorted
**ascending by time** — so it keeps the oldest 200 and drops everything after. The Dart
derivations have **no cap whatsoever**.

**Evidence, executed:** `210 DRINKS: client(uncapped)= 52500 ml  server(capped)= 50000 ml`
— `kept e000 .. e199 — the NEWEST 10 are dropped`.

Past 200 events the member's app and their coach permanently disagree, and it is the member's
**most recent** activity that vanishes. Withdrawn (soft-deleted) events count toward the cap, so
an add/remove/add cycle — the exact pattern Patrol's own "5× repeated add/remove" test exercises —
reaches it fastest.

#### **LS-08 — `LifestyleHistoryController` is never disposed when its screen closes**
`Get.put` in `lifestyle_history_screen.dart:42`, deleted only in `auth_controller.signOut`. Its
**three monthly Firestore listeners stay open for the rest of the session** after a single visit
to History. Bounded (3, one instance) but unnecessary, and inconsistent with
`LifestyleController`'s careful teardown.

#### **LS-09 — Home and Today disagree about whether an unset target exists**
With no coach water target: Home renders **"No target set"** and no percentage; Today renders a
live ring, a percentage, an ml-vs-goal line, *and* enforces LS-03's cap — all against a goal Home
denies. Same controller, two answers. Steps and sleep share the shape.

#### **LS-10 — No bound on the events map in rules or client**
`client_lifestyle_days` rules validate identity and block `computed`, but never bound `events`.
A day document can be grown to Firestore's 1 MiB limit, after which **every** write to that day
fails permanently and the member cannot log anything for that date again. `MAX_EVENTS_PER_DAY`
exists only in the CF, and only to truncate the *derivation*.

---

### 🟢 LOW

| ID | Finding |
|---|---|
| **LS-11** | `validSupplementPlan` (rules:997) — the comment claims it bounds *"the size of every string"*; it only checks `p is list && p.size() <= 40`. Item shape is unvalidated too. |
| **LS-12** | `_pendingAdds` is reset to 0 by every stream emission and then decremented on failure — a rejected write can leave it at −1, loosening the LS-03 cap by one glass. |
| **LS-13** | The sleep period is built with `DateTime.subtract`, which is absolute-time arithmetic; across a DST boundary the *displayed* bedtime shifts by an hour. The derived duration stays exact. No DST in India — accepted. |
| **LS-14** | Today's `_summary` reads "N of M goals met" where M is the number of metrics **logged**, not prescribed — logging only water reads "0 of 1 goals met". |
| **LS-15** | A sleep period whose wake time is later today is accepted — a future-dated sleep event. Both apps filter future *days*, not future *periods*. |
| **LS-16** | `schemaVersion` is client-written on every append and unconstrained by the update rule. |

---

### 🔬 TEST & PROCESS DEFECTS (root cause of why LS-01 … LS-04 shipped)

#### **LS-17 — Every fixture asserts a contract the backend does not emit**
`lifestyle_history_patrol_test.dart` builds `RollupDay(waterMl:…, steps:…, sleepHours:…,
supplementItems:…)` directly, supplying only the metrics under test. The unit fixtures do the
same. **No test anywhere feeds either app the real emission shape** (`waterMl: 0` present on a
steps-only day) — which is precisely why LS-02 is invisible to 228 passing tests.

This is the **third recurrence of one failure mode**, already recorded twice in the repos'
own CLAUDE.md: the `sleepHours`-vs-`sleepMinutes` bug ("a fixture asserting the wrong contract")
and the workout-consistency defect ("that fixture habit is exactly why this defect survived every
previous certification"). The stated lesson — *drive the engine, not a fixture* — was not applied
to Lifestyle.

#### **LS-18 — `canLog == false` is never exercised** — all four fakes hardcode `canLog => true`. Directly responsible for LS-01.

#### **LS-19 — Patrol certifies a defect as a feature** — `'the + stops at the coach's goal'` locks in LS-03.

---

## 4. Audits by dimension

**Security — PASS, with one gap.** Members cannot write `clients` (no member branch in the update
rule), so targets cannot be self-set. `computed` is server-owned and blocked on create and update.
Rollups and reviews are CF-only. Day-doc ids are pinned to their contents. Cross-tenant reads are
correctly denied, and the missing-document read fix (`resource == null && signedIn()`) is present
and correctly reasoned. **Gap:** LS-10 (no size bound) and LS-11 (unvalidated item shape). No
cross-tenant or privilege issue found.

**Performance — PASS.** One document read per month per app (3 each). No composite indexes needed
and none present. Mirror writes are debounced (900 ms) with a 5 s starvation deadline — the
starvation and self-trigger analysis in `_mirrorIfStale` is correct. Stats are memoized with the
`Obx`-subscription hazard correctly handled on both sides. The legacy unbounded scan is one-shot
per subscription. **The only leak is LS-08.**

**State management — PASS, with LS-01 and LS-08.** Both subscriptions cancelled and the link
worker disposed in `onClose`; the debounce is flushed rather than dropped. The three in-flight
race guards (`_pendingAdds`, `_pendingWithdrawn`, `_togglesInFlight`) are each correct and
correctly scoped. One controller instance serves Home and Today.

**Stress — 1 confirmed divergence (LS-07).** Rapid tapping, double/triple taps and repeated
add/remove cycles are genuinely guarded. **A hypothesis I raised was refuted by execution:** I
predicted the coach projection would go stale after every event on a day was withdrawn.
PROBE C disproved it — soft-deleted events keep the list non-empty, so `_projectionIsStale`
still runs and the mirror correctly writes `0`. Recorded here because a forensic audit that
reports only its confirmed suspicions is not an audit.

---

## 5. Production readiness

| Dimension | Score |
|---|---|
| Architecture & data model | 9 / 10 |
| Backend correctness | 5 / 10 — LS-02 originates here |
| Client correctness | 4 / 10 — LS-01, LS-03, LS-04 |
| Security & rules | 8 / 10 |
| Performance | 9 / 10 |
| State management | 8 / 10 |
| Feature completeness vs spec | 6 / 10 — LS-05 |
| **Test credibility** | **3 / 10** — 228 green tests, 0 of these 10 defects caught |
| **Overall** | **5.5 / 10 — NOT READY** |

**Ship gate:** LS-01 and LS-02 must close before release. LS-03 and LS-04 corrupt recorded health
data and should close with them. LS-05 is a product decision (ship without day editing, or build it).

**The single most important finding is LS-17, not any individual bug.** A suite this large that is
this green while this much is broken is reporting the health of its fixtures, not of the module.
Until at least one test per surface is driven from the backend's real output, the next
certification will be as confident as the last three and as wrong.

---

*Investigation only. No file in any repository was modified. Both throwaway probe suites
(`test/zz_forensic_probe_test.dart`, two repos) were deleted after execution; the working trees
are as found.*
