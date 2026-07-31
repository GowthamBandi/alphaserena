# Profile Foundation — Certification (Phase 0.5)

- **Date:** 2026-07-28
- **Mission:** make Profile **true** before making it beautiful. Eliminate every
  architectural inconsistency found in `PROFILE_EXPERIENCE_ARCHITECTURE.md`.
- **Explicitly out of scope and NOT done:** Profile redesign, premium UI,
  animations, new cards, new navigation, health sections, achievements,
  gamification, community, referrals.
- **Status:** implemented, analyzed, tested and built. **Nothing committed.
  Nothing deployed.**

**Verification performed:** `flutter analyze` → *No issues found*;
`flutter test` → **509 passed** (baseline 481 + 28 new); `flutter build apk
--debug` → **succeeded**. No device run was performed, so every runtime claim
below rests on static analysis, the test suite and traced control flow — not on
observed behaviour on hardware.

---

## 1. Root causes

The audit found nineteen defects. They reduce to **four** root causes, and
naming them correctly is what made the fixes small.

### RC-1 — Identity had no rule, so every screen invented its own

`coach_identity.dart` established a law for naming a *coach*: **a value is either
real, or it is absent — never invented.** Nothing equivalent existed for the
member, their organization, or their own photo. Each screen therefore wrote its
own fallback, and the fallbacks were plausible proper nouns: a member called
`'Alpha'`, an organization called `'Alpha Arena'`, a coach called `'Your Coach'`
titled `'Performance Coach'`, and a stock portrait shipped as that coach's face.

`'Alpha'` was the worst of them because it was not confined to a screen: it lived
in `MemberController.name`, so it flowed into `org_reviews.memberName`,
`client_feedback.clientName`, chat `senderName` and the call `callerName` — the
app recorded members in their coach's inbox under a name it had made up.

### RC-2 — Membership had an engine, and Profile did not use it

`MembershipStatus` models eight states with deliberately chosen wording and a
non-colour glyph per urgent state. Profile carried a two-state binary *and* a
separate Active/Inactive badge. Both derive from `isActive`, which is false for a
**frozen** membership — so a coach who paused a member was telling them their
membership had **Expired** on one card and they were **Inactive** on another,
while Home said **Paused**.

### RC-3 — Profile waited on the wrong flag

`MembershipController.isLoading` tracks the membership **plans** query and, in
its own words, *"says nothing about the member's own membership"*. Profile gated
on it. It clears immediately when no `adminId` is known, while `isLinked` flips
true from the earlier `clientProfiles` snapshot — so the screen rendered a full
membership verdict before the `clients` document existed. An active, paying
member's first paint read **"Transform Program · Expired · Valid Till N/A"**:
three fabricated values in one row.

### RC-4 — Identity setup was reachable exactly once, and often zero times

`HomeController.stage` evaluates `if (hasPlan) return ClientStage.ready` **before**
`identityDone`, and Home's Getting Started card — the only entrance to
`IdentitySetupScreen` — renders only while `stage != ready`. `MemberIdentityService`
was referenced in exactly two files: that screen, and the stage check.

So a coach who assigned a plan before their member finished setup removed that
member's only route to their own identity, permanently. **The more attentive the
coach, the more certainly their member was locked out.** Meanwhile Profile's
"Personal Information" row answered any attempt with a snackbar telling the
member to ask their coach to edit a document the rules make the coach incapable
of reading or writing.

---

## 2. Architectural fixes

| # | Fix | Where |
|---|---|---|
| A1 | **One identity law**, mirroring `coach_identity.dart` | `core/domain/member_identity.dart` *(new)* |
| A2 | Identity resolvers exposed once, consumed everywhere | `MemberController` |
| A3 | **Organization identity moved** from Home to `MemberController` | `MemberController`, `HomeController` |
| A4 | **One membership engine** exposed as `MembershipController.status` | `MembershipController`, `HomeHeader`, Profile |
| A5 | Compact register added to the same engine (`shortText`) | `MembershipStatus` |
| A6 | Per-component loading, not whole-screen | Profile |
| A7 | **Permanent identity entrance** via `IdentitySetupMode.edit` | `IdentitySetupScreen`, Profile |
| A8 | Privacy disclosure derived from the live projection function | `privacy_visibility_screen.dart` *(new)* |
| A9 | Store-compliance surface | `account_screen.dart`, `app_legal.dart`, `account_deletion_service.dart` *(new)* |

