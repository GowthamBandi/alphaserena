# ALPHASERENA — NUTRITION MODULE
# CTO FORENSIC AUDIT · ZERO-IMPLEMENTATION MISSION

**Date:** 2026-08-03
**Mandate:** investigate only. No source file was modified, no fix applied, no UI redesigned.
**Evidence standard:** runtime over source, source over documentation, documentation over prior certification.

---

## 1. EXECUTIVE SUMMARY

**VERDICT: NOT PRODUCTION-READY. One BLOCKER, member-facing, on the read path.**

The Nutrition module's *computation* is correct. Its *backend* is correct. Its *arithmetic* is
exact and cross-verified in three places. The break is at a single Firestore security-rules
boundary, and it disables the member-facing nutrition surface for every member on every day
**before they log their first food** — i.e. every morning, for everyone.

`client_nutrition_days` is missing the `resource == null && signedIn()` read clause. Every
nutrition day document starts non-existent. On a non-existent document every clause of the read
rule dereferences `resource.data`, which errors, so no clause can return true and **the listen is
denied**. Proven on the real rules engine with an A/B control against `client_lifestyle_days`,
which *does* carry the clause and *does* allow the read.

This is not a novel defect. It is the **identical defect this platform already found, fixed and
documented in the lifestyle collections** — the rules file itself contains a 15-line comment
explaining that its absence left "the member's own Today's Targets and Home cards permanently
empty," and that it was "observed live on device." That sweep fixed `client_lifestyle_days` and
`client_lifestyle_logs`. It did not reach `client_nutrition_days` or `client_diet_logs`.

Three consequences compound it:

1. **The listener is terminal.** Firestore kills a listener on `permission-denied`. The app
   re-binds only on date rollover. So the member opens the app → listen denied → logs food (the
   *write* is allowed, and lands correctly) → and the screen can never show it.
2. **The Home card discards the distinction.** `FoodLogController` carefully separates
   `loadError` from "nothing logged." The Home Nutrition Progress card reads `isLoading` and
   `entryCount` and **never reads `loadError`** — so a denied read renders as the sentence
   *"Nothing logged yet today."* A false claim about the member's behaviour, which is precisely
   what the controller's own doc comment says must never happen.
3. **History fails wholesale.** `fetchDays` issues 31 deterministic gets under `Future.wait`. Any
   unlogged day in the window is denied, and one rejection fails the entire page. Measured: **1
   readable, 30 denied, `Promise.all` REJECTED.**

Separately, and independent of the above: **the entire Cloud Function output is consumed by
nothing.** `onNutritionDayWritten` correctly computes `computed` and upserts `nutrition_rollups`
— verified end-to-end on the functions emulator, totals exact, rollup shape correct. But
AlphaSerena parses `computed` and never reads it, TrainerHQ's `ClientNutritionDayModel` ignores it
and re-derives from `entries`, and `nutrition_rollups` has **zero readers in all three apps**. The
pipeline is write-only.

### What I could NOT verify, and why

Stated plainly rather than papered over:

- **No live member session on device.** Phone OTP is externally blocked on this project (recorded
  in `alphaserena/CLAUDE.md`), so I could not drive the real read path on emulator-5554 with real
  credentials. The rules-engine and functions-emulator evidence below is what stands in for it —
  and it is the same evidence class the team used when they confirmed the lifestyle twin of this
  bug before observing it live.
- **Deployed rules were not read.** All rules evidence is against `trainershq-backend/firestore.rules`,
  which that repo declares canonical. If the deployed ruleset has drifted, verify against it.
- **Not audited at runtime:** the Super Admin global-food console (`alphaserena_admin`), TrainerHQ's
  coach food CRUD screens, food import/CSV, barcode (does not exist), and localization. These are
  covered here only where source or tests touched the member path.

---

## 2. RUNTIME EVIDENCE LEDGER

Everything below was executed, not read.

