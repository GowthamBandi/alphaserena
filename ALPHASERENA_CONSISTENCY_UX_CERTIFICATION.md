# AlphaSerena — Consistency UX Certification

**Date:** 2026-07-29 (session interrupted mid-output; certification completed same day)
**Scope:** Home Consistency section · Consistency detail screen (both tracks)
**Business logic:** untouched — presentation only, per mission
**Result:** `flutter analyze` clean · **663 tests passing** · 10 goldens · **Patrol 16/16 on device** · debug APK builds

> Goal: transform Consistency from an analytics widget into a motivation
> system. The member should feel *"I've made progress"*, not *"I'm reading
> statistics."*

---

## 1. Repository Reconstruction

Reconstructed from source, no memory trusted:

- **Data:** `ActivityHistoryService` (60-day day-key windows, index-free
  queries, null = unavailable, never zero) → `StreakController` (day-key sets,
  today's `SessionStats`, day-stamped) → `PerformanceController` (thin glue
  over the pure certified engine: `timeline/weekOf/monthOf/insightsFor/
  weeklyAdherenceStreak/dailyStreak`).
- **Previous UI:** two dense Home tiles (streak + week + Today row + Next row
  + two progress bars each) and a six-section analytics detail page (streak
  card, today card, week card, timeline, month grid, insights).

## 2. UX Problems Found

1. **Too much information at the wrong altitude.** Six data points per
   172px-wide Home card. Every number true; the sum read as a dashboard.
2. **No hierarchy.** Streak, week line, Today row, Next row all within a
   ~1.4× size band — nothing dominated, so nothing was felt.
3. **Tiny indicators.** 15px week squares, 3px progress bars: analytics
   furniture, invisible at glance distance.
4. **The detail page told no story.** Six correct sections, none building on
   the previous one. A member finished it informed and unmoved.
5. **26px heat-map cells** — below every touch-target guideline.
6. **Generic statistics** where milestones should be ("best in window" framed
   as a stat, not an achievement).

## 3. Home Redesign

Two cards kept, never merged (each track is its own identity). Per card,
exactly five elements — flame · large streak number (Teko display face) ·
one motivational line · seven week circles (current week only) · "Tap to
view →" affordance. Removed: both progress bars, the "Today" row, the
"Next" row, the week fraction line, all micro-labels.

- The **flame is earned** — lit only by a live streak (tested).
- The **motivation line** is engine-driven (`homeMotivation`): coach-approved
  rest/excused days are celebrated *before* any progress talk; comeback copy
  for a zero streak with history; "Start your first session." for a new
  member; "safe" reassurance for paused/offline. A test asserts no branch
  contains blame words.
- Week circles carry **state by fill + glyph + ring**, not colour alone.
- Press feedback is a 2% `AnimatedScale` shrink + haptic — no 172px ripple
  smear.
- A **Hero tag per track** flies the streak number into the detail screen.

## 4. Detail Screen Redesign — five beats

1. **WHERE YOU STAND** — hero card: flame, "CURRENT STREAK", the number in
   its unit, one encouragement, and the goal-gradient line: *"One more
   workout to reach 3 days."*
2. **THIS WEEK** — seven 34px circles, all six required states visually
   distinct (Completed / Scheduled Rest / Excused / Missed / Today / Future),
   with a legend. A "skipped day" state was deliberately **not invented**:
   the repository records skipped *sets*, not skipped *days* — a day with no
   qualifying log is `missed` whatever happened inside it.
3. **LAST 30 DAYS** — Monday-aligned five-week heat map (pattern legibility),
   34px circles in 40px targets, every past day tappable → a day sheet with
   outcome, expectation, coach reason/note verbatim, and (workout days) the
   real session's Duration/Exercises/Sets/Adherence fetched lazily via the
   same `computeSessionStats` engine.
4. **WHAT YOU'VE EARNED** — 🏆 Longest Streak · 🔥 Current Streak · 💪 Total
   Workouts · 📈 Adherence · 🎯 Monthly Goal. **Every figure states its
   window** ("in 60 days") — a record the 60-day fetch cannot verify is never
   claimed. Unearned figures render an em dash, never a zero.
5. **ONE LAST WORD** — `motivationMessage`: the most *specific* true sentence
   wins ("You're ahead of where you were last week" beats generic
   encouragement). Never fabricated, never guilt.

