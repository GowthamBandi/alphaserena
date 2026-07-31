# Member Performance Experience — Certification (Consistency System)

- **Date:** 2026-07-28
- **Delivered:** the consistency system rebuilt on the Prescription Engine —
  Today, This Week, a tappable coaching Timeline, an honest Month view,
  computed Insights, and only the streaks that survived challenge.
- **Consumes** the engine as frozen; the Prescription Engine core, its rules
  and its callables are untouched. One **additive** serving field carries the
  member their own prescription material (§3).
- **Nothing committed. Nothing deployed.**

---

## 1. Audit — what the old system did wrong (all fixed)

1. **Fabricated misses, at scale.** `summarise`/`calendar` ran with
   `schedule: null`, so every past unlogged day scored MISSED. A perfectly
   compliant Mon/Wed/Fri member saw ~16 "missed" cells per month. This was
   the founding defect of the whole program, still live on its own screen.
2. **A streak the member could not keep.** The hero was a workout DAY-streak
   — explicitly rejected by the freeze (▲4): a 4×/week member could never
   exceed 2. The number punished compliance.
3. **No vocabulary for real coaching.** Rest, paused, excused, exception and
   unknown states did not exist; `DayState.rest` was drawn in the legend but
   unreachable in production.
4. **Rates divided by calendar days** — rest days sat in the denominator.
5. **Statistics, not coaching.** No expectation, no reason, no coach note —
   nothing a coach actually said appeared anywhere.

## 2. UX and behavioural decisions

- **One engine, one answer.** Every verdict comes from the certified Step-1
  `verdictFor` — the byte-identical file both apps carry — fed by the coach's
  real prescription versions, real excuses, the real pause, and the member's
  own logs. Nothing else is consulted; nothing is inferred.
