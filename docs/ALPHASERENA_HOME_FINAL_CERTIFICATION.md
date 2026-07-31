# AlphaSerena Home — Final Experience Certification

- **Date:** 2026-07-28 · **Repo:** alphaserena
- **Mission:** a behavioural redesign, not polish. Home answers ONE question —
  *"what should I do today?"* — and everything that doesn't help today's
  coaching moves or dies.
- **Status: certified. Nothing committed. Nothing deployed.**

**Verification performed:** `flutter analyze` clean · **521 tests pass**
(515 + 6 new hero-truth tests) · debug APK builds. No device run (§10).

---

## 1. Complete Home audit (Phase 0 — reconstructed from source)

Home is one 2,000-line screen over seven controllers (Home, Training, DietLog,
CheckIn, Lifestyle, Streak, Membership), one master `Obx`, pull-to-refresh via
`refreshAll` (claim + training + streaks), and a day-rollover guard on app
resume. Sections found, audited, and ruled on:

| Section | Verdict | Why |
|---|---|---|
| HomeHeader (org·coach·comms·membership) | **keep, #1** | identity + reach-my-coach; already certified truthful |
| Expiry banner (≤7 days) | keep | revenue-critical, time-boxed, honest |
| Getting Started / unlinked / inactive / error cards | keep | lifecycle states, not content; each exclusive |
| Greeting | keep | one line, time-honest, no placeholder names |
| **TODAY hero (TodayPlanCard)** | **keep — it IS the answer** | expected · done · next action, from served expectations |
| Today's Workout (content card) | **keep, demoted & de-duplicated** | execution surface; its status chip removed (see §3) |
| Nutrition Today | **keep, promoted** | highest-frequency action of the day |
| Lifestyle Today | **keep, promoted** | second-highest-frequency action |
| Check-in follow-ups | keep (appears only when due) | actionable, cadence-gated |
| Consistency / streaks | **keep, demoted to reflection** | §2 — challenged the mission's #2 placement |
| **Progress Overview (weight·body-fat·muscle tiles)** | **REMOVED** | duplicated the Progress tab wholesale; yesterday's question on today's screen — information, not coaching |
| Quote | keep, empty-states only | fills screens that have no coaching yet; never shown to a ready member |
| Coach Updates | keep, last | communication, not action |

## 2. The new hierarchy, and the behavioural reasoning (Phases 1–3)

Three registers, in reading order:

```
ANSWER    greeting → TODAY hero (expected · done · NEXT ACTION)
EXECUTE   Nutrition → Lifestyle → Workout content
REFLECT   Check-in follow-ups → Consistency → Coach updates
```

**The mission's proposed order was challenged, half-accepted:**

- **Accepted — nutrition & lifestyle before workout content**, for a
  frequency argument, not deference: a member logs food 3–6× a day and
  lifestyle 1–3×, but starts a workout at most once — and the workout-open is
  already served by the hero's CTA with **zero scroll**. Ordering the
  execute-register by action frequency minimises average reach cost across
  the day's ~6 app opens. The workout content card is also the tallest
  section; putting it first would push every food-logging open below the fold.
- **Declined — Consistency at #2.** Streaks are reflection, not action;
  stats before actions push the day's ask below the fold, and the certified
  Consistency system itself frames presence as *quiet* pride, not a daily
  demand. It reads after execution, where reflection belongs. (The
  motivational-context job at the top is already done by the hero's
  "N of M done" line.)
- **"Today's Plan" was NOT removed** — the mission allowed its removal "if it
  adds no value"; it is the opposite: it is the one card that answers the
  screen's question, and everything else was subordinated to it.

## 3. Duplication removed (Phase 4) — one fact, one owner

- **Workout status told twice, differently.** The hero row said the binary
  "Logged today" while the content card wore the engine's "42% done" chip —
  two vocabularies for one fact, sixty pixels apart, and the exact class of
  contradiction the platform keeps stamping out. **The fraction moved INTO
  the hero** (its one home); the chip is deleted; the content card is now
  content + CTA only.
- **The upgrade this unlocked:** a partial session keeps the hero row OPEN
  with `42% done — resume to finish`, and the next-action button becomes
  **"Resume Workout"** — the single most useful sentence for someone who left
  mid-session. Complete → `Completed`, row closes. Stats unreadable → honest
  presence fallback ("Logged today"), never an invented 0%.
- **Progress Overview deleted** (§1) — with its now-dead `_statCard` helper.
- The content card's own CTA reads **Resume Workout** from the same engine
  bool, so the two CTAs can never disagree.

## 4. Data flow & cross-section truthfulness (Phase 8)

Every number on Home now has exactly one producer:

