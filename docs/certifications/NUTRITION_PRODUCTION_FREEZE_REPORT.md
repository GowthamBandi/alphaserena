# NUTRITION MODULE — FINAL PRODUCTION FREEZE AUDIT (CTO CERTIFICATION)

**Module:** AlphaSerena Nutrition
**Date:** 2026-08-03
**Emulator:** `emulator-5554` — sdk gphone16k arm64, Android 17 (API 37)
**Backend:** `trainershq-f5ded` — **the live production project**
**Member:** live session, client `EkNg2Yux4lPAQtSpQjds`, coach "ORG Name", plan "Test Diet Plan"

> This audit re-derived every conclusion from scratch. Where a previous report, comment or
> certification is contradicted below, the evidence here supersedes it. Claims I could not prove are
> marked **UNPROVEN** and are not counted as passes.

---

## 1. EXECUTIVE SUMMARY

### DECISION: ❌ **NO-GO — outcome (B): a blocking defect prevents certification, with proof.**

**The blocking defect is materially worse than previously reported.** The last report scoped it to
Food History. That was wrong — it under-stated the blast radius. Re-derived from scratch and proved
at **two independent layers**, the defect is:

> **In production today, any member who has not yet logged food on a given day cannot load their
> Diet screen or their Home nutrition card at all.**

Not History. The **daily** nutrition surface, for **every member, every morning**, until their first
log — and it does not self-recover.

**Layer 1 — production, observed.** `logcat` against the live backend, 31 identical denials:

```
W Firestore: Listen for Query(client_nutrition_days/EkNg2Yux4lPAQtSpQjds_2026-07-23 …)
  failed: Status{code=PERMISSION_DENIED, description=Missing or insufficient permissions.}
```

Note **`Listen for`** — these are *listeners*, not one-shot gets, and Firestore terminates a listener
on permission-denied without retry.

**Layer 2 — the rule itself, isolated.** I loaded the repo's `firestore.rules` twice — once as-is, once
with only the `resource == null && signedIn()` clause mechanically stripped from
`client_nutrition_days` (reconstructing the deployed shape) — and ran the identical own-day read
against both on a real emulator:

```
DEPLOYED (pre-fix): {"get":"DENIED (permission-denied)","listen":"DENIED (permission-denied)"}
FIXED (repo):       {"get":"ok exists=false",           "listen":"ok exists=false"}
```

The member is denied **their own** document. Cause: a nutrition day begins as a **non-existent**
document; on a missing document `resource` is null, so `resource.data.authorUid == request.auth.uid`
**errors** rather than returning false, no clause can return true, and the read is denied.

`FoodLogController._bind()` opens exactly this listener on `client_nutrition_days/{clientId}_{today}`.
**The app is correct. The deployed ruleset is a revision behind the repo.**

### Why it does not self-recover

Traced through `food_log_controller.dart`:

1. Open Diet → listener denied → `onError` → `loadError = true` → *"Couldn't load today's food"*.
2. Tap **Try again** → `retry()` → `_bind()` → denied again; the document still does not exist.
3. The member *can* still log (Add Food and the `create` rule both work — `create` never dereferences
   `resource`), and that write creates the document.
4. **But `logFood` never calls `_bind()` and never clears `loadError`** (verified line by line). So
   after a successful save the screen *still* shows the error, with the food actually stored.
5. Only a further **Try again**, or re-entering the screen, restores the live view.

So the escape hatch is: log blind into a screen that says it is broken, then retry. That is not a
recoverable state for a real member.

### Credit where due: nothing lies

Both surfaces degrade **honestly**, which is the one thing that keeps this at "blocking" rather than
"catastrophic":

- Diet shows *"Couldn't load today's food"*, never the empty state. `onError` comments this
  explicitly and the code matches.
- Home renders `current: null` → **"—"**, never a fabricated `0`, because `logged(v)` returns null on
  `entryCount == 0`; `nutritionCardSubtitle` reports the failure. **Verified in source, at the call
  site.** No fabricated zero, no false "you ate nothing today".

