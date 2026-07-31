# AlphaSerena — Home Screen Product Specification

- **Date:** 2026-07-28
- **Status:** Design only. No code, Firestore, Cloud Function or upstream system
  was modified in producing this.
- **Purpose:** the implementation blueprint for the next phase.
- **Grounding rule:** every field named in this document was verified to exist
  in the current codebase. Where a desirable design needs data that does not
  exist, it is listed in §16 as a future dependency and **not** specified as
  buildable now.

---

## 1. Philosophy

### 1.1 The one question

> **Home answers "What should I do today?" — and nothing else.**

Every other question a member has is legitimate and has a home elsewhere:

| Question | Belongs on |
|---|---|
| What should I do today? | **Home** |
| What has my coach prescribed? | My Plans |
| How is my body changing? | Progress |
| Who am I, what do I pay, what are my settings? | Profile |

A card earns a place on Home only if it changes what the member *does in the
next few hours*. That is the entire admissions test, and it is applied to every
section in §3.

### 1.2 What the member actually does

The usage shape of a coached fitness member is lopsided and it should drive the
layout more than any visual instinct:

| Action | Opens per day |
|---|---|
| Log / mark a meal | **4–6** |
| Log water, steps, sleep | 2–3 |
| Start or finish a workout | 1 (on training days) |
| Read a coach message | 0–1 |
| Submit a check-in | ~0.15 (weekly) |
| Look at body-composition trend | ~0.15 (weekly) |

The current Home gives roughly equal vertical weight to all six. That is the
central structural problem: **the screen is organised by topic, not by
frequency or by time.**

### 1.3 Three design laws

**Law 1 — Nothing on Home that cannot change today.**
A tile whose value is identical this morning and next month is not a daily
screen's job. It is reference material.

**Law 2 — State the truth, or say nothing.**
Already the strongest quality of this codebase and it must survive the redesign:
`'--'` instead of a fabricated stat, "no coach target set" instead of a platform
default dressed as a prescription, a distinct load-failure state instead of an
empty state that blames the coach. Every state in §3 is specified to this
standard.

**Law 3 — Predictable place, contextual prompt.**
Sections never reorder themselves — spatial memory is how a daily app becomes
fast. Context is expressed by **one** dynamic element at the top, never by
shuffling the page underneath the member's thumb.

### 1.4 Why premium apps feel premium

Benchmarks were studied for mechanism, not appearance.

- **Apple Fitness / Whoop** — a single composite "today" object above
  everything. You learn your state in under a second, before reading a word.
- **Whoop / Garmin** — one recommendation per day, stated as a sentence. The app
  takes a position instead of presenting a dashboard and outsourcing the
  thinking.
- **Cronometer** — remaining, not consumed. The number that drives a decision is
  the one that gets the large type.
- **Strong / Hevy** — the primary action is a single always-visible button. No
  navigating to start the thing the app is for.
- **MyFitnessPal** — its failure mode is instructive: a home screen that became
  a container for every feature, and now answers nothing quickly.

The common thread is **subtraction**. None of them is dense. AlphaSerena's Home
is currently denser than all of them while carrying less decision-making value.

---

## 2. Information hierarchy

### 2.1 Current (verified from `client_home_screen.dart`)

```
1  Header (org, coach, membership, bell)
2  Expiry banner (conditional)
3  Consistency        ← streaks, retrospective
4  Today's Workout
5  Check-in           ← intermittent, cadence-driven
6  Nutrition Today
7  Lifestyle today
8  Progress Overview  ← 2 of 3 tiles cannot change (§4.1)
9  Coach Updates
```

The member must read six sections and assemble the answer themselves. The screen
opens on *how consistent you have been*, not *what to do*.

### 2.2 Proposed

```
┌────────────────────────────────────────────────────┐
│ 0  HEADER — compact, collapses on scroll           │  trust
├────────────────────────────────────────────────────┤
│ 1  BLOCKERS — only when real                       │  unblock
├────────────────────────────────────────────────────┤
│ 2  TODAY  ── the composite state + one sentence    │  ORIENT   ◄ new
│ 3  NEXT UP ── one primary action                   │  ACT      ◄ new
├────────────────────────────────────────────────────┤
│ 4  NUTRITION TODAY   (highest frequency)           │  DO
│ 5  TODAY'S WORKOUT   (highest intent)              │  DO
│ 6  LIFESTYLE TODAY   (compact, one row)            │  DO
├────────────────────────────────────────────────────┤
│ 7  CHECK-IN          (only when due)               │  RESPOND
│ 8  COACH UPDATES     (only when unread)            │  RESPOND
├────────────────────────────────────────────────────┤
│ 9  CONSISTENCY       (reframed, demoted)           │  REFLECT
└────────────────────────────────────────────────────┘
   Progress Overview → moves entirely to the Progress tab (§4.1)
   Motivational quote → removed (§4.3)
```

