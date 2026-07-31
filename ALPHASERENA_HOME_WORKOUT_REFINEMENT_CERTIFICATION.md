# AlphaSerena — Home, Workout & Video Player Refinement

**Certification date:** 2026-07-29
**Scope:** Member Home hierarchy · Consistency · Home workout card · exercise video player
**Baseline:** `flutter analyze` clean · 521 tests passing
**Result:** `flutter analyze` clean · **584 tests passing** · debug APK builds

> This was a refinement, not a rewrite. The Home architecture — server-resolved
> expectations, a pure prescription engine, presence-vs-completion separation —
> was found sound and was kept. What changed is what the member *sees first*,
> what the workout card *is*, and whether the video player deserves the name.

---

## 1. Reconstruction Audit

Rebuilt from the repository with no assumed context.

### Data flow, as it actually is

```
getMyTraining (Cloud Function, one callable)
   ├── workout {name, items[]}            ─┐
   ├── diet    {name, items[]}             │  TrainingController (Rxn)
   ├── coach   {id, name, photoUrl}        │
   ├── expectation.{workout,diet}          │  ← server-resolved, per local day
   └── prescriptionData.{workout,diet}    ─┘  ← raw versions/excuses/pause

TrainingController ──► HomeController        (lifecycle stage: identity →
                                              onboarding → awaitingTrainer →
                                              preparingPlan → ready)
                  └──► PerformanceController (pure engine: timeline, week,
                                              month, insights, streaks)
StreakController  ──► own logs (day-key sets) + today's SessionStats
```

**Verified strengths, preserved intact:**

- `null` means *unavailable*, never zero. `StreakController` hides a tile rather
  than fabricate a streak of 0; `ServedExpectation.fromMap` returns null rather
  than guess a schedule.
- Completion is separated from presence. `SessionStats.progressPercent` floors,
  so 17/18 sets reads 94 — "100%" is reserved for finishing.
- Weeks-on-plan replaced the workout day-streak, because a 4×/week member could
  never push a day streak past 2.
- Rest, excused and paused sit outside every denominator.
- `workoutSessionIdFor` is deterministic; sessions exist only from meaningful
  activity; skipped ≠ incomplete ≠ abandoned.

The truthfulness discipline in this codebase is genuinely strong. Everything
below was built to preserve it.

### Surfaces audited

| Surface | File | Verdict |
|---|---|---|
| Home | `home/client_home_screen.dart` (1,760 lines) | Hierarchy reworked |
| Today's Plan hero | `home/today_plan_card.dart` | **Removed** |
| Consistency tiles | `home/consistency_cards.dart` | **Replaced by hero** |
| Coach header | `home/home_header.dart` | Unchanged — sound |
| Workout section | `client_home_screen.dart` (~370 lines) | **Replaced by card** |
| Briefing | `workout_briefing_screen.dart` | Unchanged — sound |
| Session | `workout_session_screen.dart` | One addition (resume point) |
| Player | `workout_player_screen.dart` | **Rebuilt** |
| Media serving | `trainersHQ/functions/lib/members.js` | **Patched** |
| Exercise model | `trainersHQ/.../exercise_model.dart` | Authoritative, unchanged |

---

## 2. Problems Found

Every item below was verified in code before it was fixed.

### P1 — Home exercise thumbnails were dead code *(silent, permanent)*

`client_home_screen.dart:1655` read `ex['thumbnail']`. That key is written
**nowhere in either repository**. Every other surface reads `thumbnailUrl`.
Result: every Home exercise row fell through to the grey dumbbell placeholder,
always, for every member, since the row was written.

### P2 — The backend never served the media the app renders *(the big one)*

The deployed `buildWorkout` emitted exactly:

```
name · sets · reps · weight · setRows · videoUrl · instructions · muscleGroup
```

Grep count in `functions/lib/members.js` for what the member app reads:

| Field | Read by | Occurrences in the CF |
|---|---|---|
| `thumbnailUrl` | briefing, player poster, Home | **0** |
| `equipment` | briefing "You'll need", player chip | **0** |
| `difficulty` | briefing "Level", player chip | **0** |
| `videoDurationSeconds` | player chip | **0** |
| plan `description` | briefing "About this plan" | **0** |

`ExerciseModel` (TrainerHQ) authors all five. The coach curated them; the wire
dropped them. Consequence: the briefing's equipment/level cards and the player's
poster and chips **never rendered in production** — silently, with no error,
because absent data is correctly rendered as absent.

### P3 — Deleting the hero would have hidden a due check-in

