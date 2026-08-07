# PROGRESS — CTO DISCOVERY AUDIT

**Date:** 2026-08-04
**Scope:** `alphaserena` (member app) · `trainersHQ` (coach app) · `trainershq-backend` (canonical backend)
**Mode:** DISCOVERY ONLY. Nothing was implemented, redesigned or fixed. No file outside this report was written.
**Method:** repository evidence only. Every claim below carries a file/line citation. Where the repository could not prove something (deployment state, live data), it is marked **UNVERIFIABLE FROM REPO** rather than guessed.

---

## 1. EXECUTIVE SUMMARY

### The one-sentence finding

**The flagship Progress experience is already built — in the wrong app, for the wrong audience.**

`trainersHQ/lib/features/clients/screens/client_progress_screen.dart` (1,636 lines) is a seven-section coaching dashboard — health verdict, body, workout, nutrition, lifestyle, reviews, timeline — powered by a pure, tested analytics library (`trainersHQ/lib/core/progress/progress_series.dart`, 459 lines) that computes strength trends, personal bests, training volume, streaks, moving averages, check-in rating series and a coaching verdict. **The member's own Progress tab (`alphaserena/lib/screens/dashboard/client_progress_screen.dart`) renders a weight line chart, a transformation history, and a placeholder that says "Strength trends are next."**

The gap is not data. It is not backend. It is not security rules. It is **plumbing and placement**.

### Five findings that decide the design

| # | Finding | Evidence |
|---|---|---|
| **F1** | **The member Progress tab is 3 tabs, one of which is a placeholder.** Overview = weight trend only. Transformation = the real feature. Strength = literal "coming" copy. | `alphaserena/.../client_progress_screen.dart:95` (`['Overview','Transformation','Strength']`), `:1038-1046` (`_strength` → `_honestEmpty('Strength trends are next')`) |
| **F2** | **Everything else progress-shaped already exists in the member app — but lives on four other screens.** Streaks, achievements, milestones, adherence %, monthly goal, 5-week calendar, workout history timeline, nutrition history calendar, lifestyle history. None of it is reachable from Progress. | `consistency_detail_screen.dart` (1,134 lines), `workout_history_screen.dart`, `nutrition/nutrition_history_screen.dart`, `lifestyle_history_screen.dart`. Entry points: Home cards, My Plans app bar, Diet screen, Lifestyle Today app bar — **never Progress**. |
| **F3** | **A complete, tested analytics engine exists in Dart and is coach-only.** `progress_series.dart` already computes `strengthSeries`, `personalBests`, `totalVolume`, `distinctExercises`, `workoutStreak`, `movingAverage`, `checkInRatingSeries`, `reconciledWeightSeries`, `coachingVerdict`, `overallDirection`, `progressScore`. Zero of it is imported by AlphaSerena. | `trainersHQ/lib/core/progress/progress_series.dart:41-459`; no `progress_series` import anywhere in `alphaserena/lib` |
| **F4** | **The one backend Progress computation has no readers.** `evaluateAdherence` (daily cron) writes `clients/{id}.adherence {score, workoutPct, dietPct, windowDays, computedAt}`. A repo-wide grep across both Flutter apps finds **zero reads**; `ClientModel` does not even parse the field. | `trainershq-backend/functions/src/progress.ts:98-138`; `grep adherence trainersHQ/lib/core/models/client_model.dart` → empty |
| **F5** | **"Weekly Reports" do not exist. Anywhere.** No report generator, no report collection, no report document, no report screen, in any of the three repositories. | Repo-wide grep for `weeklyReport\|monthlyReport\|generateReport\|buildReport` across `functions/src`, `alphaserena/lib`, `trainersHQ/lib` → only unrelated hits (`food_platform.ts` import summary, "Report a problem" support link) |

### The verdict on production readiness

**Progress CANNOT be built entirely from existing infrastructure — but it is closer than it looks.**

- **~75% of the flagship experience is achievable with UI + wiring only.** The data exists, the rules permit it, the pure math is written and tested (in the other repo).
- **~15% needs a cross-repo port** (`progress_series.dart` → AlphaSerena, or extraction into a shared package).
- **~10% needs genuinely new backend** — and every one of those items is a *report* or a *forecast*, not a metric.

Full P0–P3 ranking in §19.

---

## 2. ARCHITECTURE MAP

### Repository boundary (certified, enforced)

```
trainershq-backend/          ← THE ONLY BACKEND. Functions + rules + indexes + storage rules.
  functions/src/**             94 TypeScript files, 120 exported functions
  firestore.rules              156 KB, 87 collection match blocks
  firestore.indexes.json       68 composite indexes
  storage.rules

trainersHQ/lib/              ← COACH APP (Flutter). 644 dart files. No backend (tombstoned firebase.json).
alphaserena/lib/             ← MEMBER APP (Flutter). 186 dart files. No backend.
```

Firebase project: `trainershq-f5ded` · region `us-central1`. All three apps share one backend.

### Progress dependency graph — as it actually is today

```
┌─────────────────────────── MEMBER WRITES (AlphaSerena) ────────────────────────────┐
│                                                                                     │
│  client_workout_sessions   ← workout_log_service.dart      (per-set actuals)        │
│  client_nutrition_days     ← nutrition_day_service.dart    (food log, canonical)    │
│  client_diet_logs          ← diet_log_service.dart         (LEGACY adherence)       │
│  client_lifestyle_days     ← lifestyle_event_service.dart  (water/sleep/steps/supp) │
│  client_lifestyle_logs     ← lifestyle_log_service.dart    (LEGACY mirror)          │
│  client_check_in_submissions ← check_in_submission_service.dart                     │
│  client_progress           ← progress_log_service.dart     (TRANSFORMATION)         │
│  Storage: progress_photos/{uid}/transformations/{recordId}/{front|side|back}.jpg    │
└─────────────────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌───────────────────────── CLOUD FUNCTIONS (trainershq-backend) ──────────────────────┐
│                                                                                      │
│  TRIGGERS                                                                            │
│   onNutritionDayWritten   → computed.{totals,targetAdherence,planCompliance}         │
│                           → nutrition_rollups/{clientId}_{yyyy-MM}   ⚠ NO READER     │
│   onLifestyleDayWritten   → computed.metrics                                         │
│                           → coaching_rollups/{clientId}_{yyyy-MM}.tracks.lifestyle   │
│   onWorkoutSessionActivity ┐                                                         │
│   onNutritionDayActivity   ├→ clients/{id}.lastActivityAt  (max, change-guarded)     │
│   onDietLogActivity        │                                                         │
│   onCheckInSubmissionActivity                                                        │
│   onProgressActivity      ─┘                                                         │
│   onClientWriteActivation → clients/{id}.activationStage                             │
│   onCheckInSubmissionNotify → notifications/{coachUid}/items                         │
│                                                                                      │
│  SCHEDULED                                                                           │
│   evaluateAdherence      (24h) → clients/{id}.adherence     ⚠ NO READER              │
│   cleanupTransformationDrafts (24h) → deletes stale uploading/abandoned + media      │
│   evaluateNotifications  (6h)  → push to COACH only (inactivity/overdue/stalled)     │
│   engagementRollup       (nightly) → engagement_metrics/{day}  (founder console)     │
│                                                                                      │
│  CALLABLES                                                                           │
│   getMyTraining          → workout+diet+weekly overview+prescriptionData+expectations│
│   getCoachingDay / getCoachingDays                                                   │
│   rebuildCoachingRollups (super-admin replay)                                        │
│   backfillAdherence / backfillProgressVisibility (super-admin, one-shot)             │
└──────────────────────────────────────────────────────────────────────────────────────┘
          │                                                    │
          ▼                                                    ▼
┌──────────── TRAINERHQ (coach) ─────────────┐   ┌───────── ALPHASERENA (member) ────────┐
│ ProgressController → 4 streams             │   │ ProgressController → 1 stream         │
│   sessions · dietLogs · checkIns · progress│   │   client_progress (authUid == uid)    │
│ + client doc, lifestyle logs, assignments  │   │                                       │
│ ↓                                          │   │ StreakController + PerformanceCtrl    │
│ deriveProgress (4 pure providers)          │   │   ← prescriptionData + day-key sets   │
│ + progress_series.dart (17 pure fns)       │   │ LifestyleHistoryController            │
│ ↓                                          │   │   ← coaching_rollups                  │
│ ClientProgressScreen — 7 sections          │   │ WorkoutHistoryController              │
│ BodyTransformationScreen                   │   │ NutritionHistoryController            │
│ ReviewAnalyticsScreen / ReviewTimeline     │   │ ↓                                     │
│ MemberLogsScreen (calendar + heatmap)      │   │ ClientProgressScreen — 3 tabs,        │
│                                            │   │   one of which is a placeholder       │
└────────────────────────────────────────────┘   └───────────────────────────────────────┘
```

### The asymmetry, stated plainly

The coach consumes **four** activity streams plus three side streams and runs them through **21 pure derivations**.
The member consumes **one** collection (`client_progress`) on the screen literally called "Progress".

---

## 3. FIRESTORE MAP

87 collections carry rules. These 16 are Progress-relevant.

