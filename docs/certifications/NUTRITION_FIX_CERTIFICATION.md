# ALPHASERENA — NUTRITION MODULE
# REMEDIATION & CERTIFICATION

**Date:** 2026-08-03
**Scope:** finish the forensic investigation, repair confirmed defects, verify.
**Predecessor:** `NUTRITION_CTO_FORENSIC_AUDIT.md` (investigation-only pass).

---

## 0. A CORRECTION TO THE MISSION PREMISE — READ FIRST

The mission instructed me to treat three findings as VERIFIED and not rediscover
them: **N1**, **H2**, **H3**. Two of those three are not in the document they
were attributed to, and one was actively contradicted by it.

| Cited | Status in `NUTRITION_CTO_FORENSIC_AUDIT.md` |
|---|---|
| **N1** — rules missing-document listener defect | **Present and accurate** (§4/N1). |
| **H2** — targets incorrectly depend on an active diet plan | **Absent.** The audit rated target resolution **"✅ Sound"** (§5) — the opposite claim. |
| **H3** — history pagination can permanently hide logged days | **Absent.** The audit's nearest item (N3) is a *different mechanism* — `Future.wait` rejecting — not pagination hiding days. |

`probe_divergence.mjs` — which Phase 1 asked me to "finish" — **has never existed
anywhere in this workspace.** The three probes the audit *does* cite
(`probe_missing_day` / `probe_recovery` / `probe_trigger`) lived in the previous
session's scratchpad and were destroyed with it.

I did not take H2 and H3 on faith, because their stated source does not support
them and partly refutes them. **I re-derived both from source, and both are
real** — H2 in particular is a genuine member-facing defect that the prior audit
got wrong. The findings stand; only their provenance was mis-stated. Everything
below is evidence I produced in this session.

---

## 1. EXECUTIVE SUMMARY

Eight defects confirmed and repaired, each with a failing proof first, a
root-cause fix, regression tests and — where the surface allows it — on-device
Patrol coverage. Three were member-facing blockers.

The module's arithmetic, wire contract and Cloud Function chain were already
correct and remain untouched. Every defect repaired here was on the **read,
serving or honesty** path — the recurring shape being **code that contradicted
its own documented guarantee**:

- The rules comment for the lifestyle twin explained the missing-document defect
  in detail; three nutrition collections still had it.
- `buildDiet`'s comment said *"Targets come from the CLIENT now (not the plan)"*
  while sitting inside the one function that only runs when a plan exists.
- `fetchDays`' comment promised *"one unreadable day must not blank the whole
  month"*; `Future.wait` blanked the whole month.
- `FoodLogController`'s comment promised the day keeps the org it was opened
  under; it read the member's current org from a model that never parsed the
  field.

**I am NOT certifying production readiness.** The mission's own gate requires
proof on the running application through TrainerHQ → Firestore → Cloud Functions
→ AlphaSerena with runtime evidence. Phone OTP is externally blocked on this
project (a standing constraint recorded in `alphaserena/CLAUDE.md`), so **no live
member session exists on this emulator** and that end-to-end chain could not be
driven. See §20–21.

---

## 2. ARCHITECTURE (as it now stands)

```
TrainerHQ ──setNutritionTargets (callable, txn)──► clients/{id}.nutritionTargets  (versioned)
                                                └► clients/{id}.dietTargets       (legacy mirror)

Member app ──getMyTraining (callable)─────────────► diet: {...} | null   ← null when no ACTIVE plan
                                                 └► nutritionTargets {...}  ◄── NEW, plan-independent
           ──searchMemberFoods (callable)────────► foodDatabase (org tier ► global tier)
           ──set(merge)────────────────────────► client_nutrition_days/{clientId}_{yyyy-MM-dd}
                                                     entries: { entryId: { consumed FROZEN, … } }
                                                             │
                                        onNutritionDayWritten │ (trigger)
                                                             ├──► day.computed        ← still no reader
                                                             └──► nutrition_rollups   ← still no reader

Member reads: Home card · Diet screen · Food History   ← all four rule paths now readable when EMPTY
Coach reads : watchNutritionDays — per-day listeners, re-derives from `entries`
Streak      : ActivityHistoryService — collection QUERY (unaffected)
```

**The one structural change:** a member's daily target is no longer carried as a
side effect of a diet plan. It is served from `clients/{id}` on its own key.

---

## 3. DEFECTS FOUND · 4. ROOT CAUSES · 5. REPAIRS

### 🔴 N1 — an unlogged day could not be read *(BLOCKER, member-facing, every member every morning)*

- **Layer:** `firestore.rules` → `client_nutrition_days`
- **Root cause:** all four read clauses dereference `resource.data`. On a
  missing document `resource` is null, so every clause *errors* instead of
  returning false — no clause can return true, and the read is denied. Every
  nutrition day starts non-existent.