| # | What was run | Result |
|---|---|---|
| R1 | `functions/ npm test` (tsc + full suite) | **1024 / 1024 pass**, 0 fail |
| R2 | `alphaserena/ flutter analyze` | **No issues found** |
| R3 | `alphaserena/ flutter test` | **1076 tests, 14 fail** — all `home_cards_golden_test.dart` (documented pre-existing font/golden failures). Zero nutrition-logic failures. |
| R4 | Rules probe A — missing-doc read, real engine | **CONFIRMED** (below) |
| R5 | Rules probe B — listener recovery / legacy / history | **CONFIRMED** (below) |
| R6 | Functions-emulator probe C — full trigger chain | **HEALTHY** (below) |
| R7 | Full Firestore rules suite (`scripts/test_rules.sh`, real emulator) | **380 / 380 pass**, 0 fail |

### R4 — Probe A: the empty day, on the real rules engine

```
=== A. MISSING document (the state of every day before the first log) ===
  GET  client_nutrition_days        -> DENIED  (permission-denied)
  LSTN client_nutrition_days        -> DENIED  (permission-denied)
  GET  client_lifestyle_days [CTRL] -> ALLOWED (exists=false)
  LSTN client_lifestyle_days [CTRL] -> ALLOWED (exists=false)

=== B. EXISTING document (after the member logs their first food) ===
  GET  client_nutrition_days        -> ALLOWED (exists=true)
  LSTN client_nutrition_days        -> ALLOWED (exists=true)

>> H1 CONFIRMED: nutrition denies the empty day, lifestyle allows it.
```

The control is what makes this conclusive: same engine, same member, same seed data, same run.
The only variable is the rule text.

### R5 — Probe B: blast radius

```
=== Q1. Listener recovery after the first food is logged ===
  after opening the listener on an EMPTY day : ERROR(permission-denied)
  the food WRITE itself                     : ALLOWED (doc now exists)
  listener events after the write           : ERROR(permission-denied)
  >> DEAD: the listener never delivers.

=== Q2. client_diet_logs (legacy day doc) on a MISSING doc ===
  GET client_diet_logs -> DENIED (permission-denied)

=== Q3. History page: 31 deterministic gets, 1 logged day ===
  Promise.all over the 31-day window -> REJECTED (permission-denied)
  per-day tally: 1 readable, 30 denied
```

### R6 — Probe C: the Cloud Function chain, end to end

Two foods written in the exact `NutritionDayService.buildEntryWrite` shape, against
firestore+functions emulators:

```
=== computed (server-written, on the day doc) ===
  totals          : {calories 615, protein 35, carbs 53, fat 30.2,
                     fiber 5.5, sugar 4, saturatedFat 14.3}
  targetAdherence : {calories 0.308, protein 0.233, carbs 0.265,
                     fat 0.503, fiber 0.183}
  entryCount 2 · targetsVersion 3 · flags [] · computeHash 1nn4gvs

=== nutrition_rollups month cell ===
  has `days` map : true
  dotted-key bug : absent
  days cell      : totals + targetAdherence + entryCount + origin "v1"

=== arithmetic cross-check ===
  totals MATCH ·  adherence 0.308 == 615/2000
```

**Hypotheses this DISPROVED** (they were live suspicions going in, and the mission requires
recording the ones that died):

- ✗ "The rollup writer has the dotted-key defect a third time." It does not — nested map, correct.
- ✗ "The trigger's totals diverge from the client's." They do not — exact match to 0.1.
- ✗ "The loop guard suppresses the rollup write." It does not — order is rollup-first by design,
  and the rollup landed.
- ✗ "The portion math has drifted from the backend twin." It has not — `scaleMacros` mirrors
  `scaleHydratedMacros` including the `round1` and the unscaled-when-gramless branch.

---

## 3. NUTRITION ARCHITECTURE (reconstructed)

```
TrainerHQ  ──setNutritionTargets (callable, txn)──►  clients/{id}.nutritionTargets  (versioned)
                                                 └►  clients/{id}.dietTargets       (legacy mirror)
                                                 └►  clients/{id}/nutritionTargetHistory/{version}

Member app ──getMyTraining (callable)──────────►  diet.targets{...}  +  diet.items[]
           └─searchMemberFoods (callable)──────►  foodDatabase (org tier ► global tier, merged)
           └─set(merge) ─────────────────────►  client_nutrition_days/{clientId}_{yyyy-MM-dd}
                                                    entries: { entryId: { consumed FROZEN, … } }
                                                            │
                                       onNutritionDayWritten │ (trigger)
                                                            ├──► day.computed   ← READ BY NOBODY
                                                            └──► nutrition_rollups/{clientId}_{YYYY-MM}
                                                                                  ← READ BY NOBODY

Member reads:  Home card · Diet screen · Food History   ← ALL via the DENIED listener/get path
Coach reads :  watchNutritionDays — per-day listeners, re-derives from `entries`
Streak      :  ActivityHistoryService — collection QUERY (unaffected by the missing-doc defect)
```