`_checkInWidgets` contained `if (due) return const [];` — the check-in card
deliberately suppressed itself because the hero carried a "check-in due" agenda
row. Removing the hero without lifting that suppression would have made a due
check-in **invisible**: the member would simply never be asked.

### P4 — The video player was not a player

`VideoPlayer` + a tap-to-toggle `GestureDetector`. No seek bar, no scrub, no
timestamp, no duration, no fullscreen, no mute, no speed, no buffering state.
It force-looped and autoplayed with sound — in a gym, that means the phone
starts making noise the moment an exercise opens.

### P5 — The workout was answered twice, 60px apart

The hero row said "42% done — resume"; the content card below carried its own
title, plan tile and CTA. One fact, two renderings.

### P6 — "Where do I continue?" was not derivable

`SessionStats` knew *how much* was done, never *what is next*. Home could show a
percentage — a number a member can do nothing with — but not the set.

### P7 — Nutrition performance became unreachable *(a regression I introduced, then fixed)*

Collapsing the two consistency tiles into one hero removed the only route to
`ConsistencyDetailScreen(isWorkout: false)`. Caught in self-review; fixed with a
track switch in the destination itself.

### Noted, not fixed (out of scope)

The deployed `members.js` has **no weekly-plan support** — no `restDay`,
`weekly` or `nextDay` keys. `TrainingController.isWeeklyRestDay`,
`weeklyOverview` and `nextTrainingDay` are therefore inert against the deployed
backend. That belongs to the Weekly Prescription program, not this mission.

---

## 3. Why Today's Plan Was Removed

The hero listed four rows — workout, nutrition, lifestyle, check-in — each with a
status and a detail line. Directly beneath it, the same four facts were rendered
again in full by the sections that own them.

It failed three tests:

1. **It duplicated everything.** Not partially — the nutrition row said "3 of 12
   foods logged" above a nutrition section that renders a calorie ring, macro
   bars and the same count. The lifestyle row said "1 of 3 targets met" above a
   lifestyle card that lists each target.
2. **It cost the member the top of the screen.** A full card of agenda rows sat
   between the header and anything actionable. The workout CTA lived at roughly
   1,000px of scroll.
3. **It answered a question nobody asked first.** A member opening a coaching app
   is not auditing a checklist. The first feeling should be *momentum*.

**Removed, not replaced.** No second dashboard was introduced. Every state the
hero owned was re-homed to the section that owns the underlying fact:

| Hero row | New owner |
|---|---|
| Workout status, rest, excused, paused, not-started, ended, waiting | The session card (§5) |
| Nutrition progress | The nutrition section (already rendered it) |
| Lifestyle targets | The lifestyle card (already rendered it) |
| **Check-in due** | Its own card — **suppression lifted** (P3) |
| "N of M done" day progress | The Consistency hero's week (§4) |

**Also removed**, on the same reasoning:

- The standalone greeting row — one line that said nothing the coach header
  doesn't. *(This is the only place the member's own name appeared on Home. It
  is a deliberate trade for the "Consistency immediately below the header"
  requirement, and it is a one-line restore if you want it back.)*
- The three-row exercise preview — the briefing is one tap away and shows the
  full list; the preview was a second, shorter copy of it.
- `today_agenda.dart`, `today_plan_card.dart`, `consistency_cards.dart` and
  their three test files, deleted with the behaviour they described.

---

## 4. Consistency Redesign

**Position:** immediately below the coach header. First thing seen.

**New files:** `core/domain/consistency_hero.dart` (pure) ·
`screens/dashboard/home/consistency_hero_card.dart` (pure renderer)

### What it shows

```
┌────────────────────────────────────────────────┐
│  ╭───╮   5 day streak                        › │
│  │ 5 │   Today keeps it alive.                 │
│  │days│                                        │
│  ╰───╯                                         │
│                                                │
│   M    T    W    T    F    S    S              │
│  (✓)  (✓)  (●)  ( )  ( )  ( )  ( )             │
│                                                │
│  2 of 5 days done this week      ▰▰▰▱▱▱▱      │
└────────────────────────────────────────────────┘
```

- **One number, large** — the streak in its correct unit (weeks-on-plan wherever
  a prescription exists; days otherwise).
- **One forward sentence** — never backward-facing.
- **The member's own week, seven dots** — read in under a second.
- **The week's ask**, in its own unit (days, or sessions for a frequency plan).

### Every state, honestly

