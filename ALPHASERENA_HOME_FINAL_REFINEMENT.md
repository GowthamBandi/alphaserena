# AlphaSerena — Home Final Refinement

**Date:** 2026-07-29
**Scope:** exactly two sections — **Consistency** and **Today's Workout**
**Untouched:** header, nutrition, lifestyle, check-in, coach updates, navigation, video player, briefing, session, summary
**Result:** `flutter analyze` clean · **615 tests passing** · 10 goldens · debug APK builds

> The previous Consistency redesign — one combined hero card — was rejected.
> This document challenges it, explains why the rejection was right, and
> rebuilds Consistency as two independent premium cards. Today's Workout is
> rebuilt as an execution card with no artwork banner.

---

## 1. Current Problems

### Consistency — the combined hero was wrong

I built it. Reviewing it as a critic rather than its author, three things fail:

**P1 — Averaging two identities into one.** A member does not experience
"consistency". They experience *I trained* and *I ate well* — two behaviours,
two rhythms, two self-images. One card holding a single streak had to pick a
track (it picked workout) and silently drop the other. Nutrition consistency
became invisible on Home, and a strong training week papered over a collapsed
eating week.

**P2 — One state machine for two independently-stated facts.** The engine
already resolves workout and nutrition separately: one can be a prescribed rest
day while the other is mid-progress; one can be unreadable while the other is
live. A single card cannot render that. It had to collapse to whichever state
the workout track was in.

**P3 — It communicated less than what it replaced.** The old two-tile section
showed two numbers and two "logged today / pending" states. The hero showed one
number and one sentence. More pixels, less information. The user's read —
*"the original consistency section communicated progress better"* — is correct.

### Today's Workout — it looked like a report

**P4 — A 138px artwork banner that answered nothing.** A photo is atmosphere.
Atmosphere belongs *inside* the workout, after commitment. On Home it consumed
the most valuable space in the app and pushed the button — the only element
that matters — toward the fold on a small phone.

**P5 — Home was becoming a media surface.** Exercise video on Home invites
browsing. Home is for deciding; the player is for studying.

**P6 — No finished state worth the name.** A completed session showed a badge
and 100%. It stated no duration, no exercise count, no adherence, and offered
no way back to the log. It read like a receipt.

**P7 — Noise mid-session.** "6 exercises · ≈45 min · Intermediate · Barbell"
rendered while the member was 22% through. That is *decision* information; the
decision was already made.

---

## 2. Consistency Redesign — two cards

**Files:** `core/domain/consistency_pair.dart` (pure) ·
`screens/dashboard/home/consistency_cards_pair.dart` (pure renderer)
**Removed:** `consistency_hero.dart`, `consistency_hero_card.dart` and their tests.

```
┌────────────────────┐  ┌────────────────────┐
│ ⬤ WORKOUT          │  │ ⬤ NUTRITION        │
│                    │  │                    │
│ 5 🔥               │  │ 12 🔥              │
│ day streak         │  │ day streak         │
│                    │  │                    │
│ ▮▮▯░░░░            │  │ ▮▮▮░░░░            │
│ 2 of 5 this week   │  │ 3 of 7 this week   │
│ ───────────────    │  │ ───────────────    │
│ Today   22% today  │  │ Today  2 of 4 meals│
│ ▰▰▱▱▱▱▱▱▱          │  │ ▰▰▰▰▱▱▱▱▱          │
│ Next  2 days to 7  │  │ Next  2 days to 14 │
│ ▰▰▰▰▰▰▱▱▱          │  │ ▰▰▰▰▰▰▰▰▱          │
└────────────────────┘  └────────────────────┘
```

**Four beats per card, in descending motivational weight:**

| # | Beat | Workout | Nutrition |
|---|---|---|---|
| 1 | **Streak** | weeks-on-plan (with a schedule) or days | days — eating is genuinely daily |
| 2 | **This week** | `2 of 5 this week` / `2 of 4 sessions` | `3 of 7 this week` |
| 3 | **Today** | `22% today`, from SessionStats | `2 of 4 meals` |
| 4 | **Next** | `2 days to 7` + progress bar | `2 days to 14` + progress bar |

**Genuinely independent.** Two separate calls to `buildConsistencyCard`, each
reading only its own track's `TrackHistory`, `TrackWeek`, day-keys and streak.
A test asserts the workout card ignores meal data and the nutrition card
ignores session stats.

**Every engine state, per track:**