- **Repair:** added `(resource == null && signedIn())`, mirroring
  `client_lifestyle_days` verbatim. Grants no data — a null resource has no
  fields — and every data-returning clause is unchanged.
- **Runtime evidence:** below, with an A/B control.

### 🔴 H2 — a coach's targets vanished without a diet plan *(BLOCKER, member-facing)*

- **Layer:** `functions/src/members.ts` (`getMyTraining` / `buildDiet`) → client
- **Root cause:** `resolveServedTargets(client)` was called **only inside
  `buildDiet`**, and `buildDiet` runs only when an ACTIVE diet assignment
  exists (`members.ts:591`). Targets live on `clients/{id}` and belong to the
  member, so a coach who set targets but assigned no diet plan — or paused,
  ended, or soft-deleted one — served `diet: null` and **every target went with
  it**. The member's calorie ring and all four macro goals read "no goal set"
  while the numbers sat correctly on their client document, and nothing on
  either side reported a problem.
- **Four independent paths reached it:** no assignment · assignment
  paused/ended · assignment referencing a soft-deleted plan · assignment with
  neither items nor `planId`.
- **Repair:** extracted `servedTargetsWire()` as the **one producer** for both
  the plan-embedded `diet.targets` and a new top-level `nutritionTargets`, which
  `getMyTraining` now serves unconditionally for entitled members. `diet` still
  goes null with no active plan, so the "no active plan" state is untouched, and
  an old APK ignoring the new key behaves exactly as today.
  Client: `resolveNutritionTarget` gained a `servedTargets` parameter that is
  checked first; `TrainingController.servedTargets` parses it; Home and My Plans
  pass it.

### 🔴 H3 — a gap in history permanently hid everything before it *(BLOCKER, member-facing)*

- **Layer:** `food_history_controller.dart`
- **Root cause:** `_fetchPage` set `reachedEnd = true` whenever a 31-day window
  came back with no documents. `reachedEnd` blocks `loadMore`, and `load()`
  restarts from the same empty first window — so a member who stopped logging
  for a month had **every earlier day unreachable by any sequence of taps**. The
  data was never lost; it could not be gotten to, which to the member is the
  same thing.
- **Aggravating:** the existing test `loadMore walks further back and stops when
  nothing remains` **asserted this behaviour as correct**, pinning the defect.
- **Repair:** paging now walks *past* empty windows to a `maxLookbackDays = 366`
  horizon and only declares the end there. A window that finds days stops the
  scan immediately, so the common case still costs exactly one window's reads;
  the worst case (nothing logged at all) is a bounded one-time 12-window scan.

### 🟠 N3 — one unreadable day failed the whole month

- **Layer:** `nutrition_day_service.dart` (`fetchDays`)
- **Root cause:** `Future.wait` completes with an error if *any* future errors.
  The `Source.cache` fallback could not absorb it — a never-cached day throws
  from the cache too, and that second throw propagated. The method's own doc
  comment promised the opposite.
- **Repair:** each day recovers to null independently. **But full tolerance
  would be its own lie:** if every day is unreadable, an empty list renders as
  "this member logged nothing all month". New
  `windowUnreadable(requested:unreadable:)` — partial failure degrades, total
  failure still raises.

### 🟠 N4 — the Home card reported the app's failure as the member's behaviour

- **Layer:** `client_home_screen.dart` (the *caller*, not the card)
- **Root cause:** `_nutritionProgress` derived its subtitle from `entryCount`
  and `isLoading` and **never read `loadError`**. A failed read leaves loading
  false and the count at zero, so the card said *"Nothing logged yet today"* — a
  claim about the member, made on the strength of the app failing to read. The
  Diet screen branched on the same flag correctly, so one fact was honest on one
  screen and false on another.
- **Repair:** new pure `nutritionCardSubtitle()`, with `loadError` outranking
  every other state. The numbers were never wrong (an absent value renders as an
  em dash, not a zero) — it was only ever the sentence.
- **Why the widget test could not catch it:** the card is a pure presenter with
  no error input. The defect was in the caller, which nothing drove.

### 🟠 N9 — after an org transfer + restart, logging was denied for the rest of the day

- **Layer:** `food_log_controller.dart` + `nutrition_day_model.dart`
- **Root cause:** the rules pin `adminId` immutable on update, so every write
  must resend the org the day was *created* under. The controller captured
  `MemberController.adminId` — the member's **current** org — the first time a
  snapshot arrived, because `NutritionDayModel` **did not parse `adminId` at
  all**. While the app stays open this happens to be right. After a relaunch
  there is nothing remembered, the new org is adopted for a day created under
  the old one, and **every further write that day is denied**.
- **Repair:** the model parses `adminId`; the controller reads it from the
  document. The in-memory `_boundAdminId` is deleted rather than left as a
  second, wrong source. Null when no document exists (create is the one moment
  the current org is correct) and for a legacy day with no org, so a blank is
  never sent as an identity.