**A1 in one sentence:** `resolveMemberName` · `resolveMemberPhoto` ·
`resolveMemberAge` · `resolveOrgName` · `initialsOf`, each returning `''`/`null`
when nothing can be honestly claimed, with **live sources outranking mirrored
ones** exactly as `resolveCoachName` already did.

**A3 fixed a live bug in Home, not just in Profile.** The org-name chain
preferred `clientProfiles.gymName` — a mirror written once by
`claimClientAccount` and never re-derived — over the freshly fetched storefront
name. An organization that renamed itself kept showing its **former** name on
Home even after the current one had been fetched and was sitting in memory.
`resolveOrgName` inverts that precedence.

---

## 3. Identity flow (after)

```
clientProfiles/{uid}                          clients/{id}
  profile.identity.displayName ─┐               name ──────────┐
  profile.identity.name  ───────┤               age ───────────┤
  clientName (legacy dual-write)┤                              │
  profile.identity.photoUrl ────┤                              │
  profile.identity.dob ─────────┤                              │
  gymName (stale mirror) ───────┤                              │
                                ▼                              ▼
                    ┌──────────────────────────────────────────────┐
                    │  core/domain/member_identity.dart            │
                    │  real, or absent — never invented            │
                    └──────────────────────────────────────────────┘
                                        │
organizationProfiles/{adminId}.name ────┤ (live outranks mirror)
                                        ▼
                              MemberController
                    name · photoUrl · initials · age · gender
                    dob · phone · email · heightCm · weightKg
                    orgName · orgLogoUrl · orgVerified
                                        │
        ┌───────────────┬───────────────┼───────────────┬──────────────┐
        ▼               ▼               ▼               ▼              ▼
      Home          Profile         My Plans          Chat        Join / Discover
```

**Entry points to identity maintenance — before and after:**

| | Before | After |
|---|---|---|
| First run | Home → Getting Started (`stage == identity`) | unchanged |
| Later edit | **none** | Profile → Personal details, permanently |
| After a plan is assigned | **none, ever** | Profile → Personal details |

`IdentitySetupMode.edit` reuses the same form and the same service; it differs
only in framing, in being dismissible from step one, in prefilling gender, date
of birth and the existing photo (none of which were prefilled before), and in
returning to Profile instead of chaining into the coach questionnaire.

**Home's `stage` logic is deliberately unchanged.** Reordering it so identity
preceded `hasPlan` would hide a paying member's delivered plan behind a profile
form — a worse product than the bug. Three alternatives were considered and
rejected: reordering the stage, a persistent Getting Started nag at `ready`, and
blocking the dashboard until identity is complete.

---

## 4. Membership parity

**Within AlphaSerena — now one engine, verified.**

`MembershipController.status` is the single derivation. `HomeHeader` consumes it
(it previously called `MembershipStatus.of` inline with five hand-passed
primitives). Profile consumes it in two places — the badge (`shortText`) and the
card (`text` + `icon`). Neither screen derives membership language any more.

| State | Home header | Profile badge | Profile card |
|---|---|---|---|
| loading | skeleton, no date | hidden | skeleton block |
| none | No membership | No membership | No membership |
| inactive | Inactive | Inactive | Inactive |
| expired | Expired | Expired | Expired |
| **frozen** | **Paused** | **Paused** | **Paused** |
| endsToday | Ends today | Ends today | Ends today |
| endsSoon | Ends in N days | Ends in Nd | Ends in N days |
| active | Active until *date* | Active | Active until *date* |

The compact register lives on `MembershipStatus` rather than in Profile, because
letting a second surface shorten the wording itself is precisely how the
contradiction arose the first time. Tests hold the registers in agreement: no
state is ever called *Active* unless it genuinely is, and urgency/glyph agree
across both.

**States that do not exist.** The mission asked about *trial*, *future*,
*cancelled* and *grace*. **The platform has no such states.** The entire
membership model is `membershipActive` (bool), `membershipExpiry` (date),
`membershipFrozen` (bool), `membershipFrozenAt`, and a `membership` map carrying
`planName`. Introducing UI for lifecycle states the data model does not have
would be the same class of fabrication this phase removed, so nothing was added.
`membershipFrozenAt` exists and is still unread — it is the "paused since" fact a
future Paused state could use honestly.

