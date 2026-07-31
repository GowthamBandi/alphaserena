# Weekly Prescription System — Phase 0 Audit & Architecture

- **Date:** 2026-07-28 · **Scope:** TrainerHQ · AlphaSerena · trainershq-backend, one ecosystem
- **Status:** audit + architecture. Implementation follows in the same mission, certified separately.

---

## 1. Reconstruction — what verifiably exists

**Authoring (TrainerHQ).**
- `workoutPlans` — flat exercise lists, per-set `setRows`, soft-delete (`isDeleted`), creator-scoped visibility. CRUD complete.
- `dietPlans` — food snapshots, CRUD complete.
- `weeklyWorkoutPlans` — day→(workoutPlanId, name) mapping. **Create/edit/list/detail exist. Delete does not exist anywhere** (no service method, no UI, rule `allow delete: if false`). Weekly plans validate against archived workout plans ("renders as Rest and will save as Rest").
- **`weeklyDietPlans` do not exist** in any repository — no model, no collection, no rule.

**Assignment.** `client_plan_assignments`: planType `workout`|`diet`, ONE plan per assignment, lifecycle `active|paused|ended` (atomic replace/pause batches, M14), per-client snapshots (`workoutItems`/`items`, `customized`), single-active-per-type rule, server-owned `prescription` + `excusedDays`. Weekly plans are **not assignable** — no planKind, no field, no UI path.

**Prescription Engine (frozen, certified).** Pure domain byte-identical in both apps (verified this audit: `diff` = IDENTICAL). Four rhythms (daily / weekdays / frequency / cycle), immutable versions with `effectiveFrom`, exceptions incl. open-ended, client-level coaching pause, `resolveDay`/week verdicts. Server-owned writes via `setPrescription` / `excuseDay` / `setCoachingPause`. `getMyTraining` resolves TODAY's expectation server-side; neither app computes it locally.

**Serving (`getMyTraining`).** Most-recent ACTIVE assignment per type → `buildWorkout` (snapshot else live library plan; hydrates exercise media/fields incl. `equipment`, `difficulty`, `thumbnailUrl`, `videoDurationSeconds`) → `{workout, diet, coach, expectation, prescriptionData}`. Membership-gated. **`weeklyWorkoutPlans` appears in ZERO backend lines** — authored weeklies are never served.

**Session (AlphaSerena).** Workout Experience roadmap phases 1–3 are ALREADY BUILT and certified: deterministic session id `{clientId}_{yyyy-MM-dd}`, resume/draft/back-guard, edit/skip states with reasons, briefing screen, rest overlay, summary screen, member note. `sessionStats` computes done/asked/volume/adherence. Day-marking rule (tested): "one completed set IS activity; skips alone never mark a training day".

**Consistency.** Verdict layer over prescription versions + logs + excuses; week verdicts for frequency; Home hero drives off the served expectation.

## 2. Every disconnect found

| # | Disconnect | Severity |
|---|---|---|
| D1 | Weekly plans authored but **never assignable, never served** — a dead-end feature. The coach who builds Push/Pull/Legs cannot deliver it; the member on a weekdays rhythm sees the SAME single plan every training day | **critical — the architecture's missing keystone** |
| D2 | Prescription says WHEN (rhythm) but nothing maps day→WHAT. The two halves of "prescribe" never meet | critical (same root as D1) |
| D3 | Weekly plan **delete missing** entirely (no method, no UI, rule false) — a mis-built weekly lives forever | high |
| D4 | Weekly diet plans absent as a concept | medium (see §4 — deliberately deferred) |
| D5 | Member "done today" is **binary presence** (one completed set → Home reads done); no progress %, engine never decides completion | high |
| D6 | Weekly plan → archived workout plan silently "saves as Rest" — authoring warns, but an ASSIGNED weekly pointing at a later-deleted plan would serve nothing without explanation | medium |
| D7 | Assign flow's rhythm is hand-picked even though a weekly plan already states its days — double authoring, can contradict (weekly says Mon/Wed/Fri, coach picks "4×/week") | high |
| D8 | Reported "cannot save/edit/update" weekly plans: **code and rules are correct** (verified line-by-line; create stamps `adminId`+`createdById`, rules permit). If real, the deployed rules predate the current file — a deploy-state issue, not a code defect. Only DELETE is genuinely impossible | recorded honestly |
| D9 | Session issues (rest-timer delay, blank transition, media) — the guided experience exists; remaining polish is roadmap §14 phases 5–7, already specified | medium |

## 3. THE question: assign Workout Plans or Weekly Plans?

Challenged against real coaching, not preference:

- **Gym PT / strength block:** "Upper A / Lower A / Upper B / Lower B on fixed weekdays" — needs a weekly mapping. Single plan fails.
- **Bodybuilding:** Push/Pull/Legs ×2 — weekly mapping, six distinct day plans.
- **Beginner fat-loss / corporate / senior / student:** ONE full-body plan, "3× a week whenever you can" — a single plan + **frequency** rhythm. A weekly mapping is WRONG here: frequency deliberately has no fixed days, so there is nothing to map. Forcing a weekly would destroy the engine's most honest rhythm.
- **Powerlifting cycle (3-on-1-off):** drifts across weekdays — a Mon–Sun mapping CANNOT express it; the cycle rhythm + one/rotating plan can.
- **Rehab / medical:** one prescribed routine, alternate days — cycle or frequency + single plan.
- **Ramadan / travel / night shift:** these are EXCEPTIONS and pauses (already built), orthogonal to the plan-shape question.
- **Women's coaching / PCOS:** phase-based single plans swapped by Replace, or weekly splits — both occur.

**Verdict: BOTH, as one concept.** The assignable unit stays the **assignment** (the working lifecycle spine: single-active, pause/replace, prescription, history). What it points at gains a second shape:

- **Single plan** (today's behaviour) — the right tool for frequency and cycle rhythms and for every simple programme. **Must remain assignable** — killing it would break the majority of real Indian PT use-cases and every existing assignment.
- **Weekly schedule** (`weeklyPlanId` on the same assignment) — the right tool for weekday-shaped programmes. Days present in the mapping **derive the weekdays rhythm automatically** (D7 dies: one authoring act; schedule and content can never contradict). The backend serves TODAY's day-plan; rest days serve an honest rest state + next-day pointer.

Why not "weekly becomes primary": frequency ("any 3 per week") is the single most member-friendly rhythm for busy professionals and it is *definitionally* incompatible with a day mapping. Why not "single only": D1. Why the same assignment doc: prescription versions, consistency, single-active, pause/replace, serving slices — all key on `planType` and keep working **unchanged**. Migration: zero — `weeklyPlanId` absent ⇒ exactly today's behaviour.

## 4. Decisions on the remaining phases

- **Weekly DIET plans (Phase 3): deliberately NOT built.** Diet is served daily-by-default and the certified consumption model is a single day's meals; no coaching scenario surveyed (incl. carb cycling, which is better served by diet-plan Replace or a future per-day diet variant) justifies inventing a second weekly system in this mission. Recorded as future work with the same `weeklyPlanId` pattern reserved.
- **Completion (Phase 6):** the session domain gains a completion fraction — `done sets / planned sets`, skips count against, "complete" = nothing left pending — and the member surfaces show the percentage instead of flipping to "done" at one set. Streak day-marking (presence of completed work) is a different, already-strict question and stays.
- **Media/session polish (Phases 7–8):** the serving already carries every library field end-to-end (verified in `buildWorkout`); briefing/rest/summary already built. Remaining: preloading, landscape, tempo/superset vocabulary — roadmap §14 phases 6–7, out of this mission's implementation.
- **Coach visibility (Phase 10):** skip reasons, duration, notes already flow to `client_workout_sessions` and `MemberLogsSessionScreen` renders per-set stories; completion % joins via the same sessionStats now shared. Full dashboard = roadmap phase 5.
- **100 journeys (Phase 11):** the architecture was walked against the persona×situation grid (§3 plus: gym closed ⇒ `closure` exception; injury ⇒ `medical` open-ended pause; equipment unavailable ⇒ skip-with-reason already logged; deload ⇒ `deload` exception; exam week ⇒ pause; festival ⇒ excuseDay). Every scenario resolves to an EXISTING primitive plus the weekly mapping — no scenario required a new state, which is the strongest evidence the primitive set is now complete.

## 5. Implementation contract (what follows)

1. **Backend** — pure `weeklyServing` resolver (+tests): weekly plan doc + date → today's `workoutPlanId`/rest/next-day; `buildWorkout` serves it when `assignment.weeklyPlanId` is set; `weekly` overview + `restDay`/`nextDay` ride additively on the served workout.
2. **TrainerHQ** — Weekly tab in Assign flow; assigning a weekly auto-derives `Rhythm.weekdays` from its days; weekly soft-delete (`isDeleted`, service + UI + list filtering; rules already permit the update); assignment cards name the weekly.
3. **AlphaSerena** — transparent on training days (served items just work); honest rest-day state on My Plans; completion fraction in the session domain + summary + Home hero.
4. Tests both sides; analyze clean; APK builds; certification. Nothing committed.