| State | Rendering |
|---|---|
| loading | Skeleton — never a `0` |
| **unavailable** (offline / rules) | Cloud mark, "Your streak is safe" — **never a lost streak** |
| paused | Pause mark, calm, no week bar, no ask |
| unscheduled (no prescription) | Presence only, disclosed: "No schedule set" |
| rest day today | "Rest day — recovery is the work today" |
| excused today | "Today is excused — your coach cleared it" |
| perfect week | "Perfect week" / "All sessions done" |
| comeback (streak 0, history exists) | "Back at it — every run starts with one day" |
| brand new | "Your streak starts today" |

### Realtime & refresh

Reads flow through `Obx` over `StreakController` and `TrainingController`
observables, so a logged set, a pull-to-refresh and a day rollover all land
without a manual reload.

---

## 5. Workout Card Redesign

**New files:** `core/domain/home_workout_card.dart` (pure) ·
`screens/dashboard/home/home_workout_card_widget.dart` (pure renderer)

The card it replaces was a plan tile: a red rectangle, a name, an exercise
count. Correct, and completely inert — it described a document rather than
invited a session.

### Actionable day

```
┌────────────────────────────────────────────────┐
│ ▓▓▓ coach artwork ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ │
│ ▓                                            ▓ │
│ ▓  [TODAY'S SESSION]                         ▓ │
│ ▓  Upper Body                                ▓ │
│ ▓  Prepared for you by Ravi                  ▓ │
│ ────────────────────────────────────────────── │
│  ⌗ 6 exercises   ◷ ≈45 min   ⚙ Barbell·Bench  │
│  ┌──────────────────────────────────────────┐  │
│  │ " Slow negatives today — 3 seconds down. │  │
│  └──────────────────────────────────────────┘  │
│  ▰▰▰▰▰▰▱▱▱▱▱▱▱▱▱  42%                         │
│  ┌──────────────────────────────────────────┐  │
│  │ NEXT  Bench Press                        │  │
│  │       Set 2 of 4  ·  12 reps × 60 kg     │  │
│  └──────────────────────────────────────────┘  │
│  [        Resume Workout              →     ]  │
└────────────────────────────────────────────────┘
```

**The resume point is new engineering, not new UI.** `nextUpFrom()` was added to
`workout_session.dart` as a pure rule (a skipped set is *resolved* and never
re-offered; a skipped exercise is stepped over whole; prescription text passes
through verbatim — `8-12`, `bodyweight`). `StreakController` derives it from the
**same document read** that already produced `SessionStats` — zero extra I/O —
and the session screen passes it live as sets are logged.

### Every mode

| Mode | Card |
|---|---|
| loading | Skeleton shaped like the real card |
| ready | Artwork · title · "Prepared for you by X" · facts · coach note · Start |
| **inProgress** | + progress bar + **exact next set** + Resume |
| completed | "COMPLETED" badge, 100%, **no button** — a finished day earns quiet |
| **closed by skipping** | "Session closed — 8 sets skipped", true %, no button |
| rest | Calm panel, no artwork, no red button, quiet "Train anyway" |
| excused | Calm panel, success tint (the coach did something *for* them) |
| paused | Calm panel, asks for nothing at all |
| dormant | Plan not started / finished |
| waiting | "X is preparing your training" |
| unavailable | "Your plan is safe" + Retry — **never "your coach assigned nothing"** |

**Artwork:** the first exercise thumbnail the plan carries. Absent → a branded
crest, deliberately, never a broken-image glyph or a grey box.

**Facts are built from real data only.** Absent equipment produces *no chip*, not
a placeholder. Duration is the one estimate on the card and always wears its `≈`.

### Backend patch (not deployed, per instruction)

`trainersHQ/functions/lib/members.js` — additive passthrough:

```js
thumbnailUrl, equipment, difficulty, videoDurationSeconds   // per item
description                                                  // per plan
```

`videoDurationSeconds` is emitted only for a finite positive number, so a junk
value stays `null` and the client omits the chip rather than showing `0:00`.
Syntax-validated with `node --check`. **A deploy is required before artwork,
equipment, difficulty, duration or the plan description reach any member.**

---

## 6. Video Player Redesign

**New files:** `core/domain/video_playback.dart` (pure rules) ·
`core/widgets/premium_video_player.dart` · `workout_player_screen.dart` (rewritten)

| Capability | Before | Now |
|---|---|---|
| Play / pause | tap-toggle only | Centre button + tap zones |
| Replay | ✗ | Button becomes Replay at the end |
| Mute | ✗ | Toggle, and **no autoplay at all** |
| Current time / duration | ✗ | `0:09 / 1:35`, hours-aware |
| Red seek bar | ✗ | Signature `#E10600` played track |
| Draggable thumb | ✗ | 13px thumb, 28px touch band |
| Tap to seek | ✗ | Tap anywhere on the bar |
| Double-tap seek | ✗ | ±10s per half + haptic + flash |
| Fullscreen / landscape | ✗ | Same controller — position preserved |
| Poster | ✗ | Library thumbnail, cached |
| Loading vs buffering | conflated | **Distinct states** |
| Error | **spinner forever** | "Video couldn't load" + Retry |
| Speed | ✗ | 0.5× → 2×, cycling |
| Buffered range | ✗ | Lighter track behind the played track |