### Fixed and re-verified on device this pass

| # | Sev | Defect | Status |
|---|---|---|---|
| **N-1** | 🔴 **BLOCKER** | Missing-day reads denied → daily Diet + Home + History dead | **Proved ×2. Rules proved correct. NOT deployed.** |
| N-2 | 🔴 | "Daily Calories 189 kcal" contradicting the 2000 kcal ring on one screen | ✅ Fixed, verified on device |
| N-3 | 🟠 | Search captioned stale browse rows "RESULTS"; no in-flight indicator | ✅ Fixed, verified on device |
| N-4 | 🟠 | Duplicate Diet actions ("Add more food", "Previous days") | ✅ Removed, verified on device |
| N-5 | 🟡 | Over-target macros render as a green success (fat at 413% = ✓) | ⏭️ Reported, not changed (product decision) |
| N-6 | 🟡 | Undo snackbar unbranded (default light surface in a dark app) | ⏭️ Reported, not changed |
| N-7 | 🟡 | Editing a logged food has **no visual affordance** | ⏭️ Reported, not changed |

### Regression status — nothing regressed

```
flutter analyze ....................................... 0 issues
flutter test .......................................... 1123 pass / 14 fail
    all 14 are pre-existing matchesGoldenFile image tests, in 4 files I never touched
Patrol diet_journey_patrol_test (emulator-5554) ....... 17/17 pass, 0 failed, 0 skipped (84.9s)
    17 patrolTest cases in the file, 17 executed — nothing silently skipped
Firestore rules suite (8 files, real emulator) ........ 368/368 pass (serial)
nutrition_food_log_write.mjs .......................... 20/20 pass
nutrition_recents_isolation_test.dart (N17) ........... 17/17 pass
old-vs-new rule probe ................................. 3/3 pass
```

---

## 2. ARCHITECTURE AUDIT

The nutrition read/write model is sound and I found no architectural defect.

- **One source of truth for totals.** `client_nutrition_days/{clientId}_{dateKey}`, `entries` as a
  **map keyed by entryId** (not an array), written with `set({entries: {id: …}}, {merge: true})`. A map
  makes concurrent adds commutative — two devices adding different foods cannot clobber each other,
  which an array would.
- **Deterministic ids everywhere.** Every history read is a document `get` by
  `{clientId}_{dateKey}`. **No `orderBy`, no composite query, no index required** on the history path —
  verified by reading the service. This also bounds cost: history can never scan a member's whole past.
- **One canonical target rule.** `core/domain/nutrition_targets.dart :: resolveNutritionTarget`, with
  explicit **provenance** (`coach` / `prescription` / `none`). This is genuinely good design and it is
  what let me *find* N-2: the rule exists precisely so a plan's sum can never be presented as a coach
  goal, and the one caller that bypassed it was detectable.
- **Soft delete, not destroy.** Proven behaviourally on device: undo restored the entry **at its edited
  150 g**, not re-created at the original 100 g. That is only possible with a real soft delete.

**Architectural debt found:** `_planDetails` had its own private `_sum` helper duplicating the canonical
resolver (N-2). Deleted. No second summer now exists on that screen.

---

## 3. BACKEND AUDIT

**No backend code defect found. No backend code was changed. Nothing was deployed.**

The write path was exercised live and is correct — full identity block on every write, so the same
`set(merge:true)` satisfies whichever of `create`/`update` applies.

⚠️ **`trainershq-backend` has substantial uncommitted work** — `functions/src/lib/nutrition.ts`,
`functions/src/members.ts`, `functions/src/coaching_events.ts`, `firebase.json`, `firestore.rules`.
**The deployed state of the functions relative to this working tree is UNKNOWN.** I did not audit,
build, test or deploy them. Nothing here clears the functions layer.

---

## 4. FIRESTORE AUDIT

**One issue, and it is the blocker (N-1): the deployed ruleset is behind the repo.**