**The one structural asymmetry that explains everything:** every *write* path and every *query*
path is healthy. Only the *document-read-by-deterministic-id* path is broken, and that is exactly
the path the three member-facing nutrition surfaces use.

---

## 4. CONFIRMED DEFECTS

### 🔴 BLOCKER — N1 · The empty day is unreadable

- **Layer:** Firestore Security Rules → `firestore.rules:1313-1317`
- **Root cause:** the read rule has no `resource == null && signedIn()` clause. All four clauses
  dereference `resource.data`; on a missing document that errors, so none can return true.
- **Repro:** sign in as a linked member. Open the app on any day before logging food. The
  `client_nutrition_days/{clientId}_{today}` listen is denied.
- **Runtime evidence:** R4 — `LSTN client_nutrition_days -> DENIED (permission-denied)` with
  `client_lifestyle_days` ALLOWED in the same run.
- **Why tests missed it:** ① `tests/rules/nutrition_food_log_write.mjs` has thorough read
  coverage, but **every read test writes the document first** — there is no missing-doc case.
  ② `integration_test/diet_journey_patrol_test.dart` injects `_FixtureLog extends
  FoodLogController` and `_FixtureDayService extends NutritionDayService`, so **no Patrol test on
  the device ever opens a real listener.** This is the exact fixture habit `alphaserena/CLAUDE.md`
  already flags as "why this defect survived every previous certification" for the consistency
  engine.
- **Fix strategy:** add the null clause, mirroring `client_lifestyle_days` verbatim. Add a rules
  test that reads a day that was never written. It grants no data — a null resource has no fields.

### 🔴 BLOCKER — N2 · The denied listener is terminal; food is written into a screen that cannot show it

- **Layer:** Controller — `alphaserena/lib/controllers/food_log_controller.dart:128-149`
- **Root cause:** Firestore terminates a listener on `permission-denied`. `_bind()` is re-invoked
  only by `ensureFreshDay()` on a *date* change, so nothing re-subscribes after the create that
  would now make the read legal.
- **Repro:** open app (listen denied) → log a food (write succeeds) → observe the log section.
- **Runtime evidence:** R5/Q1 — write ALLOWED, listener still `ERROR(permission-denied)`.
- **Member-visible consequence:** the food is *safely stored* but invisible, which invites the
  member to log it again. Duplicate entries by design of the failure.
- **Fix strategy:** N1 removes the trigger condition. Independently, `_bind` should re-subscribe
  after a successful write that transitions the day from absent to present.

### 🔴 BLOCKER — N3 · Food History fails entirely whenever the window contains an unlogged day

- **Layer:** Service — `nutrition_day_service.dart:98-117` (`fetchDays`)
- **Root cause:** `Future.wait` over 31 gets rejects on the first error. The `catchError` fallback
  retries with `Source.cache`, which for a never-cached document also throws — so the fallback
  cannot absorb it.
- **Runtime evidence:** R5/Q3 — 30 of 31 denied, `Promise.all` REJECTED.
- **Consequence:** `FoodHistoryController.loadError = true` → the history screen is permanently in
  its error state for any member who has not logged all 31 days.
- **Fix strategy:** N1 fixes the cause. Regardless, `fetchDays` should tolerate per-day failure
  (`Future.wait(eagerError: false)` or per-future recovery to null) — its own doc comment already
  promises "one unreadable day must not blank the whole month," which the code does not deliver.

### 🟠 HIGH — N4 · The Home card renders a denied read as "Nothing logged yet today"

