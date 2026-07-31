# Home Experience — Certification (Final Redesign)

- **Date:** 2026-07-28
- **Delivered:** Home rebuilt around one idea — *the coach prepared today* —
  with a single hero that answers the five questions (expected · done · next ·
  on track · left) and a hierarchy where nothing competes with those answers.
- **Scope held:** AlphaSerena UI only. No backend, no TrainerHQ, no engine
  changes; every number rendered comes from the already-certified domains.
- **Nothing committed. Nothing deployed.**

---

## 1. Audit — what was wrong with the old Home

1. **No single answer.** The five questions were scattered across five cards;
   "what should I do next?" was answered nowhere.
2. **Consistency sat first** — a retrospective score above today's plan,
   answering a question nobody asks at 7 am.
3. **Duplicated states.** The workout section carried both the day's STATE
   (rest/paused/…) and its CONTENT; the check-in card repeated what an agenda
   row can say in one line.
4. **A quiet lie on failure:** with a stale plan in memory, a failed sync
   rendered silently as if it were today's truth.
5. **No greeting, no sense of preparation** — the screen read as a dashboard,
   not as a coach's plan for the member's day.

## 2. Hierarchy decisions (and the challenges made)

New order: **Greeting → TODAY'S PLAN (hero) → Workout content → Nutrition →
Lifestyle → Consistency → check-in follow-ups → Progress → Coach updates.**

- **The hero absorbs, the cards detail.** `TodayPlanCard` holds every
  day-state (rest, excused, paused, starting-soon, finished, waiting), the
  honest progress count, and the ONE next action. The workout section below
  is now content-only (exercise preview) and renders nothing on no-session
  days — one story, told once, less scrolling.
- **Challenged the mission's "Lifestyle before Workout":** lifestyle's
  at-a-glance state ("2 of 3 targets met") now lives INSIDE the hero, so
  promoting its detail card above the workout content would duplicate a fact
  already on screen and push the day's anchor further down. Lifestyle detail
  sits after nutrition; its glance is second row of the fold.
- **Consistency demoted below the day's content** — reflection follows
  action.
- **Removed (duplication/anxiety):** the due-state check-in card (the hero
  row carries it, amber-free); the workout section's state cards (hero);
  the "Active Recovery / Rest Day" empty-items inference (dead since Phase 3
  for served members; the hero's waiting row covers the remnant).
- **Kept deliberately:** the blockers-with-quote flow for not-linked /
  inactive / onboarding members (a warm empty state); the expiry banner
  (money-critical) above everything; the workout card's own CTA (an action
  near the content is convention, not duplication — the hero CTA serves the
  fold, the card CTA serves the scroll).

## 3. UX & behavioural decisions

- **The denominator only counts what was asked.** "2 of 3 done" excludes
  rest, excused and paused rows — pinned by test. A rest-plus-food-logged day
  reads *complete*.
- **A finished day earns quiet.** All-done → "Today is done — everything your
  coach asked." and NO further CTA. The reward for compliance is peace, not
  another task.
- **One next action**, priority-ordered: open session → unlogged food →
  lifestyle targets → check-in; a flexible-week session is suggested only
  when nothing else is open (an offer must never outrank an obligation).
- **Coach's words travel.** Rest/excused/paused rows carry the coach's own
  note into the hero, so absorbing the Phase-3 state cards lost nothing.
- **Time-honest greeting** ("Good morning, Priya") — never the "Alpha"
  placeholder, never a fake name.
- **Offline honesty:** a stale plan now renders under a calm one-line banner
  ("Offline — showing your last synced plan" + Retry) instead of silently
  posing as fresh.

## 4. Bugs discovered

1. **Silent-stale rendering** (§1.4) — fixed with the sync banner.
2. **`GradientButton` overflowed at accessibility text scales** — the app's
   signature CTA clipped ("red-stripe" overflow) on narrow phones at 1.6×
   text scale, app-wide since its creation. Caught by the new text-scale
   widget test; fixed in the shared widget (label now scales down), which
   hardens every screen that uses it.
3. **Header date overflow** in the new hero at 1.6× — caught by the same
   test before it ever shipped; fixed with a scale-down fit.

## 5. Files changed (all AlphaSerena)

| File | Change |
|---|---|
| `lib/core/domain/today_agenda.dart` | **new, pure** — agenda rows, honest denominator, next-action priority, greeting |
| `lib/screens/dashboard/home/today_plan_card.dart` | **new, pure widget** — the hero |
| `lib/screens/dashboard/home/client_home_screen.dart` | new hierarchy; greeting; stale banner; workout section content-only; due check-in dedupe; shared presentation helper |
| `lib/core/widgets/gradient_button.dart` | text-scale overflow fix (app-wide) |
| `test/today_agenda_test.dart` | **new — 16 tests** (denominator, priorities, truthfulness, greeting) |
| `test/today_plan_card_test.dart` | **new — 5 widget tests** incl. narrow-width + 1.6× text scale |

## 6. Verification

| Check | Result |
|---|---|
| `flutter analyze` | **No issues** |
| `flutter test` | **437 / 437** (21 new) |
| Consistency-card goldens | **Unchanged, passing** |
| Debug APK | **Built** |
| Accessibility | hero rows and CTA carry semantic labels; state never colour-alone (icons per status); 1.6× scale + 320-width pinned by test |
| Timezone / offline / state matrices | unchanged engines (Phases 2–4 suites all green in this session); every hero state derives from the already-pinned presentation |

**State matrix:** workout day (hero row open + content card + CTA) · rest /
travel / medical (calm hero row with the coach's words; no workout card, no
CTA) · coach-approved (excused row, success tint) · paused (row + no ask) ·
flexible week ("2 of 4 sessions… you pick the days") · no workout (waiting
row) · future plan ("starts soon") · expired ("ask your coach for the next
block") · no diet (row absent, never faked) · offline with cached plan
(stale banner + full UI) · offline cold (existing error card + retry) ·
brand-new client (unchanged onboarding blockers + quote).

**Indian member review:** the working professional and mother see one card
telling them the whole day in five seconds; the night-shift and online
clients on flexible plans see week-framed asks, never daily demands; the
bodybuilder's cycle days read required/rest correctly from the engine; the
senior on daily walking sees lifestyle targets met; the college student with
no coach targets sees no fabricated asks; every rest state reads as the
coach's instruction, in the coach's words.

**Said plainly — not machine-verified:** no human has driven the redesigned
Home on a device; `ClientHomeScreen` itself still has no widget test (it
constructs five Firebase controllers — the hero, its logic, and its states
are fully tested at the extracted layers instead); the greeting's name source
(`clientProfiles.clientName`) is the claim-time snapshot and may lag a
rename.

## 7. Remaining future opportunities

1. Widget-test `ClientHomeScreen` itself via controller-injection seams.
2. A subtle entrance animation for the hero (motion system exists;
   deliberately deferred over shipping an untested animation).
3. Live-update the agenda's diet row from mid-day plan edits (currently
   refresh-channel driven, same as all training data).
4. Weekly summary note in the greeting ("2 sessions left this week") once a
   home-level week strip earns its place.
5. The coach-updates section could collapse to a single latest item with a
   "see all" — kept whole for now to avoid burying coach communication.

---

*Verified 2026-07-28: analyze clean · 437/437 (21 new) · goldens unchanged ·
debug APK built. Nothing committed, nothing deployed.*
