# ALPHASERENA — NUTRITION MODULE
# CTO N17 RESOLUTION REPORT

**Date:** 2026-08-03
**Scope:** N17 only. No redesign, no refactor, no feature work.
**Method:** the real application on emulator-5554 against the real local Firebase
suite (real rules, real `searchMemberFoods`, real Firestore triggers, real signed-in
member session), plus the real security rules on a real Firestore emulator.
**Verdict:** **RESOLVED.** See §10.

---

## 0. WHAT N17 TURNED OUT TO BE

State it plainly, because the previous pass classified it one severity too low:

| Classification | Verdict |
|---|---|
| UI cache defect | **YES** — at origin |
| Security defect | **YES** |
| Cross-member leak | **YES** |
| Cross-tenant leak | **YES** |
| Data isolation vulnerability | **YES — client-side.** Server-side isolation never failed |
| False positive | **NO** |

**N17 is a client-side data-isolation vulnerability with a confidentiality breach and
a data-provenance breach, not a UI-only cache defect.** The prior report called it
"purely the local cache" and "MEDIUM". The cache is where it *starts*; it does not
stop there. The leaked food is loggable, the write is accepted, and the leaked
content becomes durable records inside the receiving organization's tenant — read
by that organization's coach and counted in its analytics.

It is **not** a Firestore rules bypass. Every server-side isolation probe passed.

---

## 1. RUNTIME EVIDENCE

### 1.1 The device's own disk, mid-session

Read from `emulator-5554` with `adb run-as`, while a **Steel Works** member was
signed in:

```
/data/data/com.alphaserena/shared_prefs/FlutterSharedPreferences.xml

flutter.nutrition_recent_foods_v1 =
  [{"foodId":"food-A-secret","name":"Iron Temple Secret Shake","tier":"org",
    "per100":{"calories":320,"protein":40,"carbs":20,"fat":8,"fiber":2,
              "sugar":5,"saturatedFat":2},
    "portions":[{"label":"shaker","grams":300}],
    "verification":"unverified"}]
```

A bare, **unowned** JSON array holding another organization's private food — its
name, its complete macro profile, and its coach-authored portion definition
("shaker · 300 g") — sitting on the handset of a member who has no relationship
with that organization.

### 1.2 The screen, unfixed build

Member B (Steel Works) → My Plans → Diet → Add Food:

- **RECENT** → `Iron Temple Secret Shake` · badge **"Your coach's"** · 320 kcal/100 g
- **ALL FOODS** (served live by the real `searchMemberFoods` callable) →
  `Steel Works Power Bowl` and `Basmati Rice (cooked)` — **correct**

One screenshot contains both the failure and its own control: the **server** served
only Steel Works' and global foods, exactly as designed, while the **local cache**
served a competitor's private product, mislabelled as this member's own coach's.

### 1.3 The write was accepted — Phase 1 answered

Member B tapped the leaked row, took the sheet's default (1 shaker · 300 g · 960 kcal)
and confirmed **"Add to Lunch · 960 kcal"**. Read back from Firestore:

```
client_nutrition_days/client-B_2026-08-03
  clientId  = client-B
  adminId   = coachB          ← STEEL WORKS
  authorUid = memberB
  entries.Z7MxAslXsIc3TYZA5WGf = {
     foodId   : "food-A-secret",
     foodName : "Iron Temple Secret Shake",
     foodTier : "org",
     consumed.calories : 960
  }
  computed.totals = {calories: 960, protein: 120, carbs: 60, fat: 24, ...}
```

`computed` is **server-owned** — the Cloud Function trigger ran and folded the
leaked entry into the day's totals. It did not stop there:

```
nutrition_rollups/client-B_2026-08
  adminId = coachB
  days["2026-08-03"].totals.calories = 960   (1155 after a later legitimate log)
  days["2026-08-03"].targetAdherence.calories = 0.578
```

**Outcome B. The food appears AND the backend accepts.** The leak reaches Firestore,
the Cloud Function, the coach's view and the analytics rollup.

### 1.4 Server-side isolation held — the controls

`trainershq-backend/tests/rules/n17_cross_tenant_food_write.mjs`, **5/5** on a real
Firestore emulator:

| Probe | Result |
|---|---|
| Member B reads Iron Temple's `foodDatabase` doc | **DENIED** ✅ |
| Member B reads Member A's `client_nutrition_days` doc | **DENIED** ✅ |
| Member B writes the leaked food into **their own** day | **ACCEPTED** ⛔ |
| Steel Works' coach reads the leaked entry | **ACCEPTED** ⛔ |
| Member B writes into Member A's day | **DENIED** ✅ |

Write isolation between members holds. Tenant read isolation holds. The rules
validate *identity* — `authorUid`, `clientId`, `adminId`, doc id — and nothing
about the *provenance of a food*, which is why the third row is accepted.