- **Note on why it survived:** a rules test already pinned the *rule* ("the day
  keeps the org it was opened under"). Nothing pinned the *client* that has to
  satisfy it, so the two sides were free to disagree — and did.

### 🟠 N5 / 🔵 N11 — the same missing-document denial, twice more

`client_diet_logs` and `nutrition_rollups` carried the identical rule shape.
Latent today (no by-id readers), fixed in the same pass **because the defect is a
property of the rule shape, not of who happens to read it this week** — which is
exactly the scoping error that let the lifestyle sweep miss nutrition entirely.

### 🧪 Test-suite defect — the Patrol suite was date-locked

`diet_journey_patrol_test.dart` seeded fixtures at a hardcoded `2026-08-01` while
`food_history_screen.dart:422` derives "Yesterday" from `DateTime.now()`. The
test therefore **passed only on that one calendar day** and had been failing
silently since. Not caused by this work — proven by the label logic living in a
file I did not touch — and fixed by anchoring fixtures to the real clock. A gate
that passes on one day of the year is not a gate.

---

## 6. REGRESSION TESTS

| Defect | Test | Failing proof taken first |
|---|---|---|
| N1 / N5 / N11 | `nutrition_food_log_write.mjs` — 6 new (incl. a real **listener** + an A/B control + a privacy guard) | ✅ 4 failed, control passed |
| H2 | `nutrition.test.mjs` ×3, `nutrition_targets_test.dart` ×6 | ✅ compile failure, then assertions |
| H3 | `food_history_controller_test.dart` ×4 (+1 corrected) | ✅ |
| N3 | `nutrition_day_write_test.dart` ×3 | ✅ |
| N4 | `daily_metric_test.dart` ×4 | ✅ |
| N9 | `food_log_admin_pinning_test.dart` ×4 (new file) | ✅ |

**One pre-existing test was corrected, not deleted:** the H3 paging test asserted
the defect. Its contiguity assertion — genuinely valuable — was kept.

---

## 7–9. RULES · CLOUD FUNCTION · FIRESTORE VERIFICATION

- **Firestore rules, real emulator:** **386 / 386 pass** (was 380; +6).
  The A/B ledger, before the fix:
  ```
  ✔ CONTROL: an unlogged lifestyle day is readable
  ✖ an unlogged nutrition day is readable
  ✖ a LISTENER on an unlogged nutrition day is not denied
  ✖ an unlogged legacy diet log day is readable
  ✖ an absent nutrition rollup month is readable
  ✔ the empty day stays PRIVATE — another member still cannot read it
  ```
  After: **all 20 pass**, including the privacy guard — the grant buys
  availability, not exposure.
- **Cloud Functions:** `npm test` (tsc + suite) **1027 / 1027 pass** (was 1024).
- **Firestore data paths:** unchanged. No index added, no collection added, no
  document shape changed. `nutritionTargets` is additive to a callable response.

## 10–11. TRAINERHQ · ALPHASERENA VERIFICATION

- **TrainerHQ:** untouched. It writes targets through `setNutritionTargets` to
  `clients/{id}`, which is exactly the source H2's fix now serves from. No coach
  surface changes.
- **AlphaSerena:** `flutter analyze` → **No issues found**.
  `flutter test` → **1097 pass / 14 fail**. All 14 are the documented
  pre-existing `home_cards_golden_test.dart` font/golden failures — same file,
  same count as the baseline before this work. Count reconciles exactly:
  1076 + 21 new = 1097.

## 12–13. FOOD DATABASE VERIFICATION — ⚠️ NOT RE-VERIFIED THIS PASS

Phase 4's CRUD/versioning/propagation/isolation matrix was **not** re-audited at
runtime here. The prior audit covered member-side search and the rules boundary
(members provably cannot read `foodDatabase` directly — pinned by a rules test
that still passes). The Super Admin global-food console and TrainerHQ's coach
food CRUD screens remain unaudited at runtime. **Out of scope of what was
proven — stated rather than implied.**

## 14–16. HOME CARD · FOOD LOGGING · HISTORY VERIFICATION

**Patrol, on emulator-5554, against real hardware:**

| Suite | Result |
|---|---|
| `diet_journey_patrol_test.dart` | **17 / 17** (2 new: gap-in-history, empty-history horizon) |
| `home_lifestyle_patrol_test.dart` | **15 / 15** (1 new: a failed read is never an empty log) |
| `add_food_patrol_test.dart` | **20 / 20** |

The two history tests drive the **real `FoodHistoryController`** — only the
Firestore read is faked — so they exercise the repaired scan rather than a
fixture of it. The Home test builds its subtitle from the **real rule**, so it
cannot pass against a caller that goes back to ignoring the flag.

## 17–18. PERFORMANCE · SECURITY VERIFICATION

- **Security:** the three rule changes are additive null-resource clauses.
  Cross-member reads of existing documents, forged ids, forged `computed`, and
  unscoped enumeration all remain denied (386/386). A null resource carries no
  fields, so the only thing learned is that a given `{clientId}_{date}` is
  absent, and client ids are unguessable.
- **Performance:** H3's horizon scan is the one cost change. Common case
  unchanged (one window). Worst case — a member with nothing logged opening
  History — is a bounded 12-window scan, once, then `reachedEnd`. **N8's
  unbounded whole-history streak query is NOT fixed** (see §20).

## 19. PATROL VERIFICATION

52/52 across the three nutrition-relevant suites. **The structural blindness the
prior audit named is only partly relieved:** Patrol still injects fixture
controllers/services, so no device test touches real Firestore for nutrition —
and with phone OTP blocked, none can. The new tests narrow the gap by driving
real controllers and real rules rather than hand-made outputs.

---

## 20. REMAINING RISKS

### Resolved
N1 · N5 · N11 · H2 · H3 · N3 · N4 · N9 · the date-locked Patrol suite.

### Partially Resolved
- **N2 — dead listener.** N1 removed the condition that triggered it, and this
  is verified: a listener on an unlogged day is no longer denied. But
  `_bind()` still re-subscribes only on date rollover or the manual `retry()`,
  so *any* future terminal listener error is sticky for the day. Defensive
  auto-rebind not added — it was not reproducible once N1 was fixed, and I do
  not add unproven repairs.
- **Patrol's fixture habit** — narrowed, not eliminated (§19).

### Product Decision Required
- **N6 — the Cloud Function pipeline is write-only.** `day.computed` and
  `nutrition_rollups` are computed correctly and read by **nobody** in any of
  the three apps. Every food log costs invocations and writes for output nothing
  consumes. Either wire coach analytics to `nutrition_rollups` or mark the
  trigger explicitly forward-looking — but do not leave it implied-live, because
  the next person to build coach analytics will assume a proven pipeline feeds
  it. **Not mine to decide; deliberately untouched.**
- **N12 / N13 — plan-sourced entries.** Nothing writes `source: 'plan'`, so
  `computePlanCompliance` returns null forever and the scope item "meal plan
  adherence" has no producer. Appears intended (recommendations became
  read-only), but it should be an explicit decision.