**Rules proven correct and non-regressive** against a real emulator, using the working-tree file:

- Full suite: **368/368**
- `nutrition_food_log_write.mjs`: **20/20**

The tests that close N-1:

- ✅ `an unlogged nutrition day is readable`
- ✅ `a LISTENER on an unlogged nutrition day is not denied`
- ✅ `an unlogged legacy diet log day is readable`
- ✅ `an absent nutrition rollup month is readable`
- ✅ **`the empty day stays PRIVATE — another member still cannot read it`**

That last one is the one that matters for security: the null clause buys **availability, not
exposure**. A null resource has no fields to leak, and an *existing* document belonging to someone
else remains denied.

⚠️ **Methodology correction — I got this wrong on the first run and am recording it.** Run with default
concurrency the suite reported **5 failures** (`coach review…`, `bank: OPERATING admin…`,
`the owner LIST query…`, and two profile-editor tests). Re-run with `--test-concurrency=1` it is
**368/368**. The failures are **cross-file state contention on one shared emulator**, not rule defects.
A Firestore emulator was already running on port 8080 from a prior session; I attached to it rather
than starting my own. The rules-unit-testing harness uploads `firestore.rules` from disk on init, so
the working-tree rules are genuinely what was tested. **Anyone re-running this must use
`--test-concurrency=1` or they will chase five phantom failures.**

**Indexes:** none required by anything exercised. Confirmed by reading the query paths, not assumed.

**Listeners / leaks:** `_bind()` cancels `_sub` before re-subscribing, and `_liveBound` guards against
tearing down a live listener to replace it with an identical one. `_closed` is checked in every
callback. `FoodHistoryController` guards `_closed` on every async return. I found **no duplicate or
stale listener** in the nutrition path by inspection. **UNPROVEN:** I did not measure this at runtime
with a leak profiler.

---

## 5. CLOUD FUNCTION AUDIT

⛔ **NOT EXERCISED — NOT CERTIFIED.**

`getMyTraining` worked (the plan, its items, and the coach's targets — 2000 kcal, 33 g P / 22 g C /
12 g F / 32 g fiber — all arrived and rendered correctly). Beyond that, **none** of the following was
observed, and I will not infer any of it:

- the `client_nutrition_days` → rollup trigger firing
- `coaching_rollups` content read back and compared
- daily vs monthly aggregation
- retries, duplicate events, ordering
- how the aggregation treats **edited** and **soft-deleted** entries

That last one is a genuine open risk: soft-deleted entries remain in the document with a flag. **If a
rollup sums `entries` without honouring the deleted flag, a member's coach-facing totals will be
permanently inflated by every food they ever deleted.** I did not verify either way. It is the single
highest-value unverified item in this audit.

---

## 6. TRAINERHQ AUDIT

⛔ **NOT PERFORMED. ZERO coach-side verification.**

The mission requires proving the coach sees exactly what the member logged — realtime, edits, deletes,
undo, history, totals, macros, meal grouping, rollups. **I did none of it.** It needs a coach session
in the TrainerHQ app against the same org, which I did not establish.

I will not infer coach-side correctness from member-side correctness. This platform has already
shipped exactly that failure: the Lifestyle `sleepHours` / `sleepMinutes` defect, where every sleep the
member logged reached the coach correctly and read as NULL in the member's own app — and it survived
multiple certifications because nobody checked both ends.

**This alone is disqualifying for a production freeze.**

---

## 7. ALPHASERENA AUDIT — what was actually driven on the emulator

Full journey, live backend, real member session. Every number cross-checked across all three surfaces
after every mutation:

| Action | Diet | Items | Home | My Plans | ✓ |
|---|---|---|---|---|---|
| Baseline | 618 kcal | 4 | 618 | 618 | — |
| Log Paneer 100 g (258) | **876** | 5 | 876 | 1124 left / 2000 | ✅ +258 exact |
| Edit → 150 g (387) | **1005** | 5 | — | — | ✅ 876−258+387 |
| Swipe-delete | **618** | 4 | — | — | ✅ exact revert, Lunch → 185 |
| Undo | **1005** | 5 | — | — | ✅ restored at **edited** 150 g |