| State | Rendering |
|---|---|
| prescribed rest | `Rest day` chip; Today row states the day, not a fraction |
| flexible schedule | `2 of 4 sessions` — sessions, not days |
| paused coaching | `Coaching paused`, no bars, "streak is safe" spoken |
| coach excused | `Excused` chip, in the success tone |
| unknown schedule | `No schedule set`; the weeks unit is dropped (it needs a plan) |
| offline / unreadable | `—` and `History unavailable` — **never a zero** |
| loading | Skeleton — never a zero |
| realtime | Reads flow through `Obx` over the streak/training observables |

### Milestones — bounded by what the app can actually verify

`ActivityHistoryService` fetches a **60-day** window. A "100-day streak" goal
is therefore something this app can never confirm. Offering it would be a
promise the data cannot keep.

- Day ladder: **3 · 7 · 14 · 21 · 30 · 45 · 60**
- Week ladder: **2 · 4 · 6 · 8** (60 days ≈ 8.5 weeks — which is why it stops
  at 8 rather than a more satisfying 52)
- Above the last rung: no fake goal. The card states
  `Longest we can verify: 60 days`.

### Meals completed

A meal counts when **every** prescribed food in it is marked `eaten` or
`partial`. A meal with an unmarked food is unfinished; a meal skipped outright
was not eaten, and calling it complete would be a generous lie. Grouping
matches the diet screen's own meal keys, case-insensitively.

---

## 3. Workout Redesign

**Files:** `core/domain/home_workout_card.dart` (pure) ·
`screens/dashboard/home/home_workout_card_widget.dart` (pure renderer)

**No artwork banner. No video. No image widget at all** — asserted by a test
(`find.byType(Image)` findsNothing).

### Not started

```
▎TODAY'S WORKOUT
Upper Body                          ← Teko 27, the answer to "what am I doing"
Prepared by Ravi
[⌗ 6 exercises] [◷ ≈45 min] [▮ Intermediate] [⚙ Barbell · Bench]
▎" Slow negatives today — three seconds down.
[            START WORKOUT              → ]
```

### Partially completed

```
▎IN PROGRESS
Upper Body
22%                                  ← Teko 34, larger than the title BY DESIGN
▰▰▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱
┌──────────────────────────────────┐
│ ▶  NEXT EXERCISE                 │
│    Bench Press                   │
│    Set 2 of 4  ·  12 reps × 60 kg│
└──────────────────────────────────┘
[           RESUME WORKOUT            → ]
```

Fact chips are **removed** in this state (P7). Mid-session the next set is the
only useful sentence.

### Completed

```
▎COMPLETED
Upper Body
Completed
100%
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
┌────────┬───────────┬────────┬───────────┐
│  45m   │     4     │ 12/12  │    92%    │
│Duration│ Exercises │  Sets  │ Adherence │
└────────┴───────────┴────────┴───────────┘
[  📋  Review Workout  ]      ← outline, NOT the red CTA
       Edit Workout Log ›
```

The red gradient means **"train now"**. Spending it on "look at what you already
did" would devalue it everywhere else in the app, so the finished state uses an
outline button.

`Review Workout` opens `WorkoutSummaryScreen` rebuilt from the *same*
`SessionStats` and the same `durationSeconds`. `Edit Workout Log` reopens the
session, where a set is actually corrected.

### A fifth state the mission did not name

**Closed by skipping** — every set resolved, but by skipping rather than
finishing. It is over, so it must not say "Start Workout" (denying that
anything happened); it is not complete, so it must not claim 100%. It reads
`SESSION CLOSED · 8 sets skipped · 33%` with the same Review / Edit actions.

### Every non-training day (unchanged behaviour, restyled)

rest · excused · paused · dormant · waiting · offline — each a calm panel with
an icon, no red button, and a quiet "Train anyway" where the coach allows it.

---

## 4. Progress Logic

**One engine. No second calculation anywhere.** `SessionStats.progressPercent`
is `(completedSets / totalSets * 100).floor()`. The card, the consistency
Today row, and the summary all read it.

| Prescribed | Completed | Shows | Test |
|---|---|---|---|
| 9 sets | 2 | **22%** | ✓ |
| 12 sets | 6 | **50%** | ✓ |
| 9 sets (3 exercises) | 3 (= 1 exercise) | **33%**, still IN PROGRESS | ✓ |
| 18 sets | 17 | **94%**, never 100 | ✓ |
| 12 sets | 12 | **100%**, COMPLETED | ✓ |
| 12 sets | 0 | **no bar at all** | ✓ |

- **Floored, never rounded up** — 100% is reserved for actually finishing.
- **One finished exercise never flips the card.** Explicitly tested.
- **"Logged today" does not exist** on either card. A test scans title,
  subtitle, CTA and the full semantic label across three session shapes.
