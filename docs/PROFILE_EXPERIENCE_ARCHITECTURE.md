# Member Profile Experience — Architecture (Discovery)

- **Date:** 2026-07-28
- **Status: design only. No code, no schema change, no Firestore change, no commit.**
- **Scope:** the member's complete identity, account and profile experience —
  every screen, controller, service, model, route, Firestore read and backend
  dependency that the Profile tab touches, audited end to end across
  `alphaserena`, `trainersHQ` and `trainershq-backend`; then the experience
  redesigned from first principles.
- **Direction taken (Engineering Authority, this session):**
  - PHI (medical, documents, emergency contact) is **specified now, built in a
    later phase**.
  - The information architecture is **designed to survive multi-organisation**;
    **single-org ships**.

---

## 1. Complete reconstruction

### 1.1 Where Profile sits

`ClientProfileScreen` is tab 4 of 4 in `ClientDashboard`, held in a kept-alive
`IndexedStack` alongside Home, My Plans and Progress. There is no named route; it
is never pushed, never popped, and never rebuilt from scratch after first paint.
On wide viewports the bottom bar becomes a `NavigationRail` and content is capped
at `Breakpoints.maxContent`.

The whole screen is **one 1,512-line `StatelessWidget`** with 11 private build
methods and 3 private classes (`_RateCoachCard`, `_RateSheet`, `_FeedbackSheet`)
in the same file. There is no Profile controller, no Profile model, and no
Profile service. Every value is read inline from two `Rxn<Map<String, dynamic>>`
documents.

### 1.2 Screen inventory reachable from Profile

| Destination | How | Owner |
|---|---|---|
| `BodyMeasurementsScreen` | account row | Profile *(also reachable twice from Progress)* |
| `NotificationSettingsScreen` | account row | Profile |
| `FeedbackHistoryScreen` | account row | Profile |
| `MembershipScreen` | subscription card tap | shared with Home |
| Feedback sheet (modal) | "Help & Support" row | Profile |
| Rating sheet (modal) | "Rate Your Coach" card | Profile |
| Appearance toggle | inline switch | Profile |
| Logout dialog | bottom button | Profile |
| "Personal Information" | account row | **dead — snackbar only** |

**Not reachable from Profile, though they are profile-shaped:**
`IdentitySetupScreen` (Home only, once, and never again), `OnboardingFlowScreen`
(Home only), `NotificationCenterScreen` (Home header), `ClientChatScreen` (Home
header), `CoachStorefrontScreen` (Home header).

### 1.3 Data sources — every read

| # | Read | Shape | Where |
|---|---|---|---|
| 1 | `clientProfiles/{uid}` | live snapshot | `MemberController._start` |
| 2 | `clients/{linkedClientId}` | live snapshot | `MemberController._listenClient` |
| 3 | `membershipPlans where adminId ==` | live snapshot | `MembershipController` (Profile renders none of it) |
| 4 | `org_reviews/{adminId}_{clientId}` | live snapshot | `_RateCoachCard`, **stream recreated on every build** |
| 5 | `client_feedback where authUid ==` | live snapshot | `FeedbackHistoryScreen` |
| 6 | `clientProfiles/{uid}` | one-shot `get` | `NotificationSettingsScreen` |
| 7 | `claimClientAccount` (callable) | CF | pull-to-refresh |

### 1.4 Every write

`org_reviews/{adminId}_{clientId}` (set/merge) · `client_feedback` (add) ·
`clientProfiles.notificationPreferences` (merge) ·
`clientProfiles.measurementsLog` + `latest*` (merge) · `client_progress`
(add, with a visibility choice) · `SharedPreferences.isDarkMode` ·
`FirebaseAuth.signOut`.

### 1.5 Every field currently rendered — and whether it is true

| Rendered | Source | Verdict |
|---|---|---|
| Name | `profile.clientName ?? client.name ?? **'Alpha'**` | fabricated fallback: an un-set-up member is literally called *Alpha* |
| Phone | `FirebaseAuth.currentUser.phoneNumber ?? 'No Phone'` | **empty for every Google sign-in** |
| Email | `profile.email ?? 'No Email'` | only ever written by Identity Setup; a Google member's verified email never lands here |
| Active / Inactive badge | `isLinked && membership.isActive` | a third vocabulary for one fact (see §3) |
| **Age** | `profile.age` | **dead — read from the wrong document** (corrected 2026-07-28, see §21) |
| Height | `profile.height` | transitional dual-write from Identity Setup only |
| Weight | `profile.weightLog.last.weight ?? profile.weight` | real; owned by Progress |
| Joined | `client.createdAt` → `'MMM yyyy'` ?? `'Recent'` | this is when **the coach created their record**, not when the member joined |
| Organisation | `profile.gymName ?? **'Alpha Arena'**` | stale mirror + a fallback that reads as a real gym |
| Org tagline | hardcoded *"Your journey, our arena."* | **not data** — presented as the organisation's own line |
| Coach name | `resolveCoachName(...) ?? **'Your Coach'**` | re-fabricates the exact placeholder the domain layer exists to prevent |
| Coach title | hardcoded *"Performance Coach"* | **not data** |
| Coach photo | `assets/images/trainer.png` | **a stock stranger's face, labelled as the member's trainer** |
| Plan name | `membership.planName ?? **'Transform Program'`** | fabricated fallback |
| Expiry | `membershipExpiry` | real |
| Days left | `expiry.difference(now).inDays` | raw duration; off by one against Home's calendar-day math |
| Rating | `org_reviews` doc | real |
| Dark mode | `ThemeController` | real |

**Available and never shown:** the member's own uploaded `profile.identity.photoUrl`;
`identity.dob`; `identity.gender`; `contact.*`; `preferences.units`; the live
`member.trainerPhotoUrl`; `client.goal`; the org logo and verified badge (Home
resolves both); the 8-state `MembershipStatus`; `clients.sharedProfile` — the
literal answer to *"what can my coach see?"*.

**Absent from the product entirely:** emergency contact · medical · documents ·
units preference surface · language · Terms · Privacy Policy · app version ·
**account deletion** · session/device management · data export · referral ·
membership QR.