Four bands, in the order a human actually needs them: **orient → act → respond →
reflect.** A member who does nothing but glance at band 2 has been served.

### 2.3 The two moves that matter

**Consistency moves from #3 to #9.** Streaks are a retrospective reward, and
leading with them means the app greets you with a verdict before it gives you a
task. Worse, it is loss-framed: the day after a streak breaks, the first thing
the member sees is their failure — precisely when they are most likely to churn.
Reflection belongs after action, and the reframing in §3.9 removes the cliff.

**Progress Overview leaves Home.** Body composition moves on a weekly-to-monthly
cadence. Rendering it daily trains members to ignore that region of the screen,
and it currently violates Law 1 outright (§4.1).

---

## 3. Every section

Each section is specified against the mission's checklist: purpose, priority,
real backend data, empty / loading / error / offline states, interactions,
navigation, expected behaviour — plus the admissions test.

---

### 3.0 Header

**Should it exist? Yes — but smaller.**

**Purpose.** Trust and orientation: *whose* programme is this, *who* is
coaching me, am I in good standing. Members do not read it daily, but its
absence is felt immediately — it is the difference between "my gym's app" and "a
tracking app".

**Priority.** Persistent, low visual weight.

**Real data (all verified):**
- `organizationProfiles/{adminId}` → `logoUrl`, `name`, `verified`
  (`HomeController.orgLogoUrl / orgName / orgVerified`)
- `clients` → membership status/expiry (`membershipStatusLabel`)
- `clients.trainerId` → coach name (`memberController.trainerName`)
- Notification unread count (`NotificationCenterService`)

**Change from today.** It currently occupies ~140 px with a full org row, a
membership line, a coach row and a message pill. Collapse to a **single 56 px
row**: org logo · org name (+ verified badge) · coach avatar · bell. The
membership line moves into the blocker band and appears **only** when
non-nominal (expiring ≤ 7 days, expired, frozen) — a permanent "Active" chip is
a fact that never changes and therefore fails Law 1.

**States.**
- *Empty (unlinked):* AlphaSerena brand row. Never a fabricated org identity —
  the existing `'Your Organization'` fallback is correct and must be kept.
- *Loading:* skeleton the org name only (`orgLoading` already distinguishes a
  genuine in-flight fetch from "no org"). Never flash the fallback at a member
  who has one.
- *Error:* silently fall back to the neutral mark. A failed logo fetch is not
  worth a member-facing error.
- *Offline:* cached logo and names render from Firestore's cache; the bell shows
  the last known count. No error chrome.

**Interactions.** Org row → storefront (only when `canOpenStorefront`). Coach
avatar → chat. Bell → notification centre.

**Behaviour.** Glanced at on first open of a session, then ignored. Collapsing
it is worth roughly one extra card of above-the-fold space.

---

### 3.1 Blockers

**Should it exist? Yes — and it must always win.**

**Purpose.** When something prevents the member from training today, nothing else
on the screen matters.

**Priority.** Above everything except the header. Mutually exclusive — show at
most one.

**Precedence (highest first):** not linked → membership inactive → training load
error → lifecycle stage not ready → membership expiring ≤ 7 days.

**Real data.** `memberController.isLinked`, `membershipController.isActive /
isExpiringSoon / expiry`, `trainingController.error`, `HomeController.stage`
(`identity → onboarding → awaitingTrainer → preparingPlan → ready`).

**Keep exactly as built.** The existing implementation already separates a load
*failure* from "your coach hasn't assigned a plan" — a distinction most apps get
wrong and one that directly protects the coach's reputation. The stage machine
with its step tracker is genuinely good onboarding and should not be touched.

**States.** Each blocker is itself a terminal state with one clear action:
Retry (error), Renew (inactive), Continue setup (stage). Offline: the error card
already reads "Check your connection" — correct.

---

### 3.2 TODAY — the composite state *(new)*

**Should it exist? Yes. This is the single highest-value addition.**

**Purpose.** Answer the whole question in one glance, before any reading. Today
the member must scan six cards and integrate them mentally; this does the
integration for them.

**Priority. #1 in the content area.** Everything below is detail.

**Design.** Three arcs (or a single segmented bar) — **Train · Eat · Live** —
plus one honest sentence.

**Real data — every input already exists. Nothing new is required:**

