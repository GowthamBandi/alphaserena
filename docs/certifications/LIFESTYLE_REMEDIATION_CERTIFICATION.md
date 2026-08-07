# LIFESTYLE MODULE — REMEDIATION CERTIFICATION

**Date:** 2026-08-03 · **Input:** `LIFESTYLE_CTO_FORENSIC_AUDIT.md` (treated as the sole source of truth)
**Repos touched:** `alphaserena` · `trainersHQ` · `trainershq-backend`

## Verdict

**Both release blockers are eliminated and verified.** 7 findings resolved, 1 resolved as a
side-effect, 3 blocked on a product decision and named, 5 low findings documented.

⚠️ **NOT yet production-ready — one operator gate remains.** LS-02's fix is a Cloud Function
change. Until `onLifestyleDayWritten` is deployed **and existing rollups are rebuilt**, every day
already written still carries the defective `waterMl: 0`. See §Deploy.

---

## 1. Executive summary

| # | Finding | Status | Layer |
|---|---|---|---|
| LS-01 | Today's Targets threw `ObxError` instead of the join prompt | ✅ **Resolved** | Controller + MemberController |
| LS-02 | "Did not log" stored as "logged zero" (water, supplements) | ✅ **Resolved** ⚠️ needs deploy + backfill | Cloud Function + coach controller |
| LS-03 | Water above the goal was unrecordable | ✅ **Resolved** (product decision: never cap) | Controller + widget |
| LS-04 | bed == wake silently recorded a 24-hour night | ✅ **Resolved** | Widget |
| LS-05 | No day strip — a missed day can never be logged | ⛔ **Blocked by product decision** | — |
| LS-06 | Midnight rollover only fired on app resume | ✅ **Resolved** | Controller |
| LS-07 | Event cap discarded the member's NEWEST activity | ✅ **Resolved** | Cloud Function |
| LS-08 | History controller's 3 listeners outlived its screen | ✅ **Resolved** | Screen |
| LS-09 | Home vs Today disagreed about an unset target | ✅ **Resolved in substance by LS-03** | — |
| LS-10 | No bound on the events map | ⛔ **Blocked by product decision** | — |
| LS-11 | Rules comment claimed a string bound it never implemented | ✅ **Resolved** (comment corrected) | Rules |
| LS-12 | `_pendingAdds` could go negative | ✅ **Resolved as a side-effect of LS-03** | — |
| LS-13/14/15/16 | DST display shift · "N of M goals" · future sleep period · `schemaVersion` | 📋 **Documented, not changed** | — |
| LS-17/18/19 | Fixture/process defects | ✅ **Addressed** — see §6 | Tests |

**One audit claim was wrong and is corrected below** (§7). It was found by executing the fix, not
by re-reading the audit.

---

## 2. Verification — every number re-measured

| Suite | Before | After | Notes |
|---|---|---|---|
| alphaserena `flutter analyze` | 0 | **0** | |
| alphaserena tests | 1065 (+14 golden fail) | **1069** (+14 golden fail) | the 14 are the documented pre-existing golden-image baseline |
| trainersHQ `flutter analyze` | 26 | **26** | baseline held exactly |
| trainersHQ tests | 1789 (+3 serena fail) | **1793** (+3 serena fail) | the 3 are the documented pre-existing `serena/*` goldens |
| backend `tsc` + `npm test` | 1019 | **1024** | |
| Firestore rules (real emulator) | 375 | **375** | |
| **Patrol on emulator-5554** | 44 | **47 / 47** | lifestyle 20 · history 13 · home 14 |

Every regression test added **was proven to fail before its fix and pass after** — including
LS-04, which was verified by temporarily reverting the one-line fix and re-running.

---

## 3. Findings resolved — root cause and implementation

### LS-01 — the join prompt was a framework error 🔴

**Root cause (architectural).** `MemberController.linkedClientId` was a **plain, non-reactive
field**. `canLog` reads it first and `&&` short-circuits, so for an unlinked member the body `Obx`
observed *no* `Rx` at all and GetX threw by design. A reactive guard was built on non-reactive
storage.

**Fixed at the root, in two layers** — the second exists so the first cannot be undone by accident:

1. `member_controller.dart` — the field became `RxnString`, exposed through an unchanged
   `String? get linkedClientId`. Every existing reader (`call_service`, `client_chat_screen`) is
   untouched; only the storage became observable.
2. `lifestyle_controller.dart` — `canLog` now touches `_member.isLinked` **before** delegating,
   so the reactive contract belongs to the *controller*, not to the order in which the service
   happens to evaluate its `&&`. Re-ordering that expression, or faking the service, can no longer
   take the subscription away.

**Tests:** 2 unit (`lifestyle_today_screen_test.dart` — renders the prompt; replaces it live when
linkage lands) + 1 Patrol. All three failed before the fix.

### LS-02 — "did not log" recorded as "logged zero" 🔴

**Root cause.** `deriveLifestyleMetrics` returned `null` for `sleepMinutes` and `steps` but a
**number** for `waterMl`, `supplementDoses` and `supplementItems`. Three of five metrics could not
express absence, and every reader treats presence as "logged".

