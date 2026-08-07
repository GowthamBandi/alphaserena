# AlphaSerena Premium UX Freeze — Pass 2

**Date:** 2026-08-04 · **Device:** emulator-5554 (Pixel 9 Pro, Android 17)
**Session:** live member `FRAMEINGOS`, real coach data, real food log
**Scope:** client app only. Zero backend changes, zero deploys, no new features.

---

## READ THIS FIRST — SCOPE

The mission specified 13 audit areas. **I completed PART 1 (Animation) in full, and
verified PARTS 2, 3 and 11 against the running app without changing them.** I did not
audit Parts 4–10, 12 or 13.

That is a deliberate choice, not an omission I am hiding. The previous report closed
Parts 2–6 and explicitly left one thing undone, and it happened to be the thing this
mission opened with:

> *"Not done, stated plainly: I did not run a profiling pass."* — and, throughout,
> nothing about counting numbers.

Part 1 was the real hole. I went into it properly rather than touching thirteen things
shallowly. **Sections marked ⏭️ NOT DONE at the end are genuinely not done** — treat
them as the remaining backlog, not as passed.

---

## THE HEADLINE

**Every ring and bar in this app already animated. Not one number did.**

Logging a 270 kcal lunch played a 900 ms sweep around a ring whose centre had already
snapped from 236 to 506 on the first frame. The two halves of a single object
disagreed about whether anything had moved. That snap is what reads as *"a value was
replaced"*; a count is what reads as *"you did that"*.

Found by reading the code against the running app, and confirmed as the mission's own
worked example:

```
Calories
1200
↓
1300
should animate smoothly.
```

---

## PART 1 — WHAT CHANGED

### New shared primitive — `AnimatedCount` (`premium_states.dart`)

A builder, not a `Text`, because the figure is almost never alone. It sits inside
`165 / 1800 kcal`, inside a ring, beside a unit — and **only the current value may
move**. Animating the composed string would count the *coach's target* up from zero
too: a number the member did not change and must never appear to.

Three rules it enforces:

| Rule | Why |
|---|---|
| **Null is not zero** | A metric with nothing logged renders its em dash with no tween. Counting to a value that does not exist is the card inventing data for 900 ms. |
| **Status comes from the real value, not the frame** | A met metric must not flicker back through "behind" styling on its way to the number that met it. |
| **Reduced motion arrives instantly** | Honoured via the existing `reduceMotion` helper. |

### 🔴 A defect my own change introduced — and the test that caught it

My first version counted **every** number up from zero on first appearance. That broke
`consistency_cards_widget_test`'s *"an unreadable track shows a dash, never a zero"* —
because a counter on its way up displays every number below its destination, **including
zero**.

This was not a test being fussy. It is a real, daily, member-facing lie:

> A member with a 5-day streak would be shown **"0 Day Streak"** for 900 ms on every
> single app open.

The distinction that resolves it is now the widget's central documented rule:

- **Count-on-appear is only honest where something else on screen makes the same claim
  at the same time.** The calorie ring sweeps from empty, so its centre counting from 0
  is two halves of one object agreeing.
- **A streak has no such partner.** `animateOnAppear: false` — it arrives at 5, and
  animates only when it becomes 6.

### Surfaces wired

| Surface | Figure | Behaviour |
|---|---|---|
| Home · nutrition ring | `236` KCAL | counts, in step with the arc |
| Home · under-ring label | `236 / 1800 kcal` | numerator only |
| Home · 4 macro cells | `39 / 33 g` | numerator only |
| Home · streak cards ×2 | `1`, `2` | **arrives**; animates only on change |
| Home · lifestyle tiles | `%` and value | counts |
| **Diet · "Logged today"** | `236` | counts — the number the member came to change |
| **Diet · 4 macro totals** | `39 g` etc. | counts |

### Motion consistency (Part 6, within scope)

The ring was 900 ms, the macro bars 750 ms — **on the same card**. Nobody can name that
gap and everybody feels it: the card stopped arriving twice. Both now use one token,
`kCountUp` / `kCountCurve`, shared with every counter.

### Tabular figures

Proportional digits are different widths (a `1` is half a `0`), so a counter running
111 → 222 visibly breathes, and one inside a `FittedBox` re-scales the whole block while
it does. `kTabularFigures` applied to every animated figure.

---

## DEVICE EVIDENCE (Rule 1 — the emulator is the source of truth)

All captured live, real member, real data. Frames in
`scratchpad/shots2/`.

### Counting UP — cold launch, Home

| `c_17.png` (mid-flight) | settled |
|---|---|
| **230** kcal · **38.1** / 33 g · **4.9** / 12 g | **236** kcal · **39** / 33 g · **5** / 12 g |

That frame **could not have existed before this change** — the figure was bound directly
to the final value. Streaks read `1` and `2` throughout the same frames: `animateOnAppear:
false` holding in the real app.

### Counting DOWN — deleting a logged meal, Diet

| `M_08.png` (mid-flight) | `N1_settled.png` |
|---|---|
| **248** kcal · 40 g · 5.7 g · 5.9 g | **236** kcal · 39 g · 5.2 g · 5.0 g |