| Ring | Source | Complete when |
|---|---|---|
| Train | `StreakController.workoutToday` (real saved-session evidence) | a session exists today |
| Eat | `DietLogController.loggedCount / totalFoods` | every prescribed food marked |
| Live | `LifestyleController` logged metrics vs `targets` | each coach-set target met |

**Critical honesty rule.** A ring may only fill against a target the **coach set**.
`NutritionTarget.isCoachGoal` and `LifestyleTargets.hasAny` already make this
distinguishable and both are respected today. Where no target exists, the ring
shows *logging* completion (foods marked / prescribed) and the label says so.
A platform default must never be rendered as a prescription — the existing code
is careful about this and the composite must not undo it.

**The sentence.** One line, generated from the same three inputs, in the
member's own terms:

- all complete → *"Today is done. Nice work."*
- rest day, meals pending → *"Rest day. 3 meals left to log."*
- nothing logged, morning → *"Push day and 6 meals ahead."*
- workout done, meals pending → *"Workout done. 2 meals to go."*

No motivational language, no exclamation marks, no invented urgency. It states
what is true. This is the difference between an app that respects an adult and
one that shouts at them.

**States.**
- *Empty:* no plan at all → this section does not render; the stage blocker owns
  the screen instead.
- *Loading:* three grey arcs at rest + a skeleton line. Never animate a ring
  from 0 while loading — a ring that fills then corrects reads as a data error.
- *Error:* if training failed to load, the blocker owns the screen; TODAY does
  not render a half-truth.
- *Offline:* fully functional. Every input is either a local log or cached, and
  marks made offline count immediately.

**Interactions.** Tapping a ring scrolls to (not navigates to) its section.
Scroll, not push, because the member is orienting, not committing.

**Behaviour.** This becomes the most-looked-at element in the app: 4–8 glances a
day, most lasting under two seconds and ending without a tap. That is success,
not failure — the app answered the question and let them go.

---

### 3.3 NEXT UP — one action *(new)*

**Should it exist? Yes.**

**Purpose.** Turn orientation into motion. The app takes a position on what to
do right now instead of presenting options and outsourcing the decision.

**Priority. #2.** Full-width, primary accent, the only high-emphasis button
above the fold.

**Resolution rule** — first match wins, evaluated against device clock and the
same data as §3.2:

1. Check-in due today → **Complete your check-in**
2. Workout assigned, not done, and it is not late evening → **Start workout**
3. A prescribed meal is unmarked and the current time is within/after its slot →
   **Log {meal}** *(meal slot from `DietItem.meal`; ordering already exists in
   `client_diet_screen._mealOrder`)*
4. A coach-set lifestyle target is unmet → **Log water / steps / sleep**
5. Everything done → no button. A short line: *"Nothing left today."*

**Rule 5 matters.** Most apps manufacture a task rather than admit completion.
Ending the day with a genuine "you're done" is the strongest possible reinforcement
and costs nothing to build.

**Real data.** All four inputs verified above. The only new logic is priority
resolution — pure, local, and unit-testable without Firestore.

**States.** *Loading:* hidden (never a skeleton button — a member will tap it).
*Error/offline:* falls back to the highest-priority action whose data is known
locally; meal logging always qualifies, so the button is never dead.

**Behaviour.** Expect this to become the most-tapped control in the app. It
should feel like the app knows what time it is.

---

### 3.4 Nutrition Today

**Should it exist? Yes — and it should move up.**

**Purpose.** The day's single most-repeated interaction.

**Priority. #3** — first of the detail cards, because it is touched 4–6× a day
against the workout's 1×.

**Real data.** `getMyTraining.diet` → `items[]` (each carrying resolved
calories/protein/carbs/fat/fiber/sugar/saturatedFat, `grams`, `portionLabel`,
`portionQty`, `meal`, `foodId`), plus `clients.dietTargets` resolved through
`resolveNutritionTarget`, plus today's `client_diet_logs` marks.

**Changes required.**

1. **Lead with REMAINING, not consumed.** Cronometer's insight: the number that
   drives the next decision deserves the large type. `caloriesLeft` is already
   computed — it simply is not the hero.
2. **Show protein beside calories at equal weight.** For a coached member,
   protein adherence is the macro a coach actually judges; carbs and fat are
   secondary and fibre is tertiary. Current layout gives all four equal weight,
   which is four numbers and no priority.
3. **Rename "Log Food".** *(This is a real terminology defect — see §4.4.)*
   The destination marks prescribed foods eaten/partial/skipped; it does not
   accept arbitrary food. The label creates a MyFitnessPal expectation the
   product deliberately does not meet. Use **"Mark meals"** or **"Today's meals"**.
4. **Add the next meal by name.** *"Next: Lunch · 620 kcal"* — derived from the
   meal ordering and today's marks. Turns a summary into an instruction.