**Cross-app parity with TrainerHQ — three genuine divergences, recorded not
changed.** Both apps agree on the 7-day threshold and both are internally
consistent.

1. **Precedence.** AlphaSerena checks `frozen` before `hasRecord`; TrainerHQ
   checks `hasRecord` first. Only reachable on incoherent data.
2. **`hasMembershipRecord`.** AlphaSerena counts the mere *presence* of the key;
   TrainerHQ requires an expiry or an active flag. A document with
   `membershipActive: false` and no expiry reads *Inactive* to the member and
   *No membership* to the coach.
3. **Day counting.** TrainerHQ `ceil()`s a duration; AlphaSerena counts calendar
   days. Profile's third algorithm (raw truncation) is **gone**, leaving two.

Changing AlphaSerena to match would alter certified Home behaviour; changing
TrainerHQ is outside this repository. Recorded as a cross-app item in §10.

---

## 5. Privacy verification

**Verified against the running system, not the spec.**

| Checked | Finding |
|---|---|
| Projection CF | `onClientProfileWritten` is exported in `index.ts` and **live** |
| What it writes | `clients/{id}.sharedProfile` + `sharedProfileAt`, via `sharedProfileFrom` → `coachProjection` |
| Rules — member doc | `clientProfiles/{uid}`: read/write **only** `request.auth.uid == uid`; `fcmTokens`, `fcmUpdatedAt`, `linkedClientId` CF-only |
| Rules — projection | `sharedProfile` ∈ `serverOwnedClientFields` → client cannot forge it |
| CF safety | mutual `authUid` check before stamping; change-guard against redundant writes |
| Defaults | `identity`, `contact`, `bodyMetrics` default to `coach`; `medical`/`documents` to `onlyMe`, opt-in up to `coach` |
| Coach consumption (P4) | **not built** — `sharedProfile` appears in TrainerHQ only inside a doc comment |

**The consent gap, and what was actually fixed.** Identity Setup told members
*"Your profile is private. Only what you choose to share is visible to your
coach."* That described the design, not the system: the three sections it writes
all default to `coach` visibility and are projected the moment the form is saved,
and no choice had ever been offered. This is not a leak — the projection is
exactly what the approved policy permits and the private boundary is intact — it
was a **promise ahead of its control surface**.

Two changes close it:

1. **The copy now states what actually happens:** *"Your name, photo and contact
   details are shared with your coach so they can train you — and with nobody
   else. You can see exactly what is shared under Profile."*
2. **A disclosure screen** — Profile → *What your coach can see* — that calls
   `coachProjection(profile.sections, profile.privacy)`: **the identical pure
   function the Cloud Function calls, over the identical inputs.** It cannot
   drift from what is actually shared.

**Why it is read-only, deliberately.** Write controls were considered and
rejected for this phase. The coach app does not read `sharedProfile` yet, so a
tighten-to-private toggle would change a stored value while changing nothing the
member could observe. A control that appears to act and does not is worse than an
honest statement of fact. Toggles land with P4.

**The screen states both halves of the truth.** Listing only the member's own
sections would imply they control everything their coach knows about them. They
do not: the organization independently authors `clients/{id}` — the name and
contact details they typed, the membership, their coaching notes — and the member
can neither edit nor hide it. A *What your organization holds* block says so
plainly, and is the honest replacement for the old "edit it via your coach"
snackbar.

**Two further privacy claims corrected.**

- *"Only you and your coach can see your feedback"* (rating sheet) was true of
  the **comment** — `org_reviews` list access is admin-only — but not of the
  **star rating**, which `onOrgReviewWritten` folds into the public
  `organizationProfiles` average shown on the coach's storefront. Now: *"Your
  comment is private to your coach. Your star rating counts towards their public
  rating."*
- *"Send anonymously"* promised more than the system delivers: the submission
  still carries `authUid`, `clientId` and `clientName`, and TrainerHQ honours the
  flag only by rendering "Anonymous" in place of the name. Relabelled *"Don't
  show my name"*, with an inline note that the organization can still identify
  them.

**Noted, not changed:** `org_reviews` allows `get` to any signed-in user who
knows `{adminId}_{clientId}`. The rule comment judges this low-sensitivity
because the aggregate is public and `clientId` is a non-enumerable Firestore id.
That judgement is defensible; it is flagged so it is inherited deliberately
rather than silently.