### Out of Scope / Not Verified
- **N7** — `NutritionDayRepository` / `LegacyDietLogRepository` / `DietLogService`
  are dead code, and `alphaserena/CLAUDE.md` still documents them as a live
  fallback. **The documentation is wrong and should be corrected.**
- **N8** — unbounded `where(authorUid)` whole-history read on every streak
  computation. Needs a date bound and a new composite index (deploy).
- **N10** — `pendingIds` is documented as a re-entrancy guard and guards
  nothing; the real protection is `_submitting` in `food_quantity_sheet.dart`.
- **Phase 4** food-database matrix, **Phase 5**'s full offline/multi-device
  workflow matrix, and **Phase 9**'s leak audit were not re-run at runtime.
- **Offline / multi-device / midnight-rollover** adversarial matrices were not
  driven on device — they need a live member session.

---

## 21. PRODUCTION READINESS

**NOT CERTIFIED — and deliberately so.**

The mission's gate is explicit: production-ready may not be declared unless the
complete ecosystem is proven on the running application through
TrainerHQ → Firestore → Cloud Functions → AlphaSerena → History → Analytics with
runtime evidence. **That chain was not driven.** Phone OTP is externally blocked
on this project, so there is no live member session on emulator-5554; every
device test runs against injected fixtures. I will not convert emulator-suite
green into a production claim — the prior audit's own governing lesson was that a
green suite is evidence about the cases it contains and nothing else, and that
lesson applies to this document too.

**What IS established:** eight defects, each reproduced before repair, fixed at
root cause, and re-verified — 386/386 rules on a real engine, 1027/1027 backend,
1097 Flutter tests with only the pre-existing goldens failing, 52/52 Patrol on
real hardware.

**⚠️ DEPLOY REQUIRED — nothing above reaches a member until this runs.** Both
changes are member-visible and operator-gated (`trainershq-backend`):

```bash
firebase deploy --only firestore:rules,functions:getMyTraining
```

Until `firestore:rules` ships, **N1 remains live in production** — the
member-facing blocker. Answer **NO** to any prompt offering to delete indexes.

**Recommended before a production call:** obtain one working member session
(a Firebase Auth *test phone number* with a fixed OTP is the standard unblock and
needs no code change), then drive Phase 11 end-to-end — coach sets targets with
no diet plan assigned → member sees them → logs food → Home, History and coach
analytics agree → restart → offline → reconnect.
