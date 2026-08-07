# MY PLANS REDESIGN — BACKING-DATA INVENTORY (PRE-BUILD)

**Rule applied:** *"If a required field is missing, report it, don't invent it."*
Derived from source, not assumed: `trainershq-backend/functions/src/members.ts` (`buildWorkout`,
`buildDiet`, `getMyTraining`), `alphaserena/lib/controllers/training_controller.dart`,
`member_controller.dart`, `food_log_controller.dart`, `core/domain/workout_session.dart`.

---

## A. WHAT `getMyTraining` ACTUALLY SERVES

```
workout : { name, items[], description?, restDay?, weekly{name,days[]}?, nextDay{day,planName}? }
  item  : { name, exerciseId, sets, reps, weight, setRows[{reps,weight,rest}],
            videoUrl, instructions, muscleGroup, equipment, difficulty,
            thumbnailUrl, videoDurationSeconds }

diet    : { name, items[], description?,
            targetCalories, targetProtein, targetCarbs, targetFat, targetFiber,
            targets{ calories, protein, carbs, fat, fiber, waterMl?, note?, version?, source } }
  item  : { name, meal, quantity, grams, portionLabel, foodId, entryId,
            calories, protein, carbs, fat, fiber, sugar, saturatedFat }

nutritionTargets : same shape as diet.targets — served INDEPENDENTLY of any plan
coach            : { id, name, photoUrl, assigned }
expectations     : TodayExpectations → workout / diet ServedExpectation
prescriptionData : { workout, diet } → slices { id, status, createdAtMillis,
                                                updatedAtMillis, prescription, excusedDays }
```

Plus, from other live controllers (no new backend):
`MemberController` → gymName, trainerName, member goal, name, membership status/expiry ·
`FoodLogController` → live nutrition day, entries, per-meal grouping, totals, macros ·
`client_workout_sessions` → `SetLog{pReps,pWeight,pRest,actualReps,actualWeight,completed}`,
`ExerciseLog`, `SessionStats{completedSets,skippedSets,totalSets,skippedExercises}`,
duration from `startedAtMillis`/`finishedAtMillis`.

---

## B. WORKOUT TAB — requested vs available

### Active Workout Plan hero card

| Requested | Backed? | Source / note |
|---|---|---|
| Workout name | ✅ | `workout.name` |
| Trainer | ✅ | `coach.name` (live) → `MemberController.trainerName` fallback |
| Organization | ✅ | `MemberController.gymName` |
| Status | ✅ | `prescriptionData.workout` slice `status` (active/paused/ended) |
| Today's workout status | ✅ | `expectations.workout` (+ `restDay`, `nextDay`) |
| Updated date | ✅ | slice `updatedAtMillis` |
| Assigned date | ✅ | slice `createdAtMillis` |
| Progress | ✅ | derivable from session `SessionStats` |
| Realtime status | ✅ | `TrainingController` reload + live listeners |
| Goal | ⚠️ **member's goal, not the plan's** | `MemberController.goal`. The plan has no goal field. Labelling it "Plan goal" would be a fabrication. |
| **Difficulty** | ❌ **NOT SERVED at plan level** | exists **per exercise** only (`item.difficulty`). A plan-level difficulty would have to be invented or aggregated. |
| **Duration** | ❌ **NOT SERVED** | no plan duration anywhere in `buildWorkout`. The current screen hardcodes `'Ongoing'`. |
| **Frequency** | ❌ **NOT SERVED** | only inferable when a `weekly` schedule exists (count of mapped days); **null for every single-plan member**. |
| **Start date** | ❌ **NOT SERVED** | `createdAtMillis` is when the assignment was *created*, which is not a coach-authored start date. |
| **Workout image** | ❌ **NOT SERVED** | no plan image. Only `item.thumbnailUrl` per exercise. The current screen uses a **hardcoded bundled asset** for every member. |
| **Plan badge** | ❌ | no badge/tag field exists. |

### Today's Exercises timeline

