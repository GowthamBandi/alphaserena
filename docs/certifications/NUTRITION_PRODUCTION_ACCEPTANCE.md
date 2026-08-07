# ALPHASERENA — NUTRITION MODULE
# CTO PRODUCTION ACCEPTANCE REPORT
# FREEZE GATE — **NOT APPROVED**

**Date:** 2026-08-03
**Method:** the real application, driven as a real member on emulator-5554, against
a real backend (real rules, real Cloud Functions, real Firestore, real signed-in
session). No fixture controllers, no injected repositories, no mocked services.

---

## 1. EXECUTIVE SUMMARY

**The gate condition was not met. Two reproducible runtime defects were found,
so the module cannot be frozen.**

The gate was: *approve only if you cannot reproduce another runtime defect under
real usage.* I reproduced two, both in the **food "Recents" cache**, both sharing
one root cause: **recents is a frozen device-local snapshot that is never
invalidated — not when a coach archives a food, and not when the member changes
organization.**

| ID | Severity | Defect |
|---|---|---|
| **N17** | **MEDIUM** | `forgetRecents()` is dead code. After an org transfer, the PREVIOUS gym's private org-tier foods stay in Recents, badged **"Your coach's"**, and remain loggable. |
| **N16** | **LOW** | A food the coach ARCHIVES stays in Recents and remains loggable indefinitely. Search excludes it; Recents does not. |

Neither corrupts data and neither is a Firestore rules breach — server-side tier
isolation is provably intact (ALL FOODS correctly showed only global foods after
the transfer). The leak is entirely in the local cache. But N17 means a coach's
private library follows a member to a competitor's gym, mislabelled as the new
coach's, and the **new** coach receives logs of a food from an organization they
have nothing to do with.

**Everything else I attacked held.** The core loop is genuinely solid: portion
math was exact at every multiplier tested, edit/delete/undo preserved entry
identity, the org-transfer repair (N9) held under the exact restart-then-write
sequence that used to deny writes for a whole day, and Home / My Plans / Diet /
Firestore / Cloud Function reconciled to the decimal at every step.

---

## 2. TRAINERHQ VERIFICATION

Driven through the **real callables and real documents**, not the coach Flutter
UI (stated plainly — the TrainerHQ app itself remains unexercised).

| Action | Result |
|---|---|
| `setNutritionTargets` (coach-authed callable) | ✅ versioned `nutritionTargets` v1 + legacy `dietTargets` mirror, in one txn |
| Assign diet plan (`planType:'diet'`, `status:'active'`) | ✅ served; items hydrated from the food library |
| **Pause** diet | ✅ plan withdrawn → "Pending Assignment"… |
| …targets after pause | ✅ **survive** — ring stayed 2000 kcal (H2 working as designed) |
| Archive a food | ✅ removed from member search · ❌ **still in Recents (N16)** |
| Coach edit propagation | ⚠️ `getMyTraining` is a callable, not a listener — a mid-session assignment needs an app reload. Correct by design, worth knowing. |

## 3. ALPHASERENA VERIFICATION

`flutter analyze` **clean** · `flutter test` **1 100 pass / 14 fail** — all 14 in
`home_cards_golden_test.dart`, the documented pre-existing font/golden baseline,
unchanged in file and count.

## 4–6. BACKEND · FIRESTORE · CLOUD FUNCTION VERIFICATION

- **Backend:** 1 027 / 1 027 (tsc + node:test).
- **Trigger chain, live, after every single mutation:** `computed.totals`,
  `computed.targetAdherence`, `entryCount` and the `nutrition_rollups` month
  cell were recomputed correctly on add, edit, delete AND undo.
- **Arithmetic, verified at five multipliers:**

  | Action | Expected | Stored |
  |---|---|---|
  | 0.5 egg (25 g of 155/100) | 38.75 | **38.8** |
  | 2 egg (100 g) | — | **155.2** (see §14) |
  | 1 katori rice (150 g of 130/100) | 195 | **195** |
  | 1.5 katori rice (225 g) | 292.5 | **292.5** |
  | 1 katori paneer (150 g of 250/100) | 375 | **375** |

  Final day: 155.2 + 292.5 + 375 = **822.7** ✅ · adherence 0.411 = 822.7/2000 ✅

## 7. FOOD DATABASE VERIFICATION