**"No video" and "broken video" are different truths.** The coach attaching
nothing is a calm absence; a URL that will never play says so and offers Retry.
The old screen's `catchError((_) {})` left `_ready` false forever — a spinner
that is a permanent promise.

**Deliberate behaviour changes:**

- **No autoplay.** A gym phone that starts making noise on open is a bug the
  member experiences as rudeness.
- **Loop only clips ≤30s.** A 6-second demo that stops dead is useless for
  learning a movement; a 3-minute walkthrough that restarts itself is an
  interruption.
- **Controls persist while paused.** A paused frame is being *studied*; hiding
  the scrubber on it is hostile. They auto-hide after 3s only while playing.

**Coach information retained and expanded** on the exercise screen: prescription
(sets/reps/weight — each only when real), target muscle, equipment, difficulty,
video duration, and the full written instructions. A zero prescription is
treated as missing data, never rendered as "0 sets".

---

## 7. Performance

| Improvement | Detail |
|---|---|
| **Per-frame rebuild eliminated** | The obvious `controller.addListener(setState)` rebuilds the whole subtree — poster, gestures, texture — 60×/s for the entire clip. `VideoPlayerController` *is* a `ValueNotifier`, so only the control overlay subscribes. The texture and gesture layers build once. |
| Poster caching | `CachedNetworkImage` — fetched once ever, reused inline and in the failure state |
| Decode downscaling | `memCacheWidth: 900` on card artwork and poster — a 2000px library photo no longer decodes at full resolution for a 138px band |
| Controller disposal | Always disposed; disposed early if the widget unmounts mid-`initialize()` |
| Timer cleanup | Auto-hide and skip-flash timers cancelled in `dispose` |
| Notifier cleanup | `_uiRevision` disposed |
| Background handling | `WidgetsBindingObserver` pauses on any non-resumed state |
| Orientation restore | Portrait + `edgeToEdge` restored on *every* fullscreen exit, including a system back gesture |
| Network recovery | Retry disposes the dead controller and builds a fresh one |
| No extra reads | The resume point is derived from the session document `StreakController` already fetched |
| Skeleton match | Home's skeleton reshaped to the new order so the screen settles instead of jumping |

**Offline video:** `video_player` has no offline cache and none was added —
caching a coach's video library to device storage is a product and storage
decision, not a refinement. Offline is handled honestly: poster from cache,
clear failure, one-tap Retry.

---

## 8. Accessibility Review

- **Both cards are single semantic nodes** carrying their full meaning. The
  Consistency hero speaks every day of the week (`M, done. T, missed. W, today,
  still open…`) because its colours mean nothing to a screen reader.
- **The week strip carries shape as well as colour** — filled disc (done),
  hollow ring (missed), dash (rest), shield (excused), heavy ring + dot (today).
  Readable in greyscale and with any colour vision.
- **Status is never colour-alone** anywhere in the new work.
- **1.6× text scale on a 320px phone** is an explicit test for both cards and the
  player's empty state. All pass with no overflow.
- **Player controls** are labelled buttons ("Pause", "Mute", "Fullscreen",
  "Playback speed, 1×", "Retry loading the video"); the seek bar is a semantic
  slider reporting percent.
- **Touch targets**: 28px seek band, 34–58px buttons, 44px-class quiet actions.
- **An inert card is not announced as a button** — an unavailable hero offers no
  "Open your full history".

---

## 9. Behavioural Reasoning

The copy engine is tested, not decorative. `consistency_hero_test.dart` asserts
that **no string anywhere** in the hero contains `failed`, `you missed`,
`behind`, `broke`, `lost your`, `didn't` or `should have`, across seven states.