| Collection | Purpose | Owner / Writer | Read path | Rules | Realtime | History | Indexes | Status |
|---|---|---|---|---|---|---|---|---|
| `client_progress` | **Transformation checkpoints** — weight, body-fat, 12 measurement keys, 3 posed photos, note, per-entry visibility | Member (`authUid`) | Member: `where authUid ==`; Coach: `where adminId+clientId+visibility=='shared'` | Owner RW; coach read only if `visibility=='shared'`; `delete: if false`. Full V2 schema validation incl. Storage-path pinning | ✅ `snapshots()` both sides | ✅ immutable `recordedAt`, `editedAt` proof-of-edit | 1: `[status, updatedAt]` (cleanup job only) | **HEALTHY** |
| `client_workout_sessions` | Per-set prescribed-vs-actual | Member | Coach: `adminId+clientId`; Member: `authorId==uid` | Member create/update own; `delete: if false` | ✅ | ✅ | — (equality-only) | **HEALTHY** |
| `client_nutrition_days` | Canonical food log, `{clientId}_{yyyy-MM-dd}`; `computed` server-owned | Member + CF | `adminId+clientId+dateKey desc` | Member RW own; `computed`/`coachReview` server-only | ✅ | ✅ | `[adminId, clientId, dateKey↓]` | **HEALTHY** |
| `client_diet_logs` | **LEGACY** prescribed-food adherence | Member (no writer left in AlphaSerena) | `adminId+clientId` | Member RW own | ✅ | ✅ | — | **LEGACY / DECAYING** — see §17 |
| `client_lifestyle_days` | Lifestyle **events** (drinks, sleep periods, doses, step samples) | Member | doc-by-id | Member RW own; `computed` server-only; missing-doc reads empty | ✅ | ✅ | — (deterministic ids) | **HEALTHY** |
| `client_lifestyle_logs` | **LEGACY** lifestyle totals mirror | Member | `adminId+clientId` | Member RW own | ✅ | ✅ | — | **LEGACY — scheduled to retire** |
| `client_check_in_submissions` | Member weekly check-in packet + coach response | Member writes packet; coach writes 5 review fields only | `adminId+clientId` / `authorId` | Field-level split enforced in rules | ✅ | ✅ | — | **HEALTHY** |
| `coaching_rollups` | Server-derived monthly read model `{clientId}_{yyyy-MM}` → `tracks.{track}.days.{yyyy-MM-dd}` | CF only | Coach + **member** (via `clients.authUid`) | `write: if false`; missing-doc reads empty | ✅ | ✅ monthly | `[adminId, month↓]` | **HEALTHY but only `lifestyle` track populated** |
| `nutrition_rollups` | Monthly nutrition read model | CF (`onNutritionDayWritten`) | — | `write: if false` | — | ✅ | `[adminId, month↓]` | 🔴 **WRITE-ONLY — ZERO READERS** |
| `clients` | Member record. Carries `adherence`, `lastActivityAt`, `activationStage`, `nextCheckInAt`, `checkInCadenceDays`, `scheduleStatus`, `lifestyleTargets`, `nutritionTargets`, `supplementPlan` | Coach + CF | Member reads own via `authUid` | Server-owned field denylist | ✅ | ✗ point-in-time | — | **`adherence` sub-object is DEAD** |
| `client_checkins` | Coach review-completion history | Coach | Coach only | Coach-scoped | ✅ | ✅ | — | **COACH-ONLY** |
| `client_review_events` | Review schedule/completion ledger (analytics source) | Coach (batched with state change) | Coach only | Coach-scoped | ✅ | ✅ | — | **COACH-ONLY** |
| `client_plan_assignments` | Assigned workout/diet/weekly + `status` lifecycle | Coach | Server (`getMyTraining`); coach direct | Role+tenancy | ✅ | ✅ soft-`ended` | `[adminId, clientId]` | **HEALTHY** |
| `offline_progress` | Coach-logged progress for **in-person** clients (separate universe) | Coach | Coach only | Owner-scoped | ✅ | ✅ | — | **PARALLEL SYSTEM — see §18** |
| `prescriptionHistory` / `nutritionTargetHistory` | Versioned coach prescriptions (subcollections) | Coach/CF | Served in `getMyTraining.prescriptionData` | — | — | ✅ | — | **HEALTHY** |
| `engagement_metrics` | Nightly notification read-rate cohort | CF | Founder console only | Super-admin | — | ✅ | fieldOverride `items.createdAt` COLLECTION_GROUP | **FOUNDER-ONLY** |

### Retention

**There is no retention policy on any Progress collection.** Every one has `delete: if false` by design ("preserve history"). The single exception is `cleanupTransformationDrafts`, which deletes `client_progress` docs with `status ∈ {uploading, abandoned}` older than 48 h, media first (`functions/src/progress.ts:231-256`). Photo storage grows without bound for completed checkpoints — that is deliberate, and it is a cost line item nobody has modelled.

---

## 4. BACKEND MAP

**120 exported functions. 13 scheduled jobs. 25 Firestore triggers.** Of these, the Progress-relevant set:

### Scheduled (cron)

| Function | Cadence | File | Output | Consumed by |
|---|---|---|---|---|
| `evaluateAdherence` | 24 h | `progress.ts:98` | `clients/{id}.adherence` | 🔴 **nobody** |
| `cleanupTransformationDrafts` | 24 h | `progress.ts:231` | deletes stale drafts + Storage media | — (housekeeping) |
| `evaluateNotifications` | 6 h | `notifications.ts` | push → **coach** (`trainers`/`admins`) | coach devices |
| `engagementRollup` | nightly | `intelligence.ts:86` | `engagement_metrics/{day}` | founder console |

### Triggers that feed Progress

| Trigger | File | Writes |
|---|---|---|
| `onNutritionDayWritten` | `nutrition.ts:137` | `computed.{totals, targetAdherence, planCompliance, entryCount, declaredState}` + `nutrition_rollups` cell |
| `onLifestyleDayWritten` | `coaching_events.ts:173` | `computed.metrics` + `coaching_rollups.tracks.lifestyle.days.{key}` |
| `onWorkoutSessionActivity` · `onNutritionDayActivity` · `onDietLogActivity` · `onCheckInSubmissionActivity` · `onProgressActivity` | `engagement.ts:49-108` | `clients/{id}.lastActivityAt` (monotonic max, change-guarded) |
| `onClientWriteActivation` | `activation.ts:73` | `clients/{id}.activationStage` |

### Callables relevant to Progress

- `getMyTraining` (`members.ts`) — the member's single richest server call. Returns `{workout, diet, expectations, prescriptionData}` where `workout` carries `weekly` (full week overview), `restDay`, `nextDay`, `dayPlanUnavailable`. Membership- and status-gated server-side.
- `getCoachingDay` / `getCoachingDays` — server-derived day cells.
- `rebuildCoachingRollups` — super-admin replay from events (proof-of-reconstructability).
- `backfillAdherence`, `backfillProgressVisibility` — one-shot super-admin migrations.

### Shared threshold contract (the one thing done right)

`functions/src/lib/progress_config.ts` declares `ADHERENCE_WINDOW_DAYS = 28`, `MIN_SAMPLE = 3`, `ON_TRACK_PCT = 0.8` and is drift-guarded on both sides:
- server: `functions/test/progress_config.test.mjs`
- client: `trainersHQ/test/progress_threshold_contract_test.dart` ⇄ `trainersHQ/lib/core/progress/progress_policy.dart`

**AlphaSerena is not party to this contract.** If the member app ever shows an adherence number, it will need to join it or the two apps will disagree.

---

## 5. TRANSFORMATION AUDIT

### Verdict: **PRODUCTION READY on the member side. INCOMPLETE as a coaching loop.**

This is the most carefully built feature in the Progress surface, in any of the three repos.

### What exists — end to end

**Model** (`alphaserena/lib/core/models/transformation_entry.dart`, 172 lines)
- `TransformationVisibility {shared, private}` · `TransformationStatus {uploading, complete, abandoned}` · `TransformationPose {front, side, back}`
- Defensive parse of `Timestamp | DateTime | String` (`_date`), `num | String` (`_number`)
- V1 back-compat: a legacy single `photoUrl` maps to `photos[front]` (`:112-118`)
- `recordedAt` fallback chain: `recordedAt → clientRecordedAt → date → createdAt → epoch(0)` (`:122-127`) — never `DateTime.now()`, so a missing date can never impersonate today
- `editedAt` is **proof** of an edit, not inference from timestamp drift (`:56-63`)

**Write path** (`alphaserena/lib/core/services/progress_log_service.dart`, 431 lines)
- `TransformationWriter` interface — the single persistence boundary
- Draft-first protocol: `createUploadDraft` (private envelope) → `uploadPose` (per-pose, persisted as each lands so a retry resumes) → `finalize` (atomic publish)
- `TransformationWriteOutcome {acknowledged, queued}` with a 6 s ack timeout (`:97, :113-137`) — offline writes report "queued", never a false success and never a hung button
- `updatePublished` uses `update`, **not** `set(merge:true)`, with a documented reason: a merge would deep-merge nested maps so a member could never remove a measurement or detach a photo (`:344-354`)
- Storage cleanup runs **only after acknowledged** write; same-pose replacements are skipped so a just-uploaded photo is not deleted (`:373-396`)
- `setVisibility` — re-share/hide without reopening the editor

**Security rules** (`trainershq-backend/firestore.rules`, `client_progress` block, ~170 lines)
This is the strictest block in the ruleset:
- Exact key allowlist (18 keys, `hasOnly`)
- `weightKg ≤ 300`, `bodyFatPercent ≤ 75`, each measurement `> 0 && ≤ 300`
- Measurement key allowlist: `waist, chest, hips, neck, leftArm, rightArm, leftThigh, rightThigh, leftCalf, rightCalf` + legacy `arms, thighs`
- **Photo `storagePath` is regex-pinned to `progress_photos/{request.auth.uid}/transformations/{id}/{pose}.(jpg|jpeg|png|webp|heic)`** — a URL cannot reference another member's media or another record
- `status == 'complete'` requires content (`hasTransformationContent()`)
- Non-complete records are forced `visibility == 'private'` — **a coach can never observe a half-uploaded transformation**
- Correction path preserves `recordedAt` and `createdAt` and **requires** `editedAt == request.time`
- `allow delete: if false`

**Storage rules** (`storage.rules:86-95`) — 12 MB cap, `image/*` only, filename must match `(front|side|back).(ext)`, owner-only.