- **Layer:** Widget wiring — `client_home_screen.dart:658-729`
- **Root cause:** `_nutritionProgress` passes `loading: log.isLoading.value` and derives copy from
  `log.entryCount`. It never consults `log.loadError`. On the denied path `isLoading=false`,
  `entryCount=0`, so the card asserts the member ate nothing.
- **Contrast:** `FoodLogSection` (Diet screen) *does* branch on `loadError` — so the same fact is
  honest on one screen and false on another.
- **Why tests missed it:** `nutrition_progress_card_test.dart` tests the *widget*, which is a pure
  presenter with no error input. The defect is in the *caller*, which no test drives with an
  errored controller.
- **Severity rationale:** HIGH not BLOCKER only because N1 gates it — but it is an independent
  defect that will survive N1's fix and misreport any future read failure.

### 🟠 HIGH — N5 · `client_diet_logs` carries the identical missing-doc denial

- **Layer:** Rules — `firestore.rules:1286-1290`
- **Runtime evidence:** R5/Q2 — `GET client_diet_logs -> DENIED`.
- **Blast radius today:** limited, because its only would-be reader is dead code (N7). It still
  breaks `ActivityHistoryService`'s legacy half? — **No:** that half uses a `where authorId ==`
  *query*, which is unaffected. So this is currently latent, and becomes live the moment any
  by-id reader is reintroduced.

### 🟠 HIGH — N6 · The Cloud Function pipeline is write-only

- **Layer:** Architecture — `functions/src/nutrition.ts` → `nutrition_rollups`, `day.computed`
- **Evidence:** `computed` is parsed in `nutrition_day_model.dart` and read by **no call site**
  (`grep '\.computed'` outside the model: empty). TrainerHQ's `ClientNutritionDayModel` parses
  only `entries` and re-derives. `nutrition_rollups` has **zero readers** across `alphaserena/lib`,
  `trainersHQ/lib`, `alphaserena_admin/lib` and `functions/src` other than its own writer.
- **Cost:** every food log costs 2 function invocations (the `computed` write re-triggers the
  function; the hash guard makes the second a fast return), 1 rollup write and 1 day write — for
  output nobody consumes.
- **Risk beyond cost:** the module's own comments describe `nutrition_rollups` as the thing that
  keeps "coach analytics O(months), not O(logs)." No coach analytics reads it. That is a
  correctness-of-belief problem: the next person to build coach nutrition analytics will assume a
  proven pipeline feeds it, and it has never fed anything.
- **Fix strategy:** decide deliberately — either wire the coach surface to `nutrition_rollups`, or
  mark the trigger explicitly as forward-looking. Do not leave it implied-live.

### 🟡 MEDIUM — N7 · The documented legacy fallback has no consumer

- **Layer:** Services — `nutrition_day_repository.dart`, `diet_log_service.dart`
- **Finding:** `NutritionDayRepository`, `LegacyDietLogRepository` and `DietLogService` are
  referenced **only from within their own files and doc comments**. `DietLogController`, their sole
  consumer, was deleted in the 2026-08-01 pass.
- **Contradicted documentation:** `alphaserena/CLAUDE.md` states these are "still live behind
  `LegacyDietLogRepository`, the food log's fallback for days that predate `client_nutrition_days`."
  There is no such fallback in the running app. A member's pre-migration diet history is reachable
  only through the streak union, never through the Food History screen.
- **Same failure mode** the codebase already names twice: dead code kept alive by tests, looking
  authoritative.

### 🟡 MEDIUM — N8 · The streak reads the member's entire nutrition history, unbounded

- **Layer:** `activity_history_service.dart:108-111`
- **Finding:** `.where('authorUid', ==).get()` with **no `limit`, no date bound**, then filters to a
  60-day window in Dart. A member two years in reads ~700 documents — each up to 80 entries — on
  every streak computation. The `client_diet_logs` half is identical.
- **Note:** `firestore.indexes.json` carries `client_nutrition_days (adminId, clientId, dateKey↓)`,
  which this query does not use and cannot (it has no adminId predicate). A `where authorUid +
  where dateKey >=` bound would need a new composite index.

### 🟡 MEDIUM — N9 · The gym-transfer mitigation does not work after a restart

