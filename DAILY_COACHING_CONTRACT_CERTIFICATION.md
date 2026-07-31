# Daily Coaching Contract — Final Certification

**Date:** 2026-07-29
**Scope:** TrainerHQ → `getMyTraining` (canonical backend) → AlphaSerena Nutrition Domain
**Result:** backend **576/576 tests** + clean build · **DEPLOYED to trainershq-f5ded** · nutrition **Patrol 11/11 on device** · AlphaSerena `flutter analyze` clean · **663 tests** · APKs build
**Defects found this certification: 2** (1 repo-topology, 1 backend truthfulness) — both fixed

---

## 1. Repository Reconstruction — and the finding that reframed Objective 1

**The deploy blocker was not an unwritten patch; it was repo topology.**
`trainersHQ/firebase.json` is deliberately deploy-neutered ("CANONICAL BACKEND
= trainershq-backend … `firebase deploy` from this repo must never overwrite
the canonical backend"). The `trainersHQ/functions/lib/members.js` copy —
which an earlier session patched — is a **stale, undeployable artifact** of a
pre-canonicalization vintage (its `buildWorkout(db, planId)` signature predates
assignment-based serving entirely).

The **canonical** source, `trainershq-backend/functions/src/members.ts`
(uncommitted), was already far ahead of that patch: per-item media
(`thumbnailUrl`, `equipment`, `difficulty`, `videoDurationSeconds`), plan
`description`, `exerciseId`/`foodId` identity end-to-end, weekly serving
(`weekly`/`restDay`/`nextDay`/`dayPlanUnavailable`), soft-delete guards,
server-resolved `expectation`, `prescriptionData`, live `coach`, and the
client-level diet targets. All of it covered by the canonical repo's own
**576-test** suite (members, diet_items, weekly_serving, prescription,
security_regressions, …). What production lacked was a **deploy of this
source** — delivered below.

Layers reconstructed: TrainerHQ diet builder (meal accordions, canonical meal
names, foodId + quantity/grams/portion authoring, soft-delete archive) →
`client_plan_assignments` (snapshot-or-pointer, prescription slices) →
`getMyTraining` → AlphaSerena `TrainingController` → `DietLogController`
(identity restore + plan-change remap state machines) → `ClientDietScreen`
(meal groups, adherence ring, per-food marking) → `client_diet_logs`
(frozen V2B consumption snapshots) → consistency nutrition track → coach's
compliance view.

## 2. Contract Audit — current (deployed-before) vs final (deployed-now)

| Field group | Before this deploy | Now served | Client handling |
|---|---|---|---|
| Workout items core (name, sets, reps, weight, setRows, videoUrl, instructions, muscleGroup) | ✓ | ✓ | rendered |
| `exerciseId` identity | ✗ | ✓ | stamped into session logs |
| Exercise media/meta (thumbnail, equipment, difficulty, duration) | ✗ | ✓ | briefing chips, posters, player |
| Plan `description` (coach's own words) | ✗ | ✓ | briefing "About this plan" |
| Weekly serving (`weekly`, `restDay`, `nextDay`, `dayPlanUnavailable`) | ✗ | ✓ | rest card, next-day pointer (`dayPlanUnavailable` currently unread — debt) |
| `expectation` (server-resolved, local-day clamped) | ✗* | ✓ | the entire Prescription-Engine UX |
| `prescriptionData` (versions, excuses, pause) | ✗* | ✓ | performance timeline/heatmap |
| `coach` (live id/name/photo/assigned) | ✗* | ✓ | header identity (root-caused "Your Coach") |
| Diet items (name, **foodId**, quantity, calories, P/C/F/fiber/**sugar/saturatedFat**, meal, grams, portionLabel/Qty) | partial/legacy | ✓ | rendered + frozen into logs; sugar/satFat/grams/portion are additive headroom |
| Diet targets (client-level calories/P/C/F/fiber) | partial | ✓ | one canonical resolver (`resolveNutritionTarget`) |
| Membership gate (frozen/expired → null) | ✗ | ✓ | renew state |
| Soft-delete guards (plans, exercises, **diet plans**) | ✗ | ✓ (diet fixed today) | honest degradation |

\* per the stale artifact's vintage; the deployed function's exact age was
unverifiable, which is itself why deploying the certified source was the fix.

**Deliberately NOT in this contract** (each an architectural decision, not a gap):
- **Hydration & lifestyle targets** — live on the member-streamed `clients`
  doc (`lifestyleTargets`); realtime beats request/response for coach edits.
- **Calories burned / RPE / recipes / meal imagery** — no truth exists in the
  data model to serve; nothing is fabricated.
- **Response-level version field** — evolution is governed by the proven
  additive-fields discipline: every client reader null-guards and legacy-falls-
  back (the 663-suite pins this), so unknown fields are free and absent fields
  are honest. A `contract` int adds a second mechanism nobody reads.

## 3. Defects Found & Fixed

**C1 — Stale-copy patching (topology, high).** An earlier certification
patched the undeployable `trainersHQ` copy believing it canonical. Corrected
understanding recorded here and in project memory; the canonical repo is the
only contract source. (The stale copy's local edit is inert — that repo cannot
deploy.)

**C2 — Soft-deleted diet plans kept serving (truthfulness, medium).**
TrainerHQ soft-deletes diet plans (`isDeleted`, restorable archive) and hides
them from every coach list — but `buildDiet`'s pointer/legacy fallback checked
only `snap.exists`, so a "deleted" diet kept serving to assigned members
indefinitely, contradicting the certified workout semantics. *Fix:* the same
`planServable` guard the workout path uses; snapshot assignments unaffected
by design. 576/576 after fix.

## 4. Backend Certification (Phase 2)

- `tsc` clean · **576/576** unit tests (`npm test`) including the pure serving
  mappers (`dietItemForMember`, `chooseWorkoutItems`, `planServable`,
  `exerciseHydratable`), prescription engine, weekly serving, security
  regressions.
- Error surface: missing/deleted docs degrade to `null`/snapshot (never
  throw); unauthenticated calls rejected by `assertSignedIn`; day input
  clamped ±1 day server-side (forgery-proof); linked-client pointer validated
  against `authUid` before use (stale/tampered pointer falls back).
- Read cost: hot path adds zero reads for expectations (history subcollection
  only for multi-version windows); media joins are per-item doc gets — an
  acceptable N+1 for plan-sized N, noted as future batch-get debt.
- Rules: `client_plan_assignments`/plan/food collections are coach-owned; the
  member needs **no read access** — the function is the only serving surface,
  which is the security model working as designed.

## 5. Deployment Verification

```
firebase deploy --only functions:getMyTraining --project trainershq-f5ded
i  functions: updating Node.js 22 (2nd Gen) function getMyTraining(us-central1)...
+  functions[getMyTraining(us-central1)] Successful update operation.
+  Deploy complete!
```

Scoped to the one certified function; every other deployed function
untouched. Old app builds are safe by construction (additive fields, proven
legacy fallbacks); new builds — workout media, briefing chips, posters,
weekly rest days, and the full diet contract — light up on their next
`getMyTraining` call. **This closes the release blocker carried by every
prior certification.**

## 6. Nutrition State Matrix (Phase 4)

| State | Owner | Verified by |
|---|---|---|
| No nutrition plan | `_empty` ("Your trainer will set up…") | **Patrol** |
| Load failed, nothing cached | error + Retry, never "no plan" | **Patrol** |
| Membership lapsed | renew state (server nulls diet) | unit + server gate |
| Full day / multiple meals | canonical meal order + per-meal prescribed totals | **Patrol** |
| Breakfast-only / snack-only | only real meals render, none invented | **Patrol** |
| Legacy `snacks` meal | aliased to Evening Snack (coach parity) | **Patrol** |
| No coach targets | targets fall back to prescribed sums (one resolver) | **Patrol** + unit |
| Meal completed / partial / skipped | full / half / zero credit; logged either way | **Patrol** (live math) |
| Un-mark / change answer | toggle-off; replace, never stack | **Patrol** |
| Rest day / paused / future / ended plan | expectation-driven copy (Home nutrition note) | unit (expectation suite) |
| Offline queued / failed sync | `queued` = saved-on-device truth; `failed` = error surface | unit (service contract) |
| Coach edits plan mid-day | identity **remap** moves marks with their food; deleted food loses its mark and the log stops claiming it | unit (remap suite) |
| Restore after restart | identity-first restore, index fallback for legacy | unit (restore suite) |
| Day rollover | `ensureFreshDay` rebinds — yesterday's marks never stamp today | unit |
| Duplicate submission | deterministic `{clientId}_{date}` doc — upsert | design + parity tests |
| Coach's compliance view | frozen consumed snapshots, TrainerHQ parity | unit (parity suite) |
| Hydration | lifestyle domain (clients doc), certified separately | consistency cert |
| 30-food day / long names / 1.6× / landscape | lazy list end-to-end, no overflow | **Patrol** |

## 7. Patrol Execution Report (Phase 6) — emulator-5554

**11/11 passed** (one iteration: first run 8/11 — all three failures were
viewport-culling in my asserts: a lazily-inflated `ListView` only holds
visible children in the element tree on a real device; asserts made
scroll-aware, which additionally certifies the scroll itself). Fixtures are
the canonical `dietItemForMember` shape — deterministic, no manual data.

Honest limits, same as the sibling suites: no member session exists on this
emulator (auth externally blocked), so the Firestore write itself no-ops;
marking, adherence math, grouping, states, scale and orientation all execute
the production paths. Persistence/restore/remap are pinned by the unit suite.

## 8. UX / Accessibility / Performance / Security Review

- **UX:** the day reads in one glance — ring (today's adherence), consumed/
  target macros, meals in coaching order with prescribed per-meal totals
  ("what to eat", not a running tally), three honest chips per food. Calm,
  not spreadsheet. Skips are logged without judgement. Screenshots:
  `docs/certification/nutrition_day.png`, `nutrition_marked.png`,
  `nutrition_meals.png`.
- **Accessibility:** chips are 44pt-class with icon+label (never colour-alone);
  1.6×/320px exercised on device including live marking; state changes are
  reactive text, not colour flips.
- **Performance:** lazy list (proven by the culling failures!), pure sum
  helpers, one canonical target resolver, no per-frame work; backend hot path
  read-optimized (§4).
- **Security/privacy:** member reads only via the function; log writes
  rules-owned with stamped identity; consumed snapshots contain the member's
  own data only. This certification's writes ran under the standing
  Guardian-logged-out authorization; diff uncommitted and scannable.

## 9. Self-Critique & Remaining Debt

1. **I nearly re-certified a fiction.** The stale-copy discovery (§1) means an
   earlier certification's "backend patch" was written into a repo that cannot
   deploy. Repository evidence over memory is the lesson — it is now recorded
   in memory itself.
2. `dayPlanUnavailable` is served but unread by the client (a weekly day
   whose plan was deleted shows a bare rest-like day; a one-line disclosure
   would be more honest).
3. Exercise/food hydration is N+1 per item; fine at plan sizes, worth a
   batched `getAll` if plans grow.
4. Sugar/saturatedFat/grams/portion are served and frozen into logs but not
   yet rendered — deliberate headroom, listed so it isn't forgotten.
5. On-device journeys can't execute a real authenticated save end-to-end;
   that path remains certified at unit/contract level until a test account
   exists (blocked on the external Play-Integrity fix).

## 10. Final Verification

```
Backend  (trainershq-backend):  tsc clean · 576/576 · DEPLOYED (getMyTraining)
AlphaSerena:                    flutter analyze clean · 663/663
Patrol:                         nutrition 11/11 · workout 18/18 · consistency 16/16
APKs:                           debug ✓ · release ✓ (this session)
```

Nothing committed (both repos) — the deploy was the one authorized external
action. TrainerHQ, Cloud Functions and AlphaSerena now run one coherent,
truthful, additive-evolution Daily Coaching contract.