**Compression:** `image_picker` with `maxWidth: 1800, imageQuality: 84` (`log_transformation_screen.dart:224-225`). This is a downscale-on-pick, not a post-process. Adequate. No `flutter_image_compress` in the transformation path.

**Backend lifecycle:** `cleanupTransformationDrafts` (`progress.ts:231`) — 48 h cutoff, **media deleted before the Firestore envelope** so no file is orphaned if a worker dies mid-operation. Index exists (`[status, updatedAt]`).

**Migration:** `backfillProgressVisibility` (`progress.ts:191`) stamps `visibility:'shared'` on legacy entries, and **only** on missing/invalid values — a valid `private` is never downgraded.

**Coach side** (`trainersHQ/lib/features/clients/screens/body_transformation_screen.dart`, 997 lines) — reads the **same immutable records**, never projects or copies. Filters `isComplete && !isPrivate`, sorts ascending. Reachable from `ClientProgressScreen:331` and `coaching_tools_section.dart:353`.

**Member UI** (`client_progress_screen.dart`, Transformation tab)
- Latest snapshot card, automatic latest-vs-previous comparison with per-pose before/after sliders, expandable timeline (`SliverList.builder`, keyed by record id, `memCacheWidth: 240`)
- Recovery banner for unfinished uploads with per-draft resume
- Per-entry privacy badge + toggle, with **honest queued-state copy**: *"Your coach can still see this check-in until you are back online"* (`:736-743`)

**Tests:** 44 across 5 files — `transformation_entry_test` (3), `transformation_comparison_test` (3), `progress_controller_transformation_test` (1), `log_transformation_screen_test` (13), `transformation_patrol_test` (24 on-device).

### Anything unfinished?

| Item | Status |
|---|---|
| Member logs, edits, corrects, controls privacy | ✅ complete |
| Photo compression | ✅ pick-time downscale |
| Version history | ✅ `editedAt` + immutable `recordedAt`; **no diff/revision log** — you see *that* it was edited, not *what* changed |
| Timeline | ✅ both apps |
| Before/After | ✅ both apps |
| Draft recovery | ✅ member-side resume + server-side 48 h GC |

### Anything missing? — **YES, one thing, and it is the loop**

🔴 **THERE IS NO COACH REVIEW OF A TRANSFORMATION.**

`firestore.rules` grants the coach **read only** on `client_progress`. The `allow update` clause requires `resource.data.authUid == request.auth.uid` — the owner. There is no coach-response field, no `coachReview` map, no acknowledgement, no comment.

Contrast: `client_check_in_submissions` **does** have a coach-response path (rules permit exactly `['coachResponse','reviewedByName','status','reviewedAt','updatedAt']`), and `client_nutrition_days` has a server-owned `coachReview`.

So a member uploads three posed photos and a full measurement set, and **nothing comes back**. The most emotionally loaded artifact in the product is a one-way write.

### Anything duplicated?

🟠 **`transformation_comparison.dart` exists in both apps and has DIVERGED.**
- `alphaserena/lib/core/domain/transformation_comparison.dart`
- `trainersHQ/lib/core/utils/transformation_comparison.dart`

TrainerHQ's copy gained `transformationMeasurementKeys(entries)` + `_measurementOrder` (head-to-toe reading order, unknown keys appended) — an explicit fix for the coach view silently dropping neck/per-side/calf measurements. **AlphaSerena's copy never received it.** AlphaSerena is not currently bitten (it iterates `entry.measurements.entries` directly, so it renders whatever is present) but the files are documented as twins and are not.

### Anything dead?

No dead transformation code found. The legacy `clientProfiles.weightLog` array was already removed as a writer (documented in `alphaserena/CLAUDE.md`), and `MemberController.weightKg` now ranks the canonical value first.

### Anything inconsistent?

🟡 **Two units, one concept.** `measurementUnit` is hard-coded to `'cm'` at every write (`progress_log_service.dart:280, :359`) and rendered from the stored field. The field is therefore ceremonial. `BodyUnits` (`alphaserena/lib/core/utils/body_units.dart`) supports ft/in + lb for the profile editor. A member who set imperial preferences enters transformation measurements in cm with no conversion offered.

🟡 **`bodyFatPercent` is written and validated but never rendered** on the member's Progress screen. The snapshot card shows `weightKg` + `measurements` (`:453-465`) — `bodyFatPercent` is absent from the `Wrap`. A member can log it; nobody shows it back to them.

---

## 6. SCHEDULE AUDIT

There are **five distinct things called "schedule"** in this ecosystem. Conflating them is the single biggest design risk in the Progress work.

### 6.1 Coach review cadence ("Schedules" in TrainerHQ's UI)

**Storage:** `clients/{id}.{checkInCadenceDays, nextCheckInAt, lastCheckInAt, scheduleStatus}` + history in `client_checkins` + ledger in `client_review_events`.

**Writer:** `trainersHQ/lib/core/services/check_in_service.dart` — `setNextDate` writes the client doc **and** appends a `client_review_events` row **in the same batch** (atomic state + audit).

**Coach surfaces:** `CheckInsScreen` (board: Overdue / Due today / Upcoming / Not scheduled), `TodayScheduleSection` on Home (`today_schedule_section.dart` — urgency-grouped outreach planner; its header comment explicitly notes *"the only roster-level time signal is the coach check-in CADENCE (no appointment/clock-time source)"*), `ReviewTimelineScreen`, `ReviewAnalyticsScreen`.

**Member surface:** 🟠 **one boolean.** `alphaserena/lib/controllers/check_in_controller.dart:40-52` reads `nextCheckInAt` off the client doc and exposes `isDue`. That is the whole of it. The member sees a "Due" badge on Home and can open `CheckInScreen`. **They cannot see their cadence, their next date, their history of reviews, or whether their coach paused reviews.** `client_checkins` and `client_review_events` are not in `alphaserena`'s `FsCollections`.

### 6.2 Workout schedule (the weekly split)

**Authored:** `weeklyWorkoutPlans/{id}.days[]` — TrainerHQ's Mon–Sun editor.

**Served:** `functions/src/lib/weekly_serving.ts` (157 lines, pure). `resolveWeeklyDay` returns `{restDay, planId, planName, nextDay}`; `weeklyOverview` returns the whole week with `isToday`. Wired in `members.ts:225-266`. **A rest day serves zero items plus an honest `nextDay` pointer — never yesterday's plan to fill the screen.**

**Consumed:** `alphaserena/lib/controllers/training_controller.dart:224-236` (`isWeeklyRestDay`, `weeklyOverview`, next-day label) → rendered **only** on `my_plans_screen.dart:427, 467, 568`.

**Gap:** the week overview is served but **never reaches Progress**, and there is no forward calendar. The member can see this week's shape on My Plans and nothing beyond it.

### 6.3 Rest days

Two independent sources, correctly reconciled:
- **Weekly mapping** — an unmapped weekday is a rest day (`weekly_serving.ts:115-117`)
- **Prescription engine** — `ExpectationKind.rest` (`prescription.dart`, byte-identical in both apps — verified by `diff`: **IDENTICAL**)

Rendered honestly in `consistency_pair.dart:250` (`TodayMark.rest → 'Rest day'`) and `consistency_story.dart:455` (*"Rest day. Recovery counts."*).

### 6.4 Nutrition schedule

Six meal slots — Breakfast / Mid-morning / Lunch / Evening Snack / Dinner / Bedtime (`kDietMeals`, TrainerHQ `diet_plan_model.dart`). This is a **within-day** schedule, not a calendar. Legacy `Snacks` aliases to Evening Snack. There is no per-weekday diet variation anywhere in the platform.

### 6.5 Sessions / calls

`calls` collection + `onCallCreated` / `onCallFinalized` triggers + a 1-minute cron (`calls.ts`). **There is no appointment booking, no session calendar, no clock-time scheduling.** This is ad-hoc video calling only. `today_schedule_section.dart` says so in its own header comment.

### Push notifications & reminder logic

`evaluateNotifications` (6 h, `notifications.ts`) fires three signals — `inactivity` (≥7 d), `overdueCheckIn`, `activationStalled` (≥2 d) — with a 7-day per-signal cooldown, quiet hours (UTC), and a 500-client-per-run cap.

🔴 **Every one of them is routed to the COACH.** `notifications.ts:164-169`: `trainerId ? {collection:'trainers'} : {collection:'admins'}`. **The member receives zero proactive progress or schedule reminders.** No "you have not logged in 5 days", no "check-in due tomorrow", no streak-at-risk nudge.

### Recurring & realtime

- **Recurring:** `checkInCadenceDays` on the client doc. Coach-set only. No member-set reminders anywhere.
- **Realtime:** every Progress read path is a `snapshots()` listener (member: `progress_log_service.dart:154`; coach: `client_logs_service.dart`, `progress_controller.dart:93-117`). ✅ Genuine live updates on both sides. `getMyTraining` is the exception — a callable, refreshed on tab entry via `refreshIfStale()` (`dashboard_screen.dart:154`).

---

## 7. WEEKLY REPORTS AUDIT

### **No report exists in any repository.**

A repo-wide search across `trainershq-backend/functions/src`, `alphaserena/lib` and `trainersHQ/lib` for `weeklyReport|monthlyReport|weekly_report|monthly_report|generateReport|buildReport|\breport\b` returns:
- `food_platform.ts:455` — an import summary object for a food-catalog job
- `client_profile_screen.dart:928` — the "Report a problem" support link
- `onboarding_question_model.dart:47` — a field-type label
- `org_feedback_screen.dart:186` — support copy

**Nothing else.** There is no report generator, no report collection, no report document, no report screen, no PDF/email/share path, no coach-authored summary.

### What people are calling "reports" — and what they actually are

