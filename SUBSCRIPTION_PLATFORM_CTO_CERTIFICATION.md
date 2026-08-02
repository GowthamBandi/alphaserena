# SUBSCRIPTION PLATFORM — CTO CERTIFICATION

**Date:** 2026-08-02 · **Scope:** Tier-1 Organization Subscription + Tier-2 Client Membership,
across `alphaserena`, `trainersHQ` and `trainershq-backend`.

**VERDICT: ⚠️ CONDITIONAL PASS — the money path is production-grade; the TRUTH layer is not.**

The payment core (signature verification, order binding, idempotency, renewal math, coupon
races) is genuinely well engineered and I found no way to steal or double-charge. The defects
are in what the app **tells the member** about their membership, and in **where entitlement is
enforced**. Nothing here loses money. Several things here lose trust.

---

## 0 · What was actually verified (evidence, not assertion)

| Check | Result |
| --- | --- |
| `flutter analyze` (alphaserena) | **0 issues** |
| `flutter test` (alphaserena) | **972 pass / 14 fail** — all 14 pre-existing `home_cards_golden` failures, documented in CLAUDE.md, unchanged by this audit |
| Backend `payments` + `expiry` + `members` + `money` unit tests | **57/57 pass** |
| New Patrol suite `membership_lifecycle_patrol_test.dart` | **16/17 assertions pass** — the 1 failure is defect **C-1** below, caught by the suite |
| Patrol on-device (emulator-5554) | ⚠️ **NOT TRUSTWORTHY** — see §9 |

Two throwaway probes were written, run, and deleted; their output is quoted verbatim below.
Everything asserted in this report was executed, not inferred.

---

## 1 · Architecture reconstruction

### Tier-2 — Client Membership (the member-facing system)

```
membershipPlans/{id}          coach-authored catalogue (adminId, price, months, isActive)
        │
        ▼  previewMembershipCoupon ──► membershipCoupons/{id}
createMembershipOrder (CF, member-only)
        │   · assertMemberCaller           · gym must be operable
        │   · server re-prices the coupon  · ₹1 charge floor
        ▼
pendingOrders/{orderId}   ← binds orderId → planId + memberUid
        │
        ▼  Razorpay native sheet (client)
verifyAndActivateMembership (CF, member-only)
        │   · HMAC-SHA256 constant-time signature check
        │   · checkOrderBinding (missing / wrong_buyer / plan_mismatch)
        │   · TRANSACTION: processedPayments/{paymentId} = idempotency key
        │   · expiry = addMonthsClamped(max(now, currentExpiry), planMonths)
        ▼
clients/{id}  { membership{}, membershipActive, membershipExpiry, membershipFrozen }
        │                       │
        │                       ├─► memberPayments/{id}   (receipt, settlementStatus)
        │                       └─► membershipCoupons/{id}/redemptions/{uid}
        ▼
MemberController (streams clients doc)
        └─► MembershipController  ── _parseExpiry ──► MembershipStatus.of ──► 8 states
```

**Server-side enforcement** lives in exactly one predicate, `lib/members.ts :: memberEntitled`,
applied at exactly **two** call sites: `getMyTraining` (`members.ts:529`) and `searchMemberFoods`
(`member_food.ts:70`).

**Scheduled jobs:** `expireMemberships` (hourly, flips the flag; skips frozen),
`membershipExpiringSweep` (daily, 7-day warning, 3-day cooldown).

### Tier-1 — Organization Subscription

```
registerAdmin → admins/{uid} { status:'pending', isSubscriptionActive:false, STARTER_LIMITS(all 0) }
        ▼  founder approves (alphaserena_admin)
createRazorpayOrder → verifyAndActivateSubscription
        │   planExpiry = addMonthsClamped(max(now, planExpiry), months)
        │   features = planFeatureProjection(plan)   ← capability whitelist
        ▼
admins/{uid} { isSubscriptionActive, planExpiry, subscriptionLimits, features }
        └─► propagateOrgActive() ──► trainers/{id}.orgActive   (chunked 450/batch)
```

Enforced in **Firestore rules** by `orgCanOperate(adminId)` — `status ∉ {pending, blocked} &&
isSubscriptionActive == true` — which gates every staff write path. This is the strongest gate
in the platform.