5. **Keep the dual-mode ring exactly as built.** Real coach goal → "kcal left";
   no goal → logging progress. This is already correct and is a genuine quality
   advantage over competitors that invent a target.

**States.**
- *Empty (no diet assigned):* keep the current "Meal plan on the way" card
  naming the coach. It is honest and reassuring — do not replace it with a
  generic empty state.
- *Loading:* skeleton ring + two skeleton lines.
- *Error:* the diet arrives with the training payload, so a failure is owned by
  the blocker band. Do not render a second error here.
- *Offline:* full function. Marks apply locally and the card must show the
  queued-sync affordance already implemented in the diet logger, not an error.

**Navigation.** Card body and CTA → `ClientDietScreen`.

---

### 3.5 Today's Workout

**Should it exist? Yes.**

**Purpose.** The day's highest-intent action.

**Priority. #4.**

**Real data.** `getMyTraining.workout` → `name`, `items[]` (with `sets`,
`setRows`, `exerciseId`); `StreakController.workoutToday` for real completion
evidence.

**Changes required.**

1. **Add a primary "Start workout" button on the card.** Currently the card is a
   preview and starting requires navigating. Strong and Hevy both put the start
   action one tap from the home surface, and it is the single most consequential
   friction reduction available here.
2. **Show completion state on the card.** `workoutToday` already proves a saved
   session exists. A finished workout should read *"Completed today"* with a
   quiet check, not an unchanged "start" affordance.
3. **Keep the three-exercise preview.** It answers "what am I in for" and is
   cheap. Do not expand it — the full list belongs to the player.
4. **Duration: do not display.** *(Honesty note.)* `WorkoutItem` carries
   sets/reps/weight/rest but **no duration field**, and no session-history
   average is currently computed. Any minutes figure on this card today would be
   invented. Listed as a future dependency in §16.
5. **Preserve the rest-day distinction.** The existing card separates "assigned
   plan with no exercises today" (genuine rest day) from "no plan assigned yet"
   (waiting on the coach). This is a real product insight and must survive.

**States.** *Empty:* the two honest variants above. *Loading:* skeleton card.
*Error:* owned by the blocker band. *Offline:* the plan renders from cache; the
start button works, since the workout player logs locally.

---

### 3.6 Lifestyle Today

**Should it exist? Yes — as one row.**

**Purpose.** Water, steps, sleep and supplements are a 2–3×/day micro-interaction
that must not cost a full card.

**Priority. #5.** Single tappable row, ~64 px.

**Real data.** `LifestyleController` → `waterMl`, `steps`, `sleepHours`,
`supplementChecklist`, `targets` (`waterTargetMl` etc.), `stack`.

**Changes required.**

1. **Inline water increment.** A "+1 glass" tap target on the row itself.
   Water is the highest-frequency, lowest-consequence log in the app; making it
   cost a navigation is the clearest friction defect in the current design.
2. **Keep the existing honest subtitle logic verbatim** — it already
   distinguishes "no coach targets yet" from "nothing logged yet", and refuses
   to show a denominator unless the coach set one. That nuance is hard-won.

**States.** *Empty:* "No coach targets yet — you can still track your day"
(already implemented, keep exactly). *Loading:* skeleton row. *Error:* row
renders with an unobtrusive retry; never blocks the screen. *Offline:* logs
locally. **Note:** `LifestyleLogService` currently shares the offline-hang
defect that was fixed in the diet logger — see §16.

**Navigation.** Row → `LifestyleTodayScreen`. The inline +1 must **not** navigate.

---

### 3.7 Check-in

**Should it exist? Yes — only when due.**

**Purpose.** The coach's scheduled feedback loop.

**Priority. #6.** Renders only when `CheckInController.isDue`; absent otherwise.

**Real data.** Coach cadence on the `clients` doc; submission history via
`check_in_submission_service`.

**Change.** Move out of the daily-action band (currently between workout and
nutrition, where its intermittent appearance shifts the layout members are
building muscle memory for) into the respond band. When due, it is also promoted
to **NEXT UP** (§3.3 rule 1), so demoting the card costs no urgency — it gains
it, because the member now sees it in the one place they always look.

**States.** Not due → absent. Due → prompt with CTA. Submitted today →
confirmation for the remainder of the day, then absent. Offline → allow
composition; queue submission.

---

### 3.8 Coach Updates

**Should it exist? Yes — but conditionally, and higher.**

**Purpose.** The coach's voice. Behaviourally the strongest retention driver in
a coached product: a member who feels watched by a human shows up.

**Priority. #7 — but only when there is something unread.**