| Perceived report | What it really is | Who creates | Who reads | How computed | Where |
|---|---|---|---|---|---|
| **Weekly check-in** | A member-submitted **packet** (1–5 ratings across 7 keys, optional weight, note, photos) with one coach text response | Member writes; coach responds | Both | Not computed — collected | `client_check_in_submissions` |
| **Review analytics** | Completion + punctuality rollups over `client_review_events` | Derived live in-app | **Coach only** | `review_insights.dart:89 computeReviewStats` — pure Dart, on device | `ReviewAnalyticsScreen` |
| **Review timeline** | Merge of review events + submissions, newest-first | Derived live in-app | **Coach only** | `review_insights.dart:38 buildReviewTimeline` | `ReviewTimelineScreen` |
| **Coach progress dashboard** | 7-section live derivation | Derived live in-app | **Coach only** | `progress_series.dart` (17 pure fns) + `deriveProgress` (4 providers) | `ClientProgressScreen` |
| **Adherence rollup** | `{score, workoutPct, dietPct}` over 28 d | `evaluateAdherence` cron | 🔴 nobody | `lib/progress.ts computeAdherenceRollup` | `clients/{id}.adherence` |
| **Monthly rollups** | Per-day metric cells | `onLifestyleDayWritten` / `onNutritionDayWritten` | lifestyle: both apps; nutrition: **nobody** | `deriveLifestyleMetrics` / nutrition `computed` | `coaching_rollups` / `nutrition_rollups` |
| **Admin analytics** | Revenue / client growth / membership mix | Derived live in-app | **Coach/owner only** | `dashboard_stats.dart monthlySeries` | `AdminAnalyticsSection` |

### Answering the mission's questions directly

- **Who creates them?** Nobody. Every "report" is an on-device live derivation that exists only while a screen is open.
- **Who reads them?** Coaches, almost exclusively. The member reads no report of any kind.
- **How are they calculated?** Client-side, in Dart, on device. The only server-side Progress computation (`evaluateAdherence`) has no consumer.
- **Cloud Function?** No.
- **Client?** Yes — 100% of what is rendered.
- **TrainerHQ?** Yes — 100% of what is rendered lives in the coach app.

**Design consequence:** a "Weekly Report" for the member is not a feature port. It is net-new, and it needs a persistence decision (materialised document vs. live derivation) that nothing in the repo has made.

---

## 8. EXISTING ANALYTICS

Everything below **already exists and is tested**. The column that matters is the last one.

### 8.1 `trainersHQ/lib/core/progress/progress_series.dart` — 17 pure derivations

| Function | Computes | Source | In member app? |
|---|---|---|---|
| `reconciledWeightSeries` | Weight over time, de-duped by day across `client_progress` **and** check-in packets (body log wins) | progress + checkIns | ❌ (member reads `client_progress` only) |
| `measurementSeries(key)` | One measurement over time | progress | ❌ |
| `workoutAdherenceSeries` | Per-session target-hit % over window | sessions | ❌ |
| `exerciseIdentity` | Stable key `id:{exerciseId}` else `name:{name}` — renames don't split history | sessions | ❌ |
| `topWeightedExercise` | Most-logged exercise carrying numeric weight | sessions | ❌ |
| `strengthSeries(identityKey)` | Heaviest working set per session, ascending | sessions | ❌ **← this is the placeholder tab** |
| `dietAdherenceSeries` | Per-day diet adherence 0..1 | dietLogs | ❌ |
| `dailyConsumedCalories` / `caloriesSeries` | Consumed kcal per day | dietLogs | ❌ |
| `consumedMacroSeries(pick)` | Any macro per day | dietLogs | ❌ |
| `checkInRatingSeries(key)` | One 1–5 self-rating over time | checkIns | ❌ |
| `movingAverage(values, window)` | Trailing SMA, same length as input | — | ❌ |
| `progressScore(metrics)` | Mean of trustworthy adherence-style metrics | metrics | ❌ |
| `coachingVerdict(...)` | `building / declining / needsAttention / stable / improving / excellent` | score + direction + recency | ❌ |
| `workoutStreak` | Consecutive logged days, 0 if broken | sessions | ⚠️ member has its **own** streak engine |
| `totalVolume` | Σ completed-set weight × reps, window | sessions | ❌ |
| `distinctExercises` | Unique exercises in window, identity-keyed | sessions | ❌ |
| `personalBests(limit)` | Heaviest set per exercise, strongest first | sessions | ❌ |
| `lifestyleNumericSeries(pick)` | Sleep / water / steps over time | lifestyle logs | ⚠️ member has `LifestyleHistoryController` |
| `overallDirection` | Improving / declining / steady | metrics | ❌ |

Tests: `progress_series_test.dart`, `progress_test.dart`, `progress_runtime_test.dart`, `progress_threshold_contract_test.dart`.

### 8.2 The frozen M5 engine (`trainersHQ/lib/core/progress/`)

Four implemented providers — `workoutAdherence`, `dietAdherence`, `momentum`, `weightTrend`. Four **reserved** enum values with no provider: `lifestyleAdherence`, `checkInConsistency`, `strengthProgression`, `measurementTrend` (`progress_metric.dart:24-27`).

`ProgressConfidence {none, low, ok}` — below `MIN_SAMPLE=3` the surface says "not enough data yet" and shows **no number**. This is the platform's Trust principle and it is enforced, not aspirational.

### 8.3 What AlphaSerena already computes for itself