**Fixed at the read-model boundary, not in the counting functions.** A sum of nothing is
legitimately 0 — the member's live "Today" ring genuinely wants that — so `totalWaterMl` and
`supplementAdherence` are unchanged. Absence is expressed in `deriveLifestyleMetrics`, the one
place that has to distinguish the two. "Recorded but worth nothing" deliberately stays 0: a day
holding drink events whose volumes were all out of range *did* record drinking.

**A second, independent defect was found by adversarial review and is also fixed.** The backend
change alone did not reach the coach's supplement stats: `derivedItemsTaken ?? 0` swallowed the new
null straight back into a 0, so a steps-only day still scored 0/prescribed. Both `supplementStats`
and `_computeSupplementRate7` now gate on the **already-existing** `hasSupplementData` predicate,
which draws the line correctly — a *legacy* day carrying a checklist snapshot with nothing ticked
is still a real 0, because the snapshot itself is evidence the day was recorded.

**Tests:** 3 backend (absence · "recorded but worth nothing" · withdrawal returns to absent),
4 coach-side in a **new** `lifestyle_review_controller_test.dart`, 1 member-side parser test,
1 Patrol driven from a literal `coaching_rollups` document.

### LS-03 — water above the goal was unrecordable 🟠

**Product decision (yours): never cap.** `canAddGlass` gated on `waterTargetGlasses`, which derives
from `effectiveTarget` and is therefore *never* ≤ 0 — the cap was always on, including against the
merely *suggested* platform default. Removed, along with the now-dead `_pendingAdds` race guard,
which existed only to protect that threshold. The + button is never disabled. Reaching the goal is
still celebrated; it is no longer a wall.

**Three assertions that certified this defect were retired** — two unit, one Patrol
(`'the + stops at the coach's goal'`).

### LS-04 — bed == wake recorded a 24-hour night 🟠

**Root cause.** `span = w > b ? w - b : 1440 - b + w` is **mathematically incapable of yielding 0**:
for `w == b` it takes the second branch and returns 1440. The `span == 0` guard and its error
message were unreachable dead code, and 24 h passes both `validateSleepEntry` (24 ≤ 24) and the
server's `sleepMinutes` (1440 is not > 1440). Equality is now tested explicitly, first.

**Tests:** 1 unit + 1 Patrol, both seeded with the exact corrupt state the bug produces.

### LS-06 — rollover only on resume 🟡

`ensureFreshDay()` was wired only to `didChangeAppLifecycleState`, which fires when the app is
*backgrounded and brought back*. A member who simply keeps the app open across midnight — logging a
last glass at 00:01, which is exactly when someone does that — kept writing into **yesterday's**
document. The re-anchor now also runs immediately before **all five** write paths, so the day a
record lands on is correct regardless of when the UI last refreshed. It is a no-op on every
ordinary tap, because the day key has not changed.

### LS-07 — the cap discarded the newest activity 🟡

`slice(0, MAX)` over an oldest-first list kept the **start** of the day. For steps and stated sleep
— both latest-wins — that meant the member's *corrected* figure was precisely the one dropped while
a stale morning reading stood as the day's record. Now keeps the tail, via a new pure
`eventsWithinCap`, extracted so the rule is testable without an emulator (it was two lines inside
the trigger, the one place nothing could reach). 2 backend tests, one of which asserts the
*behaviour* — a capped day reports the member's corrected step count.

### LS-08 — listeners outliving the screen 🟡

`LifestyleHistoryController` was `Get.put` from `build` and deleted only on sign-out, so three
monthly Firestore listeners stayed open for the rest of the session after one visit. Registration
moved to `initState` with an explicit `_ownsController` flag, and disposal in `dispose` — a
controller injected by a test or binding stays that owner's to manage.

### LS-11 / LS-12

LS-11: the `validSupplementPlan` comment claimed it bounded "the size of every string". It never
did. The comment now names the gap instead of implying a guarantee that does not exist.
LS-12 disappeared with `_pendingAdds` (LS-03).

---

## 4. Blocked by product decision — named, not invented

**LS-05 — no day strip.** Spec §6 required a day strip (today default, future days disabled);
it was never built, and `selectDay()` still has zero production callers. **Your decision: document,
do not build** — the mission bars new features. A member who forgets to log last night's sleep
still has no correction path. Building it is a scoped, self-contained piece of work.

**LS-09 — Home vs Today.** The *substantive* harm was the cap: Today enforced a goal Home denied.
With LS-03 that contradiction is gone. What remains is a presentation difference — Home shows no
suggestion, Today shows one explicitly labelled "suggested goal". Both statements are true and
consistent; changing either is a product call, so neither was changed silently.

**LS-10 — no bound on the events map.** A day document can be grown toward Firestore's 1 MiB limit,
after which every write to that day fails permanently. A rules cap is one line — but it would
**refuse a member's write with no UI to explain it**, which is a user-facing behaviour change
needing a product answer (what does the member see at the limit?). Named rather than invented.