| Principle | Applied as |
|---|---|
| **Loss aversion** | A live streak is named as the headline. A number you can lose is *felt*; a number you read is not. The flame is earned — it lights only for a live streak, never as decoration. |
| **Never guilt** | Guilt produces avoidance, and an avoided app coaches nobody. A missed day is shown (honesty) in a muted hollow ring, never an alarm colour. |
| **Never punish compliance** | The kindest true sentence wins: a member on a coach-approved rest day is congratulated *before* any progress number appears. A tracker that makes following the plan feel like falling behind is the worst kind. |
| **Protect the streak** | Offline, paused and excused all say "your streak is safe" explicitly. |
| **Comeback framing** | A zero streak with history is "Back at it", never a failure. |
| **Reward completion with quiet** | A finished session offers *nothing further*. No upsell, no next task. |
| **Reduce activation energy** | "42% done" tells a member they are behind. "Bench Press, Set 2 of 4, 12 reps × 60 kg" tells them what to pick up. That is the difference between a status and a coach. |
| **The coach must be present** | The prescription note now appears on Home, verbatim, in the coach's accent — the only place a member hears their coach before they tap anything. |

---

## 10. Self Critique

Honest, including two defects I introduced and caught.

1. **I broke Nutrition performance, then fixed it.** Collapsing two tiles into
   one hero removed the only route to `ConsistencyDetailScreen(isWorkout:false)`.
   Fixed with a track switch in the destination — one page, two tracks, using
   `Get.off` so the back stack cannot grow a chain of alternating pages.
2. **Fullscreen controls would have frozen while paused.** The fullscreen route
   is a *separate* route, so the inline player's `setState` could not rebuild
   it; a paused video emits no decoder ticks, so tapping to show controls would
   have appeared to do nothing. Fixed with a shared `_uiRevision` notifier.
3. **The card's `unavailable` mode is currently unreachable from Home.** Home's
   outer branch catches "error and no plan" before the ready branch, and `stage
   == ready` implies `hasPlan`. The mode is correct, tested and defensive — but
   I will not claim members see it today.
4. **The greeting is gone.** Home no longer shows the member's own name
   anywhere. Defensible (the header carries the coach's identity, the hero
   carries motivation) but it is a real loss of warmth, stated rather than
   buried.
5. **I deleted 51 tests** along with the code they covered. Correct — tests for
   deleted behaviour are worse than no tests — but the honest arithmetic is
   +114 new, −51 deleted, 521 → 584.
6. **Artwork is the first exercise's thumbnail, not plan art.** Coaches curate
   images per exercise; there is no plan-level artwork field. This is a
   reasonable proxy, not the real thing, and a plan cover would be better.
7. **The backend patch is not deployed.** Until it is, the artwork band shows
   the crest and the equipment/difficulty/duration chips do not appear. The card
   degrades honestly, but it is not yet showing its best self.
8. **`client_home_screen.dart` is still ~1,400 lines.** I removed ~370 and
   extracted two card families, but the nutrition section alone is ~300 lines
   and should be its own file. Out of this mission's scope; worth doing.

---

## 11. Future Improvements

**Release blocker**

1. **Deploy `getMyTraining`.** Nothing else on this list matters as much. Until
   the patched `members.js` ships, five curated fields still reach nobody.

**High value**

2. A plan-level `coverImageUrl` in the workout-plan builder — real artwork
   instead of borrowing the first exercise's thumbnail.
3. Extract the nutrition section out of `client_home_screen.dart`.
4. A device pass on the player: real seek/scrub feel, fullscreen rotation on
   both platforms, and behaviour on a genuinely slow connection.

**Worth considering**

5. Offline video: pre-cache today's session clips on Wi-Fi. A storage and
   product decision, not a refinement.
6. Return the member's name somewhere on Home without costing a row.
7. Golden tests for both new cards in light and dark (the repo has a
   `test/goldens` directory already).
8. Weekly-plan serving (`restDay` / `weekly` / `nextDay`) — the member app reads
   these and the deployed backend does not send them.

---

## 12. Verification

```
flutter analyze                 No issues found!
flutter test                    +584: All tests passed!
flutter build apk --debug       √ Built build\app\outputs\flutter-apk\app-debug.apk
node --check members.js         syntax OK
```

**New test files (114 tests):**

| File | Tests | Covers |
|---|---|---|
| `consistency_hero_test.dart` | 29 | Hero states, copy engine, no-guilt assertion, week strip, a11y |
| `home_workout_card_test.dart` | 24 | All 11 card modes, fact chips, failure-vs-empty |
| `video_playback_test.dart` | 21 | Clock format, seek clamping, NaN safety, stage resolution |
| `home_cards_widget_test.dart` | 16 | Both cards rendered, 1.6× scale, semantics, handlers |
| `workout_next_up_test.dart` | 14 | Resume point, skip semantics, verbatim prescription |
| `premium_video_player_test.dart` | 10 | Absence vs failure, no placeholder fields |

**Deleted with their code (51 tests):** `today_agenda_test.dart`,
`today_plan_card_test.dart`, `consistency_cards_test.dart`.

Nothing was committed. Nothing was deployed.