---

## 2. EXACT REPRODUCTION

Deterministic, on a stock build:

1. Member A (Iron Temple) logs a food from their coach's **private** org library.
   `MemberFoodService.remember()` writes the card to
   `SharedPreferences['nutrition_recent_foods_v1']`.
2. Member A signs out. `AuthController._teardownToLogin()` clears the workout draft
   and deletes fifteen member-scoped controllers. **It does not touch recents.**
3. Member B (Steel Works) signs in on the same device and opens Add Food.
4. `FoodSearchController.onInit` → `_loadRecents()` → `MemberFoodService.recents()`
   reads that same device-global key and returns Member A's list.
5. `AddFoodScreen` renders it under **RECENT**, badged **"Your coach's"** because
   the cached card's `tier` is `org`.
6. Member B taps it → quantity sheet → **Add to Lunch** → §1.3.

**Step 2 is not required.** Three variants reproduce with no sign-out at all:

- **Crash / force-stop / OS kill** — the teardown never runs.
- **Organization transfer** — the coach moves the member; `clients.adminId` changes
  under a live session and no teardown is involved.
- **Two members of the same org** on one device — a cross-*member* leak of one
  person's eating record, without any cross-tenant element.

---

## 3. ROOT CAUSE — ONE CAUSE

> **The recents cache was a device-global, identity-less slot on disk.**
>
> It is the only member-scoped store in this app that lives in a file rather than in
> a controller. Every other one is an in-memory `Rx` field destroyed by
> `AuthController._teardownToLogin`'s controller sweep — so that sweep, the app's
> whole mechanism for "the previous member must leave nothing behind", **structurally
> cannot reach this one**. And because the slot carried no owner, no reader could
> tell whose list it was, so nothing downstream could refuse it either.

**`forgetRecents()` having zero call sites is a symptom, not the cause.** The prior
report's proposed minimal fix — "invoke the existing function when `clients.adminId`
changes" — would have closed the reported path and left the defect live, because a
call site only covers the paths that *run*. A crash runs nothing. Verified as a
regression test: *"a SIGN-OUT WITHOUT forgetRecents is still safe"*, and on device as
*"MEMBER SWITCH AFTER A CRASH"*.

### Where ownership validation disappears — the full trace

`searchMemberFoods` (`functions/src/member_food.ts:77, 97–131`) resolves the caller's
`adminId` from their own `clients` document and filters `foodDatabase` by it. Global
foods carry `adminId: ''`, which no real org uid equals, so tiers cannot cross.
**That callable is the one and only authorization point in the entire flow.**

| Layer | Ownership check |
|---|---|
| `searchMemberFoods` | ✅ **THE** check — filters by caller's `adminId` |
| **`MemberFoodService.remember()`** | ⛔ **FIRST LOSS** — `toCache()` writes the card to a global key, stripping the identity that authorized it |
| `SharedPreferences` | ⛔ one slot, no owner, survives everything |
| `MemberFoodService.recents()` | ⛔ returns whatever is there |
| `FoodSearchController._loadRecents` → `recents` RxList | ⛔ none |
| `AddFoodScreen._foodRow` | ⛔ renders the cached `tier` as a trust badge |
| `FoodQuantitySheet` | ⛔ portions the cached `per100` |
| `FoodLogController.logFood` | ⛔ snapshots cached macros; no server lookup |
| `NutritionDayService.writeEntry` | ⛔ identity block is the member's OWN and correct; `entries.*` unexamined |
| Firestore rules | ⛔ validate identity, not food provenance (proven §1.4) |
| `onNutritionDayWritten` trigger | ⛔ recomputed `computed.totals` over the leaked entry |
| History | ⛔ reads the day by id — shows it |
| `nutrition_rollups` | ⛔ leaked totals filed under the receiving org |

Twelve layers, one check, and it is upstream of the cache. Nothing re-establishes it.

---

## 4. WHY PREVIOUS TESTS MISSED IT

**Unit tests:** there were none for recents. `MemberFoodService.recents/remember`
had zero direct coverage.

**Patrol:** `add_food_patrol_test.dart`'s `_FixtureFoodService` overrides
`recents()` to `const []` and `remember()` to a no-op. **Twenty device tests drove
the Add Food screen and not one of them touched the recents cache** — the defect
lived underneath a stub. The prior report concluded "Patrol could not have caught
N17 … the honest guard is a unit test, not a Patrol test." That is not right: the
limitation was the fixture's choice, not Patrol's. §7 demonstrates the opposite.

This is the third time this exact habit has hidden a defect in this codebase — the
retired nutrition screen and the workout-consistency engine both shipped broken
behind hand-made fixtures. It is now the single most reliable predictor of where the
next one is.