---

## 2. Current architecture audit — the UMHIPP position

This is the most consequential finding, and nothing about the Profile UI can be
decided without it.

An approved design spec governs this exact domain:
`trainershq-backend/docs/specs/umhipp-member-identity-privacy-design.md` —
*Unified Member Identity, Health Intelligence & Privacy Platform*. It defines 17
canonical member sections, five visibility tiers
(`onlyMe · emergency · coach · organization · aiSystem`), a member-controlled
clamp, and a five-phase rollout. Its §7 names this work explicitly:
*"Member profile screen becomes modular sections + privacy controls (AlphaSerena,
Phase 7)."*

**Verified current state of that rollout:**

| Phase | Spec intent | Reality |
|---|---|---|
| P1 | policy engine + tests | **done** — `functions/src/lib/member_profile.ts`, 13/13 |
| P2 | member model + privacy map + modular profile screen | **partial** — `core/domain/member_profile.dart` is a byte-identical port but is self-described as *"DELIBERATELY NOT WIRED"*; `MemberIdentityService` writes 3 sections from a once-only onboarding screen; **there is no privacy UI anywhere** |
| P3 | projection CF → `clients.sharedProfile` | **live** — `onClientProfileWritten` is exported and deployed |
| P4 | TrainerHQ consumes the projection | **not done** — `sharedProfile` appears in TrainerHQ only inside a doc comment |
| P5 | backfill + retire legacy fields | **not done** — dual-write still active |

Three consequences follow, and each is a product problem, not a code problem.

**The privacy engine has no steering wheel.** The clamp, the tiers and the
fail-closed authorization primitive are all live and tested. The member has no
control surface to reach any of it. Every projection today runs on
`defaultVisibility`.

**The projection has no destination.** When a member completes Identity Setup,
the CF computes their coach projection and stamps it onto their `clients`
document. No screen in TrainerHQ reads it. The data crosses the privacy boundary
and lands nowhere.

**The Identity Setup privacy promise is not yet true.** That screen tells the
member, twice: *"Your profile is private. Only what you choose to share is
visible to your coach."* In fact `identity`, `contact` and `bodyMetrics` all
default to `coach`, so name, gender, date of birth, email, phone, height and
weight are projected the moment they tap Complete Setup — and the member was
never offered a choice. The sentence describes the system that was designed; it
does not describe the system that is running.

None of this is a leak — the projection is exactly what the approved policy
permits, `clientProfiles` remains 100% member-private, and the rules are intact.
It is a **consent gap**: the design's promise is ahead of its control surface.

**Architectural conclusion.** The Profile redesign should complete P2 and become
the control surface the engine is missing. The alternative — redesigning Profile
on the legacy flat fields — would build a screen that contradicts a backend
already in production.

---

## 3. UX problems

### 3.1 The five fossils

Every truthfulness fix the team made on Home was never back-ported to Profile.
Profile is running the pre-fix version of all five.

1. **Coach naming.** `resolveCoachName` returns `''` when no name can be honestly
   claimed, with an extended comment explaining that placeholder names fired for
   *"essentially every member in production."* Profile takes that honest empty
   string and substitutes `'Your Coach'`.
2. **Organisation naming.** `HomeController` documents its own fix: *"a generic
   label that can't be mistaken for data (the old 'Alpha Arena' fallback looked
   like a real gym)."* Profile still ships `'Alpha Arena'`.
3. **Coach photo.** `resolveCoachPhoto` exists so that callers *"render initials,
   never a stranger's face."* Profile ignores it and renders
   `assets/images/trainer.png` — a stock portrait — under the label *Your
   Trainer*. This is the single worst defect in the audit: the app shows the
   member a photograph of someone who is not their coach and names them as such.
4. **Membership vocabulary.** `MembershipStatus` models eight states with
   deliberately chosen copy — *Paused · Expired · Inactive · No membership · Ends
   today · Ends tomorrow · Ends in N days · Active until 12 Dec 2026*. Profile
   collapses this to a two-state binary.
5. **Loading gate.** `MembershipController` carries an explicit warning that
   `isLoading` tracks the **plans** query and *"says nothing about the member's
   own membership"*, and provides `isMembershipLoading` for exactly that. Profile
   gates on the wrong one.

### 3.2 The consequences of fossil 4 and 5

**A paused member is told their membership expired.** `membershipFrozen == true`
makes `isActive` false, so Profile prints *Expired*. Home prints *Paused*. Those
are different situations with different remedies — one is the coach's deliberate
hold, the other is a lapsed payment — and the app gives contradictory answers on
two screens.

**Active members see a fabricated expiry on first paint.** `member.isLoading`
clears when the `clientProfiles` snapshot arrives; `membership.isLoading` clears
immediately when there is no `adminId` yet; but `isLinked` also flips true from
that same first snapshot. So the subscription card renders while
`client.value` is still null, and a fully paid premium member's first frame reads:

> **Transform Program · Expired · Valid Till N/A**

Every one of those three values is fabricated, and the member's own name badge
beside it says *Inactive*.

### 3.3 Three vocabularies for one fact, sixty pixels apart

On a frozen membership, one screen simultaneously renders **Inactive** (member
card badge), **Expired** (subscription pill) and no countdown — while Home, one
tap away, renders **Paused**. Four labels, one fact.

### 3.4 Dead surfaces

- **"Personal Information"** opens a snackbar: *"To modify profile information,
  edit it via your coach."* The security rules make `clientProfiles/{uid}`
  writable by exactly one party — the member — and readable by no one else. The
  coach **cannot** read or write it. The app instructs the member to ask someone
  to perform an action that person is structurally incapable of performing.
- **The Age tile** reads `profile.age`. Nothing in AlphaSerena, TrainerHQ or the
  backend writes that field, and the coach cannot write to that document at all.
  It renders `--` permanently.

### 3.5 The member cannot see their own face

Identity Setup uploads the member's photo to `profile_photos/{uid}`, writes the
URL to `profile.identity.photoUrl`, and projects it to their coach. The Profile
screen renders `assets/images/avatar.png` with a letter drawn on top of it. The
member never sees the photo they uploaded, anywhere in the app.

