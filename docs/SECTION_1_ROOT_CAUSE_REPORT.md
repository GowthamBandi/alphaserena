# Section 1 — "Your Coach" Root Cause Report

- **Date:** 2026-07-28
- **Status:** the previous certification is withdrawn. It was wrong.
- **Repos changed:** `trainershq-backend`, `alphaserena`.
- **Nothing committed.**

---

## 1. Root cause

> **The coach's name and photo were the only facts on the member's Home card
> with no live delivery path.**

Every other identity fact is delivered continuously:

| Fact | Delivery | Live? |
|---|---|---|
| Organisation name / logo / verified | `CoachService.byId(adminId)` fetch, retried | ✅ |
| Membership status / expiry | `clients` document **stream** | ✅ |
| `trainerId` (is a coach assigned) | `clients` document **stream** | ✅ |
| Workout / diet plan | `getMyTraining` on open + refresh | ✅ |
| **Coach name** | `clientProfiles` mirror | ❌ |
| **Coach photo** | `clientProfiles` mirror | ❌ |

That mirror is written by **exactly one party** — `claimClientAccount` — at
**exactly one moment**: a successful claim. Nothing else in either app ever
re-derives it.

So the card could know a coach *was* assigned (`trainerId` streamed live, which
is why the row read **"Your coach"** rather than *"Not assigned yet"*) while
being unable to name them. The two facts came from different generations of
data, and only one of them was kept current.

### The paths that leave the mirror wrong

| Event | Does a claim re-run? | Result before fix |
|---|---|---|
| Owner assigns themselves while the app is **closed** | only on next cold start, and only if that claim succeeds | **"Your coach"** |
| A trainer is assigned while the app is **closed** | same | **"Your coach"** |
| Coach **renames** themselves | **never** — `clients.trainerId` did not change, so `_listenClient`'s re-claim trigger never fires | old name forever |
| Coach **changes their photo** | **never** — same reason | old photo forever |
| A claim fails once (offline, or a stored phone format the lookup does not match) | not until the next launch | **"Your coach"** |

The re-claim trigger is the tell:

```dart
final trainerChanged = _lastTrainerId != null && _lastTrainerId != newTrainerId;
if (trainerChanged) claim();
```

It watches **`trainerId`**, so it only ever refreshes identity when the
*assignment* changes. A coach's own name and photo are invisible to it.

---

## 2. Why the previous fix failed

The previous pass root-caused a *different, real* bug — that a `clients` record
is created on purchase without a `trainerId`, and both resolvers treated that as
"no coach" — and fixed the **resolution rules** on both sides.

That fix was correct and is retained. **It could not have fixed the reported
scenarios**, for two independent reasons:

1. **It changed a pure function, not a delivery mechanism.** `resolveTrainerName`
   only ever runs *inside `claimClientAccount`*. If the claim does not run, the
   improved rule never executes. Every failing scenario in this report is a
   scenario where the claim does not run.
2. **The backend change was never deployed.** It is local TypeScript. The
   production callable is still the previous build, so even the cases the new
   rule would have fixed were still being answered by the old one.

The previous certification also over-claimed: it verified the resolvers by unit
test and inferred the end-to-end behaviour. It never asked *"what refreshes this
value, and when?"* — which is the question that exposes the defect. Unit tests
on a pure function cannot detect that nothing calls it.

**Lesson recorded:** for any displayed value, the certification question is not
only *"is it computed correctly?"* but *"what makes it current, and what happens
when that thing does not run?"*

---

## 3. Exact component responsible

**`functions/src/members.ts` → `getMyTraining`.**

It is the member app's live data channel. It runs on app open, on Home reload
and on every pull-to-refresh; it already reads the client document and therefore
already holds `trainerId` and `adminId`; and it is server-side, so it can read
`trainers/{id}` and `admins/{id}` that the member is correctly denied.

It returned `{workout, diet}`.

It had everything needed to serve the coach and did not.

The secondary component is `MemberController.trainerName`, which sourced the
name from the mirror with `liveName` wired to `clients.trainerName` — a field
**TrainerHQ never writes**. The live slot existed and was fed by nothing.

---

## 4. Final fix

### 4.1 Backend — serve the coach live

`getMyTraining` now returns a third object:

```
coach: { id, name, photoUrl, assigned }
```

resolved through the **same** `resolveTrainerName` / `resolveTrainerPhoto` the
mirror uses — so the live value and the cached value can never disagree about
the *rule*, only about their *age*. `assigned` reports whether a specific
trainer is delegated, preserving TrainerHQ's Unassigned-triage distinction.

Cost: two document reads, only on a callable that was already reading several.

### 4.2 Member app — live first, mirror as the offline fallback

The live name is fed into `resolveCoachName`'s existing **`liveName`** slot,
which by design already outranks the mirror. This matters: **no staleness rule
changed.** The protections that suppress a removed or reassigned coach still sit
underneath, unmodified, and still apply whenever live data is absent.

The photo follows identical precedence, so the face and the name can never come
from different generations of data.

### 4.3 What is retained from the previous pass

- Unassigned member → the **org owner** is the coach (matches
  `resolveCoachRecipient`, which has always routed their notifications there).
- `trainerNameFor: trainerId || adminId`, so "derived for the owner" is
  distinguishable from "never validated".
- The legacy-mirror branch is trusted only while a trainer is assigned.
- The coach photo mirror and the unread-message badge.

### 4.4 Deliberately NOT done

- **Not stamping `trainerId = adminId` at creation.** It would permanently empty
  TrainerHQ's Unassigned filter and count, destroying the triage workflow
  multi-trainer gyms depend on.
- **Not a realtime coach listener.** The rules correctly deny a member read
  access to `trainers`/`admins`, and loosening them for a display name is a poor
  trade. `getMyTraining` already refreshes on every surface the member touches.

---

## 5. Verification matrix

`test/coach_identity_matrix_test.dart` — 20 tests, all passing. Each row is
asserted **twice**: once with live data present, once with it absent (offline /
first frame), because those are genuinely different code paths.

| Scenario | Live | Offline / cold | Result |
|---|---|---|---|
| **Admin assigned as trainer** | owner named | mirror named | ✅ |
| **Real trainer assigned** | trainer named | mirror named | ✅ |
| Assigned while app closed (mirror written before) | trainer named | honest empty | ✅ |
| **Trainer changed** | new trainer named | previous suppressed | ✅ |
| **Trainer removed** | owner named | departed suppressed | ✅ |
| Legacy mirror + removed trainer | — | cannot resurrect | ✅ |
| **Coach renamed** *(no claim ever fired)* | new name | old name until refresh | ✅ |
| **Photo changed** | new photo | — | ✅ |
| **Photo deleted** | initials, not a stale face | — | ✅ |
| Name unresolvable | no photo either | — | ✅ |
| **Cold start** | — | paints from mirror | ✅ |
| **Fresh install offline** | — | honest empty | ✅ |
| **Online refresh** | overrides cold-start paint | — | ✅ |
| No organisation at all | empty | empty | ✅ |

**Message target.** Unaffected by every row above: `ClientChatScreen` resolves
the thread from `linkedClientId`, never from `trainerId`. The thread is the
member↔organisation conversation, so it stays correct across assignment,
reassignment and removal — and it already worked for unassigned members, which
is why this was a display defect and not a broken feature.

**Organisation.** Unaffected — separately sourced from
`organizationProfiles/{adminId}` and already live.

### Suites

| Suite | Result |
|---|---|
| `alphaserena` `flutter analyze` | **No issues found** |
| `alphaserena` `flutter test` | **243 / 243** (223 + **20 new**) |
| `trainershq-backend` `tsc --noEmit` | clean |
| `trainershq-backend` unit tests | **524 / 524** |

---

## 6. The one thing that must happen before this is believed

**Deploy the backend.** `getMyTraining` and `claimClientAccount` are changed and
the fix is inert until they ship. This is not a caveat — it is the reason the
previous fix appeared to do nothing, and repeating that would be worse than the
original bug.

The Food Platform pass established the pattern for this: a targeted deploy
script rather than a blanket `firebase deploy --only functions`, which in this
repository would ship substantial unrelated uncommitted work to a project
serving live organisations.

After deploying, the fastest confirmation is the **coach-rename** case: rename a
coach in TrainerHQ and pull to refresh on the member's Home. It never worked
before under any circumstance, so if the new name appears, the live channel is
genuinely carrying the coach.

