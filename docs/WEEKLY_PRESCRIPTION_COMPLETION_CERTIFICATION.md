# Weekly Prescription System — Completion Certification

- **Date:** 2026-07-28 · **Repos:** trainershq-backend · trainersHQ · alphaserena
- **Companion:** `WEEKLY_PRESCRIPTION_COMPLETION_AUDIT.md` (Phase 0 reconstruction,
  the assignment-unit decision, and the scope rulings this implements)
- **Status: implemented and verified. Nothing committed. Nothing deployed.**

**Verification performed:**
backend `npm test` → **576 pass** (564 baseline + 12 new; the build step
type-checks the `members.ts` change) · TrainerHQ `flutter analyze` clean,
**992 tests pass** · AlphaSerena `flutter analyze` clean, **515 tests pass**
(509 baseline + 6 new) · both debug APKs build. No emulator/device run and no
CF deployment — runtime claims are tests + traced control flow.

---

## 1. Root cause

The platform had two halves of "prescribe" that never met. The **Prescription
Engine** (frozen, certified) says **when** — rhythms, versions, exceptions,
pauses. The **assignment** says **what** — but could only point at ONE workout
plan. `weeklyWorkoutPlans` (day→plan mappings) existed as an authoring feature
and appeared in **zero backend lines**: buildable, listable, never assignable,
never served. A coach running Push/Pull/Legs could author the split and then
could not deliver it; their member saw the same single plan every training day.

Secondary root causes, same audit: weekly plans had **no delete path at all**
(no method, no UI, rule `false`); the assign flow asked the coach to hand-pick
a rhythm that a weekly mapping already states (two authorings that could
contradict); and member-side "done today" was **binary presence** — one
completed set rendered `Logged today ✓` identically for 1-of-18 and 18-of-18.

## 2. The assignment-unit decision (Phase 0's mandated challenge)