### 3.6 Copy that does not match behaviour

- The Profile row says *"Send feedback or a concern **to your coach**"*; the sheet
  it opens says *"Only your **gym admin** sees this — not your trainer."* The row
  contradicts the sheet, and the sheet is the accurate one.
- **"Send anonymously"** writes `anonymous: true` alongside `clientName`,
  `clientId` and `authUid`. TrainerHQ honours the flag in its UI
  (`displayName` → *Anonymous*), so the intent is respected on screen — but the
  identity is fully present in the document, and a member requesting a trainer
  change "anonymously" is identified by `clientId` regardless. The promise is a
  UI convention, not a data property.
- **"Only you and your coach can see your feedback"** (rating sheet). The
  *comment* is genuinely restricted — `org_reviews` list access is admin-only. The
  *rating* feeds the public `organizationProfiles` aggregate rendered on the coach
  storefront. The sentence is true of half of what the sheet collects.

### 3.7 Structural and quality issues

- **Duplicate destination.** Body Measurements is reachable from Profile and from
  two places in Progress. Progress owns the charts, the photos and the weight log;
  Profile owns a third door into the same room.
- **Stream churn.** `_RateCoachCard` constructs a `ReviewService` and a fresh
  stream inside `build()`, so the `StreamBuilder` resubscribes to Firestore on
  every rebuild. Home solved precisely this with `_WithCoachConversation`, whose
  doc comment explains the bind-once pattern.
- **No error state.** If `claim()` fails or either snapshot errors, listeners
  swallow it (`onError: (_) {}`) and the screen shows stale data or the
  not-connected placeholder, with no message and no retry.
- **An unread signal is discarded.** `MemberController.notice` is set to
  `'no_membership'` when the CF reports the member has no gym record. Profile
  never reads it, so the most actionable state a new member can be in is invisible.
- **Pull-to-refresh is partial and conditionally unreachable.** It calls `claim()`
  only — not membership, not reviews, not feedback. And the `ListView` uses default
  physics, so on a viewport where the content does not overflow (tablet, or an
  unlinked member on a large device) the gesture cannot fire at all.
- **The skeleton does not resemble the screen.** Five blocks stand in for six
  sections at different heights, so the layout jumps on load.
- **Dead layout.** The header wraps its only child in an `Expanded` inside a
  single-child `Row`.
- **Destructive-action copy.** *"Exit the Arena?"* is brand voice in a
  confirmation dialog. Confirmations are the one place where voice should yield to
  clarity.

---

## 4. Behavioural analysis

### 4.1 What real coaching businesses look like

Fat-loss and transformation coaching, bodybuilding and powerlifting prep,
women's coaching, PCOS and hormonal coaching, medical and post-injury fitness,
lifestyle and corporate wellness. In the Indian online-coaching market these
share a shape: a small organisation (often one coach), a monthly or quarterly
package sold on WhatsApp or Instagram, a member who is paying real money for
attention, and a relationship that lives or dies on whether the member feels
*seen*.

### 4.2 Why does a member actually open Profile?

Ranked by genuine frequency, not by what a settings screen usually contains:

| # | Reason | Frequency | Stakes |
|---|---|---|---|
| 1 | *When does my plan expire / how many days left?* | high, spiking near renewal | **revenue** |
| 2 | *Who is my coach, how do I reach them?* | high in week 1, then low | retention |
| 3 | *Stop these notifications* | occasional, spiky, anger-driven | **channel loss** |
| 4 | *Something is wrong — wrong plan, wrong trainer, double charge* | low | **churn moment** |
| 5 | *Update my photo / name / weight* | low–medium | identity |
| 6 | *Log out / switch account* | low | trust |
| 7 | *What does my coach know about me?* | today: zero (does not exist) | **trust, esp. women's & medical coaching** |
| 8 | *Delete my account* | rare | **legal** |
| 9 | *Rate my coach* | once or twice, ever | social proof |

### 4.3 The conclusion that should govern the design

**Profile is a low-frequency, high-stakes screen.** A member opens it when they
have a question about their *relationship with the business*, not about their
*training*. Training questions belong to Home, My Plans and Progress — which are
the daily surfaces and are already built for it.

That single insight decides most of the mission's open questions. A screen visited
monthly, often in a moment of friction (expiry, annoyance, complaint, exit), must
optimise for **findability, truthfulness and calm** — never for engagement.
Anything designed to make a member *linger* on Profile is a category error, and
anything the member might urgently need must be reachable without hunting.

Reason 3 deserves emphasis: if a member cannot find the notification controls
inside the app, they mute at the OS level. That kills the coach's push channel
permanently and silently. The setting exists today and is genuinely well built —
it is buried third in an ungrouped list, under an "Account Settings" heading that
does not describe it.

---

## 5. Information architecture

### 5.1 Challenging the proposed hierarchy

The mission proposes ten groups: PROFILE · ACCOUNT · COACHING · MEMBERSHIP ·
HEALTH · PREFERENCES · SUPPORT · SECURITY · LEGAL · DANGER ZONE.

That hierarchy is correct as a **domain model** and wrong as a **screen**. Ten
group headers on a screen visited monthly is ten scroll decisions, and several of
those groups are one decision from the member's point of view:

- **Coaching and Membership are one relationship.** *Who coaches me* and *what I
  pay for, until when* are the same fact to a member; separating them is an
  org-chart split, not a member split.
- **Security, Legal and Danger Zone are all "my account".** No member has ever
  looked for a *Danger Zone* — that is developer vocabulary. Delete is simply the
  last, most destructive thing in Account.
- **Health belongs inside My Information**, not beside it, and — per the direction
  taken — it is specified now and built later.

The member's real mental model is five buckets: *me · my coaching · how the app
behaves · help · the exit*.

### 5.2 The proposed architecture