- **Layer:** `food_log_controller.dart:80-85, 133-135`
- **Root cause:** `_boundAdminId` is set to `_member.adminId` — the member's **current** org — the
  first time the day snapshot arrives. It is *not* read from the day document, because
  `NutritionDayModel.fromMap` **does not parse `adminId` at all**.
- **Failure:** member transfers orgs mid-day, then restarts the app. The stream delivers the
  existing day (opened under orgA); `_boundAdminId` is null, so it is set to orgB. Every
  subsequent write sends `adminId: orgB`; the update rule pins `adminId` immutable → **denied for
  the rest of the day.**
- **Why it matters more than its rarity:** the code carries a detailed comment asserting this case
  is handled, and a rules test (`'the day keeps the org it was opened under'`) that pins the *rule*
  while the *client* it protects reads the wrong source.

### 🔵 LOW — N10 · `pendingIds` is documented as a re-entrancy guard and guards nothing

`food_log_controller.dart:60` — "the re-entrancy guard behind duplicate taps." It is added to,
removed from, and **never read** by any widget or controller. It could not work in principle:
`logFood` mints a fresh `newEntryId()` per call, so two taps produce two different ids. The actual
double-submit protection is `_submitting` in `food_quantity_sheet.dart:64,148` — which is correct
and sufficient, since `add_food_screen.dart:131` is the only `logFood` call site.

### 🔵 LOW — N11 · `nutrition_rollups` also lacks the null clause

`firestore.rules:1441-1446`. Latent today (no readers, N6). Will bite on the first month a member
has not logged, for coach and member alike.

### 🔵 LOW — N12 · Plan-sourced entries are never written, so plan compliance is permanently null

`logFood` hardcodes `source: FoodEntrySource.search`, including for foods surfaced from the coach's
plan via `planFoodsFor`. Nothing in either app writes `source: 'plan'` or a `planStatus`. Therefore
`computePlanCompliance` returns null for every day, forever, and `PLAN_STATUSES` /
`planEntryId` / `portionFactor` are dead wire fields. This appears to be intended (recommendations
became read-only) but the scope item "meal plan adherence" has **no producer**.

### 🔵 LOW — N13 · Plan foods are logged with a contradictory tier