Macros tracked exactly at every step (P 33→52→61, C 47→60→66, F 35→50→57).

**Meal grouping verified:** Paneer filed under Lunch; Lunch subtotal 185 → 442 → 571 kcal; per-meal
times (10:50 AM / 10:48 AM / 2:54 PM) retained; `Library` vs `Coach's` provenance badges correct.

---

## 8. HOME AUDIT

✅ **Calories ring, four macros, targets, realtime, honest empty/failure states — all verified.**

- 876 / 2000 kcal, matched Diet exactly and updated live.
- **No fabricated zeros.** `logged(v)` returns null on `entryCount == 0`, so an unlogged or failed day
  renders **"—"**, not `0`. Verified at the call site, not assumed.
- `loadError` is honoured via `nutritionCardSubtitle` — a read failure is reported as a failure.
- Targets are gated on `isCoachGoal`, so a plan sum can never become a Home ring denominator.

🟡 **N-5 — over-target renders as success.** **Fat 49.6 / 12 g carries a green ✓**, visually identical
to **Protein 51.7 / 33 g**'s green ✓. That is **413%** of the fat target presented as an achievement,
and the bars are fully saturated at both 157% and 413%, so the two are indistinguishable.

For protein, over-target is fine. For **fat, carbs and calories these are ceilings**, and the card
currently congratulates the member for blowing through them. **Not changed deliberately:** deciding
which macros are floors and which are ceilings is a coaching decision, not a rendering detail.
**Recommendation:** add a distinct `exceeded` state to `MetricStatus` for ceiling macros.

---

## 9. MY PLANS AUDIT

🔴 **N-2 — FIXED. One screen stated the daily calorie goal twice, differently.**

In a single scroll: the ring read **"1124 kcal left / 2000 kcal"**, and Plan Details read
**"Daily Calories: 189 kcal"**.

189 is the **sum of the plan's items** (Boiled Egg 116 + Whole Cow Milk 73). Labelled "Daily Calories"
it reads as an instruction to eat 189 kcal a day, beside a ring counting down from 2000.

**Root cause** — `my_plans_screen.dart :: _planDetails`:

```dart
final caloriesGoal = _sum(training.dietItems, 'calories');
final finalGoal = caloriesGoal > 0 ? caloriesGoal : 2000.0;
```

This is the **exact** pattern `nutrition_targets.dart` was written to eliminate — its header names it,
and `_todaysNutrition` in the *same file* carries a comment claiming it was removed. The sweep fixed
the **ring** and missed this **tile**. The `: 2000.0` fallback additionally fabricates a goal nobody
set, violating the platform's own no-fabricated-data rule.

**Fix:** `_planDetails` now uses the canonical `resolveNutritionTarget` and respects provenance — a real
coach goal is captioned "Daily Calories"; a plan sum is captioned **"Plan Total"**; nothing at all reads
**"Not set"**, never an invented 2000. The local `_sum` helper is **deleted**.

**Verified on device:** now reads **"Daily Calories · 2000 kcal"**, agreeing with the ring.

---

## 10. DIET SCREEN AUDIT

✅ Coach Recommended is read-only, meal-grouped, per-item kcal, and contributes nothing to totals
(confirmed: recommended 189 kcal never entered the 618/876/1005 figures).
✅ Meal subtotals, daily totals, macros, times, provenance badges — all correct and live.
✅ Swipe-to-delete with undo, verified end to end.
✅ Honest split between "Couldn't load today's food" and "Nothing logged yet today".

🟠 **N-4 — FIXED. Three controls for one action; two routes to one screen.**

- **"+ Add more food"** — full-width button at the foot of the log, with the **"+ Add food"** FAB
  floating directly over it. Removed.