**Rules tests:** 368 of them, all correct, none applicable. Every one asks "may this
identity write this document?" — which is answered *yes*, correctly. No test asked
"where did this food come from?", because provenance is not a property the rules
model at all.

**The runtime pass that found it stopped one step early.** It observed the leak and
inferred "the leak is entirely in the local cache" without logging the leaked food.
One tap separated MEDIUM from a cross-tenant write.

---

## 5. THE REPAIR

Two files, +87 / −5.

### 5.1 `lib/core/services/member_food_service.dart` — the cache carries its owner

```dart
/// `uid|adminId` — the identity a cached recents list belongs to.
String get _owner { ... }
```

Both halves are load-bearing: the **uid** separates two members sharing a device;
the **adminId** separates one member's two organizations, which is the transfer case
where no sign-out happens.

Stored shape becomes `{"owner": "<uid>|<adminId>", "foods": [...]}`.

| Stored | Current owner | Behaviour |
|---|---|---|
| absent | any | `[]` |
| **bare list** (pre-repair) | resolved | `[]` + **slot purged** |
| stamped, matching | resolved | serve |
| stamped, different | resolved | `[]` + **slot purged** |
| anything | **unresolved** | `[]`, **slot preserved** |

- A foreign or unstamped list is **destroyed on read**, not merely hidden — which is
  what removes an already-leaked library from devices upgrading into the fix.
- An unresolved identity (a `clients` document still in flight) **fails closed** but
  does **not** delete: failing closed must not become data loss.
- `remember()` refuses to write an unowned list — the same defect from the other side.

The key `nutrition_recent_foods_v1` is deliberately **not** bumped, so existing
leaked blobs are purged in place rather than orphaned on disk forever.

### 5.2 `lib/controllers/auth_controller.dart` — eager clear on sign-out

```dart
WorkoutDraftStore().clear();
MemberFoodService().forgetRecents();   // ← the other device-local store
```

One line, beside the existing precedent, best-effort and un-awaited like every other
step in that teardown. This is **not** what stops the leak — the owner stamp is. It
makes the window brief rather than lasting until the next read.

### What was deliberately NOT done

- `MemberFoodService.invalidate()` (the in-memory search cache) is also uncalled, but
  that cache is instance-scoped and dies with its controller, which sign-out deletes.
  Not part of N17; left alone.
- **N16 is untouched.** Archived foods still linger in recents. Out of scope, still open.
- No redesign of recents into a server-backed list. The device-local trade-off
  documented in that file remains correct; it only ever needed an owner.

---

## 6. REGRESSION TESTS

`test/nutrition_recents_isolation_test.dart` — **17 tests**.

**Fail before the repair: 10. After: 0.** Verified by restoring the pre-repair
`recents()`/`remember()` bodies and re-running — the ten leak/purge/fail-closed tests
fail, the seven "the feature still works" tests pass in both states, which is the
correct signature for a fix that isolates without breaking.

Coverage: same member · different member · same org · different org · sign-out ·
sign-out-that-never-ran (crash) · restart/cold start · shared device · pre-repair
blob upgrade · unresolved identity (both directions) · corrupt JSON · ordering,
dedupe and `maxRecents` bounds · tier and macro fidelity through the cache round trip.

`trainershq-backend/tests/rules/n17_cross_tenant_food_write.mjs` — **5 tests**,
pinning both what the rules *do* protect and what they provably do not, so the
severity can never quietly drift back down.

---

## 7. PATROL COVERAGE

`integration_test/recents_isolation_patrol_test.dart` — **11/11 on emulator-5554**.

Real `MemberFoodService.recents`/`remember`/`forgetRecents`, **real SharedPreferences
on the device's own disk**, real `FoodSearchController` (registered, so `onInit`
actually fires), real `AddFoodScreen`. Only `search()` is stubbed, because it is the
one call that needs a phone-OTP session, which is externally blocked on this hardware.
Identity is supplied through `cacheOwner` — the exact value a live session resolves
to — so a member switch and an org transfer happen the way the app does them: the
identity changes and the disk does not.

Covers: member switch · member switch after a crash · org switch · same-org different
member · same member (recents survive, tier badge intact) · cold start · sign-out then
sign back in · a new member building their own list on the same device · pre-repair
blob purged on sight · corrupt cache · unresolved identity in both directions.

**Two defects in my own first Patrol run, worth recording because they are the exact
failure mode §4 is about:**

1. The section header renders `text.toUpperCase()`. My assertion `$('Recent')` matched
   nothing — including the **negative** assertion, which was passing *vacuously* and
   would have stayed green with the leak on screen. Now asserts `'RECENT'`.
2. `pumpWidgetAndSettle` on a second `AddFoodScreen` at the same tree position reuses
   the old `State`, which pins its controller in `initState` — so the second mount
   silently rendered the first identity's controller. A harness artifact, not an app
   defect (the app never swaps identity under a mounted screen; sign-out destroys the
   tree). Fixed by discarding the tree between mounts.