---

## 5. Verification by dimension

**Backend.** `tsc` clean; 1024/1024. The derivation change was proven by executing the **compiled**
output over steps-only, sleep-only, supplement-only and 210-event days before and after.

**Firestore / security.** No rules logic changed (one comment corrected). 375/375 on a real
emulator, before and after. No new collection, field, index or query — the module still contains
zero `.where()` on its own read paths.

**Performance.** LS-08 removes three per-session listeners. LS-03 removes a per-tap guard. LS-06
adds one integer comparison per write. No new reads or writes anywhere.

**Patrol.** 47/47 on emulator-5554. The suite now covers the unlinked member, over-target water,
equal sleep times, and a rollup day parsed from a literal server document.

**Adversarial review.** Applied per finding; it produced two real results — the coach-side half of
LS-02 (§3) and the audit correction (§7) — plus one test-driving defect caught by the device run
(§8).

---

## 6. The process defect (LS-17) — the audit's headline finding

Every fixture in the module hand-built cells supplying only the metric under test, which is why
LS-02 was invisible to 228 passing tests. This is the **third** recurrence of that pattern in this
repository. Addressed concretely, not just noted:

- **`lifestyle_review_controller_test.dart` is new.** Nothing had ever constructed
  `LifestyleReviewController`; its stats were covered only by tests that *re-implemented its own
  selector beside it*, so the copy could agree perfectly while the controller was wrong — which is
  exactly what happened. It is now driven for real, over the shape the backend emits.
- **The history Patrol test now starts from a literal `coaching_rollups` document** and lets
  `MemberRollupService.daysFrom` parse it, rather than constructing `RollupDay` objects by hand.
- **LS-18** closed: `canLog == false` is now exercised in unit and device tests.
- **LS-19** closed: the Patrol assertion certifying LS-03 is gone.

---

## 7. Correction to the forensic audit

The audit claimed a steps-only day broke the water streak — *"streak 1 instead of 3"*. **That was
overstated.** A goal-*hit* streak requires the goal hit on each consecutive day, and a day that
says nothing about water cannot be a hit — so the streak reads 1 both before and after. LS-02's
real damage to water is the **average, the hit rate and the fabricated worst day**, all of which are
confirmed and fixed. The corrected expectation is recorded in the test itself, not only here.

---

## 8. Discrepancy between tests and the running app — investigated, explained

Required by Phase 5, and it happened once. The new LS-04 Patrol test passed as a widget test but
**failed on the device**. The running app was treated as authoritative and the difference chased to
the end: the sleep card sits below the fold on a real phone and opening its editor pushes Save down
again, so the test was tapping an off-screen control. Driving each control after scrolling it into
view made the assertion pass — proving the real app **does** show the refusal on real hardware. The
app was not changed; the test was. No other divergence appeared across 47 device tests.

---

## 9. ⚠️ DEPLOY — required, and the order matters

```bash
firebase deploy --only functions:onLifestyleDayWritten
```

Run from `trainershq-backend`. This carries **both** LS-02 and LS-07. Nothing else changed on the
backend: no rules logic, no indexes, no other function.

**Then the backfill, which is NOT optional.** Every rollup cell already written still carries
`waterMl: 0`. The trigger's loop guard hashes the **events**, not the derived metrics — so
redeploying will *not* recompute a day whose events have not changed. Existing days must be
replayed explicitly per member over the window you care about:

```bash
# super-admin callable, ≤120 days per call
rebuildCoachingRollups({ clientId, from: 'yyyy-MM-dd', to: 'yyyy-MM-dd' })
```

Until that runs, members and coaches keep seeing the old zeros for historical days. New days are
correct from the moment the function is deployed.

**One expected consequence, not a regression.** `compareCoachingParity` will now report
`legacy 0 / native null` differences on days the member logged something other than water. The
legacy document always writes `waterMl`; the native model no longer does. The legacy projection is
never rendered anywhere (verified — it is read only to compute the staleness signature), so this
affects the super-admin diagnostic only. It was left alone deliberately rather than changing a
deprecated bridge's write shape.

---

## 10. Production readiness

| Gate | State |
|---|---|
| Both blockers eliminated | ✅ |
| Source analysis | ✅ |
| Automated tests (3 repos) | ✅ 1069 · 1793 · 1024, all baselines held |
| Rules on a real emulator | ✅ 375/375 |
| Patrol on real hardware | ✅ 47/47 |
| Test↔runtime divergence explained | ✅ §8 |
| **Backend deploy + rollup backfill** | ⛔ **outstanding** |

**Ship gate:** the code is certified; the *system* is not, until §9 runs. LS-05 and LS-10 remain
open product decisions and neither blocks release — LS-05 is a missing convenience, LS-10 a
self-inflicted limit no ordinary member reaches.

---

*Every fix is root-cause, at the layer that owns the rule. No architecture was redesigned, no
feature added, and no behaviour changed beyond the two decisions you made explicitly (LS-03, LS-05).*