**Both plan shapes, one assignment spine** — argued against real coaching in
the audit §3. Single plans remain assignable because frequency ("any 3 per
week") and cycle (3-on-1-off) rhythms are *definitionally* incompatible with a
Mon–Sun mapping, and they serve the largest real segments (beginner fat-loss,
corporate, rehab, powerlifting). Weekly mappings become assignable because
weekday-shaped programmes (splits) are the other half of real coaching. The
assignment document stays the unit: single-active, pause/replace, prescription
versions, consistency and serving slices all key on `planType` and required
**zero changes**. Migration: none — `weeklyPlanId` absent ⇒ prior behaviour.

## 3. What was implemented

### Backend (`trainershq-backend`)
- **`lib/weekly_serving.ts`** (new, pure): weekday resolution for `yyyy-MM-dd`
  keys (UTC-constructed so server timezone can never shift a member's day),
  `parseWeeklyDays` (malformed rows degrade to rest), `resolveWeeklyDay`
  (mapped day → its plan; unmapped → `restDay` + wrapped `nextDay`; malformed
  key fails closed), `weekdaySetOf` (the derived rhythm, 1=Mon..7=Sun),
  `weeklyOverview` (week-at-a-glance with `isToday`).
- **`getMyTraining`**: `todayKey` is now resolved BEFORE the workout build so
  the served content and the served expectation are computed for the SAME
  member-local day. `buildWorkout` gains the weekly branch: assignment with
  `weeklyPlanId` → read the mapping (deleted/missing ⇒ same contract as a
  deleted single plan) → serve today's day-plan through the existing hydration
  (media, setRows, equipment — everything) → additive `weekly`/`restDay`/
  `nextDay` fields; a rest day serves NO items (never yesterday's plan to fill
  the screen); a day whose plan was archived serves `dayPlanUnavailable`.
  Per-client snapshots stay a single-plan tool (weekly always serves the live
  library day-plan, documented in place).

### TrainerHQ
- **Weekly delete exists** (D3 closed): `isDeleted` soft-delete — service
  method + confirmed UI on the detail screen + filtered from lists and
  intelligence. Rides the already-permitted `update` rule; hard delete stays
  rule-blocked by design. Serving stops via the same `planServable` gate as
  single plans.
- **Weekly is assignable** (D1 closed): third segment in the Assign flow
  listing weekly mappings ("N training days · M rest"); preview names the
  actual week (`Mon: Push · Wed: Pull · Fri: Legs`); assignment writes
  `planType: 'workout'` + `weeklyPlanId` (track unchanged ⇒ single-active,
  pause/replace and history all just work; replace intent now correctly
  survives switching workout↔weekly and still drops crossing to diet).
- **One authoring act** (D7 closed): the rhythm is DERIVED —
  `Rhythm.weekdays(weekly.weekdaySet)` — shown read-only in the review sheet
  ("from the weekly plan"); an all-rest mapping is rejected at the gate (the
  engine's own empty-weekdays reasoning). The plan card's schedule editor
  declines weekly assignments and points at the weekly editor; date-ranged
  exceptions (travel, deload, medical) remain fully available.
- **Edit-desync solved by the engine's own design**: editing a weekly's days
  re-prescribes every current assignment of that mapping (a NEW immutable
  version per member, skipped when the weekday set is unchanged, failures
  disclosed per member by name). History stays truthful: past dates resolve
  the version in force then.
- Assignment card: weekly icon; source-health check correctly bypassed
  (a weekly's `planId` is not a workout-library id — without the guard every
  healthy weekly would have shown a false "not served" warning).

### AlphaSerena
- **Serving is transparent on training days** — the member app renders the
  served day-plan with zero changes to the session flow, briefing, logging or
  coach visibility.
- **Honest rest day** (My Plans): schedule name, "Rest day today — next: Push
  Day on Wednesday", and the week at a glance — every line a served fact.
  `dayPlanUnavailable` renders as a coach-side fault ("its plan was removed —
  ask your coach"), never as the member's rest day or a broken 0-exercise card.
- **Truthful completion** (Phase 6, D5 closed): `SessionStats` gains the ONE
  completion authority — `progressFraction` (skips count against), floored
  `progressPercent` (94, never a rounded-up 100), `isFullyResolved` (nothing
  pending), `isComplete` (every prescribed set done). Home's chip now reads
  `42% done` / `Completed ✓` live from the session's own saves (and from a
  cold-open fetch of today's deterministic session doc), falling back to the
  presence-only wording when stats are genuinely unavailable — never a
  fabricated 0%. The summary screen's private "complete" re-derivation was
  deleted in favour of the engine, and a partial finish now states its real
  percentage instead of a congratulation it didn't earn.

## 4. Phases answered without new code (verified, not assumed)

- **Weekly DIET plans**: do not exist anywhere; deliberately NOT invented
  (audit §4 — daily-by-default diet + Replace covers surveyed scenarios;
  the `weeklyPlanId` pattern is reserved if evidence ever demands it).
- **Weekly CRUD bugs as reported**: save/edit/update code and rules verified
  correct line-by-line; only DELETE was genuinely missing (now built). If
  save/edit failures are real on a device, the deployed rules predate the
  repo's — a deploy-state issue named honestly (§6).
- **Session experience / media (Phases 7–8)**: briefing, rest overlay,
  summary, resume, skip-with-reason are ALREADY BUILT and certified
  (`WORKOUT_GUIDED_EXPERIENCE_CERTIFICATION.md`); `buildWorkout` already
  hydrates every library field (video, thumbnail, duration, equipment,
  difficulty, instructions) end-to-end. Remaining polish (preloading,
  landscape, tempo/superset vocabulary) = roadmap §14 phases 6–7, unstarted
  and stated as such.
- **Coach visibility (Phase 10)**: verified rendering TODAY in
  `member_logs_screen.dart` — completion stats, skipped sets, per-exercise
  skip reasons, member note, per-set prescribed-vs-actual. The new completion
  getters live in the shared domain, available to any coach surface next.
- **Finish-early / skip semantics (Phase 9)**: decided and now enforced by
  the engine — finishing early is allowed (autonomy), but the summary and
  Home state the real fraction; skips are first-class, honest, and never
  count as done work; the coach sees reasons.

## 5. Coaching-journey validation (Phase 11)

The audit's persona×situation grid (§3, §4) was re-walked over the FINISHED
implementation. Every journey resolves to an existing primitive: splits →
weekly mapping · "any N/week" → frequency + single plan · 3-on-1-off → cycle
+ single plan · Ramadan/travel/exams → exceptions & pauses (unchanged) ·
gym closed → `closure` exception · injury → open-ended `medical` pause ·
equipment unavailable → skip-with-reason · deload → `deload` exception ·
festival day off → `excuseDay`. No journey required a new state; the two that
previously had NO honest expression (weekday splits; day-resolved content)
are the two this mission built.

## 6. Honest limitations

1. **The Cloud Function is not deployed** — weekly serving reaches members
   only after `getMyTraining` ships. Until then a weekly assignment serves
   nothing (workout: null); the TrainerHQ UI is additive so nothing breaks.
2. **Re-prescription is client-driven, best-effort**: it runs when the coach
   saves the weekly edit, per-assignment, with per-member disclosed failures —
   not transactional with the mapping write. A backend trigger
   (`onWeeklyPlanWritten`) would be the airtight home; recorded as the next
   governed backend change.
3. **Per-client customization of weekly day-plans is out of scope** — weekly
   serves the live library plan; snapshots remain a single-plan tool (said in
   code where it is enforced).
4. **Weekly source-health on the client card is a stub** (`ok`): a weekly
   whose day-plans are archived is caught at serve time (`dayPlanUnavailable`)
   and in the weekly editor's health banner, but the assignment card does not
   yet name it.
5. **Deleting an assigned weekly warns generically** — the confirm names the
   consequence but not the count of affected members.
6. **`markWorkoutToday` presence semantics unchanged** for streaks (completed
   work = presence): deliberate — showing up is the streak question;
   completion is now answered separately and truthfully.
7. **No device run; no deployed-rules verification** (D8): if weekly saves
   fail in production, deploy `firestore.rules` from this repo.
8. **Weekly diet plans intentionally absent** (audit §4).

## 7. Files

**Backend:** `functions/src/lib/weekly_serving.ts` (new) ·
`functions/src/members.ts` · `functions/test/weekly_serving.test.mjs` (new).
**TrainerHQ:** `weekly_plan_model` · `weekly_plan_service` ·
`weekly_plan_controller` · `weekly_plan_detail_screen` ·
`plan_assignment_model` · `client_plans_controller` · `client_plans_screen` ·
`assign_plan_screen`.
**AlphaSerena:** `workout_session.dart` (domain) · `streak_controller` ·
`training_controller` · `workout_session_screen` · `workout_summary_screen` ·
`client_home_screen` · `my_plans_screen` · `workout_session_test`.

## 8. Verdict

The trainer now prescribes **once**: build the week, assign it, done. The
schedule falls out of the mapping (and follows its edits, version-safely);
today's content, the rest-day story, the expectation, consistency and the
coach's per-set visibility all flow from that single act — and the member's
"done" is finally a number the engine computed rather than a chip the UI
flipped. What remains is enumerated in §6, led by one deployment and one
backend trigger. **The architecture is no longer incomplete; the remaining
work is hardening, not design.**

---

*Nothing committed. Nothing deployed.*