```
┌─ IDENTITY HEADER ────────────────────────────────────────┐
│  photo · name · organisation · member since              │  → Personal details
└──────────────────────────────────────────────────────────┘

MY COACHING
  Coach                <real name, or "Not assigned yet">   → coach detail
  Membership           <one of eight MembershipStatus lines>→ Membership
  Rate your coach      <your stars, or "Not rated">         → rating sheet

MY INFORMATION
  Personal details     name · photo · date of birth · contact
  Body & health        height · weight · measurements       → Progress
  What your coach sees "3 of 7 shared"                      → Privacy centre

PREFERENCES
  Notifications        "All on · quiet 10pm–7am"
  Appearance           dark / light                          (inline switch)
  Units                kg · cm                               (phase 2)
  Language             English                               (phase 3)

HELP
  Report a problem     goes to your organisation             → report sheet
  My requests          <N open>                              → history

ACCOUNT
  Terms of Service                                           → external
  Privacy Policy                                             → external
  App version          1.0.0 (1)
  Sign out
  Delete account                                             (destructive)
```

Five groups, ~16 rows. Today: three ad-hoc groups, eight rows, of which four
carry fabricated values and one is dead.

### 5.3 The decisions inside that structure

**Rate your coach moves into MY COACHING**, beside the coach it rates. It is not
help and it is not a preference; it is feedback about the relationship, and it
belongs next to the relationship. It stays gated on an active membership, because
the security rules gate the write on `membershipActive`.

**"Help & Support" becomes "Report a problem"**, and its subtitle names the true
recipient: the organisation, not the trainer. Today's label promises a channel to
the coach that the rules explicitly deny.

**Body & health routes to Progress rather than duplicating it.** Progress owns
the weight log, the photo timeline, the charts and the measurement history.
Profile should state the current values and hand off. One room, one door.

**The identity header is a header, not a card.** Photo, name, organisation and
member-since answer *is this me?* at a glance. Everything editable sits behind it.

**Multi-organisation readiness, at zero cost today.** The header carries
org-independent identity; MY COACHING carries the org-scoped relationship. A
second organisation becomes a second MY COACHING block plus a switcher — an
additive change rather than a migration. Nothing multi-org ships now.

### 5.4 What every retained item must justify

| Item | Verdict | Why |
|---|---|---|
| Organisation | **keep**, in the header | it is who the member pays; the fabricated fallback dies |
| Coach | **keep** | but honestly named, honestly pictured, or honestly absent |
| Membership | **keep**, promoted | reason #1 to open the screen |
| Goal | **reject here** | it is coaching content; Home and My Plans own it |
| Progress / achievements | **reject** | Progress and the certified Consistency system own these |
| Health profile | **specify now, build later** | direction taken; needs consent + retention first |
| Emergency contact | **specify now, build later** | high value for medical/women's coaching; PHI-adjacent |
| Diet preference | **reject here** | it is plan input; the coach questionnaire owns it |
| Units | **keep**, phase 2 | already stored under `preferences.units`, never surfaced |
| Language | **keep**, phase 3 | the app is hardcoded English today; see §17 |
| Theme | **keep** | already correct, already the only entry point |
| Notifications | **keep**, promoted | reason #3, and losing it costs the coach their channel |
| Privacy controls | **add — highest value new item** | §2; the engine exists and is unsteered |
| Support / report | **keep**, renamed | reason #4, the churn moment |
| My requests | **keep** | closes the loop; already built and good |
| FAQ | **reject** | one coach, one member, one chat — a static FAQ is a call-centre artefact |
| Terms · Privacy Policy | **add — mandatory** | agreed to at login, unreadable thereafter |
| Delete account | **add — mandatory** | store policy; see §15 |
| Sign out | **keep** | plain copy |
| Referral / invite | **reject for now** | see §18 |
| Community | **reject** | see §18 |
| Membership QR | **reject** | this is an online-coaching product; there is no door to scan at |
| Coach contact | **keep as a route**, not a duplicate | chat lives in the Home header; Profile links to it |
| Version / build | **add** | support triage is impossible without it |
| Beta features | **reject** | no channel exists to gate |

---

## 6. Complete screen hierarchy

```
Profile (tab)
├── Personal details                     [new]      identity · contact · photo
│   └── Change photo                     [new]      camera / gallery / remove
├── Privacy centre                       [new]      per-section visibility
│   ├── What you share                              member-owned sections
│   └── What your organisation holds     [new]      honest read-only disclosure
├── Coach detail                         [new]      name · photo · message · org
├── Membership                           [exists]   status · plans · renew
├── Body & health                        [rework]   → Progress (single owner)
│   └── Body Measurements                [exists]   entry point deduplicated
├── Notifications                        [exists]   good as built
├── Report a problem (sheet)             [rename]   category · message · flags
├── My requests                          [exists]   good as built
├── Rate your coach (sheet)              [move]     into MY COACHING
├── Terms of Service                     [new]      external
├── Privacy Policy                       [new]      external
└── Delete account                       [new]      confirmed, consequence-stated
```

Two additions and one relocation carry most of the value: the **Privacy centre**,
**Delete account**, and moving **Personal details** from a once-only onboarding
screen into a permanently editable surface.

---

## 7. Navigation flow

**Into Profile:** the fourth tab, only. Deep links from a push notification
(membership expiring, coach reply) should land on the relevant destination
directly — Membership or My requests — not on the Profile root.

**Identity Setup, today, is a trap.** It is reachable from exactly one place: the
Home *Getting Started* card, at `ClientStage.identity`. `MemberIdentityService` is
referenced in exactly two files — that screen, and the stage check. The moment
`profile.identity.displayName` is non-empty, the stage advances and the card
disappears. There is no second door. A member who skipped the photo, mistyped
their name or wants to change their date of birth has no route back, and Profile
answers their attempt with a snackbar telling them to ask their coach.

**And the trap can spring before the member ever reaches it.** `HomeController.stage`
evaluates `if (hasPlan) return ClientStage.ready` **before** it checks
`identityDone`, and the Getting Started card only renders while
`stage != ClientStage.ready`. So if the coach assigns a plan before the member
completes setup, the card — the only entrance — never appears at all. That member
can never set a photo, a date of birth, a gender, a height or a weight, in any
build of the app. Their name remains whatever the coach typed into the `clients`
record, or the literal string *Alpha*.