- **A 0% bar is not drawn.** An empty bar reads as failure before the member
  has done anything.
- **Skipped sets count against.** A 100% that included skips would be a lie.

`completedExercises` was added **to `SessionStats` itself**, not to a caller —
a second place computing "exercises done" is exactly how two surfaces start
disagreeing.

---

## 5. Alternative Layouts Rejected

| Considered | Rejected because |
|---|---|
| **Keep the combined hero, add a nutrition line** | Still one state machine. Cannot render rest-in-one-track-and-active-in-the-other, which is a real and common day. |
| **Two stacked full-width consistency cards** | Doubles vertical cost of the least actionable section on Home and pushes the workout button below the fold. Side-by-side is the compression the data supports. |
| **Circular progress rings in each card** | Beautiful at 172px, unreadable at 1.6× text scale, and a ring cannot show a *week* (seven discrete states) without becoming a pie chart nobody can parse. Linear bar + a 7-mark rail carries strictly more. |
| **Milestones to 100 / 365 days** | The log window is 60 days. A goal the engine can never verify is a promise the data cannot keep. Ladders stop at what is observable. |
| **Keeping artwork but shrinking it to a 56px thumbnail** | A small photo is neither atmosphere nor information — it is a decorative square. Removed outright. |
| **A "streak at risk" warning before midnight** | Pure loss-aversion pressure, and it fires hardest on the evening a member is already struggling. Guilt produces avoidance. Rejected on behavioural grounds. |
| **Red gradient CTA on the completed card** | The signature CTA must mean "train now" everywhere, or it means nothing anywhere. |
| **Showing misses in red on the week rail** | The rail's job on Home is momentum. Full miss history — honestly, in context, with reasons — lives one tap away on the performance screen. |

---

## 6. Behavioural Reasoning

| Principle | Applied as |
|---|---|
| **Loss aversion, honestly** | The streak is the biggest thing on each card, in the display face. A number you can lose is *felt*. But no countdown, no "at risk" nag. |
| **Earned signifiers** | The flame lights **only** for a live streak. A permanently lit icon is decoration, and decoration that looks like status is a small lie told daily. Tested. |
| **Goal-gradient effect** | The "Next" milestone bar exists because effort rises as a visible goal approaches. There is always a rung slightly ahead — and never one out of reach. |
| **Separate identities** | Two cards, because "I train" and "I eat well" are two self-images. Merging them lets one hide the other. |
| **Never punish compliance** | Rest, excused and paused sit outside every denominator and render as positive chips. A member following the plan exactly must never read as behind. |
| **Never guilt** | No copy blames. Offline says "your streak is safe". A miss is a neutral slot, not an alarm. |
| **Reduce activation energy** | "22%" tells a member they are behind. "Bench Press, Set 2 of 4, 12 reps × 60 kg" tells them what to pick up. |
| **Reward completion with quiet** | A finished session gets four figures and two calm ways back in — no confetti, no upsell, no next task. The numbers are the reward. |
| **The coach is present** | Their note appears verbatim, in their accent colour, with a quote bar — the only place a member hears their coach before tapping anything. |

---

## 7. Performance

- **No image decoding on Home's workout card.** Removing the banner removed a
  network fetch, a cache entry and a full-width decode from the screen opened
  most.
- **No `DateTime.now()` inside a widget.** `todayIndex` moved onto the model:
  a widget that reads the clock is untestable and can disagree with the rail it
  is drawing when a build straddles midnight.
- **No extra reads.** Duration and the resume point come from the *same*
  session-document fetch that already produced `SessionStats`.
- **`MainAxisSize.min` on all three card panels.** Caught by looking at the
  generated golden: the default `max` made the card stretch to fill any
  loose-height parent. It survived inside Home's ListView only because
  unbounded height forces `min` — a latent bug anywhere else it is reused.
- **Both card families are pure `StatelessWidget`s** with no controllers, so
  they rebuild only when their model changes.
- `IntrinsicHeight` on the pair costs one extra layout pass over two shallow
  subtrees — the correct trade for two cards that must never differ in height.

---

## 8. Accessibility

- **Each consistency card is its own semantic node**, naming its track:
  *"Workout consistency: 5 day streak. 2 of 5 this week. 22% today. Next: 2 days
  to 7."* Two separate nodes, so a screen-reader user can tell the tracks apart.
- **The week rail carries state in shape as well as colour** — filled block
  (done), check (coach excused), dash (rest), pause glyph (paused), heavier ring
  (today). Readable in greyscale and with any colour vision.