| Requested | Backed? |
|---|---|
| Exercise name, muscle group, equipment, sets, target reps, rest | ✅ `item.*` + `setRows[].rest` |
| Exercise image | ✅ `item.thumbnailUrl` (**empty when the coach never set one** — needs a real fallback, not a placeholder pretending to be a photo) |
| Completed reps, weight used, completed sets | ✅ `SetLog.actualReps/actualWeight/completed` |
| Duration | ✅ derived from `startedAtMillis`/`finishedAtMillis` |
| Completion badge, time finished | ✅ |
| **Personal notes** | ❌ **NO per-exercise member note field exists** in the session wire. |

### Previous Workout / Weekly Consistency

| Requested | Backed? |
|---|---|
| Last completed workout, duration, completion % | ✅ |
| **Volume** | ⚠️ derivable (Σ reps×weight) but **only where weight is numeric** — `weight` is a free-text String (`"8-12"`, `"bodyweight"`). Honest for some members, null for others. |
| **Calories burned** | ❌ **NOT SERVED and NOT DERIVABLE.** No MET, bodyweight-at-time, or duration-per-exercise data. Any number here would be fabricated. |
| **Personal records** | ⚠️ `core/domain/workout_memory.dart` exists — needs verification that it computes PRs rather than last-used weights. **Unverified.** |
| Weekly consistency | ✅ existing consistency engine + `StreakController` |

---

## C. DIET TAB — requested vs available

| Requested | Backed? |
|---|---|
| Plan name, coach, organization | ✅ |
| Calories / Protein / Carbs / Fat / Fiber targets | ✅ `resolveNutritionTarget` — **with provenance** |
| Status, updated/assigned date | ✅ diet slice |
| Today's Nutrition card | ✅ **reuse `NutritionProgressCard` + `DailyMetric`** — same widget Home uses, single source of truth |
| Today's Meals timeline (per meal: calories, macros, time, food count, expand) | ✅ `FoodLogController.entriesByMeal` |
| Meal details: food, quantity, serving, calories, macros, coach/global/custom, edit, delete | ✅ all live in `FoodEntry` + the existing edit sheet and swipe-delete |
| **Plan goal** | ⚠️ member's goal only — same caveat as workout |
| **Duration / start date** | ❌ **NOT SERVED** (same as workout) |
| **Coach Notes** | ⚠️ **plan-level `description` ONLY** |
| **Meal Notes** | ❌ **NO per-meal note field exists.** `diet_screen.dart` already documents this: *"It is PLAN-level — the data model has no per-meal note, and inventing one would attribute words to a coach who never wrote them."* |
| **Instructions / Warnings / Tips** | ❌ **NO such fields.** Only one free-text `description`. |
| **Hydration reminder** | ⚠️ `targets.waterMl` exists — but it is a **Lifestyle** target, and Lifestyle is **out of scope** for this mission. |
| **Supplement reminder** | ❌ `supplementPlan` is **Lifestyle** — out of scope. |

---

## D. PLAN HISTORY TIMELINE

| Requested | Backed? |
|---|---|
| Assigned / Updated | ✅ `createdAtMillis` / `updatedAtMillis` per slice |
| Paused / Removed (ended) | ✅ slice `status` |
| **Completed** | ❌ **no `completed` status exists** — the enum is `active | paused | ended` |
| **Archived** | ❌ **no `archived` status exists** |

⚠️ `prescriptionData` carries slices for **every** assignment including paused/ended, so a real
history timeline is buildable — but only over the three statuses that exist.

---

## E. SUMMARY OF UNBACKED REQUESTS

**Cannot be built without inventing data (13):** plan-level difficulty · plan duration · frequency
(except weekly-schedule members) · coach-authored start date · workout plan image · plan badge ·
per-exercise personal notes · calories burned · per-meal notes · coach instructions · warnings · tips ·
plan-history "completed" and "archived" states.

**Backed but needs an honest caveat (5):** goal (member's, not the plan's) · volume (only where weight
is numeric) · personal records (implementation unverified) · hydration/supplements (Lifestyle — out of
scope) · exercise image (frequently empty).

### Two fabrications already live in the current screen, which this redesign must NOT carry forward

1. **`Duration: 'Ongoing'`** — hardcoded string, not a backend value.
2. **A bundled workout image asset** rendered as though it were the member's plan image.

(A third, `Daily Calories` showing the plan-item sum with a hardcoded 2000 fallback, was fixed
earlier in this session and is already verified gone on the device.)