| Module | Computes |
|---|---|
| `core/domain/consistency_story.dart` (523 l) | `buildStreakHero`, `buildAchievements` (5 kinds: longestStreak, currentStreak, total, adherence, monthly), `adherenceOf`, `monthlyGoalOf`, next-milestone copy |
| `core/domain/consistency_pair.dart` (476 l) | 5-week rail, month cells, milestone ladder **bounded by the 60-day fetch window** (a 100-day goal is never offered because it cannot be verified) |
| `core/domain/performance.dart` + `prescription.dart` | `TrackHistory`, `expectationFor`, `verdictFor` — the certified two-axis engine (**`prescription.dart` is byte-identical across both apps**) |
| `core/utils/streak_math.dart` | Raw calendar-consecutive-day streak (no-prescription fallback) |
| `core/services/activity_history_service.dart` | `workoutDayKeys` / `dietDayKeys`, 60-day window, day-aligned cutoff, **`isFromCache` empty ⇒ null, never 0** |
| `core/domain/nutrition_history.dart` | History calendar day states |
| `core/domain/workout_history.dart` | `computeSessionStats` → completed / partial / skipped |
| `core/services/member_rollup_service.dart` | `RollupDay.fromCell` — parses `tracks.lifestyle.days.{key}`, nulls stay null |
| `core/utils/lifestyle_math.dart` | glasses↔ml, `glassesToReach`, sleep/step derivations |
| `core/utils/diet_adherence.dart` | `consumedMacro`, `statusScore` — cross-app parity-tested |
| `core/utils/check_in_math.dart` | Check-in date math (⚠️ diverged from TrainerHQ's copy — formatting only) |

### 8.4 Backend

`functions/src/lib/progress.ts` — `sessionTargetHitPct`, `dietDayAdherence` (**clamped** — the field is member-written and unbounded in rules), `nutritionDayAdherence` (reads server-computed `computed.targetAdherence`, never re-derives), `computeAdherenceRollup`, `adherenceChanged`.

---

## 9. MISSING ANALYTICS

Split by what it would actually take. **Nothing here is invented — each row names the concrete gap.**

### 9.1 Exists in TrainerHQ, absent in AlphaSerena (port / share, no backend)

- Strength progression per exercise (the literal placeholder)
- Personal bests board
- Training volume (kg·reps) over window
- Distinct exercises trained
- Per-session workout adherence trend
- Weight series reconciled across check-ins **and** body log
- Per-measurement trend lines (waist, chest, arms…)
- Consumed calories / macro trends
- Check-in self-rating trends (energy, sleep, stress, hunger, motivation, training, diet)
- Moving-average smoothing
- Overall direction (improving / stable / declining)
- A single headline verdict

### 9.2 Exists in AlphaSerena but not on the Progress screen (wiring only)

- Streaks (workout + nutrition), achievements, milestones
- Adherence % with an honest denominator
- Monthly goal progress
- 5-week rail + month calendar
- Workout history timeline (per-day session detail)
- Nutrition history calendar
- Lifestyle history (water / steps / sleep / supplements, streaks + averages)
- Check-in history + coach responses

### 9.3 Genuinely missing — needs new backend

| Missing | Why it needs backend | Evidence of absence |
|---|---|---|
| **Any report artifact** (weekly / monthly / coach summary) | Nothing materialises a period summary; the client cannot author a trusted one | §7 — zero hits repo-wide |
| **Coach review of a transformation** | Rules grant coach read-only on `client_progress`; needs a `coachReview` field + rules clause + a notification | `firestore.rules` `client_progress` `allow update` = owner-only |
| **Member-facing progress push** | `evaluateNotifications` routes only to `trainers`/`admins` | `notifications.ts:164-169` |
| **Goal weight / target body composition** | No field, no writer, no editor anywhere. `EditProfileScreen` previously *required* a goal weight no surface collected — that was removed as a defect | `alphaserena/CLAUDE.md` 2026-08-02 Profile entry |
| **Prediction / forecast / projection** | No trend extrapolation, no ETA-to-goal, no regression, anywhere | grep: no `forecast`/`predict`/`projection` in any progress module |
| **`nutrition_rollups` consumption** | Written monthly, read by nobody. A member nutrition trend over months has a ready read model that no code opens | `grep nutrition_rollups` across both apps → 0 |
| **Workout track in `coaching_rollups`** | `COACHING_TRACKS = ['nutrition','lifestyle','workout']` but `buildRollupCell` is called with `'lifestyle'` **only** (2 call sites) | `lib/coaching_events.ts:48`; `coaching_events.ts:232, :329` |
| **Body-fat rendering** | Written + validated, never displayed to the member | `client_progress_screen.dart:453-465` |
| **Progress photo compression beyond pick-time** | 12 MB/photo cap × 3 poses × unbounded history, no retention | `storage.rules:90` |
| **Attendance** | No attendance concept exists. The nearest analogue is logged-session presence | no `attendance` symbol in any repo |
| **Coach adherence** (does the coach hold up their end?) | `client_review_events` supports it and `computeReviewStats` computes it — **coach-only**, never surfaced to the member | `review_insights.dart:89` |

---

## 10. UX PROBLEMS

Evaluated against Whoop, Apple Fitness, Garmin Connect, Fitbod, Strong, MyFitnessPal — **not to copy, only to locate the shortfall.**

### 10.1 Structural — the ones that matter

🔴 **P1 · The tab lies about its scope.** Three tabs; one is a placeholder that says so out loud (*"Strength trends are next"* — `:1044`). A member paying for coaching taps "Progress" and finds a weight chart and a photo album. Strong, Fitbod and Garmin all open on training performance. Ours opens on a scale reading.

🔴 **P1 · Progress is an island.** `ClientProgressScreen` is reachable only as bottom-nav index 2 (`dashboard_screen.dart:160`). **Not one other screen links into it.** Meanwhile the five screens that hold the real progress story all link *away* from it — Home → Consistency, My Plans → Consistency/WorkoutHistory, Diet → NutritionHistory, Lifestyle Today → LifestyleHistory. Progress is where progress *isn't*.

🔴 **P1 · Six competing homes for one question.** "How am I doing?" is answered by ClientProgressScreen, ConsistencyDetailScreen, WorkoutHistoryScreen, NutritionHistoryScreen, LifestyleHistoryScreen and CheckInScreen. Every one is well built. None knows the others exist. Whoop answers it on one screen; Garmin on one screen with drill-downs.

🟠 **P2 · No time-range control anywhere.** No 7d/30d/90d/1y/all selector on any member Progress surface. Windows are hard-coded and inconsistent: 60 days (`activity_history_service`), 28 days (`ProgressPolicy`), 3 months (lifestyle rollup listeners), all-time (transformation weight chart). **A member cannot ask a question about a period they choose.** Every named competitor ships range selection as table stakes.

🟠 **P2 · No filters, no comparison, no export.** No metric picker, no period-over-period comparison, no share/export. The one comparison that exists is fixed at latest-vs-previous (`:319`).

### 10.2 Information hierarchy

🟠 **P2 · No headline.** The screen opens with a 24pt "Progress" title and a subtitle, then a weight card. There is no single answer to "am I winning?" — TrainerHQ has exactly that (`coachingVerdict` → six states, rendered in `_healthHero`). The member gets none of it.

🟠 **P2 · Overview is not an overview.** `_overview` (`:152-206`) = weight trend + a compact latest-transformation snapshot. Workout, nutrition and lifestyle — three of the four things the member does daily — are absent from a tab named "Overview".

🟡 **P3 · Density inversion.** The transformation timeline is dense and rich (photos, measurements, chips, notes, per-entry actions). The Overview tab is two cards. The most-used surface is the emptiest.

### 10.3 Charts

🟠 **P2 · One chart type, one metric.** `fl_chart` `LineChart` (`:233-294`), weight only. No bars, no area, no distribution, no heatmap, no rings on Progress. The app **already** has a heatmap and calendar (`consistency_detail_screen`) and animated rings (`progress_ring.dart`, `nutrition_progress_card`) — they just are not here.

🟡 **P3 · No interactivity.** No touch/tooltip/`LineTouchData`, no pan/zoom. A member cannot find out what a point is. Whoop, Garmin and MFP all make every point interrogable.

🟡 **P3 · Axis heuristics.** `xInterval = (maxX - minX) / 2` gives exactly 3 x-labels regardless of range (`:232`). Y padding is a fixed ±2 kg (`:237-238`), which flattens a 30 kg transformation and exaggerates a 0.5 kg fluctuation.

🟢 Credit where due: the single-point case is handled (`hasTimeRange` → ±12 h synthetic span, `:229-231`) and the chart carries a full `Semantics` label (`:195-197`).

### 10.4 Loading, empty, error

🟢 **Loading:** a real three-block skeleton (`:1131-1159`), not a spinner.
🟠 **P2 · The skeleton is wrong for two of three tabs.** It always draws title + 48 px bar + 300 px card — the Overview shape. Switching to Transformation shows an Overview skeleton.
🟢 **Empty:** genuinely excellent. `_honestEmpty` never fabricates. *"Log only what matters today… Nothing is estimated or required unnecessarily."* (`:383`)
🟢 **Error:** *"Your data was not replaced with zeros"* (`:1086`) + Retry. Best-in-class honesty.
🟠 **P2 · Loading is all-or-nothing.** `member.isLoading || progress.isLoading` blanks the **whole** screen (`:34`). TrainerHQ tracks per-source loading so a partial feed never renders as complete (`progress_controller.dart:119-131`). The member app has one source, so this is cheap today — and will not survive adding four more.

### 10.5 Performance

🟠 **P2 · The tab is built eagerly and never disposed.** `IndexedStack(children: _pages)` (`dashboard_screen.dart:174`) builds all four pages at dashboard mount. `ProgressController` is `Get.put` at `:72` and streams `client_progress` for the whole session, whether or not the member ever opens Progress.
🟢 The transformation history was correctly moved to `SliverList.builder` with `ValueKey(id)` and `memCacheWidth: 240` (`:346-355`) — a documented fix for decoding every photo on open.
🟠 **P2 · The weight chart is unbounded.** `c.weights.reversed` plots **every** weight checkpoint ever recorded, with no window and no downsampling.

### 10.6 Accessibility

🟢 Good: chart `Semantics` label, `Semantics(selected:, button:)` on tabs (`:100-102`), photo semantics (`:766-768`), privacy-badge semantics (`:963-966`).
🟠 **P2 · The tab strip is not a tab strip.** Three `InkWell`s in a `Row` (`:96-133`) — no `TabBar`, no `Semantics(container:)` per control, no keyboard traversal, no announced tab-set position ("tab 2 of 3").
🟠 **P2 · Sub-11 px type.** `AppText.body(size: 9.5)` on summary chips (`:934`), `10.5` on change chips (`:918`), `11` and `11.5` throughout. At 2.0× OS scale these will fight the fixed `_photo` widths (`(maxWidth - 16) / 3`) and the `maxWidth: 280` chip constraint.
🟠 **P2 · Colour-only direction encoding.** `_changeChip` (`:894-924`) uses accent for both up and down. **A weight reduction and a weight gain render identically** — same colour, same weight, distinguished only by a small arrow glyph and the word. There is no semantic good/bad, deliberately (the app has no goal weight, §9.3) — but the result is that direction is easy to misread.

### 10.7 Premium feel

🟠 **P2 · Static.** The app has `TweenAnimationBuilder` sweep-gradient rings with bloom on the Home nutrition card, and `FadeSlideIn` staggering in TrainerHQ. Progress has **zero animation** — no chart draw-in, no counter roll, no stagger, no shared-element transition into a photo (a `heroTag` is passed at `:773` but there is no Hero widget to receive it).
🟡 **P3 · No haptics** on tab switch or photo open.
🟡 **P3 · Flat card system.** `_card` is `surface` + 1 px border (`:1118-1129`) — no elevation, no gradient, no glass. TrainerHQ's `GlassScaffold`/`GlowCard` system is not present in AlphaSerena's Progress.

### 10.8 Where we stand vs. the reference set

| Capability | Whoop | Apple Fitness | Garmin | Fitbod | Strong | MFP | **Us (member)** |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Single headline verdict | ✅ | ✅ | ✅ | — | — | — | ❌ (exists coach-side) |
| Time-range selector | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Strength / PR tracking | — | — | ✅ | ✅ | ✅ | — | ❌ (placeholder) |
| Training volume | — | — | ✅ | ✅ | ✅ | — | ❌ |
| Body measurements | ✅ | — | ✅ | — | ✅ | ✅ | ✅ **best-in-class** |
| Progress photos | — | — | — | — | — | ✅ | ✅ **best-in-class** |
| Streaks / consistency | ✅ | ✅ | ✅ | — | — | ✅ | ✅ (wrong screen) |
| Nutrition trends | — | — | — | — | — | ✅ | ⚠️ (wrong screen) |
| Sleep / recovery trends | ✅ | — | ✅ | — | — | — | ⚠️ (wrong screen) |
| Interactive charts | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Weekly/monthly report | ✅ | ✅ | ✅ | — | — | ✅ | ❌ |
| Coach feedback loop | — | — | — | — | — | — | ❌ **(our differentiator, unbuilt)** |

**Read the last row.** No competitor has a coach. Ours is the only product where a human can respond — and the response path exists for check-ins and does not exist for transformations, the artifact members care most about.

---

## 11. EXISTING SCREENS

### AlphaSerena (member)

| Screen | Lines | Reached from | Progress content |
|---|---|---|---|
| `dashboard/client_progress_screen.dart` | 1,161 | **bottom nav only** | Weight trend · Transformation timeline · Strength placeholder |
| `dashboard/log_transformation_screen.dart` | ~1,100 | Progress tab | Weight, body-fat, 12 measurements, 3 posed photos, note, visibility |
| `dashboard/consistency_detail_screen.dart` | 1,134 | Home ×2, My Plans, Workout Summary | Streak hero · week rail · month calendar · 5 achievements · adherence · monthly goal |
| `dashboard/plans/workout_history_screen.dart` | — | My Plans | Scrubable day timeline + full session detail; 7 day-states |
| `dashboard/nutrition/nutrition_history_screen.dart` | — | My Plans, Diet | Month calendar + per-day log |
| `dashboard/lifestyle_history_screen.dart` | — | Lifestyle Today app bar | Water/steps/sleep/supplements history, streaks, averages |
| `dashboard/check_in_screen.dart` | — | Home ×2, notifications, push | Submit packet · past check-ins + coach responses |
| `dashboard/home/consistency_cards_pair.dart` | — | Home | Workout + Nutrition consistency cards |
| `dashboard/home/nutrition_progress_card.dart` | — | Home | Animated calorie ring + 2×2 macro grid |
| `dashboard/home/lifestyle_progress_card.dart` | — | Home | 2×2 tile grid with bars |
| `dashboard/workout_summary_screen.dart` | — | post-session | Session summary → Consistency |

### TrainerHQ (coach)

| Screen | Lines | Progress content |
|---|---|---|
| `clients/screens/client_progress_screen.dart` | **1,636** | **7 sections: Health verdict · Body · Workout · Nutrition · Lifestyle · Reviews · Timeline** |
| `clients/screens/body_transformation_screen.dart` | 997 | Transformation timeline, before/after, measurement deltas |
| `clients/widgets/client_progress_summary_section.dart` | 382 | M5 metric summary on the client cockpit |
| `member_logs/screens/member_logs_screen.dart` | — | Workouts \| Diet tabs, activity calendar, log heatmap |
| `member_logs/screens/streak_detail_screen.dart` | — | Streak drill-down |
| `member_logs/screens/missed_days_screen.dart` | — | Missed-day analysis |
| `check_ins/screens/review_analytics_screen.dart` | — | Completion + punctuality rollups |
| `check_ins/screens/review_timeline_screen.dart` | — | Merged review story |
| `clients/screens/lifestyle_review_screen.dart` | — | Lifestyle adherence review |
| `clients/screens/lifestyle_habit_history_screen.dart` | — | Per-habit history |
| `shell/widgets/admin_analytics_section.dart` | — | Revenue / growth / membership charts |
| `offline_clients/screens/offline_progress_screen.dart` | — | **Parallel** progress system for in-person clients |

---

## 12. EXISTING CONTROLLERS

### AlphaSerena

| Controller | Owns | Registered |
|---|---|---|
| `ProgressController` | `client_progress` stream, `weightChange` (chronology-correct, skips partials) | `Get.put` at dashboard mount (`dashboard_screen.dart:72`) |
| `StreakController` | Day-key sets, `ensureFreshDay()` midnight rollover | dashboard |
| `PerformanceController` | Glue: `prescriptionData` + day-keys → `TrackHistory`. **Holds no logic** | lazy (per screen) |
| `TrainingController` | `getMyTraining` — workout, diet, expectations, prescriptionData, weekly overview | dashboard |
| `WorkoutHistoryController` / `NutritionHistoryController` / `LifestyleHistoryController` | Per-domain history | per screen |
| `CheckInController` | Submissions + `isDue` from `clients.nextCheckInAt` | dashboard |
| `LifestyleController` | Events, debounced legacy mirror | dashboard |
| `FoodLogController` | `client_nutrition_days` | dashboard |
| `MemberController` | `clients` + `clientProfiles` live docs | dashboard |

All member-scoped controllers are torn down in `auth_controller.dart signOut` (`:483` for `ProgressController`) — a documented cross-member-bleed fix.

### TrainerHQ

| Controller | Owns |
|---|---|
| `ProgressController` (`core/progress/`) | **4 streams**, per-source `_emitted`/`_sourceError` tracking, `revision` counter, `retry()` re-subscribe |
| `TimelineController` | Canonical activity aggregation (governance: all activity aggregation MUST consume it) |
| `EngagementController` / `AttentionController` | Signals + coach attention queue |
| `CheckInController` / `CheckInReviewController` / `ReviewAnalyticsController` / `ReviewTimelineController` | Review lifecycle |
| `LifestyleReviewController` | Lifestyle adherence, memoized per data-change keyed on today's day-key |
| `AdminDashboardController` | Revenue/growth from already-streamed `ClientController` (no new queries) |

---

## 13. EXISTING MODELS

| Model | Repo | Key fields |
|---|---|---|
| `TransformationEntry` + `TransformationPhoto` | alphaserena | id, clientId, adminId, authUid, schemaVersion, recordedAt, createdAt, updatedAt, **editedAt**, visibility, status, measurementUnit, weightKg, bodyFatPercent, measurements{}, photos{pose→{url,storagePath}}, note |
| `ClientProgressEntry` | trainersHQ | same collection, coach-side parse (151 l) |
| `ProgressMetric` + `ProgressContext` | trainersHQ | type, clientId, value, direction, windowDays, sampleSize, confidence, label, trendValues |
| `TrendPoint` | trainersHQ | date, value |
| `CheckInSubmissionModel` | both | ratings{} (open map, 1–5), weightKg, note, photos, status, coachResponse, reviewedAt |
| `ClientWorkoutSessionModel` + `SessionEntry` + `SessionSet` | both | prescribed vs actual reps/weight, completed, `adherence.targetHitPct` |
| `ClientNutritionDayModel` | both | entries{}, computed{totals,targetAdherence,planCompliance}, coachReview |
| `ClientDietLogModel` | both | items[], adherencePct (**legacy**) |
| `LifestyleLogModel` | both | waterMl, steps, sleepMinutes, supplements, derivedItemsTaken, derivedDoses |
| `RollupDay` | alphaserena | parses `tracks.lifestyle.days.{key}` — nulls stay null |
| `Prescription` / `Expectation` / `TrackHistory` | **both, byte-identical** | the certified two-axis engine |
| `ConsistencyCard` / `StreakHero` / `Achievement` / `MonthCell` | alphaserena | streaks, milestones, calendar |
| `ReviewEventModel` / `TimelineEntry` / `ReviewStats` | trainersHQ | review ledger + analytics |
| `OfflineProgressEntry` | trainersHQ | **parallel** in-person system |

---

## 14. EXISTING CLOUD FUNCTIONS

**Directly Progress-owned** (`functions/src/progress.ts`, 257 lines):
1. `evaluateAdherence` — `onSchedule("every 24 hours")`. Paginated (`PAGE=300`) cursor over active clients; per-client equality-only reads of sessions + diet logs + nutrition days (no composite index required, windowing in memory); change-guarded write. Per-client `try/catch` so one failure never aborts the run. **Scheduled, not trigger-based, so adherence DECAYS when logging stops** — a write trigger never fires for a silent client.
2. `backfillAdherence` — super-admin one-shot, all statuses, idempotent.
3. `backfillProgressVisibility` — super-admin, stamps legacy `visibility:'shared'`, never downgrades a valid `private`.
4. `cleanupTransformationDrafts` — 48 h GC, media before envelope.

**Indirectly feeding Progress:** `onNutritionDayWritten`, `onLifestyleDayWritten`, the five `engagement.ts` activity triggers, `onClientWriteActivation`, `getMyTraining`, `getCoachingDay(s)`, `rebuildCoachingRollups`, `evaluateNotifications`, `onCheckInSubmissionNotify`, `engagementRollup`.

**Deployment state: UNVERIFIABLE FROM REPO.** `trainersHQ/CLAUDE.md` records `evaluateAdherence` + `backfillAdherence` as *"⚠️ OPERATOR GATE — deploy pending"* as of 2026-07-04, with no later entry confirming it. Given F4 (no readers), whether it is deployed changes nothing today.

---

## 15. EXISTING SECURITY RULES

`firestore.rules` — 156 KB, 87 collection blocks. Progress-relevant assessment:

| Collection | Read | Write | Notable |
|---|---|---|---|
| `client_progress` | Owner always; coach **only if `visibility=='shared'`** | Owner only, full V2 schema validation | Storage-path regex pinning; `hasOnly` 18-key allowlist; bounded numerics; `editedAt` mandatory on correction; `delete: if false` |
| `client_workout_sessions` | Owner + org | Owner create/update | `delete: if false` |
| `client_nutrition_days` | Owner + org; **missing doc reads empty** | Owner; `computed`/`coachReview` server-only | — |
| `client_lifestyle_days` | Owner + org; missing-doc clause | Owner; `computed` server-only | — |
| `client_check_in_submissions` | Owner + org | Member owns packet; coach may write **exactly** `['coachResponse','reviewedByName','status','reviewedAt','updatedAt']` and must land on `'reviewed'` | The only field-level write split in the Progress surface |
| `coaching_rollups` | Org + **member via `clients.authUid`**; `(resource == null && signedIn())` | `if false` | The missing-doc clause is load-bearing — its absence caused a real coach-facing outage |
| `nutrition_rollups` | same shape | `if false` | Correct, unused |
| Storage `progress_photos/{uid}/transformations/{recordId}/{file}` | Owner only | Owner, ≤12 MB, `image/*`, filename `(front\|side\|back).(ext)` | — |

### Rules-level observations

🟢 **The `resource == null` missing-document clause** is now applied consistently to `coaching_rollups`, `nutrition_rollups`, `client_lifestyle_logs`, `client_lifestyle_days`, `client_nutrition_days`. This defect class has bitten this platform three times and is now systematically closed.

🟠 **`client_progress` does NOT carry that clause.** Every read branch dereferences `resource.data`. This is harmless for the current access pattern (both apps *query*, never `get()` by id) but it is the one Progress collection outside the pattern — and any future deep link of the form `client_progress/{id}` would be denied for a missing doc rather than reading empty.

🟠 **A coach cannot write to `client_progress` at all.** Correct today; it is the exact rule that must change to build a transformation review loop (§5).

🟡 **`client_diet_logs.adherencePct` is unbounded in rules.** The backend defends itself by clamping in two places (`lib/progress.ts:75`, `lib/nutrition.ts clampLegacyAdherence`). Any *new* reader must clamp too, or a forged `adherencePct: 999` pins a member at a perfect score.

---

## 16. RISKS

| # | Risk | Severity | Evidence |
|---|---|---|---|
| **R1** | **Building Progress in AlphaSerena without porting `progress_series.dart` will fork the analytics.** Two apps computing "adherence"/"streak"/"volume" from different code will disagree in front of a coach and a member on a call. `prescription.dart` was kept byte-identical precisely for this reason. | 🔴 CRITICAL | `prescription.dart` diff → IDENTICAL; `transformation_comparison.dart` diff → **already diverged** |
| **R2** | **`transformation_comparison.dart` has already drifted.** The mechanism that is supposed to prevent R1 has already failed once, silently, on the Transformation feature itself. | 🔴 CRITICAL | TrainerHQ's copy has `transformationMeasurementKeys` + `_measurementOrder`; AlphaSerena's does not |
| **R3** | **Unbounded reads.** `watchTransformations()` streams **every** `client_progress` doc for the member, forever, with no window and no pagination. The weight chart plots every point ever. A 3-year member is a growing cold-start cost on a screen built eagerly at dashboard mount. | 🟠 HIGH | `progress_log_service.dart:152-166`; `client_progress_screen.dart:153` |
| **R4** | **No index for a windowed transformation read.** The only `client_progress` composite index is `[status, updatedAt]` (the GC job). Any `where(authUid) + orderBy(recordedAt) + limit` needs a new index, and `firestore.indexes.json` must stay a superset of every app's queries. | 🟠 HIGH | `firestore.indexes.json` — 1 `client_progress` index |
| **R5** | **Photo storage grows without bound.** 12 MB × 3 poses × unbounded checkpoints × every member. No retention, no tiering, no thumbnail derivative. Only *abandoned drafts* are collected. | 🟠 HIGH | `storage.rules:90`; `progress.ts:231-256` |
| **R6** | **`client_diet_logs` is decaying.** AlphaSerena has no writer left (Phase 3B made coach recommendations read-only). `computeAdherenceRollup` already carries an explicit workaround so `dietPct` did not silently decay to null as legacy days aged out. Any new consumer of `dietLogs` inherits an emptying collection. | 🟠 HIGH | `lib/progress.ts:171-195` (comment names the exact failure) |
| **R7** | **Device-clock trust.** `clientRecordedAt` is device time; `recordedAt` is a server timestamp. Streak/consistency day-keys are computed from **local device time** (`activity_history_service.dart`). A skewed clock shifts a member's whole progress calendar. *(This machine has a documented history of emulator clock skew breaking Firebase Auth.)* | 🟠 HIGH | `progress_log_service.dart:188` vs `:281` |
| **R8** | **The 60-day fetch window is an invisible ceiling.** `kLogWindowDays` bounds the milestone ladder — deliberately, honestly (a 100-day streak cannot be verified so is never offered). A "flagship" Progress that claims year-long history contradicts the guarantee the current engine makes. | 🟠 HIGH | `consistency_pair.dart:94-107` |
| **R9** | **Sub-11 px type + fixed-width photo grids** will overflow at 2.0× OS text scale. TrainerHQ has already shipped and fixed exactly this class of defect (153 px roster overflow, 41 px nutrition-row overflow). | 🟡 MEDIUM | `client_progress_screen.dart:918, :934`; `trainersHQ/CLAUDE.md` |
| **R10** | **14 pre-existing golden-image test failures** in AlphaSerena (missing font faces on this machine). Any new Progress goldens would bake in that failure. | 🟡 MEDIUM | `alphaserena/CLAUDE.md`, repeated across entries |
| **R11** | **Patrol runs leave the app unlaunchable and signed out** — rebuild a debug APK before runtime verification. | 🟡 MEDIUM | prior session memory, confirmed by `patrol_test/` presence |
| **R12** | **`evaluateAdherence` deploy state unknown.** If it is live and unread, it is spending daily reads across the whole active roster for nothing. | 🟡 MEDIUM | UNVERIFIABLE FROM REPO |
| **R13** | **No member-facing notification path exists.** Any "your weekly report is ready" or "you haven't logged in 5 days" needs the routing in `evaluateNotifications` extended — and `registerFcmToken`'s resolver is documented as audience-blind (admins → trainers → clientProfiles). | 🟡 MEDIUM | `notifications.ts:164-169`; `alphaserena/CLAUDE.md` 2026-08-01 |

---

## 17. DEAD CODE

Evidence-backed. Nothing listed here on suspicion alone.

| Item | Kind | Evidence |
|---|---|---|
| **`nutrition_rollups` collection** | 🔴 **Write-only.** Written on every nutrition-day change, monthly document, indexed `[adminId, month↓]`, rules-protected. **Zero readers in either Flutter app.** | `grep nutrition_rollups` → `nutrition.ts:210` (write) only |
| **`clients/{id}.adherence`** | 🔴 **Write-only.** Daily cron over the whole active roster. `ClientModel` does not parse it. | `progress.ts:98`; `grep adherence trainersHQ/lib/core/models/client_model.dart` → empty |
| **`coaching_rollups` `nutrition` + `workout` tracks** | 🟠 **Declared, never written.** `COACHING_TRACKS = ['nutrition','lifestyle','workout']`; both `buildRollupCell` call sites pass `'lifestyle'`. | `lib/coaching_events.ts:48`; `coaching_events.ts:232, :329` |
| **`ProgressMetricType` reserved values** | 🟢 **Deliberate.** `lifestyleAdherence`, `checkInConsistency`, `strengthProgression`, `measurementTrend` have no provider — the documented reserved-enum pattern, not rot. | `progress_metric.dart:24-27` |
| **`TransformationEntry.bodyFatPercent`** | 🟠 **Written, validated, never displayed** to the member. | `client_progress_screen.dart:453-465` |
| **`TransformationEntry.measurementUnit`** | 🟡 **Ceremonial.** Hard-coded `'cm'` at every write; rendered from the field. | `progress_log_service.dart:280, :359` |
| **`_latestSnapshot(previous:)` parameter** | 🟡 Every call site passes `previous: null` (the comparison card renders the same chips one card below). Live parameter, no live caller. | `client_progress_screen.dart:316, :467` |
| **`heroTag` on transformation photos** | 🟡 Built and passed (`:773`); no `Hero` widget receives it. | `client_progress_screen.dart:770-774` |

Already-removed dead code, confirmed gone (do not re-introduce): `core/domain/consistency.dart` (473 l, second divergent engine), `client_diet_screen.dart`, `DietLogController`, `dashboard_data.dart`, `macro_calculator.dart`, `DietPlanModel.target*`.

⚠️ **`core/utils/streak_math.dart` is LIVE** (StreakController's no-prescription fallback) despite superficially overlapping `consistency_story.dart`. Do not delete it.

---

## 18. DUPLICATE LOGIC

| # | Duplication | State | Guard |
|---|---|---|---|
| **D1** | `prescription.dart` — alphaserena `core/domain/` ⇄ trainersHQ `core/domain/` | ✅ **byte-identical** (verified by `diff`) | trainersHQ's mirrored `prescription_test.dart` does **not** yet carry the two-axis cases |
| **D2** | `transformation_comparison.dart` — alphaserena `core/domain/` ⇄ trainersHQ `core/utils/` | 🔴 **DIVERGED** | none |
| **D3** | `check_in_math.dart` — both apps | 🟡 diverged (formatting only) | none |
| **D4** | `lifestyle_math.dart` — both apps | 🟡 diverged (`glassesToReach`/`hoursMinutes` are alphaserena-only) | `lifestyle_cross_app_contract_test.dart`, twinned |
| **D5** | `diet_adherence.dart` ⇄ TrainerHQ `consumed_nutrition.dart` | ✅ parity-tested both ways | `diet_trainerhq_parity_test.dart` + `lifestyle_nutrition_summary_parity_test.dart` |
| **D6** | Adherence math: `functions/src/lib/progress.ts` ⇄ `trainersHQ/lib/core/progress/providers/*` | ✅ intentional mirror | `progress_config.ts` + drift-guards **both** sides |
| **D7** | **Streak computation ×3** — `progress_series.dart:322 workoutStreak` (coach) · `streak_math.dart` (member fallback) · `consistency_story.dart bestDailyStreak`/`bestWeeklyAdherenceStreak` (member primary) | 🟠 three implementations, three definitions | none |
| **D8** | **Weight series ×2** — `progress_series.dart:41 reconciledWeightSeries` (progress **+ check-ins**) vs `ProgressController.weights` (progress **only**) | 🟠 **the member's chart is missing check-in weights** — the exact bug TrainerHQ's V1 audit already fixed | none |
| **D9** | Calendar/heatmap ×3 — `consistency_detail_screen` (member), `nutrition_history_screen` (member), `member_logs/widgets/activity_calendar.dart` + `log_heatmap.dart` (coach) | 🟡 three implementations | none |
| **D10** | Transformation timeline ×2 — `client_progress_screen` (member) ⇄ `body_transformation_screen` (coach) | 🟢 acceptable — same data, different audience, no shared logic to fork | — |
| **D11** | **Two parallel progress universes** — online (`client_progress`) vs offline (`offline_progress` + `OfflineProgressController` + `offline_progress_screen` + `log_progress_sheet`) | 🟠 duplicate concept, duplicate UI, duplicate model | — |

**D8 is a live member-facing defect, not a refactor:** a member who records weight *only* in weekly check-in packets sees a Progress weight chart that says *"Add at least two check-ins to see a trend"* while their coach's chart shows the trend.

---

## 19. PRODUCTION READINESS

### Can Progress be built entirely from existing infrastructure?

**No — but the shortfall is narrow and precisely locatable.**

| Layer | Ready? | Detail |
|---|---|---|
| **Data capture** | ✅ 95% | Every source the flagship needs is already written by the member. Gaps: goal weight, target body composition. |
| **Firestore schema** | ✅ 95% | All collections exist, are rules-protected, are realtime, preserve history. Gap: no index for a windowed transformation read (R4). |
| **Security rules** | ✅ 90% | Excellent. Gaps: no coach write on `client_progress` (blocks the review loop); no `resource == null` clause on `client_progress`. |
| **Backend computation** | ⚠️ 40% | One cron with no readers; two rollup collections, one unread; **zero report generation**; **zero member-facing notification**. |
| **Analytics logic (Dart)** | ✅ 90% — **in the wrong repo** | `progress_series.dart` (17 fns) + 4 M5 providers + `consistency_story`/`consistency_pair` cover nearly everything. Needs a port or a shared package. |
| **Member UI** | ❌ 25% | One real tab of three. No range control, no filters, no interactivity, one chart type, no headline. |
| **Coach↔member loop** | ❌ 20% | Check-ins have a response path. Transformation — the emotional core — has none. |

### Ranked gaps

#### 🔴 P0 — blocks a credible flagship

| ID | Gap | Where | Complexity |
|---|---|---|---|
| P0-1 | **Analytics library not available to the member app.** Port `progress_series.dart` (or extract to a shared package) with a parity test on the boundary — D2 proves twinning-by-copy already fails here. | AlphaSerena + shared | **M** (459 l pure Dart, no Firebase, fully tested) |
| P0-2 | **Strength tab is a placeholder.** `strengthSeries`, `personalBests`, `topWeightedExercise`, `totalVolume`, `distinctExercises` all exist and run on `client_workout_sessions`, which the member already writes and reads. | AlphaSerena UI | **M** (unblocked by P0-1) |
| P0-3 | **No time-range selector.** Every named competitor treats this as table stakes. Also forces the R8 window decision. | AlphaSerena UI + read path | **M** (needs a windowed query + index, R4) |
| P0-4 | **No headline verdict.** `coachingVerdict` + `progressScore` + `overallDirection` exist coach-side. | AlphaSerena UI | **S** (unblocked by P0-1) |
| P0-5 | **Progress is an island / six competing homes.** An information-architecture decision, not code: does Progress absorb Consistency + the three histories, or become their hub? | Product decision first | **L** (touches 6 screens) |
| P0-6 | **Weight series drops check-in weights (D8).** A live defect with a written fix in the other repo. | AlphaSerena | **S** |

#### 🟠 P1 — required for the experience to feel finished

| ID | Gap | Complexity |
|---|---|---|
| P1-1 | **Transformation coach review.** New `coachReview` field + rules clause + notification + both UIs. The single highest-leverage differentiator in the product. | **L** (backend + rules + 2 apps) |
| P1-2 | **Nutrition & lifestyle trends on Progress.** `consumedMacroSeries`, `caloriesSeries`, `lifestyleNumericSeries` exist; `coaching_rollups` and `nutrition_rollups` already hold the monthly read models. | **M** |
| P1-3 | **Check-in rating trends.** `checkInRatingSeries` exists; the member already reads their own submissions. | **S** |
| P1-4 | **Interactive charts** (touch, tooltip, pan). | **M** |
| P1-5 | **Per-source loading + partial-error state.** Mandatory once Progress has >1 source — mirror `ProgressController._mark`. | **S** |
| P1-6 | **Bounded reads + windowed queries + index.** Closes R3 + R4. | **M** |
| P1-7 | **Member-facing progress notifications.** Extend `evaluateNotifications` routing; resolve the audience-blind `registerFcmToken`. | **M** (backend) |
| P1-8 | **Measurement trend lines** — `measurementSeries` exists; 12 keys already captured and rules-validated. | **S** |

#### 🟡 P2 — quality, correctness, cost

| ID | Gap | Complexity |
|---|---|---|
| P2-1 | Resolve D2 (`transformation_comparison` divergence) and D7 (three streak definitions) | **S** |
| P2-2 | Render `bodyFatPercent`; honour `BodyUnits` for measurements | **S** |
| P2-3 | Accessibility: real `TabBar`/semantics, ≥11 px type, non-colour-only direction encoding | **M** |
| P2-4 | Premium motion: chart draw-in, counter roll, `FadeSlideIn` stagger, wire the orphan `heroTag` | **M** |
| P2-5 | Decide `nutrition_rollups` — consume it or delete it. A write-only collection is a permanent cost with a permanent maintenance tax | **S** decision / **M** to consume |
| P2-6 | Decide `clients.adherence` — consume it or stop the cron | **S** |
| P2-7 | Photo retention + thumbnail derivatives (R5) | **M** (backend) |
| P2-8 | Per-tab skeletons | **S** |
| P2-9 | Lazy-build the Progress tab / dispose its stream (R3) | **S** |

#### 🟢 P3 — deferred, needs a product decision first

| ID | Gap | Complexity |
|---|---|---|
| P3-1 | **Weekly / monthly report artifact.** Net-new. Needs a persistence decision (materialised doc vs. live derivation) and a delivery decision (in-app / push / email / PDF). | **XL** |
| P3-2 | **Goal weight & target body composition** — unlocks progress-toward-goal, direction semantics (good/bad), and the ETA class of features. No field, no writer, no editor exists. | **L** |
| P3-3 | **Prediction / forecast / trajectory.** Nothing exists. Needs P3-2 first. | **XL** |
| P3-4 | Workout + nutrition tracks in `coaching_rollups` — the vocabulary reserves them | **L** (backend) |
| P3-5 | Export / share a progress card | **M** |
| P3-6 | Reconcile the two progress universes (D11: online vs `offline_progress`) | **L** |

### Complexity legend
**S** ≤ 1 day · **M** 2–4 days · **L** 1–2 weeks · **XL** > 2 weeks

---

## 20. RECOMMENDATIONS

*Discovery findings only. No design, no implementation — these are the decisions the next phase must make before a line is written.*

### The five decisions that gate everything

**1. Where does the analytics library live?**
Three options, and the answer determines every subsequent estimate:
- (a) copy `progress_series.dart` into AlphaSerena and twin it — **the mechanism that has already failed once (D2)**;
- (b) extract a shared Dart package consumed by both apps;
- (c) move the derivations server-side into a callable.

The repository's own history argues loudly against (a): `prescription.dart` survived twinning only because someone remembered to sync it, and `transformation_comparison.dart` did not.

**2. What is the observation window?**
`kLogWindowDays = 60` is currently a load-bearing honesty guarantee: `consistency_pair.dart:94-107` refuses to offer a milestone the engine cannot verify. A flagship Progress that shows year-long trends must either extend the window (cost, index, pagination) or keep the guarantee and be explicit about the horizon. **It cannot quietly do both.**

**3. Does Progress absorb the other five screens, or become their hub?**
`ConsistencyDetailScreen`, `WorkoutHistoryScreen`, `NutritionHistoryScreen`, `LifestyleHistoryScreen` and `CheckInScreen` are individually excellent and collectively incoherent. Each is reached from a different place; none is reached from Progress. This is the single largest UX decision and it is an information-architecture question, not a visual one.

**4. Is the coach part of Progress?**
The product's only genuine differentiator against Whoop/Garmin/Strong is that a human can respond. Today the transformation loop is one-way by rule (`allow update` = owner-only). Deciding to close it is a backend + rules + two-app change; deciding not to is a decision to ship a fitness tracker.

**5. Report vs. dashboard.**
The mission asked for weekly reports. **No report exists anywhere.** A live dashboard and a materialised weekly report are different products with different persistence, different cost and different delivery. Pick one before scoping.

### Do these in discovery's shadow, before design

- **Resolve D2 now.** The `transformation_comparison.dart` divergence is a live inconsistency in the feature the audit was asked to certify as production-ready. It costs an hour.
- **Fix D8 now.** A member whose weight lives only in check-in packets is told they have no trend while their coach can see one. `reconciledWeightSeries` is the written fix.
- **Decide `nutrition_rollups` and `clients.adherence` now.** Two computed artifacts, zero readers, permanent cost. Either the new Progress consumes them — and both are genuinely useful — or they should stop being written. Leaving them is the worst of the three options.
- **Verify `evaluateAdherence`'s deploy state** against the live project. The repo cannot answer it, and the answer determines whether a daily full-roster scan is currently running for nothing.

### What must NOT be repeated

This codebase has a documented, recurring failure mode, and Progress is where it will strike next:

- **Two self-consistent sides of a boundary is not a contract.** The `coaching_rollups` dotted-key defect passed unit tests, `tsc` and review on both sides because each side agreed about a shape that never existed in the database. Any new Progress read model needs a wire test against a real Firestore.
- **A fixture asserting the wrong contract hides a permanent outage.** `RollupDay.fromCell` read `metrics['sleepHours']`, a key nothing has ever written; the member's sleep history was permanently empty and the test passed because it fed a hand-made cell.
- **Never put `/` in a `patrolTest` name.** Patrol's Android JUnit runner reads it as a group separator and silently drops the whole file's enumeration.
- **Never build an `AnimationController`/`TabController` in a `late final` field.** `dispose()` can be its first access.
- **Never resolve a Firebase singleton in a field initializer.** It has made four services untestable in this repo already.
- **A certified screen with no route is not shipped.** TrainerHQ's Team roster was built, tested and Patrol-certified while `main_shell_screen` still rendered the old screen.

### The honest bottom line

**The Progress module is not a greenfield build. It is a consolidation.**

The data exists. The rules permit it. The math is written and tested. What does not exist is: a place for it in the member's app, a range control, a headline, a report, and a way for the coach to answer.

Estimated shape of the work, from this audit alone:
- **~55%** — wiring existing member-app capability into one coherent surface
- **~20%** — porting/sharing existing coach-app analytics
- **~15%** — genuinely new UI (ranges, interactivity, motion, hierarchy)
- **~10%** — genuinely new backend (report artifact, coach review loop, member notifications)

**Nothing in this report was implemented, redesigned or fixed.**

---

*Compiled 2026-08-04 from repository evidence across `alphaserena`, `trainersHQ` and `trainershq-backend`. Every claim carries a file/line citation. Deployment state and live data were not accessible and are marked UNVERIFIABLE FROM REPO wherever they bear on a conclusion.*
