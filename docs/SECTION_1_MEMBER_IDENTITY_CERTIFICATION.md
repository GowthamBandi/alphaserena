# Section 1 — Member Identity & Coach Relationship Certification

- **Date:** 2026-07-28
- **Scope:** the Home identity surface only — organisation, coach, membership,
  notifications, messaging entry point. Nutrition, Workout, Lifestyle and
  Progress were not touched.
- **Repos changed:** `alphaserena`, `trainershq-backend`. `trainersHQ` was
  audited and required no change.
- **Nothing committed.**

---

## 1. Architecture

```
TrainerHQ / purchase                          Firestore
────────────────────                          ─────────
verifyAndActivateMembership ──creates──►  clients/{id}
                                            adminId, authUid, name, phone,
                                            status, membership*          ← NO trainerId
admin assigns a trainer      ──updates──►    trainerId                   ← optional, later
                                                 │
                    claimClientAccount ◄─────────┘  (member opens the app)
                       reads admins/{adminId}, trainers/{trainerId}
                       resolveTrainerName  ─┐
                       resolveTrainerPhoto ─┴──►  clientProfiles/{authUid}
                                                    gymName
                                                    trainerName
                                                    trainerPhotoUrl      ← new
                                                    trainerNameFor       ← now effective coach
                                                 │
AlphaSerena Home ◄───────────────────────────────┘
  resolveCoachName / resolveCoachPhoto  →  HeaderView
  organizationProfiles/{adminId}        →  logo, name, verified
  chats/{clientId}.unread.member        →  message badge   ← new surface
```

**The load-bearing constraint:** a member may not read `trainers/{id}` or
`admins/{id}` — the security rules correctly deny it. So the member app *cannot*
resolve a coach's name or face itself. `claimClientAccount` is the only party
that can, and the mirror it writes on `clientProfiles` is the entire identity
channel. Every defect below lives in that mirror or in how it is read.

---

## 2. Root cause of "Your Coach"

**Every member in production saw the literal string "Your Coach" instead of their
coach's name.** The chain, verified end to end:

1. `verifyAndActivateMembership` (`memberships.ts:421`) creates the `clients`
   record on purchase with `name, phone, adminId, authUid, status, createdAt`.
   **It does not set `trainerId`** — and the code comment states the product
   rule plainly: *"members join a coach ONLY by subscribing — no manual add"*.
   So this is the only way a client record is ever born.
2. Assigning a trainer is a separate, deliberate act the owner performs later
   from the **Unassigned** triage list in TrainerHQ. A solo gym owner who *is*
   the coach never performs it — they would be assigning themselves.
3. `resolveTrainerName` opened with `if (!trainerId) return ""`.
4. `resolveCoachName` (member app) opened with the same guard.
5. `HomeController.coachName` fell back to `'Your Coach'`.

So the "no coach" path was not an edge case — **it was the default state of
every member who had ever paid.**

**The decisive evidence was already in the repository.** `resolveCoachRecipient`
— the function that decides who receives the member's notifications — has always
read:

```ts
if (trainerId) { … }
if (adminId) return {collection: "admins", uid: adminId};   // ← the owner
```

and `functions/test/coach_identity.test.mjs` asserted both of these, in the same
file:

- `"no trainer assigned resolves to empty, never the admin"` (the name)
- `"routing: no trainer assigned falls back to the owning admin"` (notifications)

The member's messages went to the org owner while the member was told they had
no coach. The system already knew who was responsible; only the display refused
to say so.

### The fix, and why it is at read time

`trainerId` empty never meant *coachless*. It means **no specific trainer has
been delegated yet, and the org owner is responsible in the meantime.** Both
resolvers now encode exactly that.

**Deliberately NOT fixed by stamping `trainerId = adminId` at creation.** That
was the obvious repair and it is wrong: TrainerHQ has a real *Unassigned* filter
and count (`clients_list_screen.dart:28,556`) that a multi-trainer gym uses to
triage new members. Auto-assigning would leave that list permanently empty and
silently destroy the workflow. Resolving at read time leaves `clients.trainerId`
untouched, so the owner's triage is exactly as it was.

---

## 3. Resolved defects

### D1 · Every member read "Your Coach" *(critical)*

Root-caused in §2. `resolveTrainerName` (backend) and `resolveCoachName`
(member app) now resolve the org owner when no trainer is delegated.

**The staleness guard the old rule was protecting had to be preserved**, and it
is now stronger rather than weaker:

| Situation | Before | After |
|---|---|---|
| No trainer delegated | "Your Coach" | **the owner's name** |
| Trainer delegated | trainer's name | trainer's name |
| Owner assigned as trainer | owner's name | owner's name |
| Trainer **reassigned** t1→t2 | suppressed until re-claim | suppressed until re-claim |
| Trainer **removed** | suppressed | suppressed, then the owner |
| Legacy mirror, trainer removed | suppressed | **suppressed** (see below) |
| No organisation at all | empty | empty |

The subtle case: a `clientProfiles` document written before `trainerNameFor`
existed carries an unvalidatable name. Simply deleting the guard would have made
`derivedFor == assignedTo` compare `'' == ''` and **resurrect a departed coach's
name**. Two changes prevent it — the mirror now records the *effective* coach
(`trainerNameFor: trainerId || adminId`, so "derived for the owner" is no longer
indistinguishable from "never validated"), and the legacy branch is trusted only
while a trainer is actually assigned.

### D2 · The coach's photo never reached the member

TrainerHQ models a coach avatar on both sides (`TrainerModel.profilePicUrl`, and
`AdminTrainerIdentity.asTrainer()` explicitly carries it forward so an
admin-coached member "sees the same shape of coach profile"). The member app
rendered **initials only** — no photo was mirrored, and none was requested.

Added `resolveTrainerPhoto`, mirrored as `trainerPhotoUrl`. **No extra Firestore
read:** the trainer document is already fetched for the name and the admin
document is already fetched for `gymName`.

The photo is gated on the name (`resolveCoachPhoto`), so a reassignment can never
pair the new coach's name with the previous coach's face — the failure mode that
makes an app feel untrustworthy in a way users struggle to articulate.

### D3 · Unread coach messages were invisible

`chats/{clientId}.unread.member` has always been maintained — `ChatService`
*resets it to zero* in `markRead`. **Nothing ever displayed it.** A member with
five messages waiting saw an inert "Message" button.

For a coaching product this is the most consequential of the three: the coach
writes, the member never learns, and the relationship the member is paying for
quietly stops functioning. Added `watchUnread` and a count badge on the pill.

**Count, not a dot** — "3" tells the member whether this is a quick read or a
real conversation. The stream is created once per `clientId` in a dedicated
widget, because a `StreamBuilder` inline inside the header's `Obx` would
resubscribe to Firestore on every emission of any other observable the header
reads.

### D4 · Two backend tests encoded the bug

`"no trainer assigned resolves to empty, never the admin"` and `"trainer removed
clears the name"` asserted the defective behaviour. Both were rewritten with the
contract change stated explicitly, and cross-referenced to the routing test that
contradicted them.

---

## 4. Audit results — what was already correct

Much of this section was already well built and required no change. Recorded so
it is not "fixed" later by someone who did not check.

**Organisation.** Logo, name and `verified` come from
`organizationProfiles/{adminId}`, fetched once per adminId with a retry on
transient failure. The verified badge renders **only** when the platform flag is
genuinely true — it used to be drawn unconditionally, claiming a verification no
document backed. `orgLoading` distinguishes a genuine in-flight fetch from "no
org", so the generic fallback never flashes at a member who has one. Fallback
copy is `'Your Organization'`, which cannot be mistaken for a real gym.

**Membership.** Every field is read from the member's own `clients` document;
`MembershipStatus.of` separates loading / frozen / active / expiring / no-record,
and a keyed skeleton guarantees no date is claimed before the document arrives.

**Reassignment liveness.** `MemberController` watches `clients.trainerId` and
re-claims **only on an actual change**, not on initial load — so the coach card
updates live without a re-claim loop.

**Messaging reachability.** `ClientChatScreen` resolves the thread from
`linkedClientId`, never from `trainerId`. Messaging therefore works for an
unassigned member — which, given §2, is nearly all of them. This was already
right and is the reason D1 was a display defect rather than a broken feature.

**Offline.** `ConnectivityController` mounts a full-screen takeover above every
route, so the header is never on screen while offline. Per-card offline chrome
here would be dead code.

**TrainerHQ client profile.** Audited against `ClientModel`: name, photo, phone,
email, gender, DOB/age, membership, `trainerId`, `adminId`, goal and emergency
contact are all modelled and displayed. No dummy data, no stale duplicate
fields. **No change was required in TrainerHQ.**

---

## 5. Message experience — supported vs. not

Separated as the mission requires; nothing below invents a backend feature.