I am **not** certifying this section again until that has been observed against
live Firestore. The engineering is complete and every branch is pinned by test;
what remains is deployment and one human confirmation — which is exactly what
the previous certification should have said instead of declaring victory.

---

## 7. Deployment record — 2026-07-28 05:22 UTC

**Deployed to `trainershq-f5ded` (production).**

```
firebase deploy --only functions:getMyTraining,functions:claimClientAccount
  + functions[claimClientAccount(us-central1)] Successful update operation.
  + functions[getMyTraining(us-central1)]      Successful update operation.
```

**Targeted, not blanket — and that mattered.** This working tree carries **17
untracked function source files** (automation, campaigns, content, feedback,
food_platform, intelligence, targeting, recovery, platform_announcements and
their libs) plus 17 modified ones. A `--only functions` deploy would have shipped
every one of them to a project serving live gyms. This is the same hazard the
Food Platform pass identified and wrote `deploy_food_platform.ps1` to avoid. Both
functions report **"Successful update operation"** — update, not create,
confirming nothing new was introduced.

**Post-deploy verification performed:**

| Check | Result |
|---|---|
| Transport — `getMyTraining` | HTTP **401** (deployed, auth required — not 404) |
| Transport — `claimClientAccount` | HTTP **401** |
| Revision | `getmytraining-00014-yem`, `state: ACTIVE` |
| `updateTime` | `2026-07-28T05:22:12Z` |
| Deployed inventory | 76 functions; both present; no others altered |
| Runtime errors since deploy | **none** — the only `E` entries are the unauthenticated probe above; the AppCheck warnings predate the deploy (05:05) |

## 8. NOT CERTIFIED — what remains, and why I cannot do it

**The live behavioural matrix has NOT been observed, so this section is not
certified.** That is the instruction, and it is the right one.

I cannot perform it. Driving it requires signing into AlphaSerena as a member
and into TrainerHQ as a coach. Member sign-in is **phone OTP**, and entering
credentials or one-time codes on someone's behalf is something I will not do.
Independently, this project's phone OTP is blocked by the Play Integrity API
being disabled on the Cloud project — a pre-existing external issue. There is no
service-account file in either repo, and no `gcloud`, so I also cannot read
production Firestore directly to verify the data half.

**What is proven:** the corrected code is live in production, serving, and
error-free.
**What is unproven:** that the member's screen now shows the right name and face.

### The 6-minute runbook

Highest-signal first. **Test 1 is decisive** — it never worked before under any
circumstance, in any build, so a pass proves the live channel is genuinely
carrying the coach rather than a mirror that happened to be fresh.

| # | Do this | Expect |
|---|---|---|
| 1 | **Rename a coach** in TrainerHQ → pull-to-refresh member Home | the NEW name (this could never work before) |
| 2 | Change that coach's **photo** → pull-to-refresh | the new photo; delete it → initials |
| 3 | **Assign a real trainer** → pull-to-refresh | trainer's name + face |
| 4 | **Assign the owner** to themselves → pull-to-refresh | owner's name + face |
| 5 | **Reassign** trainer A → B → pull-to-refresh | B immediately; never A |
| 6 | **Remove** the trainer → pull-to-refresh | the owner's name (not "Your Coach") |
| 7 | **Logout / login**, then **cold start** | correct name on first paint |
| 8 | **Airplane mode**, reopen | last known name from the mirror, no placeholder |
| 9 | **Fresh install**, first login | correct name after the first load |

If any row fails, send me the row number and what appeared — the failure point
is now narrow: either `coach` is absent from the `getMyTraining` payload, or
`MemberController._liveCoach` is not reading it.

**If you generate a service account** (`scripts/service-account.json`, as for the
food migration), I can verify the data half of every row directly against
production — real `clients.trainerId`, `trainers.name`, `admins.name` and the
resulting resolver output for real members — which would leave only the on-screen
rendering to your eyes.

---

*Verified 2026-07-28: analyze clean · 243/243 AlphaSerena · 524/524 backend ·
tsc clean · **deployed to production 05:22 UTC, live and error-free**. Live
behavioural matrix NOT yet observed — NOT CERTIFIED. Nothing committed.*