- **Two-tier search:** `""` → org first then global; `rice`/`basmati` → global
  only; `paneer` → org only. Org-wins ordering correct.
- **Tier signalling:** "Your coach's" (org) vs "Verified" (global `official`) vs
  "Library" on logged entries — all correct.
- **Archived food excluded from search** ✅ — but **not from Recents (N16)** ❌.
- **Empty state** is helpful and honest ("No foods match … try a shorter word").
- ⚠️ **Global tier has no legacy fallback.** The org tier has an explicit
  fallback scan for libraries predating `searchTokens`; global has none, so a
  global food with missing tokens is invisible with no recovery path.

## 8. MEAL BUILDER VERIFICATION

Plan items serve with macros hydrated from the library (Paneer 375 / Rice 195 at
150 g each) and group by the item's `meal` field. Coach description carried
through. Not exercised: authoring UI, weekly day-plans, plan replacement.

## 9. NUTRITION TARGETS VERIFICATION

- Served **top-level** (`nutritionTargets`) and **plan-embedded**
  (`diet.targets`) — verified **byte-identical** at runtime, confirming the
  shared `servedTargetsWire` producer prevents drift.
- **Survive having no plan** and **survive a plan pause** — both observed live.
  This is the H2 repair holding under two distinct conditions.

## 10. HOME VERIFICATION

Ring and all four macros matched Firestore and the Cloud Function exactly
(375 / 2000, 27/150 P, 9/200 C, 27/60 F, 1.5/30 fiber in the earlier pass).
Subtitle logic correct. **Known gap: N14** — with targets but no plan, Home
renders the Getting-Started card and hides the nutrition card entirely, while My
Plans shows it. Still open; still a product decision.

## 11. FOOD LOGGING VERIFICATION

| Workflow | Result |
|---|---|
| Breakfast / Lunch / Dinner, meal auto-selected by time | ✅ |
| Canonical meal ordering, per-meal kcal + timestamp | ✅ |
| Half serving (0.5) | ✅ 39 kcal, exact |
| **Minus clamped at 0.5** — never 0, never negative | ✅ |
| Multi-portion (katori / cup / grams) | ✅ |
| Edit → same `entryId` rewritten | ✅ |
| Delete (swipe) → soft delete + Undo snackbar | ✅ |
| **Undo → SAME `entryId` restored**, not re-created | ✅ |
| Rapid double-tap submit → exactly 1 entry | ✅ |
| Recents populated, most-recent-first | ✅ (but see N16/N17) |
| **Offline logging** | ⛔ **impossible by design** — see §17 |

## 12. HISTORY VERIFICATION

Three consecutive days rendered with correct relative labels
(Yesterday / Saturday / Friday) and **average 1917 kcal = (1700+2100+1950)/3**,
denominated over *logged* days only. The 45-day-gap traversal (H3) was proven in
the prior pass and its regression test stands.

## 13. ANALYTICS VERIFICATION