**Already supported and now surfaced**
- Unread count (`chats/{clientId}.unread.member`) — **shipped in D3**
- Read receipt reset on open (`markRead`)
- Reachability without an assigned trainer

**Needs backend work — deliberately not built**
- **Last-message preview.** The thread document carries no `lastMessage`
  snippet, and reading the newest message from the subcollection to render the
  header would add a query on every Home open. Correct fix: denormalise a
  snippet onto the thread on write.
- **Typing indicator.** No presence or typing document exists.
- **Coach online state.** No presence system exists in either app. The current
  header deliberately has no presence dot, and inventing one would be a lie.

**Future enhancement**
- New-message animation on the badge (needs a previous-count comparison worth
  holding only once a preview exists)
- Per-thread mute

---

## 6. Verification

| Suite | Result |
|---|---|
| `alphaserena` `flutter analyze` | **No issues found** |
| `alphaserena` `flutter test` | **223 / 223** (211 baseline + **12 new**) |
| — `coach_identity_unassigned_test` | 12 new — the unassigned owner rule, removed-coach suppression, legacy mirrors, photo gating |
| — existing `coach_identity_test` | 15/15 still pass unchanged (the new `adminId` parameter defaults to `''`, preserving prior behaviour exactly) |
| `trainershq-backend` `tsc --noEmit` | clean |
| `trainershq-backend` unit tests | **524 / 524** (5 new / 2 rewritten in `coach_identity.test.mjs`) |
| `alphaserena` `flutter build apk --debug` | **Built** `app-debug.apk` |
| Firestore rules | unchanged — the mirror is written by the Admin SDK and read by the member from their own profile |

---

## 7. Remaining ideas (not built)

1. **Show the effective coach in TrainerHQ.** An unassigned client correctly
   reads "Unassigned" to the admin, while the member now sees the owner's name.
   Both are true answers to different questions, but a line on the client detail
   — *"Coached by you until a trainer is assigned"* — would remove any doubt for
   the coach about what their member sees.
2. **Mirror refresh when a coach renames or changes their photo.** The mirror is
   re-derived on re-claim, which fires on assignment changes — not when the
   coach edits their own name or avatar. A member could see a stale name until
   their next claim. Low impact, real.
3. **Last-message preview** (§5) — the highest-value messaging improvement.
4. **Coach role/credential line** ("Head Coach", certifications). All of it
   exists on `TrainerModel`/`AdminModel` and none is mirrored.

---

## 8. Certification

**1 · Does TrainerHQ display the correct client information?**
**Yes.** Every `ClientModel` field is sourced and rendered; no dummy, stale or
duplicated fields were found. TrainerHQ required no change.

**2 · Does AlphaSerena display the correct organisation?**
**Yes.** Real logo, name and verified flag from `organizationProfiles/{adminId}`,
with a loading state that never flashes a fallback at a member who has an org,
and a neutral placeholder that cannot be mistaken for a real gym.

**3 · Does AlphaSerena display the correct assigned coach?**
**Yes — now.** This was **NO** before this pass: every member read "Your Coach"
because a client record is created without a `trainerId` and both resolvers
treated that as coachless. The member now sees their delegated trainer, or the
org owner who is genuinely responsible for them — the same person the backend
has always routed their notifications to.

**4 · Are profile images handled correctly?**
**Yes — now.** This was also **NO**: the coach's photo existed in TrainerHQ and
was never mirrored. It now resolves by the same rule as the name, is gated on
the name so a stale face can never outlive it, is cached, and degrades to
initials on a slow or dead URL.

**5 · Is messaging production ready?**
**Yes, for its current scope.** Reachable for every linked member including
unassigned ones, unread count now visible, read state reset on open. Preview,
typing and presence are honestly documented as absent rather than faked.

**6 · Would I personally approve this section for production?**
**Yes.** I would not have before this pass, and not because of styling: an app
that cannot name your coach after you have paid for coaching has failed at the
one thing it exists to do, and an app that hides your coach's messages has
failed at the second. Both were single-line rules, both were contradicted by
code already sitting in the same repository, and both are now closed and pinned
by tests.

The honest caveat carried from the three certifications before this one:
**no authenticated live run.** Every branch is unit-tested, but nobody has yet
watched a real member's header resolve a real coach's name and face against live
Firestore.

---

*Verified 2026-07-28: analyze clean · 223/223 AlphaSerena · 524/524 backend ·
tsc clean · debug APK built. Nothing committed.*