The perverse consequence is worth stating plainly: **the faster and more attentive
the coach, the more likely their member is permanently locked out of their own
profile.** An organisation that assigns plans promptly — the behaviour the whole
product is built to encourage — is the one whose members never get an identity.
This alone justifies moving Personal details into Profile as a permanent surface,
independent of everything else in this document.

**The fix is a boundary, not a new screen.** *Identity Setup* is onboarding —
first-run, sequenced, chained into the coach questionnaire — and should stay on
Home. *Personal details* is maintenance and belongs to Profile. They edit the same
canonical sections through the same service; they differ in framing and entry
point. Onboarding sets up; Profile maintains.

**Out of Profile:** Membership (renewal), Progress (body data), chat (via coach
detail), and external legal URLs. Every one of those is a hand-off to an existing
owner rather than a reimplementation.

---

## 8. Card hierarchy

Today Profile has six visual blocks of nearly identical weight: a bordered card,
a bordered card, a bordered card, a bordered card, a bordered list, a bordered
button. Everything is `p.surface` with `p.border` and `AppRadii.cardR`. Nothing
is more important than anything else, so the member scans all of it every time.

Proposed weight, strongest first:

1. **Identity header** — no border, no card. Photo at 64px, name at title scale,
   a quiet org + member-since line. It is the page's title, not a component.
2. **Membership** — the only card that may carry colour, and only when the state
   is urgent. This is reason #1 for the visit. Frozen, expired and expiring
   states earn an icon plus text; a healthy membership stays calm and states a
   date.
3. **Coach** — a card, plain, with a real photo or real initials. Never a stock
   face, never an invented job title.
4. **Grouped rows** — MY INFORMATION, PREFERENCES, HELP as standard inset lists.
   These are destinations, not content; they should look uniform and boring.
5. **Account** — the same list treatment, with Delete account visually separated
   and coloured only at the point of action.

Rule: **exactly one card may be visually loud, and only when a real state
demands it.** Today three cards compete and the one that matters most is third.

The four-tile stats strip is deleted. One tile is dead, one belongs to Progress,
one reports the coach's record-creation date under the label *Joined*, and the
strip as a whole is a vanity object on a screen whose job is not vanity.

---

## 9. Premium design recommendations

**Truth over decoration, without exception.** Every fabricated fallback is
removed: no *Alpha Arena*, no *Your Coach*, no *Performance Coach*, no
*Transform Program*, no *Recent*, no stock trainer portrait, no member named
*Alpha*. Where a value is unknown, the UI states that it is unknown — *"Coach not
assigned yet"* — which is both honest and actionable. This is not a stylistic
preference; the codebase already made this decision on Home, wrote the reasoning
into the domain layer, and Profile is the one screen that never adopted it.

**One vocabulary per fact.** `MembershipStatus` becomes the only source of
membership language in the app. A frozen membership says *Paused* everywhere.

**Show the member their own face.** The uploaded photo appears in the header, in
the coach's view, and nowhere is a placeholder person substituted for a real one.

**Calm by default, urgent only when it is.** A healthy membership states a date —
*Active until 12 Dec 2026* — rather than counting down 142 days. This reasoning is
already written into `MembershipStatus.text`; Profile simply has to use it.

**Density and type.** The screen currently uses font sizes of 8, 8.5, 9, 10 and
10.5 px. The organisation label — the name of the business the member pays — is
8px. The floor should be 11px for labels and 13px for content, with a real type
scale rather than eighteen ad-hoc sizes.

**The privacy centre is the premium signal.** A member being able to open one
screen and see exactly what their coach can see about them — and change it — is
what separates a coaching platform from a fitness app. It matters most in exactly
the businesses this product serves: women's coaching, PCOS coaching, medical
fitness. It also happens to be the missing half of a system that is already
deployed.

**What premium does *not* mean here.** No glassmorphism, no animated gradients, no
completion ring gamifying an account screen, no motivational copy. This screen is
opened when a member is annoyed, worried or leaving. It should feel like a bank
statement designed by someone with taste — legible, honest, quick to exit.

---

## 10. Accessibility review

**Current state.**

- The only `Semantics` on the entire screen is the dark-mode row. The member card,
  the stats strip, all six account rows, the subscription card, the rating card
  and the logout button expose nothing to a screen reader beyond raw text.
- Membership state is signalled by a coloured pill with an 8.5px label. Removed
  colour leaves *Active* and *Expired* distinguishable only by that text, at a size
  most members cannot read. `MembershipStatus` already provides an `icon` per
  urgent state precisely so *"the state is never signalled by colour alone"* — and
  Profile does not use it.
- Text at 8–10.5px fails every contrast-plus-size guideline regardless of the
  palette, and `p.textMuted` on `p.surface` is the app's lowest-contrast pairing.
- Nothing sets `maxLines`/`overflow` on the stats strip or the org label, so large
  text scales reflow unpredictably inside fixed-height rows and a 56px hard-coded
  divider.
- Tap targets: account rows land near 44px and are acceptable; the rating card's
  *Rate / Edit* text is a label inside a larger tappable card, which is fine; the
  logout `GestureDetector` has no button semantics at all.

**Required.**

Semantic buttons with state on every actionable row · icon-plus-text for every
membership state · an 11px label floor and 13px content floor · `maxLines` with
ellipsis on every name field (long coach and organisation names are the norm, not
the exception, in Indian gym branding) · verified layout at 200% text scale ·
explicit focus order through the five groups · a live-region announcement when an
optimistic toggle reverts.

---

## 11. Loading states

**Current:** one skeleton, gated on the wrong flag, that does not resemble the
screen it replaces — and which clears before the document that carries the
membership truth has arrived (§3.2).

**Required.** The gate becomes `MembershipController.isMembershipLoading`, which
is true until the `clients` document exists. Then:

- **Identity header** — the name is known from `clientProfiles` almost
  immediately; render it as soon as it is real, and skeleton only the photo.