**Sweeps:** `expireSubscriptions` (hourly), `subscriptionExpiringSweep` (daily).
**Revocation:** `refundPayment` with `revokeAccess` resets `planExpiry` to now inside a
transaction that re-asserts the payment is still current.

---

## 2 · Lifecycle reconstruction — the states that DON'T exist

You asked me to trace Registration → **Trial** → Active → … → **Cancelled** → **Deleted**.

**Half of that lifecycle is not implemented.** Proven by exhaustive grep over
`functions/src` + `firestore.rules`: the only match for "trial" anywhere in the backend is a
comment on `STARTER_LIMITS` (`admins.ts:12`), which is a **zero-limit pending state**, not a trial.

| Requested state | Org (Tier-1) | Member (Tier-2) |
| --- | --- | --- |
| Registration | ✅ `registerAdmin`, status `pending` | ✅ implicit on first purchase |
| **Trial** | ❌ **does not exist** | ❌ **does not exist** |
| Active | ✅ | ✅ |
| Warning / Renewal due | ✅ `subscriptionExpiringSweep` | ✅ `membershipExpiringSweep` |
| Expired | ✅ hourly sweep | ✅ hourly sweep |
| Suspended | ✅ `status:'blocked'` | ✅ `membershipFrozen` |
| Reactivated | ✅ repurchase | ✅ `unfreezeMembership` / repurchase |
| **Cancelled** | ⚠️ only via founder refund | ❌ **no member-initiated cancel exists** |
| **Deleted / Archived** | ❌ no lifecycle | ❌ no lifecycle |

There is **no self-service cancellation** for either tier and **no refund path for Tier-2 at all**
(see **H-3**). For an Indian consumer subscription product this is a compliance and
app-store-review risk, not merely a feature gap.

---

## 3 · Truthfulness audit — PROVEN failures

You asked: *can the UI lie?* Yes, in four proven ways. Probe output quoted verbatim.

### 🔴 C-1 — Every expiry date and countdown is computed in the WRONG TIMEZONE

**This is the headline defect, and it affects essentially the whole user base.**