**Real data.** `NotificationCenterService().watchItems(uid, limit: 10)`, already
streamed and already correctly hidden when empty.

**Changes required.**

1. **Show only UNREAD items.** Currently the latest three always render, so the
   section becomes wallpaper within a week and stops being noticed at all.
2. **Move above Consistency.** A message from a human outranks a statistic about
   the member's own past.
3. **Cap at two**, with "View all".
4. **Deduplicate against the bell.** The header already carries the unread
   count; the section should suppress itself if the member has visited the
   notification centre since the newest item arrived.

**States.** No unread → absent (already correct). Loading → absent, never a
skeleton; an empty comms section that shimmers implies a message is coming.
Error → absent. Offline → cached items render.

---

### 3.9 Consistency

**Should it exist? Yes — reframed and demoted.**

**Purpose.** Reflection and habit reinforcement.

**Priority. #8 — last.**

**Real data.** `StreakController` → `workoutDays`, `dietDays`, `workoutStreak`,
`dietStreak`, `workoutToday`, `dietToday`, `cap`. All real, all derived from the
member's own logs.

**Changes required.**

1. **Lead with a 7-day dot row, not the streak number.** A streak is a cliff: it
   is either alive or dead, and the day after it dies the app opens on the
   member's failure. A seven-dot row shows *5 of 7*, which is both true and
   recoverable. Keep the streak count as a secondary line — it is genuinely
   motivating while alive, and it should simply stop being the headline.
2. **Merge the two cards into one section with two rows.** Two full cards for
   two numbers is disproportionate at this priority.
3. **Keep the existing hide rule** (`!loading && !hasAny → hidden`), which
   correctly refuses to render two "couldn't load" tiles.

**States.** *Empty:* hidden. *Loading:* the existing skeleton state is already
handled inside `ConsistencyCardData`. *Error:* hidden. *Offline:* cached day
keys render.

**Behaviour.** Looked at deliberately maybe twice a week, and that is the correct
frequency for a reflective metric.

---

### 3.10 Progress Overview — **remove from Home**

**Should it exist on Home? No.**

**Why.** Two independent reasons, either sufficient:

1. **It violates Law 1 — and today it is partly untrue.** See §4.1. Two of the
   three tiles read static profile scalars that cannot change over time.
2. **Cadence mismatch.** Body composition moves weekly at best. A tile that is
   identical for seven consecutive days teaches the member to skip that region
   permanently — and that learned blindness then costs the sections near it.

**What replaces it on Home:** nothing, most days. Optionally **one line**, and
only when there is a genuinely new fact: *"Weight logged 2 days ago — 82.4 kg
(−0.6 this week)"*, sourced from the real `client_progress` collection and
rendered only when an entry exists within the last 7 days. Otherwise absent.

**Where it goes.** The Progress tab, which already exists in the bottom
navigation and is the correct destination.

---

### 3.11 Motivational quote — **remove**

**Should it exist? No.** See §4.3.

---

## 4. Challenging the current implementation

Each issue below states **why it matters**, not merely what it is.

### 4.1 Progress Overview reads a source that cannot progress *(most serious)*

`HomeController.latestBodyFat` reads `clientProfiles.bodyFat`; `latestMuscleMass`
reads `clientProfiles.muscleMass`. **Both are scalar profile fields with no
history array.** They are set at onboarding and never change again.

Meanwhile the app already has a real, per-entry progress log — `client_progress`
(`ProgressLogService.watchEntries()`), carrying `weightKg`, `measurements`,
`photoUrl`, `note` and a `visibility` flag — and **Home does not read it at all.**
Weight on Home comes from a third source again, the legacy `profile.weightLog`
array.

**Why it matters.** A section titled *Progress Overview* in which two of three
tiles are frozen at signup is not a hierarchy problem, it is a truthfulness
problem — the one standard this codebase otherwise holds to rigorously. A member
who loses 4 % body fat over three months sees the same number on Home the entire
time and reasonably concludes the app is broken. There are also **three
independent weight/composition sources** in one app, which will drift.

### 4.2 A fabricated default in the progress chart

`ProgressController.weightSpots` falls back to `?? 70.0` when nothing is logged
— an invented 70 kg data point rendered as a chart.

**Why it matters.** It is the only place in the reviewed code that manufactures a
member-facing number, and it is exactly what Law 2 forbids everywhere else. A
member who has never logged a weight sees a chart of a body that isn't theirs.
*(Progress tab, not Home — recorded here because the Home redesign inherits the
progress domain.)*

### 4.3 The motivational quote is decorative content in premium space