⚠️ **Unchanged and unresolved.** `nutrition_rollups` is written correctly on
every mutation and **still has no reader in any of the three apps**. The pipeline
remains write-only (prior audit's N6). No coach analytics surface consumes it,
so "trainer analytics reconcile" cannot be asserted — there is nothing to
reconcile against.

## 14. PERFORMANCE VERIFICATION

- **One controller, one listener.** All six `Get.put(FoodLogController)` sites
  are guarded by `Get.isRegistered`, so a single instance serves Home, My Plans,
  Diet and Add Food — corroborated by every screen showing identical values
  simultaneously.
- **No listener churn.** The N15 repair's `_liveBound` guard prevents
  re-subscribing on every `clients` snapshot (pinned by regression test).
- **Reconnect is clean** — no duplicate listeners, no stale state, no data loss
  after airplane-mode on/off.
- 🟡 **Technical debt — rounding drift on edit.** Editing scales the *frozen
  snapshot* rather than recomputing from per-100 (0.5 egg → 38.8, then ×4 →
  **155.2** where a fresh 2-egg log would be 155.0). Defensible (it preserves
  what the member actually recorded even if the coach later edits the food) and
  invisible to the member (display rounds to 155), but repeated edits compound
  the error.

## 15. SECURITY VERIFICATION

- **Rules: 386 / 386** on a real emulator.
- **Tenancy isolation intact server-side:** after transferring the member to a
  new org, `searchMemberFoods` correctly returned only global foods — the
  previous org's private foods were NOT served. The N17 leak is purely the local
  cache, not a rules or query failure.
- **Identity immutability holds:** the day document kept `adminId: coach-uid-1`
  while `clients.adminId` was `coach-uid-2`, and an edit still succeeded — the
  N9 repair, proven under the exact restart-then-write sequence that previously
  denied writes for the remainder of the day.

## 16. PATROL VERIFICATION

Unchanged from the prior pass (52/52). **Not expanded this session** — Patrol
could not have caught N16 or N17 either, because both require a *server-side
state change* (archive / org transfer) landing against a *device-local cache*,
which fixture-injected controllers do not model. The honest guard for these is a
unit test around recents invalidation, not a Patrol test.

---

## 17. REMAINING RISKS

### Confirmed defects (block the freeze)
- **N17 · MEDIUM** — `forgetRecents()` has **zero call sites**. Previous org's
  private foods persist in Recents after transfer, mislabelled "Your coach's",
  and are loggable. *Minimal fix: invoke the existing function when
  `clients.adminId` changes.*
- **N16 · LOW** — archived foods stay loggable from Recents. *Minimal fix:
  re-validate cached recents against served food status.*

### Product decisions (unchanged, still open)
- **N14** — Home hides the nutrition card when targets exist but no plan does.
- **N6** — write-only rollup pipeline: wire coach analytics to
  `nutrition_rollups`, or mark the trigger explicitly forward-looking.
- **Offline logging is not supported.** The app-wide connectivity takeover
  replaces the entire UI when offline, so a member *cannot reach* the log screen.
  Consequence: the nutrition module's documented `DietSaveResult.queued` path,
  its 4 s `ackTimeout` and its "saved on this device" messaging are
  **unreachable from a genuinely offline device**. Either accept and delete the
  dead path, or exempt logging from the takeover. Currently it is implied-live
  and is not.

### Technical debt
- Rounding drift on repeated edits (§14).
- Global food tier has no legacy/no-token fallback (§7).
- N7 (dead legacy repos + stale docs), N8 (unbounded streak query), N10, N12, N13
  — all carried forward unchanged.

### Out of scope / not verifiable here
- **Midnight rollover** — the emulator refuses date changes even after
  `adb root`; day-scoping was verified indirectly via consecutive days.
- **Multiple devices** — one emulator available.
- **TrainerHQ Flutter UI** — coach side driven via real callables/documents only.
- **Google Sign-In**, the actual production auth path — cannot complete locally
  (`idToken` null without a configured `serverClientId`). Still unvalidated.

---

## 18. PRODUCTION READINESS

### ⛔ FREEZE NOT APPROVED

Two runtime defects were reproduced, so the stated gate fails. N17 is the one
that matters: it is a cross-organization leak of a coach's private library into
a competitor's context, and the function written to prevent it exists, is
documented, and is never called.

**Also still blocking, from prior passes and unchanged:** nothing is deployed.

```bash
firebase deploy --only firestore:rules,functions:getMyTraining
```

Until that runs, **N1 is live in production** (every member's empty day denies
its read) and H2 is unserved. Answer **NO** to any prompt offering to delete
indexes.

### What I could not break

Worth recording, because it is most of the module: portion math at five
multipliers, quantity clamping, meal taxonomy, edit/delete/undo entry identity,
duplicate-tap protection, reconnect recovery, org-transfer writes, pause-safe
targets, two-tier search isolation, single-listener lifecycle, and exact
Home ↔ My Plans ↔ Diet ↔ Firestore ↔ Cloud Function reconciliation at every
mutation. The core loop is sound. The defects are at its edges — in a cache that
nothing invalidates.

### Recommended path to freeze
1. Fix **N17** (wire up `forgetRecents()`) and **N16** (validate cached recents).
2. Decide **N14** and the **offline-logging** contradiction.
3. Deploy, then re-run this acceptance pass against the deployed backend.
4. Validate **Google Sign-In** and **midnight rollover** on hardware that permits
   a clock change.

*No production code was modified in this session. The temporary
`_showPhoneAuthentication` flag used to obtain a member session has been
reverted to `false`; suites re-verified green afterwards.*