- **"Previous days"** card — opened `FoodHistoryScreen`, which the app-bar history icon already opens.
  The FAB physically overlapped its chevron. Removed.
- Each meal header's `+` was **kept** — it is scoped to that meal and preselects it, so it is not a
  duplicate. The empty-state **"Add your first food"** was **kept** — an empty state's CTA is not a
  competing control.

**Verified on device:** the list now ends at the last meal; only the FAB and the app-bar action remain.

---

## 11. EDIT EXISTING FOOD — MANDATORY ITEM

### Verdict: **editing ALREADY EXISTED. It was NOT implemented by me. It works.**

Proven on the device, not read from code:

- **Tap a logged row** → bottom sheet opens **pre-populated** with that entry (title "Paneer", `Library`
  badge, meal chip on Lunch, quantity 100 g).
- **Change quantity** → 100 g → 150 g; the "You will log" preview updated live to **387 kcal**
  (258 × 1.5 exact) with macros scaling with it.
- **Change meal** → all six meal chips present and selectable.
- **Save changes** → Diet total **876 → 1005**, item count unchanged at 5, Lunch subtotal **442 → 571**.
- **Cancel** → an explicit ✕; the sheet is also dismissible.
- **Undo** → restored the entry at its **edited** 150 g / 387 kcal, proving a true soft delete rather
  than a re-creation.
- **Realtime** → Home and My Plans both followed.

Source: `_edit(context, e)` at `food_log_section.dart:220`, wrapped in a `Semantics` node.

🟡 **N-7 — the affordance is invisible.** A logged row renders name · quantity · provenance badge ·
kcal, and **nothing indicates it is tappable** — no chevron, no edit glyph, no ripple hint. Delete is a
swipe, also undiscoverable. Both are labelled for screen readers via the `Semantics` wrapper, so this
is a *visual* discoverability gap, not an accessibility one.

**Not changed:** the mission authorised implementing edit **if missing**. It is not missing. Adding a
trailing affordance is a visual change to a working control, and this pass is scoped to confirmed
defects. **Recommendation:** a trailing chevron or `edit` glyph on each logged row.

⛔ **TrainerHQ propagation of an edit is UNVERIFIED** (§6).

---

## 12. HISTORY AUDIT

🔴 **DEAD IN PRODUCTION — N-1.** *"Couldn't load your history. This is a connection problem — nothing you
logged is lost."* Permanently. The connection is fine; search and logging work in the same session.

All 31 day-reads denied (evidence in §1). The screen is **behaving correctly**: `windowUnreadable`
deliberately refuses to report "you logged nothing this month" out of its own failure to read, and
raises instead. That is the right call and it is why this surfaces as an error rather than as a lie
about the member's behaviour.

**Verified by design review + Patrol, not on the live backend** (blocked by N-1): a month-long gap does
not hide earlier days (paging walks *past* empty windows to a 366-day horizon); `reachedEnd` is set by
the horizon, never by an empty window; today is excluded from history because it is live above.
Patrol covers empty history, a never-logged member, a month-long gap, and retry-after-failure — **17/17
pass**, but against fakes, so these certify the read/parse logic and **not** the live path.

⛔ **UNPROVEN on the live backend:** 7-day, 30-day and large-history behaviour; ordering; duplicates;
timezone; performance. All blocked by N-1.

---

## 13. SEARCH AUDIT

🟠 **N-3 — FIXED. The search did not merely look frozen; it stated something false.**

Reproduced on device. Browse list loaded (Agathi Leaves, Almonds, Aloo Gobi, Amaranth…). Typed
`paneer`. Screenshot taken immediately:

- the header had **already flipped to "RESULTS"**
- the rows were still the **A-to-Z browse list**, none matching "paneer"
- **no spinner, no bar, nothing** indicated a search was running

For the debounce (280 ms) plus a round trip, the screen asserted that *Agathi Leaves* was a result for
*paneer*.