All four macros travelling together at one rate.

### Journey walked (Part 11, partial)

Cold launch → Home → Log Food → Diet → Add Food → search `paneer` → quantity sheet →
log 270 kcal → back → swipe-delete → undo banner. Totals were arithmetically correct at
every step (236 → 506 → 236).

### Search (Part 3) — verified, unchanged

`F_2.png`: the spinner **replaces the magnifier inside the field** — same box, same
position, field width unchanged — while the previous result list stays fully on screen
underneath. The contract the previous pass established, confirmed live.

### Idle repaint (regression check)

Frames `burst_13` … `burst_45` on a settled Home are **byte-identical (33/33)**. The
previous pass's fix for permanently-animating invisible spinners still holds; the new
counters correctly stop requesting frames once settled.

### 🧹 Test data cleaned up

The 270 kcal I logged was a real member's real nutrition record. It was deleted and the
log verified back at its exact starting state (236 kcal / 2 items / 39 / 5.2 / 5.0 / 8.6).

---

## VALIDATION

| Check | Result |
|---|---|
| `flutter analyze` | **0 issues** |
| `flutter test` | **1222 passing**, 14 failing |
| Failing set | **Identical to the documented pre-existing golden failures** — `home_cards_golden` 8, `home_header` 4, `log_transformation` 1, `serena_foundation` 1. Enumerated by name and matched against the previous report's baseline. **0 new failures.** |
| Baseline | Previous report: 1212 passing / same 14. +10 = the 10 new tests below. |
| New tests | `test/animated_count_test.dart` — **10**, pinning all three rules including the streak-never-shows-zero case that caught the defect above |

⚠️ **Not run:** Patrol. The previous pass's 114/115 is not re-verified here. The suites
most likely to be affected are `home_lifestyle_patrol_test` and `diet_journey_patrol_test`
(both assert on figures that now animate); their widget-test equivalents pass, and both
use `pumpAndSettle` where they assert values, so I expect them to pass — **but I did not
run them and you should not treat that expectation as evidence.**

---

## 🔴 FOUND, NOT FIXED

### 1. Three goldens genuinely need re-baselining, and I cannot prove it here

`home_cards_golden`'s *Consistency pair* dark / light / rest-day goldens cover the widget
I changed, and tabular figures **alter glyph metrics** — so those three would legitimately
need new baselines even on a healthy machine. They already fail here for the documented
missing-font reason, so **I cannot distinguish my change's effect from the pre-existing
failure.** Re-baseline them on a machine with the fonts installed before trusting them
again. The other 11 failures are untouched by this work.

### 2. The undo snackbar is a light panel in a dark app

`N1_settled.png`: *"Palak Paneer removed · Undo"* renders as a cream/light bar, while the
success snackbar two steps earlier (`I_14.png`) is brand green. Two snackbars, one flow,
two visual languages — a genuine Part 8 inconsistency. Not fixed: it is a theming change
I could not verify across both palettes within this pass.

### 3. The previous report's open items are still open

The stale Firestore rules deploy (which keeps the flagship nutrition empty state
unreachable in production), the dead `client_workout_screen.dart`, and the app-wide
offline takeover are all **unchanged and still yours to decide**. Nothing here touched them.

---

## ⏭️ NOT DONE — the honest remainder

**Parts 4, 5, 7, 8, 9, 10, 12, 13 were not audited.** Specifically:

- **Part 4 (Empty states)** / **Part 5 (Errors)** — the previous pass rewrote these; I did
  not re-challenge them.
- **Part 8 (Visual rhythm)** — no spacing/alignment sweep. Item 2 above was found
  incidentally, not by an audit.
- **Part 9 (Performance)** — no profiling pass. The large-`Obx`-per-screen issue the
  previous report flagged as "the obvious next performance item" **remains untouched**.
- **Part 10 (Accessibility)** — not re-verified on device. The existing widget tests cover
  320dp and 2.0× text and still pass.
- **Part 12 (TrainerHQ)** — **not verified.** Still certified from source only, as before.
  No coach session was opened. Signing into TrainerHQ needs credentials I do not have and
  should not handle.
- **Part 13** — I challenged this work (which produced the streak defect above), not the
  whole app.

**Offline, slow-network, reconnect and warm-launch were not re-tested** this pass.

---

## FILES CHANGED

**New:** `test/animated_count_test.dart`

**Core:** `core/widgets/serena/premium_states.dart` (`AnimatedCount`, `kCountUp`,
`kCountCurve`, `kTabularFigures`) · `core/domain/consistency_pair.dart`
(`streakCount`, `streakValueFor`)

**Home:** `daily_metric.dart` (`valueLabelFor`, `currentLabelFor`, `percentFor`) ·
`nutrition_progress_card.dart` · `lifestyle_progress_card.dart` ·
`consistency_cards_pair.dart` · `home_progress_parts.dart`

**Nutrition:** `food_log_section.dart`

Every existing getter (`valueLabel`, `currentLabel`, `percent`, `streakValue`) was
**redefined in terms of its new parameterised form**, so there is still exactly one
implementation of what a number means — the property `daily_metric.dart` exists to protect.