| Fact | Producer | Home consumers |
|---|---|---|
| what's asked today | server expectation (`getMyTraining`) | hero row states, workout presentation |
| workout progress | `SessionStats` (day-stamped, §5) | hero detail + both CTAs |
| workout presence | streak day-keys (completed work only) | hero done-fallback, streaks |
| nutrition logged | `DietLogController` day stream (realtime) | hero row + nutrition section |
| lifestyle met | logged values vs coach targets only | hero row + lifestyle card |
| check-in due | cadence engine | hero row + follow-up cards |
| membership | `MembershipStatus` engine | header + banners |
| coach/org identity | member-identity layer | header |

No section computes any of these locally; contradiction is now structural,
not disciplinary.

## 5. Self-challenge results (Phase 9)

Attacking my own changes found **one real bug, fixed**: `todayWorkoutStats`
was fetched once and never day-stamped — a phone left overnight would have
woken with the hero claiming yesterday's "42% done — resume" against a fresh
morning. Fixed: stats are **day-stamped**, the public getter refuses to serve
them across midnight (while carefully keeping Obx reactivity — a naïve
throwaway-Rxn return would have silently detached rebuilds), and
`StreakController.ensureFreshDay()` joined the dashboard's existing rollover
guard beside diet/lifestyle/training.

Member simulations traced: new member (Getting Started path untouched) ·
returning ready member (three registers) · rest day (hero rest wording, no
workout content card, no contradiction) · workout half-complete (open row +
Resume everywhere) · complete (row closes, "next" falls to food/lifestyle,
all-done earns quiet) · no nutrition logged (hero open + section CTA) ·
paused membership (blocker card, no private content) · offline (streams
serve cache; stats fetch fails → honest fallback; quote never fabricated) ·
refresh (`refreshAll` + realtime streams → no stale UI path found) · kill/
reopen (controllers rebind; rollover guard) · fresh install (skeleton →
lifecycle cards).

## 6. Nutrition & lifestyle verification (Phases 5–6)

Both sections sit inside the master `Obx` over REALTIME day-doc streams, so
refresh cannot strand them; day rollover is guarded (`ensureFreshDay` on
both controllers, called from the dashboard resume hook); "Log Food" and the
lifestyle CTAs navigate unconditionally to their owning screens (no
state-gated dead buttons found); offline writes ride the diet logger's
certified queued-save contract. The deep logging experiences themselves were
certified in their own missions (diet consumption; lifestyle within Section
1/Phase 4 work) and were re-traced, not re-litigated.

## 7. Workout section verification (Phase 7)

The content card renders only in content modes (training / flexible /
disclosed-unknown); every day-state (rest, excused, paused, not-started,
ended, waiting) lives in the HERO alone — verified: no second state card
remains. Weekly rest days, `dayPlanUnavailable`, replaced/paused plans and
the stale-sync banner all pass through the presentation layer certified in
the weekly-prescription mission. Resume correctness was certified end-to-end
prior mission; Home now *surfaces* it (§3).

## 8. Premium review (Phase 10)

Above the fold a ready member sees: who coaches them → today's ask, with done
state → one button that does the right next thing. Scroll cost fell (one
whole section removed; the tallest card demoted below the two most-used);
cognitive load fell (workout status appears once; countdown noise absent;
reflection after action). What keeps it from "unquestionably premium" is
listed in §10, not hidden: no entrance animation/polish pass, the exercise
preview thumbnails vary in coach quality, and the header is dense on the
smallest phones. **Would I ship this Home as every member's first screen?**
Yes — the story is finally singular, and every number on it is earned.

## 9. Tests

**521 pass** (6 new): partial → open row + real percent + Resume label ·
complete → Completed + closed row · presence-without-stats → honest binary ·
0%/skips-only → no false resume · rest-day bonus keeps rest wording ·
plus the untouched agenda/denominator/greeting suites and the full app suite.

## 10. Honest limitations

1. **No device run** — the reorder, Resume flow and rollover guard deserve
   one manual pass (this mission's changes are UI-flow level).
2. **No golden tests exist** in this repo — visual regressions are not
   machine-checked (mission's VERIFY listed them; they were never built).
3. **`_isPartialToday` reads the streak controller outside the build's
   parameters** — consistent because both sit in the same Obx; noted as a
   candidate for the presentation layer if it ever grows.
4. Section internals (nutrition macros layout, lifestyle tiles, consistency
   cards) were deliberately NOT redesigned — this mission changed the story,
   not every sentence; typography/spacing polish remains open.
5. Coach Updates and check-in internals re-traced only to their certified
   boundaries.

---

*Nothing committed. Nothing deployed.*