`Quotes.daily()` renders a hardcoded string from a fixed list ("Rise. Grind.
Conquer.") in every non-ready state.

**Why it matters.** It occupies the most valuable region of the screen for a
member who is *blocked* — unlinked, expired, or waiting for a plan — precisely
when they need an action, not a slogan. It also communicates that the app has
nothing real to say, which is the opposite of the intended effect. None of the
ten benchmark apps ships decorative quotes on its primary surface.

### 4.4 "Log Food" promises a feature the product does not have

The control reads *"Log Food"* and navigates to a screen that marks
coach-prescribed foods eaten / partial / skipped. There is no free-text food
entry, and by design there should not be — adherence is the product.

**Why it matters.** Every member arrives with a MyFitnessPal mental model. The
label sets a search-and-add expectation, the screen delivers a checklist, and the
member concludes the feature is broken rather than different. A wrong label is
more damaging than a missing feature, because it converts a deliberate product
decision into a perceived defect.

### 4.5 The hierarchy opens on the past

Consistency (#3) precedes Today's Workout (#4). The first thing a member reads is
a verdict on their history.

**Why it matters.** On a good day it is a small delay before the answer; on the
day after a broken streak it is a demotivator at the exact moment of highest
churn risk. Loss-framed metrics belong after the action, not before it.

### 4.6 Frequency and position are inverted

Nutrition (4–6 opens/day) sits below Workout (1/day), and both sit below
Consistency (~2/week). Progress (~1/week) outranks Coach Updates.

**Why it matters.** Every extra scroll is multiplied by the interaction count.
Nutrition being one card lower costs the member roughly 1,800 unnecessary scroll
gestures a year.

### 4.7 The check-in card shifts the layout intermittently

It renders between workout and nutrition only when due.

**Why it matters.** Spatial memory is how a daily app becomes fast. A section
that appears weekly moves everything below it and breaks the thumb's learned
position, on the one day the member is also being asked to do extra work.

### 4.8 Coach Updates is both buried and duplicated

Three latest notifications at the very bottom, while the header bell already
carries the unread count.

**Why it matters.** Read items rendered indefinitely turn the section into
wallpaper; within a week the member's eye skips it, including on the day the
coach writes something that matters.

### 4.9 A permanent "Active" membership chip

`membershipStatusLabel` returns `'Active'` whenever nothing is wrong.

**Why it matters.** It is a fact that is true 95 % of the time and actionable 0 %
of the time. Status indicators earn their space only by exception.

### 4.10 Typography is inconsistent at the same semantic level

Section titles are drawn variously through `AppText.cardTitle(size: 14)`,
`AppText.title(size: 16)` and direct `GoogleFonts.poppins(fontSize: 14,
fontWeight: w600)` calls within the same file.

**Why it matters.** Inconsistent weights and sizes at one level of the hierarchy
are the single most reliable way for a UI to read as amateur, and it is invisible
in code review — you only see it when the cards sit next to each other.

### 4.11 Colour is used decoratively rather than semantically

`_progressOverview` assigns green to weight, amber to body fat and blue to muscle
mass — three hues carrying no meaning. Elsewhere green legitimately means
nutrition and the brand red means action.

**Why it matters.** Once colour stops meaning something, it stops being readable
anywhere, including where it does mean something.

### 4.12 Structural note: a 1,751-line screen

`client_home_screen.dart` holds 24 private widget builders in one file.

**Why it matters.** Not a member-facing defect, but at this size every section is
harder to test in isolation, and the widget-test gap is exactly how the four
rendering bugs in the sibling admin console survived a certification. The
implementation phase should extract each section into its own widget.

---

## 5. Backend data inventory

Everything the specification depends on, confirmed present. **No new backend
work is required for §3.**

| Data | Source | Used by |
|---|---|---|
| Workout plan + items | `getMyTraining.workout` | 3.2, 3.3, 3.5 |
| Diet plan + items (resolved macros, meal, grams, portions) | `getMyTraining.diet` | 3.2, 3.3, 3.4 |
| Coach daily targets | `clients.dietTargets` → served targets | 3.2, 3.4 |
| Today's meal marks + adherence | `client_diet_logs/{clientId}_{date}` | 3.2, 3.3, 3.4 |
| Workout completion evidence | `StreakController.workoutToday` | 3.2, 3.3, 3.5 |
| Streak history | `StreakController` day-key sets | 3.9 |
| Water / steps / sleep / supplements + targets | lifestyle logs + `LifestyleTargets` | 3.2, 3.3, 3.6 |
| Check-in cadence + history | `clients` cadence, `check_in_submission_service` | 3.3, 3.7 |
| Coach + org identity | `clients.trainerId`, `organizationProfiles/{adminId}` | 3.0 |
| Membership state | `membershipController` | 3.0, 3.1 |
| Notifications | `NotificationCenterService.watchItems` | 3.0, 3.8 |
| Body progress entries | `client_progress` | 3.10 (Progress tab) |
| Lifecycle stage | `HomeController.stage` | 3.1 |

**Deliberately not used:** `clientProfiles.bodyFat`, `clientProfiles.muscleMass`
(§4.1), `Quotes` (§4.3).

---

## 6–10. States and navigation

### 6. Empty states
Every empty state names **who** will fill it and **what** will appear. Never a
generic "No data". The existing "Meal plan on the way — {coach} is building your
nutrition plan" is the model.

### 7. Loading
- **Skeletons, not spinners**, for content with known shape (rings, cards, rows).
- **Never skeleton an action button.** A member will tap it.
- **Never animate a ring from zero while loading.** A ring that fills then
  corrects reads as a data error.
- The screen-wide skeleton already exists and its trigger (`HomeController.isLoading`
  as a plain getter so the enclosing `Obx` tracks all three sources) is correct.

### 8. Errors
- One error at a time, owned by the highest band that can express it.
- Always distinguish *load failed* from *nothing assigned* — already correct and
  non-negotiable, because conflating them makes the coach look negligent.
- Every error offers Retry only where retrying can help.

### 9. Offline
Home is **fully usable offline** and this should be stated to the member once,
not repeatedly:
- Plans render from cache.
- Meal marks, water, steps and sleep all log locally and replay on reconnect.
- Queued writes must read as *"Saved on this device"*, never as failure.
- The TODAY composite and NEXT UP work entirely from local state.
- A single unobtrusive offline pill in the header; no per-card error chrome.

### 10. Navigation
The four-tab structure (Home · My Plans · Progress · Profile) is **correct and
should not change.** Home is the daily surface; the other three are destinations
Home routes into.

| From | To |
|---|---|
| TODAY ring | scroll to section (never a push) |
| NEXT UP | the relevant logger or player |
| Nutrition card / CTA | `ClientDietScreen` |
| Workout card / Start | workout player |
| Lifestyle row | `LifestyleTodayScreen`; inline +1 does **not** navigate |
| Check-in | check-in screen |
| Coach update | notification detail |
| Coach avatar | chat |
| Org row | storefront (only when resolvable) |
| Consistency | Progress tab |

---

## 11. Interaction flow

**Morning (06:00–09:00).** Open → TODAY reads 0/3 → NEXT UP says *"Start
workout"* or *"Log breakfast"* by cadence → one tap → done → Home now reads 1/3.
Target: **under 8 seconds, one tap.**

**Midday.** Open → glance → *"Log lunch"* → mark 3 foods → close. **Under 15
seconds.** This is the highest-volume flow in the product and everything else
should yield to it.

**Post-workout.** Player writes the session → `workoutToday` flips → the Train
ring completes on return. The member should never mark a workout done manually
when the system already knows.

**Evening.** Open → TODAY reads 2/3 → *"Log water"* → inline +1 without leaving
Home. **One tap, zero navigation.**

**Completion.** All three complete → NEXT UP is replaced by *"Nothing left
today."* No manufactured task.

**Weekly.** Check-in due → promoted to NEXT UP and shown as a card → submit →
absent until next cadence.

---

## 12. Visual hierarchy

Five levels, strictly applied:

| Level | Used by | Treatment |
|---|---|---|
| 1 — Hero | TODAY composite | largest element; the only ring above the fold |
| 2 — Primary action | NEXT UP | full-width, brand accent, the only high-emphasis button |
| 3 — Daily cards | Nutrition, Workout | glass cards, equal weight |
| 4 — Compact rows | Lifestyle, Coach Updates | single row, chevron |
| 5 — Ambient | Header, Consistency | muted, low contrast |

**Rules.**
- **One accent-filled button per screen.** Everything else is text or outline.
  The current screen has several competing high-saturation surfaces.
- **Colour is semantic only**: brand red = action, green = nutrition, amber =
  attention, muted = ambient. Retire the decorative hues in §4.11.
- **Gradient exclusively for the primary action.** The workout card's
  `[#D50000 → #8A0000]` gradient currently competes with the brand's own accent.

---

## 13. Typography

Standardise on the existing `AppText` scale; **no direct `GoogleFonts` calls in
screen code** (§4.10).

| Role | Token | Size / weight |
|---|---|---|
| TODAY sentence | `AppText.title` | 20 / 600 |
| Hero numerals (kcal left, protein) | `AppText.display` | 30–32 / 700, tabular figures |
| Section titles | `AppText.cardTitle` | 15 / 600 — **one size everywhere** |
| Card body | `AppText.body` | 13 / 400 |
| Metadata, units | `AppText.body` | 11 / 400, muted |
| Buttons | `AppText.label` | 14 / 600 |

- **Tabular figures for every metric.** Numbers that change must not reflow the
  layout — currently they do.
- **Maximum three type sizes per card.**
- Units always smaller and muted beside their value (`82.4` large, `kg` small),
  never equal weight.

---

## 14. Spacing

An 8 pt grid, using existing `AppRadii` tokens (`sm 14 / md 16 / card 18`).

| Context | Value |
|---|---|
| Screen horizontal padding | 20 (currently 18 — align to grid) |
| Between bands (§2.2) | 28 |
| Between cards inside a band | 16 |
| Card internal padding | 16 |
| Related elements | 8 |
| Tight pairs (value + unit) | 4 |
| Minimum tap target | 48 × 48 regardless of visual size |

**Band separation must exceed card separation.** The current uniform 18 px gap is
why the screen reads as nine equal items rather than four groups — this single
change does more for perceived hierarchy than any colour or type work.

---

## 15. Animation

**Principle: motion confirms, it never entertains.**

| Moment | Motion | Duration |
|---|---|---|
| Ring progress change | animate to the new value | 600 ms, `easeOutCubic` |
| Marking a meal | chip fill + ring tick | 200 ms |
| NEXT UP changing | cross-fade | 250 ms |
| Card entry (first load only) | fade + 8 px rise, 40 ms stagger | 300 ms |
| Pull to refresh | brand-accent indicator | system |
| Day completion | **one** restrained pulse on the composite | 400 ms, once |

**Prohibited:** looping animation, confetti, bouncing, anything that repeats on
every open, and any motion on data the member did not just change. Rings must
animate **only** from their previous real value — never from zero on rebuild,
which reads as data loss.

**Respect `MediaQuery.disableAnimations`** for accessibility.

---

## 16. Future expansion

### 16.1 Needs backend work first — deliberately not specified above

1. **Workout duration** (§3.5). No duration field exists on `WorkoutItem`, and no
   session-average is computed. Requires either a coach-set estimate on the plan
   or a derived average from `client_workout_sessions`.
2. **Coach plan instructions** (already flagged in the diet-consumption
   certification). `buildDiet` returns `{name, items, targets}` only — the plan's
   `description`, the coach's sole free-text field, never reaches the member.
   The natural Home surface is a coach-note line under NEXT UP. **This is the
   highest-value backend gap affecting Home.**
3. **Meal timing.** `DietItem.meal` is a slot name, not a time. NEXT UP's meal
   rule (§3.3 rule 3) must therefore use fixed slot windows rather than real
   prescribed times until a time field exists.
4. **Pre/post-workout meal slots.** `kDietMeals` has six slots and no
   pre/post-workout; AlphaSerena's ordering list already anticipates
   `Pre-Workout`. A two-app taxonomy change.

### 16.2 Known defects the implementation phase should carry

- **`LifestyleLogService` offline hang.** `setMetric` / `setSupplements` await
  Firestore's `set()`, whose Future never completes offline — the same defect
  already fixed in the diet logger. Directly affects §3.6's inline water tap.
- **§4.1 and §4.2**, which the Progress tab work inherits.

### 16.3 Deliberately out of scope

Free-text food logging (adherence is the product), barcode scanning, wearable
integration, social feeds, and in-app workout video. Each would answer a
question other than *"what should I do today?"* and belongs to a different
surface.

---

## 17. Self-challenge — would this feel premium at 1M DAU?

**Does it answer one question?** Yes. Bands 2 and 3 answer it in under two
seconds; everything below is optional detail.

**Does it scale?** Yes. Reads are unchanged — the composite is computed from data
Home already holds. Nothing new is fetched. The only additional logic is local
priority resolution.

**Is anything fabricated?** No. Every number traces to a verified field; three
untrue or invented elements are removed (§4.1, §4.2, §4.3).

**Would a member notice care?** Yes, in five places: the app admits when the day
is done; it never invents a target the coach did not set; it distinguishes a rest
day from a missing plan; it separates a load failure from a negligent coach; and
it works fully offline without pretending otherwise.

**Would it survive a bad day?** Yes — the reframing in §3.9 removes the broken-
streak cliff from the top of the screen.

**Is it dense?** No. Nine sections become four bands, two of which are usually
absent.

**Verdict: yes.** The remaining gap to world-class is not layout — it is §16.1.2:
a coach can write instructions no member can read. Delivering the coach's voice
is worth more than any further visual refinement.

---

*Design specification only. No code, Firestore, Cloud Function or upstream
system was modified. Nothing committed.*