- **Status is never colour-alone** anywhere in either section.
- **1.6× text scale on a 320px phone** is an explicit test for the pair *and*
  for the workout card in its densest states (in-progress with a long plan name;
  completed with four figures). All pass with no overflow.
- **An inert card is not announced as a button** — an unavailable track offers
  no "Open full history".
- **Touch targets**: 48px primary and outline buttons, 44px-class quiet actions,
  full-card tap targets for each consistency card.
- **10 goldens** in light and dark lock the layout of both sections.

---

## 9. Self Critique

1. **The rejected hero was my work, and the rejection was correct.** I argued a
   single card would feel more premium. It was quieter, not better: it showed
   one number where two were available and made nutrition consistency invisible
   on Home. Density in the right place beats elegance in the wrong one.

2. **I found a real layout bug only by looking at the rendered golden.** All 605
   tests passed while the workout card stretched to fill loose height. Assertions
   don't see whitespace. That is an argument for goldens, and an argument against
   trusting a green suite as evidence that a UI is right.

3. **The goldens render with a fallback font.** `AppText` routes every style
   through `google_fonts`, which fetches over the network and is not bundled as
   an asset. The goldens lock **layout**, not typography. Worth noting: the
   repo's existing header goldens pass only by accident — thirty earlier tests
   absorb the one font error before the goldens run. Mine absorbs it explicitly
   in a named warm-up test.

4. **Two cards at 172px is genuinely tight.** The four beats fit, but a member
   with a 10-week streak on a frequency plan sees `10` / `weeks on plan` /
   `2 of 4 sessions` — all correct, all near the ellipsis boundary. It holds at
   1.6×, but there is no headroom left for a fifth fact.

5. **The nutrition streak stays in days even with a prescription.** Defensible
   (eating is daily) but asymmetric with the workout card's weeks-on-plan, and a
   member may reasonably wonder why one says "weeks" and the other "days".

6. **`Edit Workout Log` routes to the briefing, not straight into the session.**
   The briefing then offers Resume. One extra tap versus a direct jump, chosen
   because the briefing is the screen that knows how to restore a draft. Not
   ideal.

7. **The card's `unavailable` mode is still unreachable from Home**, as in the
   previous pass: Home's outer branch catches "error and no plan" first, and
   `stage == ready` implies `hasPlan`. Correct, tested, defensive — but not
   something members see today.

8. **Still blocked on a deploy.** `difficulty` and `equipment` chips, and the
   plan description, depend on the `getMyTraining` patch from the previous pass.
   Until it ships, the fact row shows only exercise count and duration.

---

## 10. Future Improvements

**Release blocker**

1. **Deploy `getMyTraining`.** Two of the four fact chips do not exist until it
   ships.

**High value**

2. Bundle Poppins/Teko as assets so goldens lock typography, not just layout —
   and so the app renders its own faces offline on first run.
3. Route `Edit Workout Log` directly into the session with the draft restored.
4. A device pass on the pair at 172px with real long plan names and a
   frequency prescription.

**Worth considering**

5. Milestone *celebration* — the cards state the next rung but nothing marks
   arriving at one. A single restrained moment at 7 / 30 / 60 would pay for
   itself.
6. Align the nutrition streak unit with the workout card, or state in-card why
   they differ.
7. Extract the nutrition section from `client_home_screen.dart` (~300 lines) —
   out of this mission's scope, still true.

---

## 11. Verification

```
flutter analyze              No issues found!
flutter test                 +615: All tests passed!
flutter build apk --debug    √ Built build\app\outputs\flutter-apk\app-debug.apk
```

| Suite | Tests | Covers |
|---|---|---|
| `consistency_pair_test.dart` | 37 | Track independence, milestone bounds, meal rule, every engine state, "never Logged today", a11y |
| `home_workout_card_test.dart` | 32 | Three execution states + closed-by-skipping, progress truthfulness, results, failure states |
| `home_cards_widget_test.dart` | 21 | Both sections rendered, equal-height pair, no artwork, 1.6× scale, semantics, handlers |
| `home_cards_golden_test.dart` | 10 | Pixel lock, light + dark, rest / loading / progress / completed |

Suite total 521 → **615**. Removed with the rejected hero: `consistency_hero.dart`,
`consistency_hero_card.dart`, `consistency_hero_test.dart`, and four orphaned
`consistency_*.png` goldens.

**Sections touched:** Consistency, Today's Workout. Nothing else on Home was
modified.

Nothing committed. Nothing deployed.