---

## 6. Store compliance

| Requirement | Before | After |
|---|---|---|
| In-app account deletion (Play policy; Apple 5.1.1(v)) | **absent** | implemented |
| Reachable Privacy Policy | untappable grey text at login | surface built, **URL unset** |
| Terms of Service | untappable grey text at login | surface built, **URL unset** |
| App version / build | absent | real values via `package_info_plus` |
| Open-source licences | absent | `showLicensePage` |

**Account deletion — what it genuinely does.** The member owns exactly one
document, and the rules let precisely one party delete it: them
(`allow delete: if signedIn() && request.auth.uid == uid`). So deletion runs
entirely client-side, with no Cloud Function and no elevated privilege:

1. release this device's push token (session still live)
2. end any live call and release the call lock
3. best-effort profile-photo removal (see §10)
4. delete `clientProfiles/{uid}` — **15s timeout**
5. delete the Firebase Auth user
6. tear down to login

**Ordering is deliberate:** everything needing a live session runs first, and the
auth account dies last, so a failure at any earlier step leaves a member who can
still sign in and retry rather than an orphaned, unreachable account.

**What is not deleted, and why that is correct.** `clients/{id}`, payments and
training logs are the organization's business record of a commercial
relationship, subject to their own retention obligations, and the member never
had write access to them. The confirmation sheet states this distinction in plain
language **before** the member can proceed, names their organization, and
requires an explicit acknowledgement checkbox. Conflating "delete my account"
with "erase my coach's books" would be both impossible from the client and wrong.

**Three outcomes, three different sentences.** `deleted` · `needsRecentLogin`
(Firebase requires a fresh credential — the member is told to sign out and back
in, and that **nothing has been deleted**) · `failed`. A recoverable condition is
never reported as a generic failure.

---

## 7. Edge cases

| Case | Behaviour |
|---|---|
| Coach reassigned | `_listenClient` detects the change → re-`claim()` re-derives the mirror; live `TrainingController.coach` outranks it |
| Coach removed | mirror's `trainerNameFor` no longer matches the effective coach → name suppressed → **"Not assigned yet"** (was: `'Your Coach'`) |
| Admin is the coach | `effective = trainerId.isEmpty ? adminId : trainerId` — unchanged, covered by existing coach-identity tests |
| Organization renamed | live storefront name now outranks the stale mirror; pull-to-refresh re-fetches it |
| Organization/coach deleted | `CoachService.byId` returns null → falls back to mirror → else the shared generic label |
| Photo changed | upload path is timestamped, so the URL changes and `CachedNetworkImage` cannot serve a stale image |
| Membership paused → resumed | single engine; **Paused** everywhere, never Expired |
| Identity incomplete | "Add your name", initials or a neutral glyph, `--` for unknown metrics |
| **Unlinked member** | screen renders fully; membership card carries its own skeleton (see §8) |
| Fresh install | `member.isLoading` gates the skeleton; `claim()` resolves link or `no_membership` |
| Slow network | membership card skeletons alone — the fabricated first paint is gone |
| Google sign-in | email resolves from the credential; phone row hidden when genuinely absent (was: literal `'No Phone'`) |
| Offline | Firestore cache serves reads; deletion is time-boxed (see §8) |
| Multiple devices | deletion releases **this** device's token only (see §10) |
| Long org/coach names | `maxLines` + ellipsis on every name field |

---

## 8. Self-challenge results

Challenging my own implementation found **two defects I had introduced** and one
I had missed. All three are fixed.

**S-1 — I nearly shipped an infinite skeleton.** My first pass gated the whole
Profile screen on `isMembershipLoading`. That flag is `member.isLoading || client.value == null`,
and an **unlinked member never gets a `clients` document** — so they would have
stared at a skeleton for the entire session. Fixed by adopting Home's actual
pattern: whole-screen loading waits only on the member's own load, and the card
that makes a membership claim carries its own skeleton.

**S-2 — the deletion flow would hang forever offline.** A Firestore write issued
without connectivity is queued locally and its `Future` does not complete until
the server acknowledges it. `await ...delete()` on the delete path would have
left an offline member on a spinner indefinitely while believing their account
was being deleted — the same trap already root-caused in the diet logger's
permanent "Saving…". Fixed with explicit timeouts on the Firestore delete (15s) and on
the Storage list/delete calls (8s/5s), and an honest failure message stating that
nothing was deleted.