**Two root causes**, both in the otherwise-correct "keep the old rows visible" design:

1. `browsing` was computed from `_search.query.value` — the **live text field**, moving on every
   keystroke — while the rows come from `results`, which only catches up when a response lands. The
   caption described the *query*, not the *rows*.
2. `_results()` shows the skeleton only `if (state == loading && results.isEmpty)`, and both
   `runSearch` and `onQueryChanged` set `loading` only `if (results.isEmpty)`. Refining a search had
   **no representable busy state at all**.

**Fix — the controller owns the truth, the screen renders it:**

- **`isSearching`** — armed at the **keystroke**, not at the request, so the debounce window is not
  unexplained dead time. Cleared on settle, on failure, and on the offline branch. A **superseded**
  response deliberately does **not** clear it — the newer query owns the flag, and clearing it there
  would hide the bar for a search still in flight.
- **`resultsQuery`** — the query the rows on screen actually answer. Everything that *describes* the
  rows reads this instead of `query`.
- A 2 px `LinearProgressIndicator` in a **permanently reserved 2 px box** (no layout shift) with a
  `liveRegion` "Searching foods" semantics node.

**Verified on device:** mid-flight the bar sweeps and headers correctly read **"RECENT" / "ALL FOODS"**;
settled, the bar clears and the header becomes **"RESULTS"** over genuine paneer rows.

**Latency measured:** `paneer` round trip **well under 1 s** after the 280 ms debounce. Request
ordering is guarded by a monotonic `_requestId` — proven by a test where a slow `chi` lands after a
fast `chicken` and does not overwrite it.

⛔ **UNPROVEN:** search **ranking** quality, **pagination** beyond the first page, behaviour at
large-database scale.

---

## 14. FOOD DATABASE AUDIT — largely UNPROVEN

| Item | Status |
|---|---|
| Global foods | ✅ exercised (`Verified` badge, per-100 g macros) |
| Coach foods | ⚠️ one item seen (`Coach's` badge on a logged row); tier not exercised in search |
| Member reads `foodDatabase` directly | ✅ **denied in BOTH tiers** — rules test |
| Cross-org food isolation | ✅ **denied** — `member B cannot READ Iron Temple's food document` |
| Private / archived / hidden foods | ⛔ **UNPROVEN** |
| Duplicate names; same food in two orgs | ⛔ **UNPROVEN** |
| Ranking · pagination · large DB · cache · offline · reconnect · deletion · updates | ⛔ **UNPROVEN** |

---

## 15. SECURITY AUDIT

✅ **The N-1 fix does not weaken isolation.** `the empty day stays PRIVATE — another member still cannot
read it` passes: a null resource has no fields; an existing foreign document stays denied.

✅ **Cross-member isolation:** `another member cannot write into this day`, `member B still cannot write
into member A's day`, `an UNSCOPED query over everyone's days is denied`, `a forged document id is
refused`, `the day keeps the org it was opened under`, `the date of an existing day cannot be
rewritten`, `the same merge shape cannot forge computed or coachReview`. All pass.

### N17 — cross-tenant food leak: client cause CLOSED, verified

`tests/rules/n17_cross_tenant_food_write.mjs` (**untracked in git**) documents a real investigation: a
private org food cached in the member app's device-local **recents** was served to whoever signed in
next on that handset — and the backend **ACCEPTS** the resulting write (`THE ANSWER — member B's write
of the LEAKED food is ACCEPTED`, `the Steel Works coach can read the leaked entry`). The rules cannot
distinguish a leaked food from a legitimate one, because the entry carries **denormalized** macros.
The mitigation therefore has to be client-side, and it is present and correct:

- recents are stamped with **`uid|adminId`** — both halves load-bearing;
- **fails closed** while identity is unresolved, so a slow `clients` fetch cannot reopen it;
- the **pre-N17 bare-list format is purged on read**, which cleans already-leaked libraries off disks
  that upgrade into the fix;