- **Two honest modes.** With a prescription: the full coaching experience.
  Without one (or on an old backend): the presence view, *disclosed* ("No
  schedule set — showing the days you logged"), where unlogged days read
  **"Not logged"**, never "Missed" — a verdict nobody issued.
- **The streaks that survived challenge** (freeze ▲4 applied, at last):
  - *Workout → weeks-on-plan.* "3 weeks on plan" is holdable by a 3-day
    member and a 6-day member alike; frequency weeks count by target met.
    Excluded weeks (all rest/paused/nothing asked) are TRANSPARENT — medical
    leave returns to the same number, not to zero. The rejected day-streak is
    gone from the hero and from Home's card.
  - *Nutrition → daily streak, prescription-aware.* Genuinely daily,
    genuinely binary — kept, upgraded so paused/excused days are transparent.
  - Nothing else. No composite streak, no check-in streak, no
    coach-interaction streak (gameable, and it pressures the coach).
- **Anxiety rules, enforced in pixels:** today is a ring, never a gap; a miss
  is a quiet outline, never red; rest/excused/paused are calm filled states; a
  bonus session on a rest day is celebrated ("only ever helps"); insight
  wording states facts a member can act on, never how to feel.
- **The timeline is a conversation.** Tap any day: what the coach asked, what
  happened, the reason (Travel / Deload / Medical…), the coach's own note,
  and exactly how the day counts ("Not counted either way").
- **Insights are computed, never invented** — each requires real evidence
  (≥2 same-weekday misses; ≥4 required days per side and a ≥25-point gap for
  weekend/weekday; actual rest days actually rested), at most three, positive
  framing preferred and week-over-week stated only when genuinely up.

## 3. Files changed

**trainershq-backend** (additive serving only — no rules, no callables):
- `functions/src/lib/prescription.ts` — `historyNeededForWindow`,
  `clampVersionEnd` (pure).
- `functions/src/members.ts` — `getMyTraining` response gains
  `prescriptionData: {workout, diet, coachingPause}`: versions in force
  (current rides documents already fetched; the history subcollection is read
  only when a multi-version prescription's `effectiveFrom` falls inside the
  70-day window), per-day excuses, the client pause. Versions from
  ended/replaced assignments are **end-clamped to the day they left service**
  so a finished plan can never fabricate a miss.
- `functions/test/prescription.test.mjs` — 2 new tests.

**alphaserena:**
- `lib/core/domain/performance.dart` — **new, pure**: `TrackHistory` (served
  parse), `timeline`, `monthCells` (8 honest states), `weekSummary`
  (Completed/Expected in the prescription's own unit), `weeklyAdherenceStreak`,
  prescription-aware `dailyStreak`, evidence-gated `insightsFor`.
- `test/performance_test.dart` — **new, 24 tests** (the matrices, §5).
- `lib/controllers/performance_controller.dart` — **new**: logic-free glue.
- `lib/controllers/training_controller.dart` — parses `prescriptionData`.
- `lib/screens/dashboard/consistency_detail_screen.dart` — **rebuilt**:
  streak hero → Today → This Week (+ coach-approved and check-in-due chips) →
  Timeline (tap-a-day sheet) → Month calendar (Monday-aligned, full legend) →
  Insights; legacy presence mode with disclosure for unprescribed members.
- `lib/screens/dashboard/home/consistency_cards.dart` — `weekUnit` ("N
  weeks"); defaults unchanged, all four goldens untouched.
- `lib/screens/dashboard/home/client_home_screen.dart` — cards read the
  truthful streaks when prescribed; legacy values otherwise.

**TrainerHQ:** untouched this phase.

## 4. Bugs discovered (beyond the audit)

1. **Ended plans could haunt the timeline.** A replaced assignment's
   prescription carried no end date, so fed raw into `versionEffectiveOn` it
   would keep claiming required days after it left service — fabricated
   misses. Fixed server-side (`clampVersionEnd`), pinned by test.
2. **History reads on the hot path** would have violated freeze §11 —
   avoided by the `historyNeededForWindow` gate (version >1 AND effectiveFrom
   inside the window; a handful of members at any moment).

## 5. Verification

| Check | Result |
|---|---|
| Backend `npm test` | **560 / 560** (2 new) |
| AlphaSerena `flutter analyze` | **No issues** |
| AlphaSerena `flutter test` | **416 / 416** (24 new) |
| Consistency-card goldens | **Unchanged, passing** |
| Debug APK | **Built** |
| TrainerHQ / rules | Untouched — Phase 2 verification stands |

**The matrices, each pinned by test:**
- *Rest-day matrix* — compliant Mon/Wed/Fri member: **zero misses**, 4 rest
  days, 3 hits; training on rest = DONE (bonus); rest never breaks a streak.
- *Flexible matrix* — frequency weeks count sessions ("2 of 4, 2 remaining");
  a 4×/week member holds a 3-week streak (the original defect, closed); a
  partial current week is open, never a miss.
- *Coach-approved matrix* — an excused day is never a miss, leaves the week's
  ask, and is surfaced as "coach-approved"; the excused state renders in
  timeline, month and week chips.
- *Pause matrix* — a fully-paused week reads "Paused", never 0-of-N; paused
  weeks are transparent to streaks; paused month cells are their own state.
- *Travel/exception matrix* — exception rest days resolve with reason and
  note (server domain pinned in Phase 2's 34 tests; wording pinned here).
- *Timezone matrix* — all day math on local day keys (Phase 3's `localDate`
  channel; server clamping pinned in Phase 2).
- *Offline/legacy matrix* — unreadable/absent served data → empty history →
  the disclosed presence view; day-key sets `null` → "Couldn't load", never 0.
- *Edge matrix* — junk versions dropped not defaulted; no-prescription weeks
  read "unknown"; before-start days render faint `unknown`, never missed.

**Coach parity:** the member's numbers are computed by the same certified
engine, from the same server-owned prescription block, as everything TrainerHQ
displays. TrainerHQ today has NO day-level consistency surface (deliberately a
later phase), so no screen pair can disagree; when its block is built it will
run the identical domain file against the identical documents — same inputs,
same rules, one answer. The engine copies were diff-verified byte-identical in
Phase 2.

**Indian-coach persona review:** the 3-day gym member and the "any 4/week"
online client see zero fabricated misses and a streak they can hold; Ramadan
and travel weeks show the coach's replacement rhythm with the reason chip;
medical leave shows "Paused — your run is safe" and returns without reset;
the night-shift and corporate clients on frequency plans are judged by week,
never by day; the student with no schedule sees a disclosed presence view,
not a judgement; injury recovery = pause transparency throughout.

**Said plainly — not machine-verified:** no human has driven these screens on
a device (APK built, not manually exercised); the rebuilt screen and the
tap-a-day sheet have no widget tests (its state logic is fully covered at the
domain layer; the pure-widget extraction pattern is the later path); lifestyle
and cardio "Completed/Expected" rows are **absent, not faked** — no lifestyle
day-key history service exists and no cardio track exists in production, and
inventing either would break the founding rule. One live end-to-end run
(coach sets a schedule → member's timeline/month/insights) is owed.

## 6. Remaining future opportunities

1. **Lifestyle history** — a day-key read over `client_lifestyle_logs` would
   light up a truthful lifestyle week row (targets-met days).
2. **Cardio track** — arrives free with the cardio `planType` (Phase 2 §11).
3. **TrainerHQ consistency block** — the same `performance.dart` derivations,
   coach-side; plus relabelling existing metrics "Adherence (quality)".
4. **Per-version plan names in the day sheet** — the wire could tag versions
   with the plan name in force, so old days name their plan.
5. **Milestones for the weekly streak** — the day-milestone chips were
   removed with the day-streak; week-based ones (4, 8, 12 weeks) could
   return under the same sparse-and-reachable rule.
6. Reminders, analytics, AI — as sequenced in Phase 2 §11.

---

*Verified 2026-07-28: backend 560/560 · analyze clean · 416/416 (24 new) ·
goldens unchanged · debug APK built. Nothing committed, nothing deployed.*