**S-3 — the same fossil existed on two more screens.** A residual sweep for the
fabricated literals found the identical partner card duplicated into **My Plans**
(`'Alpha Arena'`, `'Your Coach'`, `'Performance Coach'`, the stock portrait) and
the fabrications in the **chat header**. My Plans additionally drew
`Icons.verified` **unconditionally** — the exact defect `HomeHeader` documents
fixing (*"it was previously drawn unconditionally, which claimed a verification
no document backed"*). Certifying Profile as truthful while leaving those in
place would have made this document false, so they were fixed too.

**Also caught and closed:** Home and Profile still worded the unknown-organization
state differently (*"Your Organization"* vs *"Not available"*) — a member would
have read one on one tab and the other on the next. Unified on Home's existing,
defended wording.

**S-4 — a title-cased role label was still being read as a name.**
`HomeController.coachName` fell back to `'Your Coach'`, and that getter is
interpolated **mid-sentence** on Home ("Answer a few questions from
${coachName}"), so an unassigned member was addressed as though *Your Coach* were
the person's name. Changed to lowercase `'your coach'` — unambiguously a role —
and the one sentence-initial usage now branches on `hasCoachName` for the
capitalised form.

**Deliberately retained, after review.** Three call-flow sites keep title-cased
`'Your Coach'` (`call_service.dart:223`, `:328`, `call_screen.dart:36`). These
render the **peer identity on a full-screen call**, a display-name position where
a title-cased role reads correctly and conventionally — the same category as
*Unknown Caller* on a phone dialler. The label is also true: the peer genuinely
is the member's coach. The same reasoning covers `'Member'`, now needed as the
`callerName` fallback because `member.name` can honestly be empty, and
`'Your Organization'` on Home/Profile/My Plans.

The distinction this phase enforces: **fabricated proper nouns out; generic role
labels allowed, honest, and consistent across screens.** A future sweep will
surface the three call sites — they were considered, not missed.

---

## 9. Tests

**509 passing** (baseline 481 + 28 new). `flutter analyze` clean. Debug APK builds.

**`test/member_identity_test.dart` — 23 new tests.** Every case is a regression
guard for something that actually shipped:

- name: canonical → legacy → coach record → **empty**; explicitly asserts the
  result `isNot('Alpha')`
- photo: absent → empty, so callers render initials rather than a stock face
- age: derived from date of birth; a birthday later this year has **not** happened;
  the birthday itself counts; date of birth outranks the coach's integer; falls
  back through `int`/`num`/`String`; impossible values read as unknown
- organization: live outranks the stale mirror (the rename case); nothing known →
  empty, asserted `isNot('Alpha Arena')`
- initials: two words, one word, empty, punctuation, emoji, extra whitespace

**`test/membership_status_test.dart` — 5 new tests** holding the two registers in
agreement: every state has compact wording; a paused membership never reads as
expired or inactive **even when it carries a stale past expiry** (the exact shape
that produced the contradiction); nothing is called *Active* unless it is; the
registers agree on urgency and glyph for every state.

**Not tested, and why.** No widget test covers `ClientProfileScreen` itself. It is
a single `StatelessWidget` wired directly to GetX controllers and Firebase
streams, with no pure view to render in isolation — the pattern `home_header_test`
relies on. Extracting one is exactly the decomposition that belongs to the
redesign phase this mission excludes. The logic those tests would assert is
covered as pure functions instead.

---

## 10. Honest limitations

1. **Store compliance is not complete.** `AppLegal.termsUrl` and
   `privacyPolicyUrl` are empty, so those rows do not render. Play will not
   accept a production release without a reachable Privacy Policy. **One file,
   two constants** — no other change is needed; the rows appear on their own.
2. **A deleted member's profile photo is orphaned.** The Storage rule
   `profile_photos/{uid}/{file}` uses `allow write: ... && okMedia()`, and
   `okMedia()` dereferences `request.resource.size`/`.contentType`, which are
   null on a delete — so the rule denies the member deleting their own photo. The
   call is made and fails silently by design. **Fix belongs in
   `trainershq-backend/storage.rules`:** separate `delete` from `write`.
3. **The privacy screen is read-only.** By choice (§5), until P4 ships.
4. **A latent cross-app schema divergence.** The canonical registry specifies
   *sections* but not their *fields*, and `identity` has already diverged:
   AlphaSerena writes `displayName`/`dob`, TrainerHQ's adapter reads `name`/`age`.
   AlphaSerena now reads both keys — that is **tolerance, not a fix**. The schema
   decision is cross-repo and needs its own governed change.
5. **Membership parity with TrainerHQ is not exact** — three divergences in §4,
   recorded rather than changed.
6. **`requires-recent-login` has no in-app re-auth.** The member is told to sign
   out and back in. A re-authentication flow (re-OTP / re-Google) would be better.
7. **Deletion releases only this device's push token.** Other signed-in devices
   keep stale tokens pointing at a deleted uid; server sends to them will fail
   harmlessly. A CF-side sweep would be cleaner.
8. **The organization is fetched once per session** plus on pull-to-refresh. A
   rename is not pushed live — there is no listener on `organizationProfiles`.
9. **Profile is still a ~1,500-line single file.** Decomposition, the five-group
   IA, the type-scale floor and the full accessibility pass belong to the
   redesign phase. This phase added `Semantics` to the account rows, the logout
   button and the privacy rows, raised those rows' subtitles off 10px, and gave
   every membership state an icon — but the screen still contains sub-11px text
   elsewhere and has not been verified at 200% text scale.
10. **`today_agenda.dart` still guards against the string `'Alpha'`.** Now
    unreachable, but harmless and covered by a passing test; removing it would
    change a certified greeting for no benefit.
11. **No device run.** Everything above is static analysis, tests and traced
    control flow. The deletion flow in particular — which destroys an auth
    account — has not been executed against a live Firebase project.

---

## 11. Stop conditions

| Condition | Status |
|---|---|
| Identity is truthful | **met** — every fabricated proper noun removed across Profile, My Plans, chat, join and the controllers that fed them |
| Home and Profile never disagree | **met** — one identity layer, one membership engine, one unknown-state wording |
| Identity Setup can never become permanently inaccessible | **met** — permanent Profile entrance, independent of `stage` |
| Every placeholder removed | **met** for fabricated data; generic role labels deliberately retained and made consistent (§8) |
| Membership has one shared engine | **met** — `MembershipController.status`; both registers on the same object |
| Privacy foundation ready | **met** — disclosure derived from the live projection function; false copy corrected |
| Production store requirements satisfied | **NOT met** — deletion, version and licences ship; **legal URLs are unset** (§10.1) |

Six of seven met. The seventh is one configuration change, and it is the user's
to make: no brand URL exists in the repository and inventing one would have been
the same fabrication this phase spent its effort removing.

---

## 12. Files

**New (7):** `core/domain/member_identity.dart` · `core/constants/app_legal.dart` ·
`core/services/account_deletion_service.dart` ·
`screens/dashboard/profile/privacy_visibility_screen.dart` ·
`screens/dashboard/profile/account_screen.dart` · `test/member_identity_test.dart` ·
this document.

**Modified (15):** `member_controller` · `membership_controller` ·
`home_controller` · `auth_controller` · `discover_controller` · `call_service` ·
`home/membership_status` · `home/home_header` · `profile/client_profile_screen` ·
`my_plans_screen` · `client_chat_screen` · `onboarding/identity_setup_screen` ·
`join/join_coach_screen` · `test/membership_status_test` · `pubspec.yaml`
(+`pubspec.lock`), plus §21 corrections to `PROFILE_EXPERIENCE_ARCHITECTURE.md`.

---

## 13. Verdict

Profile no longer tells the member anything the platform cannot back. The five
fossils are gone — from Profile, and from the two other screens that had quietly
inherited them. A paused membership reads *Paused* on every surface. A member can
reach their own identity at any time, whatever their coach did first. They can
see, for the first time, exactly what their coach can see — computed by the same
function that performs the sharing. And they can leave, which the app previously
gave them no way to do.

What remains is honest and enumerated: two URLs, one Storage rule, one cross-repo
schema decision, and the redesign this phase was told not to start.

**The foundation is true. It is not yet beautiful, and it was not meant to be.**

---

*Nothing committed. Nothing deployed.*