`food_search_controller.dart:210-238` sets `tier: MemberFoodTier.org` unconditionally and
`foodId: ''`. A plan item with no library food therefore logs `foodTier: 'org'` with
`foodId: null` — a combination the backend model documents as impossible ("null for custom/quick
entries with no library food").

---

## 5. AREA-BY-AREA VERDICTS

| Area | Verdict | Basis |
|---|---|---|
| Firestore structure & wire contract | ✅ Sound | Nested `entries` map, frozen `consumed`, deterministic id — all verified live (R6) |
| Cloud Function chain | ✅ Correct | R6 end-to-end; R1 1024/1024 |
| Progress calculations / macros | ✅ Exact | R6 cross-check; `scaleMacros` ≡ `scaleHydratedMacros`; `sumMacros` ≡ `computeDayTotals` (same incremental `round1`) |
| Target resolution & provenance | ✅ Sound | `resolveServedTargets` handles cleared prescriptions → `none`; client mirrors provenance so a plan sum is never framed as a coach goal |
| Meal taxonomy | ✅ Sound | Slug-stored/label-rendered, alias tables byte-identical across the two binaries |
| Indexes | ✅ Adequate for what runs | 68 indexes; 19 on `foodDatabase` covering both tiers, search tokens, category and status. No index is *missing* for a query the apps issue — see N8 for the query that should exist but doesn't |
| Food search (member) | ✅ Sound design | Callable-gated (members provably cannot read `foodDatabase` — pinned by rules test), monotonic `_requestId` defeats the stale-response race, debounce 280ms, org-wins dedup by `duplicateKey` |
| Security — tenancy & forgery | ✅ Strong | Cross-member writes, forged doc ids, forged `computed`/`coachReview`, unscoped enumeration — all denied (existing suite + R7) |
| Security — availability | 🔴 Broken | N1, N5, N11 |
| Member read path | 🔴 Broken | N1 → N2 → N3 |
| Home card honesty | 🟠 Broken | N4 |
| Offline | ⚠️ Untested at runtime | `queued` semantics and 4s ack timeout are correct by construction and unit-tested; not exercised on a real device this pass |
| Memory / listeners | ✅ No leak found | `_sub` + `_linkWorker` both cancelled in `onClose`; one `FoodLogController` instance serves Home and Diet; `FoodHistoryController` is in the sign-out teardown |
| Rapid taps | ✅ Guarded | `_submitting` at the only call site |
| Patrol coverage | 🔴 Structurally blind | Fixture-injected controllers; no device test touches Firestore for nutrition |

---

## 6. WHY EVERY PREVIOUS CERTIFICATION PASSED

Three independent blind spots, all of which this module inherited rather than invented:

1. **The rules suite tests writes, then reads what it wrote.** Correctness of the *populated*
   state is thoroughly pinned; the *empty* state — which is where every member starts every day —
   was never a case.
2. **Patrol runs on a device but not on the data path.** `_FixtureLog` / `_FixtureDayService`
   replace exactly the two classes that would have hit the denial. The suite proves the widgets
   render; it cannot prove they receive anything.
3. **The lifestyle sweep was scoped by collection name, not by defect shape.** The fix landed on
   `client_lifestyle_days` and `client_lifestyle_logs`. A shape-scoped sweep — "every collection
   read by deterministic id whose read rule dereferences `resource.data`" — would have caught
   `client_nutrition_days`, `client_diet_logs` and `nutrition_rollups` in the same pass. That query
   is mechanical; §4/N11 lists its full answer for this ruleset.

---

## 7. CLASSIFICATION

| ID | Severity | Defect |
|---|---|---|
| N1 | **BLOCKER** | `client_nutrition_days` denies the read of an unlogged day |
| N2 | **BLOCKER** | Denied listener is terminal; logged food is invisible until relaunch |
| N3 | **BLOCKER** | One unlogged day fails the entire Food History page |
| N4 | HIGH | Home card renders a denied read as "Nothing logged yet today" |
| N5 | HIGH | `client_diet_logs` carries the same denial (latent) |
| N6 | HIGH | `computed` + `nutrition_rollups` have no readers — write-only pipeline |
| N7 | MEDIUM | Legacy fallback documented as live is dead code |
| N8 | MEDIUM | Unbounded whole-history query on every streak computation |
| N9 | MEDIUM | Gym-transfer adminId pinning reads the wrong source; fails after restart |
| N10 | LOW | `pendingIds` guards nothing |
| N11 | LOW | `nutrition_rollups` missing null clause (latent) |
| N12 | LOW | No producer for plan-sourced entries; plan compliance permanently null |
| N13 | LOW | Plan foods logged with `foodTier: 'org'` and no `foodId` |

**Recommended order:** N1 (one clause, plus the missing rules test) → N3 and N4 (they are
independent of N1 and will outlive it) → N2 → N6 as a product decision → the rest.

---

## 8. REPRODUCTION ASSETS

The three probes are in the session scratchpad and are read-only — they seed their own data and
touch no repository file:

- `probe_missing_day.mjs` — A/B missing-doc read, nutrition vs lifestyle control
- `probe_recovery.mjs` — listener recovery, legacy collection, 31-day history window
- `probe_trigger.mjs` — full Cloud Function chain against firestore+functions emulators

Run with `firebase emulators:exec --only firestore[,functions] --project demo-trainershq-rules`.

---

## 9. FULL RULES SUITE — AND WHY ITS GREEN IS THE POINT

`./scripts/test_rules.sh` against a real Firestore emulator: **380 tests, 380 pass, 0 fail.**

That number is the strongest single piece of evidence in this report. The security suite is
comprehensive, it is honest, it runs on the real engine — **and it is completely green while a
member-facing BLOCKER is live in the very collection it covers most thoroughly.**

The suite cannot fail, because the case does not exist in it. `nutrition_food_log_write.mjs`
contains 20+ assertions about `client_nutrition_days` reads, writes, tenancy, forgery and query
scoping. Every one of them operates on a document that the test itself created moments earlier.
The state the rule actually mishandles — *no document* — is never constructed.

This is the governing lesson of the audit: **a green suite is evidence about the cases it
contains, and nothing else.** The same three sentences would have been true of the lifestyle
suite the day before that twin defect was found on a device.