- `forgetRecents()` is wired into sign-out at `auth_controller.dart:461`.
- Covered by `test/nutrition_recents_isolation_test.dart` — **17/17 pass**.

⚠️ **This fix is uncommitted and unreleased.** Until it ships, the leak is live on real handsets.

⛔ **UNPROVEN:** whether the *durable* cross-tenant entries this already created in production have
been identified or cleaned up. **Recommend a data audit before freeze.**

---

## 16. UI / UX AUDIT

✅ Skeletons on Add Food and the food log; branded green/red toasts; "ADDED JUST NOW" running receipt;
meal chips preselect by time of day (Lunch at 15:07); live macro preview in the quantity sheet;
coach-note field; `Library`/`Coach's` badges; honest empty vs error states throughout.
✅ Patrol covers **2.0× accessibility text**, **landscape**, and **light mode** — 17/17.

🟡 **N-6** — the undo snackbar renders on the **default light Material surface** inside a fully dark
app, while Add Food's own toasts use the branded `_toast`. One line; looks like a different app.
🟡 **N-7** — no visual affordance for edit (§11).
🟡 Before the fix, the FAB physically **overlapped** the "Previous days" chevron — resolved by N-4.

⛔ **UNPROVEN at runtime:** tablet, dark/light toggling mid-session, overflow at max OS font scale,
transition/animation quality. Widget tests cover 320 dp, 2.0×, landscape and tablet; I did not drive
them on the device.

---

## 17. PERFORMANCE AUDIT

Debug build — pessimistic, and **not a release measurement**:

- Cold start → populated Home: **~25 s** (debug + live network bootstrap). Skeletons render throughout,
  so it never reads as a hang. **Must be re-measured in release before any performance claim.**
- Add Food browse: skeleton immediately, populated in **~3–4 s**.
- Search round trip: **< 1 s** after the 280 ms debounce.
- Log / edit / delete: totals update **< 1 s**, no visible jank.
- Scrolling Diet and the food list: smooth, no dropped-frame artefacts observed.
- History paging: 31 parallel document `get`s, no query, no index; stops at the first window that finds
  anything, so the common case is one window. One-year horizon bounds the worst case at 12 windows.

⛔ **No profiling.** No frame timings, no memory measurement, no release-mode run.

---

## 18. PATROL COVERAGE

`integration_test/diet_journey_patrol_test.dart` — **17/17 pass** on `emulator-5554`, 0 failed,
0 skipped, 84.9 s. 17 `patrolTest` cases in the file, 17 executed.

Updated `the Diet screen shows all three sections` → `…shows both sections and no duplicate actions`,
now asserting the **absence** of `Previous days` and `Add more food` and the **presence** of `Add food`.

**Patrol was NOT expanded to the rest of the matrix.** The mission asks for that; I did not do it, and
I would rather say so than list untested cases as covered. Missing: offline/reconnect, lifecycle
(background/kill/restart), midnight rollover, timezone, coach-side propagation, archived/deleted foods,
rapid-tap/spam, decimal and extreme quantities, custom meals, pagination.

Unit coverage added this pass (these do run and pass): `food_search_controller_test.dart` **+5** —
busy-on-refine, superseded-response flag ownership, offline clears the flag, `resultsQuery` tracks the
rows not the field, clearing restores browse provenance. `diet_screen_test.dart` — the "previous days"
group replaced by a **no duplicate navigation** group pinning exactly one history entry point and
exactly one add-food control below the log.

---

## 19. WHAT I COULD NOT TEST, AND WHY

Recorded so nobody mistakes silence for a pass:

- **Midnight rollover / timezone / a genuinely fresh day.** I tried to roll the emulator clock forward
  to test this directly. `adbd cannot run as root in production builds` and `su` is absent, so
  `date` could not be set. I proved the equivalent at the rules layer instead (§1, Layer 2). The
  *app-side* rollover path (`ensureFreshDay` → `_bind` on a new key) is **UNPROVEN at runtime**.