Regression: `add_food_patrol_test.dart` re-run unchanged — **20/20**, so the
constructor change to `MemberFoodService` broke none of the existing device coverage.

---

## 8. FULL VERIFICATION

| Suite | Result |
|---|---|
| `flutter analyze` (whole project) | **0 issues** |
| `flutter test` | **1117 pass / 14 fail** — the same 14 pre-existing `home_cards_golden_test.dart` font/baseline failures, unchanged in file and count (was 1100+14; +17 is exactly this session's new suite) |
| Firestore rules, per file | **368 / 368** |
| Patrol `recents_isolation_patrol_test` | **11 / 11** on emulator-5554 |
| Patrol `add_food_patrol_test` (regression) | **20 / 20** on emulator-5554, unchanged |
| Real app, member switch on one device | **no leak**, verified on screen and on disk |

**Rules-harness note:** running all files in a single `node --test` invocation against
one shared emulator produces 6 spurious failures from cross-file `clearFirestore`
interference. Per-file, all 368 pass. Pre-existing harness property, not a rules
regression — but `scripts/test_rules.sh` runs the directory, so the suite is
currently self-interfering and should be serialized.

---

## 9. REMAINING RISKS

### Closed
- N17, in every variant reachable on this hardware.

### Open, unchanged, NOT touched by this session
- **N16 · LOW** — an archived food stays in recents and remains loggable. Same file,
  different defect (staleness, not ownership). Deliberately out of scope.
- **N14** — Home hides the nutrition card when targets exist but no plan does.
- **N6** — `nutrition_rollups` still has no reader in any of the three apps.
- **Offline logging** remains unreachable behind the app-wide connectivity takeover.
- **Nothing is deployed.** N17's repair is **client-only** — no rules, no function, no
  index — so it needs no deploy. The pre-existing backend deploy debt stands unchanged:
  `firebase deploy --only firestore:rules,functions:getMyTraining`.

### Found in passing this session
- **A prior session's temporary flag was left in the working tree**, contrary to the
  previous report's closing statement that it had been reverted:
  `login_screen.dart` held `_showPhoneAuthentication = true; // TEMP-ATTACK — REVERT`
  against a committed value of `false`. **Reverted.** Flagging the process failure,
  not just the line: a report asserted a cleanup that had not happened.
- **Cosmetic race, pre-existing:** `logFood` fires `unawaited(_foods.remember(food))`
  and `AddFoodScreen` fires `unawaited(_search.refreshRecents())`, so the refresh can
  read the disk before the write lands and the just-logged food may not appear under
  RECENT until the next screen open. Observed on device. Not N17, not data loss.

### Not verifiable here
- Multiple physical devices (one emulator).
- Google Sign-In (`idToken` null without a configured `serverClientId`).
- Midnight rollover (the emulator refuses clock changes).

---

## 10. PRODUCTION IMPACT AND FINAL DECISION

### Impact of the defect as it stands in production today

Any AlphaSerena member who signs into a device a different member used before them —
a shared family phone, a gym-floor handset, a resold or returned device — receives up
to **12** of that person's recent foods as tappable shortcuts. When the two belong to
different organizations, that includes the previous gym's **private** library: product
names, complete macro profiles and coach-authored portion definitions that
`searchMemberFoods` exists specifically to withhold. The same happens to a single
member whose coach transfers them between organizations.

The receiving member can log those foods. The write succeeds. The record lands in the
receiving organization's tenant, is read by that organization's coach, and is counted
in its analytics rollup.

Two harms, not one: a **confidentiality breach** of a paying organization's
competitive asset, and a **provenance breach** in which one gym's coach reviews a
member's intake containing a competitor's product they have never heard of.

### Decision

> ## ✅ N17 — RESOLVED
>
> Root cause identified as one cause and repaired at that cause, not at the symptom.
> Repair proven on the running application against real rules, real callables and real
> triggers — including the upgrade path, where a device already holding a leaked
> library had it destroyed on first read. Permanently guarded by 17 unit tests
> (10 of which fail without the repair), 5 rules tests and 11 Patrol tests on real
> hardware exercising the real on-device cache.
>
> **N17 no longer blocks the module freeze. N16 does, and remains open.**

**Severity correction for the record:** N17 was rated **MEDIUM / "purely the local
cache"**. It is a **HIGH** client-side data-isolation vulnerability. The reclassification
comes from one fact the previous pass did not establish: the leaked food is loggable,
and the write is accepted.

---

*Production code changed: two files (`member_food_service.dart`,
`auth_controller.dart`), plus the revert of a prior session's temporary
`login_screen.dart` flag. No backend, rules, function or index change. No deploy
required for this repair.*