Adherence is defined as hits ÷ (hits + misses) — rest/excused/paused/open
days excluded from the denominator, so a member who hits all four days of a
four-day plan reads 100%, not 57%.

## 5. Behavioural Psychology Decisions

- **Loss aversion honestly**: the streak dominates; no "streak at risk"
  countdown nag (guilt produces avoidance).
- **Goal gradient**: the next milestone is always slightly ahead, and the
  ladder stops at what the log window can verify (3·7·14·21·30·45·60 days;
  2·4·6·8 weeks).
- **Separate identities**: "I train" and "I eat well" never averaged.
- **Compliance never punished**: rest/excused/paused outside every
  denominator, celebrated first.

## 6. Alternatives Rejected

| Considered | Rejected because |
|---|---|
| Single combined hero (built previously) | One state machine can't render rest-in-one-track/active-in-other; averaged two identities |
| Circular rings per card | Unreadable at 1.6× scale; a ring can't show seven discrete day states |
| "Streak at risk" evening warning | Pure guilt pressure — fires hardest on the worst evening |
| Milestones to 100/365 days | The 60-day window cannot verify them |
| Red misses on the Home rail | Home is momentum; the full miss story lives one tap away |

## 7. Interaction

Home card → press-scale + haptic → **Hero transition** (streak number flies,
`flightShuttleBuilder` renders a bare number so it reads as one object
moving) → detail. Track switch in-place on the detail screen (`Get.off`, so
the back stack never chains). Micro-interactions only; nothing flashy.

## 8. Accessibility

- Each Home card is one semantic node speaking streak + copy + week summary.
- Detail week circles individually labelled ("Wed: scheduled rest"); heat-map
  cells labelled with date + state; inert surfaces never announce as buttons.
- 1.6× text on a 320px phone tested for both surfaces (widget + on-device).
- State never by colour alone (fill + glyph + ring everywhere).
- 40px heat-map targets (was 26px).

## 9. Performance

- No `DateTime.now()` in widgets (todayIndex on the model).
- Day-sheet session fetch is lazy — 30-day grid never fires 30 reads.
- Pure `StatelessWidget` renderers over precomputed models.
- Skeletons shaped like real content (no settle jump).

## 10. Patrol Execution Report (emulator-5554, Android 16)

**16/16 passed** after two fix iterations:

| Iteration | Result | Fixes |
|---|---|---|
| 1 | 13/16 | My assertions matched the achievement tile's "Current Streak" instead of the hero's uppercase label — a false positive that surfaced at 1.6× and landscape |
| 2 | 15/16 + infra EOF | `native.pressBack()` at the root finished the activity and killed Patrol's channel → switched to Flutter-level back |
| 3 | **16/16** | — |

Coverage: both cards render (dark/light/1.6×/mixed week), empty/offline/
loading states, navigation + hero into both tracks and back, full detail
story scroll, all six week states + legend, no-history invitation, landscape,
scroll performance. (Setup note: Patrol was not installed in this repo —
added `patrol` 4.6.1 + CLI, Android `PatrolJUnitRunner` config, orchestrator.)

## 11. Verification

```
flutter analyze              No issues found!
flutter test                 +663: All tests passed!
Patrol (consistency)         16/16 on emulator-5554
flutter build apk --debug    ✓
```

New/updated suites: `consistency_pair_test.dart` (36), `consistency_story_test.dart`
(44), `consistency_cards_widget_test.dart` (21), goldens regenerated.

## 12. Self-Critique

1. The on-device screenshot pass was cut short when the session was
   interrupted; the Patrol assertions and goldens carry the visual evidence,
   and `tool/consistency_preview.dart` remains for a manual capture.
2. Patrol asserting title-case "Current Streak" passed by accident against a
   lazy-list tile — a lesson recorded: assert the *rendered* string.
3. The nutrition day-sheet states less than the workout one (no session doc
   exists for meals) — honest, but asymmetric.
4. Milestone *arrival* is stated, never celebrated — a restrained moment at
   7/30/60 would pay for itself (future).

## 13. Future Improvements

1. Deploy `getMyTraining` (release blocker recorded in prior certifications).
2. Milestone celebration moments.
3. Bundle Poppins/Teko as assets (goldens currently lock layout, not type).
4. A per-day nutrition sheet fed by the diet log document.

Nothing committed. Nothing deployed.