- **Membership** — skeleton until the `clients` document arrives.
  `MembershipState.loading` already exists for this and already renders an empty
  string rather than a date, on the stated principle that *a wrong date is worse
  than no date*.
- **Coach** — skeleton until assignment truth is known; then either a real name or
  an explicit *not assigned* state. Never an interim placeholder name.
- **Rating** — the row renders with no stars until the review stream reports;
  never a zero-star state that reads as a one-star review.
- **Rows** — destinations, not data. Render immediately; their subtitles fill in.

Principle, already established by this codebase on Home: **a skeleton is honest,
a fabricated default is not.** Profile currently fabricates.

---

## 12. Offline states

`ConnectivityController` mounts a full-screen takeover above every route from
`main.dart`, so Profile is never visible while the device is fully offline. That
handles the easy case and hides the hard one.

**The hard case is degraded, not absent, connectivity** — and it is unhandled:

- `claimClientAccount` fails on pull-to-refresh → the `catch` is silent, the
  spinner ends, nothing changed, no message.
- Either snapshot errors → `onError: (_) {}` discards it and the screen shows
  stale data indefinitely.
- The notification toggle saves optimistically and reverts on failure with a
  snackbar — correct, and the only place in the module that gets this right.
- A rating or a report submitted with no connectivity will hang on the Firestore
  write. This is the same failure mode already root-caused in the diet-consumption
  work, where `set()` never resolves offline and the UI showed *Saving…* forever.
  Both sheets here have the identical shape and need the same treatment: a
  timeout, an honest failure message, and the member's typed text preserved.

**Required.** Firestore's local cache means most of Profile renders fine offline —
so the design should say so. A single quiet banner, *"Showing your last saved
information"*, is worth more than five per-card error states. Writes must state
plainly that they will not be sent until the member is back online, and must never
silently discard what the member typed.

---

## 13. Empty states

| Situation | Today | Should be |
|---|---|---|
| No coach connected | a card explaining trainer bio will appear here | *"You're not connected to a coach yet"* + a route to discovery |
| No membership record | `notice == 'no_membership'` is set and never read | a first-class state: *"Your coach hasn't added your membership yet"* + who to contact |
| No trainer assigned, org exists | *"Your Coach"* (fabricated) | *"Your coach will be assigned shortly"* — true, and it is genuinely what happens |
| Never rated | *"Share your experience with the arena"* | keep the intent, drop the brand noun |
| No feedback sent | already good | unchanged |
| No photo | stock avatar + letter drawn on top | initials only, with a clear *Add photo* affordance |
| No body data | dead `--` tiles | *"Add your height and weight so your coach can tailor your plan"* |
| Profile incomplete | invisible | one quiet prompt in MY INFORMATION — never a gamified completion ring on an account screen |

The distinction that matters and is currently collapsed: **"not connected to a
coach", "connected but no membership", and "membership lapsed" are three different
situations with three different remedies.** Today the first is a card, the second
is invisible, and the third is indistinguishable from a paused membership.

---

## 14. Membership lifecycle states

`MembershipStatus` already models the full lifecycle correctly. Profile should
consume it unchanged, and the rest of the screen should react to it:

| State | Membership card | Rate coach | Report a problem | Elsewhere |
|---|---|---|---|---|
| `loading` | skeleton, no date | hidden | available | header skeleton |
| `none` | *No membership* + who to contact | hidden | **available** | this is a support case |
| `inactive` | *Inactive* + renew | hidden | available | — |
| `expired` | *Expired* + renew, urgent | hidden | available | — |
| `frozen` | **_Paused_** + why + when it resumes | hidden | **available** | never *Expired* |
| `endsToday` | *Ends today* + renew, urgent | available | available | — |
| `endsSoon` | *Ends in N days* + renew | available | available | — |
| `active` | *Active until 12 Dec 2026*, calm | available | available | — |

Two rules follow. **Rate-coach visibility must track `isActive`**, because the
security rules gate the write on `membershipActive` — offering a control that the
backend will reject is worse than hiding it. **Report a problem must never be
gated**, because a member whose membership just lapsed or froze is precisely the
member with something to report, and `FeedbackService.canSend` only requires a
link, not an active membership.

Frozen deserves its own treatment. A pause is usually a kindness — travel,
injury, illness, a payment holiday the coach granted. Presenting it as *Expired*
converts a retained member into a confused one.

---

## 15. Security review