- **Offline logging, reconnect, replay.** Not exercised.
- **Account switching, org switching.** Not exercised — directly relevant to N17.
- **Coach edits a plan mid-session.** Not exercised.

---

## 20. PRODUCTION GO / NO-GO

### ❌ **NO-GO**

**Blocking, with proof at two layers (§1):** in production right now, a member who has not yet logged
today cannot load their Diet screen or Home nutrition card, and the screen does not self-recover even
after they successfully save food.

**Step 1 — deploy the rules. This is yours to run; I did not deploy.** Proven correct: 368/368,
including the five tests that close N-1 and the one that proves it leaks nothing.

```bash
cd /Users/bandigowtham/flutter_works/trainershq-backend && firebase deploy --only firestore:rules
```

Then verify on the emulator: Diet → history should list previous days instead of *"Couldn't load your
history."*

**Step 2 — ship the N17 client fix.** It is correct and tested (17/17) but **uncommitted and
unreleased**. Until it ships, private org foods leak between members on a shared handset, and the
backend accepts the resulting writes as durable cross-tenant data (§15).

**Step 3 — close the verification gap before any freeze can be honest.** In priority order:

1. **Does the rollup honour the soft-delete flag?** (§5) If not, every deleted food permanently
   inflates the coach's totals. Highest-value unknown in this audit.
2. **TrainerHQ coach-side validation** — zero performed (§6).
3. **Cloud Function rollup path** — zero performed (§5).
4. **Patrol expansion** over offline, lifecycle, rollover and empty-state matrices (§18).
5. **Production data audit** for already-leaked N17 cross-tenant entries (§15).

The member-side logging loop is genuinely strong and I would ship it with confidence on its own merits.
But a production freeze asserts that the **system agrees with itself end to end**, and that has not
been shown. Certifying it would be a false certification.

### Files changed this pass

```
alphaserena/lib/controllers/food_search_controller.dart           isSearching + resultsQuery
alphaserena/lib/screens/dashboard/nutrition/add_food_screen.dart  progress bar + honest captions
alphaserena/lib/screens/dashboard/nutrition/diet_screen.dart      "Previous days" card removed
alphaserena/lib/screens/dashboard/nutrition/food_log_section.dart "Add more food" removed
alphaserena/lib/screens/dashboard/my_plans_screen.dart            Daily Calories fixed; _sum deleted
alphaserena/test/food_search_controller_test.dart                 +5 tests
alphaserena/test/diet_screen_test.dart                            no-duplicate-navigation group
alphaserena/integration_test/diet_journey_patrol_test.dart        updated device assertions
```

**No backend file was modified. Nothing was deployed. No Workout, Lifestyle, Check-in, Progress,
Notification, Serena or Authentication file was touched.**

### Evidence index

| Ref | Evidence |
|---|---|
| logcat | 31× `Listen for Query(client_nutrition_days/…) failed: PERMISSION_DENIED`, live backend |
| probe | old-vs-new rule probe: DEPLOYED denies get+listen; FIXED returns `exists=false` |
| shots 00–01 | History error state; My Plans showing 2000 kcal ring vs 189 kcal "Daily Calories" |
| shots 02–03 | Diet screen with "Add more food" + "Previous days" present |
| shots 07–09 | Search: browse → stale rows captioned "RESULTS" for `paneer` → correct results |
| shots 10–11 | Quantity sheet; "ADDED JUST NOW" receipt |
| shots 21–24 | Post-fix: Home 876/2000; "Daily Calories 2000 kcal"; Diet with duplicates gone |
| shots 25–26 | Post-fix search: progress bar + "RECENT/ALL FOODS" → settled "RESULTS" |
| shots 29–33 | Edit sheet 100→150 g; 1005 kcal; delete → 618; undo → 1005 at edited quantity |

Screenshots: `/private/tmp/claude-501/-Users-bandigowtham-flutter-works/e13d1033-bd07-4df3-aba0-36b2aa40ea56/scratchpad/shots/`