`MembershipController._parseExpiry` ([membership_controller.dart:123-129](lib/controllers/membership_controller.dart#L123-L129)):

```dart
if (v is Timestamp) return v.toDate();      // → LOCAL DateTime
if (v is String)    return DateTime.tryParse(v);  // → UTC DateTime, never converted
```

The backend **always** writes the ISO string shape (`expiry.toISOString()` in
`memberships.ts:404`, `.toUtc().toIso8601String()` in trainersHQ). So in production the parser
**always** returns a UTC `DateTime`. `MembershipStatus.formatExpiry` then reads `.day/.month/.year`
off it, and `_wholeDaysBetween` compares that **UTC calendar date against a LOCAL `DateTime.now()`**.

Probe output, on this machine (`local offset = 5:30:00.000000 (IST)`):

```
  true local expiry : 2026-12-12 02:00:00.000
  header renders    : "11 Dec 2026"        ← a full day early
  header SHOULD say : "12 Dec 2026"

  stored (UTC) -> state=endsSoon days=6 text="Ends in 6 days"
  correct(local)-> state=endsSoon days=7 text="Ends in 7 days"
```

**Impact.** For an IST member, any membership whose expiry instant falls between 18:30 and 23:59
UTC — **≈23% of all memberships, uniformly distributed by purchase time** — displays an expiry
date one day early and a countdown one day short, on Home, Profile and the Membership screen.
The error scales with offset: a member at UTC+13 sees it wrong **54%** of the time.

**Also a cross-app inconsistency:** the `Timestamp` branch returns local, the `String` branch
returns UTC, so *the same membership renders a different date depending on which app last wrote
the field*. This is what the new Patrol test `the ISO and Timestamp shapes agree` catches — it is
the suite's one failing assertion, and it is correct to fail.

**Root cause.** A parser that returns a value in an unspecified timezone, feeding formatters that
assume local. **Architectural cause:** `_parseExpiry` is the single parser (good) but it never
normalises (bad) — the type of `DateTime` is not expressive enough to carry the invariant, and no
test pinned it.

**Affected dependency graph:** `_parseExpiry` → `MembershipController.expiry` →
{`isActive`, `isExpiringSoon`, `MembershipStatus.of`} → {`HomeHeader._membershipLine`,
`client_profile_screen` "Valid till", `membership_screen` "Valid until",
`HomeController.membershipExpiryText`}.

**Not affected:** the expired/active *state* itself. Dart compares `DateTime` by absolute instant,
so `isActive` and `MembershipState.expired` remain correct. **No member is ever wrongly
entitled by this bug** — they are only ever mis-*informed*.

### 🔴 C-2 — Home contradicts itself on the same screen

Four different remaining-days formulas exist for one fact:

| Formula | Site | Method |
| --- | --- | --- |
| A | `MembershipStatus._wholeDaysBetween` | calendar-day floor |
| B | `MembershipController.isExpiringSoon` | `expiry.difference(now).inDays` |
| C | `HomeController.membershipExpiryText` | `expiry.difference(now).inDays` |
| D | trainersHQ `ClientModel.membershipDaysLeft` | `ceil(ms / day)` |

Probe output — one membership, 23 hours left, one screen:

```
PROBE 1: header : "Ends tomorrow"
         banner : "Membership expires today!"
         coach  : 1 day(s) left
```

And at the 7-day boundary (7d 23h left), the red warning banner fires while the header stays calm:

```
PROBE 2: isExpiringSoon (banner shows?) : true
         header state                   : MembershipState.active
         header text                    : "Active until 10 Aug 2026"
         banner text                    : "Membership expires in 7 days (10/8/2026)"
```

Worst case — the banner text is stuck on "today" for a full 24 h while the header moves through
three states:

```
PROBE 4: now=2026-08-02 22:00 -> header="Ends tomorrow" banner="Membership expires today!"
         now=2026-08-03 00:00 -> header="Ends today"    banner="Membership expires today!"
         now=2026-08-03 01:00 -> header="Expired"       banner="Membership expires today!"
```

**Root cause.** `MembershipStatus` was introduced as the single engine and Home's *header* and
Profile's *badge* were migrated to it — but `HomeController.membershipExpiryText` and
`isExpiringSoon` were **missed**. [client_profile_screen.dart:840-845](lib/screens/dashboard/profile/client_profile_screen.dart#L840-L845)
even documents removing "a third day-count algorithm" — the migration was correct in intent and
incomplete in execution.

`HomeController.membershipStatusLabel` is a **fifth** formula that is dead code (defined, never
rendered) — delete it.

### 🔴 C-3 — A PAUSED member is told to buy a plan they already own

`MembershipStatus` has eight states. Every **blocker** surface still gates on the raw
`isActive` boolean and collapses frozen + expired + inactive + none into one message:

| Surface | Frozen member reads |
| --- | --- |
| Home header | "Paused" ✅ |
| Home blocker card | **"Membership Inactive — Subscribe to a plan to unlock…"** ❌ |
| My Plans | `_inactiveMembershipCard` ❌ |
| Workout tab | **"Membership inactive — Renew Membership"** ❌ |
| Membership screen | pill **"Inactive"** + **"Pick a plan below to join the arena."** ❌ |

A coach freezing a membership is usually a kindness — travel, injury, a payment holiday. That
member opens the app and, sixty pixels apart, is told they are Paused and that they have no
membership and should buy one.

**It is worse than a wording bug.** If they act on that instruction, **C-4** applies.

### 🔴 C-4 — Renewal math is inconsistent between the two renewal paths

| Path | Frozen days credited? |
| --- | --- |
| Coach: `extendMembership` / `unfreezeMembership` (trainersHQ) | ✅ yes, explicitly |
| Member: `verifyAndActivateMembership` (backend) | ❌ **no** |

`renewalBaseMs(now, currentExpiry)` correctly preserves unused days, but it never reads
`membershipFrozenAt`. It also sets `membershipFrozen: false` unconditionally. So a frozen member
who follows the "Subscribe to a plan" instruction from **C-3** silently **forfeits every day they
were frozen** — the exact days the freeze existed to protect.

---

## 4 · Countdown correctness

| Question | Answer |
| --- | --- |
| Can days go negative? | **No.** All four formulas are gated behind an active state first. |
| Can expired show "0 days left"? | **No** on the header (`endsToday` is its own state); **yes** on the banner ("expires today!" for anything < 24 h) — see C-2. |
| Leap year / month-end? | ✅ **Correct.** `addMonthsClamped` (both TS and Dart copies) clamps Jan 31 + 1mo → Feb 28/29. Verified by the 57 passing backend unit tests. |
| DST? | Low risk — India has no DST. Would compound C-1 elsewhere. |
| Who owns expiry? | **The server**, correctly — computed in `verifyAndActivateMembership`, never accepted from the client. |
| Who owns "is it expired"? | **Split.** Server for reads (`memberEntitled`), device clock for UI. See S-2. |

---

## 5 · Feature gating — where enforcement actually is

### Organization (Tier-1) — ✅ **strong**

`orgCanOperate()` is enforced in **Firestore rules**, so it holds against a bypassed UI, a direct
REST call, or a forged client. `propagateOrgActive` cascades to trainers. This is correct design.

### Client (Tier-2) — ⚠️ **read-gated, write-open**

| Member action | UI blocks? | Server blocks? |
| --- | --- | --- |
| View workout / diet | ✅ | ✅ `getMyTraining` → `memberEntitled` |
| Search coach's food library | ✅ | ✅ `searchMemberFoods` → `memberEntitled` |
| Voice/video call coach | ✅ | ✅ rules check `membershipActive && !frozen` |
| **Log a workout session** | ✅ | ❌ **rules check ownership only** |
| **Log food** (`client_nutrition_days`) | ✅ | ❌ **ownership only** |
| **Log diet adherence** | ✅ | ❌ **ownership only** |
| **Log progress / upload photos** | ✅ | ❌ **ownership only** |
| **Submit check-ins** | ✅ | ❌ **ownership only** |
| **Chat with coach** | — | ❌ ownership only (**deliberate**, documented in rules) |

Verified by reading the rule blocks at `firestore.rules:1151` (`client_workout_sessions`),
`:1201` (`client_nutrition_days`), `:1426` (`client_progress`), `:1343`
(`client_check_in_submissions`). **None reference `membershipActive`, `membershipExpiry` or
`membershipFrozen`.**

**Consequence:** an expired member's write surfaces are enforced by UI only. Chat staying open is
a defensible product decision; storage-consuming writes (progress photos) and coach-queue-polluting
writes (check-ins, sessions) are not.

### 🟠 H-2 — `memberEntitled` fails OPEN

```ts
if (d.membershipFrozen === true) return false;
if (d.membershipActive === false) return false;
const exp = toMillis(d.membershipExpiry);
if (exp > 0 && exp < Date.now()) return false;
return true;                        // ← absent fields ⇒ ENTITLED
```

A `clients` doc with **no membership fields at all** is fully entitled. Documented as legacy
safety, and safe today because purchase always writes the fields — but any future path that
creates a client without them grants free coaching platform-wide. This is a
**security-critical default in the wrong direction**; it should fail closed with an explicit
legacy allowlist.

---

## 6 · Security certification

**Attempted and could not break:**

| Attack | Blocked by |
| --- | --- |
| Forge a payment signature | HMAC-SHA256 + `crypto.timingSafeEqual` — **constant-time**, with an explicit length guard. Correct. |
| Pay for the cheap plan, activate the expensive one | `checkOrderBinding` pins orderId → planId + buyerUid at creation |
| Replay a payment | `processedPayments/{paymentId}` created **inside the transaction** |
| Claim someone else's order | `wrong_buyer` branch |
| Set your own expiry / months | Read from the plan doc server-side; client input ignored |
| Coupon over-redemption race | Re-read **inside** the txn; over-limit is flagged (`overRedeemed`) rather than rejected after the member has paid — **correct call**, the money already moved |
| Coach buying a member plan | `assertMemberCaller` on both money callables |
| Free membership via 100% coupon | ₹1 floor in `priceMembershipDiscount` |
| Tamper `clientProfiles.linkedClientId` to read another member | `linkedClientUsable` verifies `authUid == caller` |

The money path is the strongest part of this platform. I have no findings against it.

### 🟠 S-2 — Device clock is the client-side entitlement clock

`isActive`, `isExpiringSoon` and `MembershipStatus.of` all call `DateTime.now()`.

Rolling the device clock **back** flips `isActive` to true and unlocks the UI. The server still
refuses (`getMyTraining` → `memberEntitled` uses server time), so **no content leaks**. But the
member then sees the *wrong empty state*: `_membershipInactive` is false, so the Workout tab falls
through to `_empty()` — **"No workout assigned yet · Your trainer will assign one soon."** An
honest "renew" screen degrades into a lie about the coach. Low severity, but it converts a
security non-event into a support ticket blaming the coach.

### 🟡 S-3 — `previewMembershipCoupon` uses `assertSignedIn`, not `assertMemberCaller`

Inconsistent with `createMembershipOrder` alongside it. No money moves, but it lets any signed-in
account (including a coach) enumerate coupon validity for any plan.

### 🟡 S-4 — `pendingOrders.consumed` is written but never checked

`checkOrderBinding` validates buyer and plan but not `consumed`. Currently unexploitable —
a second activation needs a second Razorpay-signed `paymentId` for the same order — but the
flag exists specifically to express single-use and is not enforced. Defence in depth is missing.

---

## 7 · Firestore rules audit

✅ **Correct:** `orgCanOperate` is existence- and field-based (negation-safe — the `isSuperAdmin()`
trap documented in CLAUDE.md is genuinely avoided here); `membershipPlans` are coach-write /
member-read; `memberPayments` receipts are server-written; the calls gate checks freeze state.

⚠️ **Gaps:**
1. Member logging collections carry **no membership predicate** (§5).
2. The calls gate checks `membershipActive` but **not `membershipExpiry`** — during the ≤1 h window
   before the hourly sweep, a just-expired member can still initiate a call.
3. `clients` membership fields are directly writable by the operating admin
   (`firestore.rules:958`, `:1003`) — which is what makes freeze/extend a client-side write
   (see **H-1**).

---

## 8 · Cloud Functions audit

✅ Transactions used where they matter. ✅ Idempotency keyed correctly. ✅ Sweeps page by
`documentId()` (index-free, no full-set load, self-healing on timeout — genuinely good design for
10 k+ rosters). ✅ Best-effort notifications never block the money path. ✅ Chunked batch writes
respect the 500-op cap.

### 🟠 H-1 — Freeze / unfreeze / extend are CLIENT-SIDE writes with client-side math

[`memberships_controller.dart:116-218`](../trainersHQ/lib/features/memberships/controllers/memberships_controller.dart) —
the coach app writes `membershipExpiry`, `membershipActive`, `membershipFrozen` **directly**, and
computes credited frozen days from `DateTime.now()` on the coach's device.

Consequences:
- **No audit trail.** Every server-driven transition writes to `auditLogs`; a coach extending a
  membership by 12 months writes nothing. For a billing system this is a gap.
- **No idempotency.** A double-tap in a bad network is two extensions.
- **Device-clock dependent.** A coach with a wrong clock mis-credits frozen days.
- **`membershipFrozenAt` is written WITHOUT a timezone** (`DateTime.now().toIso8601String()`,
  line 173) while every sibling write uses `.toUtc()`. Dart parses it back as local; Node would
  parse it as UTC. Latent only — the server never reads this field today — but it is a trap the
  next backend feature will step in.

**Root cause:** the controller's own comment states the design — *"All actions are DIRECT writes …
so no Cloud Function is needed."* That was a reasonable velocity trade at the time. It is not
appropriate for the fields that define entitlement.

### 🔴 H-3 — There is NO Tier-2 refund path

`refundPayment` touches `admin_payments_history` and `admins` only. Grep confirms **nothing**
in `functions/src` ever refunds a `memberPayments` receipt or deactivates a membership on refund.

A member refunded through the Razorpay dashboard keeps `membershipActive: true` and their full
expiry — they train free until natural expiry, the coach's earnings still count the payment, and
`settlementStatus` still says `pending`, so **the platform may settle refunded money to the coach's
bank**. This is a real financial-reconciliation hole, not a UX one.

---

## 9 · Patrol certification — HONEST RESULT

I wrote [`integration_test/membership_lifecycle_patrol_test.dart`](integration_test/membership_lifecycle_patrol_test.dart)
(17 tests). It deliberately **drives the real engine from raw `clients` document maps** —
Timestamp parsing included — rather than handing the widget a fixture, because CLAUDE.md
identifies that fixture habit as the reason the workout-consistency defect survived every prior
certification. It mounts the real production `HeaderView`.

**Result under `flutter test`: 16/17 pass.** The single failure is **C-1**, which the suite
caught unaided. That is the suite doing its job; the assertion is correct and should stay red
until C-1 is fixed.

**Result on emulator-5554: ⚠️ NOT TRUSTWORTHY, and I will not certify it.**

Successive runs produced mutually inconsistent output: one run executed my 11 lifecycle tests
(9 pass, 2 fail with a **null** Dart assertion message), and three subsequent runs executed
`team_roster_device_test.dart` — a suite that **does not exist in this repository**. I located it
at `trainersHQ/patrol_test/team_roster_device_test.dart`. A stale/shared build artifact is
leaking another project's Patrol bundle into this project's APK. `patrol_test/test_bundle.dart`
regenerates correctly; the contamination is downstream of it.

The two on-device failures show `AssertionError: Dart test failed … null` — a null message is the
signature of the native runner requesting a test the loaded Dart bundle doesn't contain, i.e. the
same contamination. **Both reproduce as PASSING in a widget test**, so I believe they are
artifacts, not defects — but I could not prove that, and I am not going to certify a green run I
don't trust.

**To resolve:** `flutter clean && flutter pub get`, then re-run. I began this and stopped when you
interrupted, so it remains outstanding. **Phase 8 is INCOMPLETE.**

---

## 10 · Performance findings

### 🟠 P-1 — A permanent listener on a collection almost nobody is looking at

`MembershipController` is `Get.put` **eagerly on dashboard load**
([dashboard_screen.dart:45](lib/screens/dashboard/dashboard_screen.dart#L45)) and immediately
opens `.snapshots()` on `membershipPlans where adminId == X` — the coach's plan **catalogue** —
for the member's entire session. Those plans render on exactly two screens (Membership, Storefront).

At a 10 000-member coach that is 10 000 permanently open listeners on one small collection, plus a
re-delivery to every one of them on every plan edit. The membership **status** the dashboard
actually needs comes from `MemberController`'s `clients` doc, which is already streamed.

**Fix:** make the plans query lazy (`CoachService.watchPlans` on the screens that render plans);
keep the controller for status only. This is the same class of defect the team already fixed for
`DietLogController` — the comment three lines below documents removing exactly this pattern.

### 🟡 P-2 — `CoachService.hasActiveMembership` is an unindexed collection-group-ish scan

Runs on **every** cold start via the routing gate: `clients where authUid == uid` with no limit,
then filters in Dart. Bounded by memberships-per-member (small) — acceptable, but it is on the
critical startup path and re-reads on every launch.

---

## 11 · Consistency audit

**Duplicated logic found — there is not one definition of anything:**

| Concept | Copies |
| --- | --- |
| Remaining days | **5** (4 live + 1 dead) — §3 C-2 |
| Membership state machine | **2** — `MembershipStatus` (8 states, alphaserena) vs `ClientModel.membershipStatus` (5 states, trainersHQ), with different boundary maths |
| "Is this member entitled?" | **3** — `memberEntitled` (TS), `MembershipController.isActive` (Dart), `CoachService.hasActiveMembership` (Dart, and it **omits the freeze check**) |
| Add-months-clamped | **2** — `lib/dates.ts` and `memberships_controller.dart`, correctly twinned, no drift found ✅ |
| Renewal base | **2** — `renewalBaseMs` (TS) vs `extendMembership` (Dart), **and they disagree on frozen days** (C-4) |

---

## 12 · Product gaps for enterprise

- No trial (§2) — the single biggest commercial gap for a SaaS.
- No self-service cancellation, either tier.
- No proration, no plan upgrade/downgrade — only "extend by N months".
- No auto-renew / saved mandate. Every renewal is a manual repurchase, so churn is structural.
- No dunning: one 7-day notice at a 3-day cooldown, then silence.
- No grace period. Expiry is a hard cliff at the instant.
- No member-visible billing history (`memberPayments` has no member-facing screen).
- No invoice / GST receipt — a legal requirement for Indian B2C.
- No audit trail for coach-side membership actions (**H-1**).

---

## 13 · Recommendations, ranked

### CRITICAL — fix before any production billing
1. **C-1** Normalise timezone in `_parseExpiry`: `return DateTime.tryParse(v)?.toLocal();` and
   `v.toDate()` is already local. One line, plus a pinned test. Fixes every date and countdown
   in the app.
2. **C-2** Delete `HomeController.membershipExpiryText` and `membershipStatusLabel`; drive the
   banner from `MembershipStatus`. Move `isExpiringSoon` onto `status.state` so the gate and the
   text can never disagree.
3. **C-3** Route every blocker card through `MembershipStatus`; give `frozen` its own copy
   ("Paused by your coach — no action needed") with **no buy CTA**.
4. **C-4** Credit `membershipFrozenAt` in `verifyAndActivateMembership`'s renewal base.
5. **H-3** Build the Tier-2 refund path, or at minimum block settlement of refunded
   `memberPayments`.

### HIGH
6. **H-1** Move freeze/unfreeze/extend behind a Cloud Function with audit + idempotency.
7. **H-2** Make `memberEntitled` fail closed.
8. **§5** Add a membership predicate to the member logging rules (keep chat open, deliberately).
9. **§9** Resolve the Patrol build contamination and complete Phase 8.

### MEDIUM
10. **P-1** Make the plans listener lazy.
11. Add `membershipExpiry` to the calls rule gate (closes the ≤1 h window).
12. **S-4** Enforce `pendingOrders.consumed`.
13. Unify the two membership state machines into one shared definition.

### LOW
14. **S-3** `assertMemberCaller` on `previewMembershipCoupon`.
15. `membershipFrozenAt` → `.toUtc()`.
16. **S-2** Show the renew state whenever the server serves null and membership is not provably
    active, so a skewed clock can't produce "your trainer will assign one soon".

---

## 14 · Production readiness score

| Dimension | Score | Note |
| --- | --- | --- |
| Money path & payment security | **9.5 / 10** | Genuinely excellent |
| Backend architecture & sweeps | **8.5 / 10** | Well-designed, scale-aware |
| Firestore rules (Tier-1) | **9 / 10** | Strong, negation-safe |
| Firestore rules (Tier-2) | **5 / 10** | Reads gated, writes open |
| **Truthfulness of the UI** | **3 / 10** | C-1 + C-2 + C-3 |
| Consistency / single source of truth | **4 / 10** | 5 day-counters, 3 entitlement checks |
| Lifecycle completeness | **4 / 10** | No trial, no cancel, no refund (T2) |
| Verification coverage | **6 / 10** | Strong unit; Patrol incomplete |
| Performance at scale | **7 / 10** | P-1 is the one real cost defect |

**Overall: 6.2 / 10 — CONDITIONAL PASS.**

**Certification verdict:** Approved to **continue operating** — no member can be defrauded and no
content leaks to an unentitled member. **NOT approved for scale-up marketing or enterprise sale**
until CRITICAL 1–5 are closed. C-1 alone mis-states the expiry date for roughly a quarter of your
members, every day, and C-3 actively instructs paused members to pay again for time they already
own.

---

## What I did not audit

Stated explicitly so this report is not read as broader than it is:

- `alphaserena_admin` (founder console) — not opened.
- The full 2 700-line ruleset — I audited the subscription-relevant gates only.
- 80+ backend functions unrelated to billing.
- Real load testing at 1 k / 10 k members — P-1/P-2 are static analysis, not profiling.
- Live Razorpay sandbox transaction — the money path was verified by code + the 57 unit tests.
- iOS — all device work targeted Android.