**What is sound and should not be touched.** `clientProfiles/{uid}` is readable
and writable by exactly one uid, with `fcmTokens`, `fcmUpdatedAt` and
`linkedClientId` carved out as CF-only — and the rule comment documents the
escalation that carve-out prevents (a member repointing their link at another
org's client doc). `sharedProfile` sits in `serverOwnedClientFields`, so the
projection cannot be forged client-side. `org_reviews` writes are gated on an
active membership with immutable link fields. `client_feedback` is invisible to
trainers by design. The projection CF performs a mutual `authUid` check before
stamping, explicitly to prevent cross-member contamination. This is careful work.

**Gaps that belong to this program.**

1. **No account deletion.** Google Play's Data deletion policy and Apple's
   Guideline 5.1.1(v) both require an in-app path to delete the account for any
   app that lets users create one. There is none — the string does not appear in
   the codebase. This is a store-review blocker, not a nice-to-have, and it is
   genuinely hard here: the member owns `clientProfiles`, but their `clients`
   record, payments and logs are the organisation's business records. The design
   must separate *delete my account and my personal data* from *erase the
   organisation's transaction history*, and say which is which in plain language.
2. **No session or device visibility.** A member cannot see where they are signed
   in or revoke a device. Push tokens are per-device and released on sign-out, but
   a lost phone has no remote remedy.
3. **`org_reviews` single-document reads are open to any signed-in user** who
   knows `{adminId}_{clientId}`. The rule comment acknowledges this and judges it
   low-sensitivity because the aggregate is public. That judgement is reasonable —
   `clientId` is a non-enumerable Firestore id — but the document also carries
   `memberName` and the free-text comment, so it is worth revisiting rather than
   inheriting silently.
4. **No re-authentication before destructive or identity-changing actions.** Once
   deletion and contact editing exist, both need it.

---

## 16. Privacy review

**The consent gap is the finding.** §2 establishes it: the projection runs on
defaults, the member has no control surface, and Identity Setup tells them they
chose. Closing that gap is the privacy work of this program.

**The privacy centre — what it must and must not claim.** A screen that lists the
member's sections and lets them tighten each one would be a real advance. But if
it implies that the member controls *everything the coach knows about them*, it
replaces one inaccuracy with a larger one. The coach independently owns
`clients/{id}` — name, phone, email, gender, age, goal, coach notes, membership,
targets — authored by the organisation and not member-controlled.

So the screen needs two honest halves:

- **What you share** — the member-owned sections, each with a state and, where the
  policy permits, a control. PHI sections stay `onlyMe` and offer opt-in *up to*
  `coach`, never wider; `effectiveVisibility` already clamps anything broader.
- **What your organisation holds** — read-only, plainly explained: *"Your coach
  keeps their own record of you as their client. You can ask them to correct it."*

That second half is the difference between a privacy feature and a privacy
theatre. It is also the honest replacement for today's *"edit it via your coach"*
snackbar — which is the right sentence attached to the wrong data.

**Smaller corrections.** Anonymous feedback should either strip identity at the
write (and accept that the coach cannot follow up) or describe itself accurately
— *"Your name won't be shown to your coach"* — rather than implying the submission
is untraceable. The rating sheet should state that the star rating contributes to
the organisation's public rating while the comment stays private. Both are one
sentence each.

**Deferred but specified.** Medical, documents and emergency contact are designed
here and built in a later phase. Holding PHI brings India's DPDP Act obligations —
purpose limitation, explicit consent, retention limits, breach notification — into
scope, and the correct sequence is consent surface first, data second. Building the
privacy centre now is precisely what makes that later phase safe.

---

## 17. Future expansion strategy

**Phase-ready, designed now, deliberately not built:**

- **Health sections** — medical, documents, emergency contact. Already canonical
  in the registry with the correct defaults (`onlyMe`, opt-in to `coach`;
  `emergency` break-glass). They become additional rows in MY INFORMATION with the
  privacy control already in place. This is where PCOS, medical-fitness and
  post-injury coaching earn their platform.
- **Multi-organisation.** The IA already separates org-independent identity from
  the org-scoped MY COACHING block. A second organisation adds a second block and
  a switcher. The data model needs the real work — `linkedClientId` is singular
  and `claimClientAccount` links one record — but the *screen* will not need
  rearranging, which is the point of deciding this now.
- **Units and language.** `preferences.units` is already written by Identity Setup
  and never surfaced; exposing it is a small, high-satisfaction win. Language is
  larger: the app has no localisation layer and every string is hardcoded English,
  which for an Indian coaching product is a real ceiling. The Profile row is
  trivial; the programme behind it is not, and it should be scoped separately.
- **Wearables and derived data.** The `aiData` section exists in the registry with
  an `aiSystem` tier that is never projected to a coach. When derived features
  arrive they slot in without a policy change.
- **P4 — the coach's view.** Completing the loop so TrainerHQ renders
  `sharedProfile` as privacy-aware sections. Until that ships, the member's
  sharing choices are real but unobserved. This is a TrainerHQ program, not this
  one, but this program is its precondition.

---

## 18. Features deliberately rejected

| Rejected | Why |
|---|---|
| **Completion ring / profile gamification** | The spec proposes one and `completionRatio()` exists. Rejected on this screen: gamifying an account page pressures members into sharing health data for a progress bar, which is the opposite of informed consent. Prompt once, quietly, in context. |
| **Achievements, badges, streaks** | Progress and the certified Consistency system own these, and that system deliberately measures presence rather than manufacturing streaks. Duplicating them here would fragment a considered design. |
| **Weight and measurement logging in Profile** | Progress owns the log, the charts and the photos. Profile states the current value and hands off. |
| **Membership QR / check-in code** | This is an online-coaching product. There is no door. |
| **Referral / invite friends** | Real revenue potential, but it needs attribution, reward mechanics and a coach-side settlement model. Bolting a share sheet onto Profile without those is a dead button. Revisit as its own program. |
| **Community / social feed** | Enormous moderation, privacy and safety surface for a product whose value is one-to-one attention. Explicitly out. |
| **Static FAQ** | One coach, one member, one chat. A generic FAQ is a call-centre artefact that would deflect members away from the channel they are paying for. |
| **Beta features toggle** | No gating channel exists. |
| **Separate "Security" group** | One member, one phone-or-Google identity, no password. Sessions and re-auth belong under Account until there is enough to warrant a group. |
| **"Danger Zone" heading** | Developer vocabulary. Delete is the last row in Account, treated with the weight it deserves. |
| **In-app Terms / Privacy Policy viewer** | External links via `url_launcher`, which is already a dependency and already used by the storefront. A bundled copy goes stale the moment legal updates it. |
| **Editing the coach-owned record** | The member cannot write `clients/{id}` and should not appear able to. The privacy centre explains it instead. |

---

## 19. Implementation roadmap

Phased so each step is independently shippable and independently verifiable. No
code is written until this document is approved.

**Phase 0 — truth (no new features).** Delete every fabricated fallback. Adopt
`MembershipStatus` and `isMembershipLoading`. Use the live coach name and photo
via `resolveCoachName`/`resolveCoachPhoto`, or render initials. Remove the dead
Age tile, the dead "Personal Information" snackbar and the duplicate Body
Measurements entry. Fix the rebuild-time review stream. Correct the report-a-problem
recipient copy. *Outcome: nothing on the screen is a lie. Smallest diff, highest
value.*

**Phase 0.5 — unlock the locked-out (one route, no redesign).** Give Personal
details a permanent entrance from Profile, reusing the existing Identity Setup
form and service unchanged. This is a handful of lines and it is the difference
between a member owning their identity and never being offered one (§7). It ships
ahead of the architecture work because members are locked out **today**.

**Phase 1 — compliance.** Terms and Privacy Policy links. App version and build.
Account deletion, with the personal-data / business-record distinction stated in
plain language and a re-authentication step. *Outcome: the app can pass store
review.*

**Phase 2 — architecture.** Rebuild Profile as the five-group IA over a real
`ProfileController`, decomposing the 1,512-line file into per-section widgets.
Identity header with the member's own photo. Personal details as a permanently
editable surface writing the canonical sections through `MemberIdentityService`.
*Outcome: the member owns their identity, and the file is maintainable.*

**Phase 3 — privacy centre.** Wire `MemberProfile` and the `privacy` map. Build
*What your coach sees* with both halves — what you share, and what your
organisation holds. Correct the Identity Setup promise to match. *Outcome: UMHIPP
P2 is complete and the deployed engine finally has a steering wheel.*

**Phase 4 — accessibility and states.** Semantics throughout, the type floor,
icon-plus-text for every state, 200% text-scale verification, the full empty and
degraded-connectivity matrix, write timeouts on both sheets. *Outcome: usable by
everyone, honest in every state.*

**Phase 5 — preferences.** Units surfaced from the value already stored. *Outcome:
a small, visible win.*

**Later, separately scoped.** Health sections (needs a consent and retention
decision first) · TrainerHQ P4 · localisation · multi-organisation data model.

---

## 20. Final product verdict

**The Profile screen is the one surface of AlphaSerena that was never brought
forward.** Every truthfulness fix this codebase made — honest coach naming, honest
organisation naming, honest photo attribution, one membership vocabulary, loading
gates that refuse to state a date before it is known — was made on Home, written
into the domain layer with its reasoning attached, and never applied here. Profile
still runs the pre-fix version of all five. The result is a screen that greets an
unconfigured member as *Alpha*, tells them their organisation is *Alpha Arena*,
introduces a stock photograph as their *Performance Coach*, and informs a paying
member on first paint that their *Transform Program* is *Expired · Valid Till N/A*.

Worse than any single fabrication: a member whose coach assigned their plan
promptly has **no route to their own identity at all**, in any build, forever —
and the screen that should be that route answers them with a snackbar telling
them to ask their coach to edit a document their coach cannot read.

Underneath that, something more interesting is true. A serious member-identity and
privacy architecture already exists, is specified, is unit-tested, and is
**running in production**. The projection function stamps every member's
coach-visible sections onto their client record on every profile write. No screen
in either app reads it, and no member has ever been shown a control that steers
it. The platform built the hard half — the policy engine, the clamp, the
fail-closed authorization, the projection — and never built the easy half: the
screen where a member sees what their coach can see.

That is the opportunity. This is not a settings page that needs nicer cards. It is
the **control surface of the member's relationship with the business that coaches
them** — what they are paying for and until when, who is responsible for them, what
that person is allowed to know, and how to leave. Those four questions are the
whole product from the member's side of the transaction, and today the screen
answers the first inaccurately, the second dishonestly, the third not at all, and
the fourth incompletely.

Fixing that needs no new backend, no schema change and no new Cloud Function. It
needs the fabrications deleted, the two legally-required surfaces added, and the
privacy engine given the steering wheel it was designed to have.

I can say this without qualification: **this Profile experience is not yet worthy
of a premium coaching platform used by real organisations, real trainers and real
members — and the architecture above is what makes it so.** The gap is not
ambition or infrastructure. It is that one screen was left behind, and the most
valuable thing the platform has already built was never given a door.

---

## 21. Corrections from the Phase 0.5 re-verification (2026-07-28)

Phase 0.5 re-derived every finding above against the three repositories before
touching code. Three needed correcting; everything else held.

**1. The Age tile — right symptom, wrong root cause.** §1.5 said nothing writes
`age`. In fact `age` is a real, coach-authored field on `clients/{id}`, written
by TrainerHQ (`ClientModel`, and the offline-clients controller). The defect is
that Profile read it from `clientProfiles` — the member-private document, which
the coach cannot write even in principle. *Wrong document, not missing field.*
This changed the fix: the tile is repaired rather than deleted, resolving the
member-authored `identity.dob` first and falling back to the coach's integer.

**2. A latent cross-app schema divergence, not previously noted.** The canonical
section registry specifies *sections* but not their *fields*, and the two apps
have already diverged inside `identity`: AlphaSerena writes `displayName` and
`dob`; TrainerHQ's `ClientProfileAdapter` reads `name` and `age`. Nothing breaks
today because P4 is unbuilt, but the projection AlphaSerena produces would not be
readable by the coach app as written. AlphaSerena now reads both keys, which is
tolerance, not a fix — the schema decision is cross-repo and belongs in its own
governed change.

**3. Membership parity with TrainerHQ is not exact.** Both apps agree on the
7-day "expiring soon" threshold, and both are internally consistent, but three
differences exist:

- **Precedence.** AlphaSerena checks frozen before "has a record"; TrainerHQ
  checks "has a record" first. Only reachable on incoherent data (frozen with no
  membership), so no member-visible impact.
- **`hasMembershipRecord`.** AlphaSerena treats the mere *presence* of the key as
  a record; TrainerHQ requires an expiry or an active flag. A document carrying
  `membershipActive: false` and no expiry therefore reads *Inactive* to the
  member and *No membership* to the coach.
- **Day counting.** TrainerHQ uses `ceil()` on a duration; AlphaSerena's
  `MembershipStatus` counts calendar-day boundaries; Profile used raw truncation.
  Profile's third algorithm is gone — it now uses the shared engine — leaving two
  across the platform.

These are recorded rather than changed: altering AlphaSerena's semantics to match
TrainerHQ would change certified Home behaviour, and altering TrainerHQ is
outside this repository. It is a genuine cross-app item for a later governed
change.

**Everything else verified as written**, including the lockout (and its sharper
form in §7), all five fossils, the frozen→"Expired" contradiction, the
fabricated-first-paint sequence, the absent account deletion, and the unreachable
legal documents.

---

*Discovery complete. Phase 0.5 implementation is certified separately in
`PROFILE_FOUNDATION_CERTIFICATION.md`.*
