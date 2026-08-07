# CTO PRODUCTION UX COMPLETION REPORT
## Loading, Empty States & Perceived Performance — Home · My Plans · Nutrition · Workout

**Date:** 2026-08-04 · **Device:** emulator-5554 (Pixel 9 Pro, Android 17), live member session
**Scope:** client app only. **Zero backend changes, zero deploys, no new features.**

---

## THE HEADLINE

One flag was doing two jobs, and it cost the member their entire Home screen on every
background refresh.

`TrainingController.isLoading` is the re-entrancy guard that stops two `getMyTraining`
calls running at once. It was **also** the gate on Home's full-page skeleton. That
controller re-loads on app resume, on entering the My Plans tab, on a coach's
client-doc change, at midnight rollover, and on every pull-to-refresh — so each of
those threw away the coach header, both streak cards, today's session and the
nutrition card (all already in memory) and replaced them with grey rectangles for the
length of a network round trip.

**Reproduced on device before the fix**, by tapping My Plans and returning to Home:

| Before — `shots/stale_home_1.png` | After — `shots/V2_home_2.png` |
|---|---|
| Every card gone. Static grey boxes. 2 of 8 captured frames blank. | Every card intact. One line: *"Checking for coach updates"* with a spinner. 8/8 frames retain content. |

---

## PART 1 — LOADING EXPERIENCE

### Root cause fix — `training_controller.dart`

`isLoading` keeps its exact old meaning (in-flight, spans the whole load) so both
guards that depend on it — `refreshIfStale`'s early return and
`HomeController._maybeReloadTraining`'s queue — still work. Two derived states were
added beside it:

```
hasLoadedOnce   a load has COMPLETED, success or failure
isFirstLoad     isLoading && !hasLoadedOnce   → skeleton allowed
isRefreshing    isLoading &&  hasLoadedOnce   → skeleton forbidden, content stays
```

Failure counts as "loaded" deliberately: by then the member has been shown something
real (an error with a Retry), and a second attempt should keep that on screen rather
than flashing back through a skeleton.

`StreakController` gained a matching `isRefreshing` — its `isLoading` was already
first-load-only (correctly), which left a reload with **no observable signal at all**.

### Applied

| Screen | Before | After |
|---|---|---|
| **Home** | Full-page skeleton on every refresh | Skeleton on cold start only; `SyncWhisper` under the header otherwise |
| **Home — today's workout card** | Reverted to a loading shell on every refresh | Keeps plan name, exercise count, resume set |
| **My Plans** | Cold-load test was *"do we hold a plan?"* | Now *"have we loaded?"* — see below |
| **Diet — coach recommended** | Claimed *"No diet plan yet"* during first load | Shimmer skeleton until the answer exists |

**A second, separate defect found in My Plans.** Its stale-while-revalidate used
`loading && !hasContent`, where `hasContent` meant *a workout or diet plan is held*.
For a member whose coach has assigned **nothing yet** — common in the first days after
joining — that is false forever, so every refresh re-ran the cold skeleton and the
screen never once settled on the "no plan yet" message that is the actual answer to
their question. Now gated on `isFirstLoad`.

---

## PART 2 — SEARCH EXPERIENCE

The controller was already correct (280 ms debounce, monotonic request ids that drop
superseded responses, previous rows kept on screen). Two presentation gaps closed:

- **The spinner moved into the search bar.** It replaces the magnifier in place —
  same 20 px box, same position — so the field never changes width. Verified on
  device: `shots/J3_search_busy.png`.
- **The redundant 2 px bar under the field is gone.** Two indicators for one fact,
  and the one inside the field is where the member is already looking. The
  screen-reader live region ("Searching foods") was kept as a zero-size node — a
  spinner cannot announce itself.
- **Results crossfade**, keyed on `resultsQuery` (the query the rows *answer*), not
  on the text field — keying on `query` would restart the animation on every
  keystroke while the same rows sat underneath.

---

## PART 3 — PREMIUM EMPTY STATES

New shared `SerenaEmptyState` (glyph · headline · explanation · optional action).
An action is included **only where the member can actually act** — an empty state
with a button for something only the coach can do is worse than none.

| Surface | New copy |
|---|---|
| Today's food log | 🍽️ **Today's nutrition hasn't started** — "Log your first meal and we'll track calories, protein, carbs and fats through your day…" → **Log First Meal** |
| Diet plan (Diet screen + My Plans) | 🥗 **No diet assigned yet** — "…it will appear here automatically when they do. You can still log everything you eat below." *(no button, deliberately)* |
| Workout plan (My Plans) | 💪 **No workout plan assigned** — "…plans can also be paused between training blocks, so nothing is wrong." *(no button)* |
| Food history | 📈 **Nothing here yet** — "Every day you log builds your history — trends, averages and the days you hit your targets." |
| Search, idle | 🔍 **Search foods** — "Start typing to search your coach's foods and our global library." |
| Search, no match | 🥣 **Couldn't find that food** — "…Try a shorter or simpler word — 'chicken' finds more than 'grilled chicken breast'." |
| Search / plan / log failures | 📡 / 📴 with **Try again** |

---

## PART 4 — ERROR STATES

**A dead end, found live on device.** Home's nutrition card reported *"Couldn't load
today's food"* over four em-dashes and offered **nothing to do about it**. Firestore
does not retry a terminated listener, and the controller's own self-heal only fires
after a successful *write* — so the member's only exit was to log food blind or
restart the app. `FoodLogController.retry()` existed and had simply never been wired
to the surface that reports the failure. Now wired: `shots/V4_retry.png`.

New shared `StaleDataBanner` ("Couldn't refresh. Showing your last synced
information." + Retry) is available for the refresh-failed-over-good-data case; Home's
existing `_staleSyncBanner` already covered the plan path and was left in place.

---

## PART 5 — ANIMATION POLISH

- **`SerenaSkeleton`** — every skeleton in the four areas was a **static grey
  rectangle**, visually indistinguishable from a card that failed to render. All now
  carry a 1.4 s shimmer sweep (`-1 → 2` so the band is fully off-screen at both ends;
  sweeping `0 → 1` parks it at the edge and reads as a flicker).
- **`StateSwap`** — one crossfade (260 ms, 2 % rise) for skeleton → content → empty →
  error. Uses a **top-aligned** stack layout builder; the default centres both
  children and visibly shifts a tall skeleton against short content mid-transition.
- **My Plans** previously animated only the tab swap — the transition that matters
  most (skeleton giving way to the plan) was the one that popped. One `StateSwap` now
  spans cold-load, both blockers and both tabs.
- **All of it honours `MediaQuery.disableAnimations`.**

---

## PART 6 — SKELETON AUDIT

Every skeleton in scope now answers *"is this the FIRST load?"*:

| Skeleton | Verdict |
|---|---|
| Home full page | ✅ first-load only (was: every refresh) |
| Home nutrition card | ✅ first snapshot of the day only |
| My Plans | ✅ first-load only (was: every refresh for unassigned members) |
| Diet — coach recommended | ✅ **added** — was a wrong empty state |
| Food log section | ✅ first snapshot / genuine day rollover |
| Add Food results | ✅ only when nothing is underneath |
| Food history | ✅ first page only |

---

## PART 7 — PERFORMANCE

**One real defect found and fixed, by measurement.** My first `SyncWhisper` kept the
row mounted at opacity 0 so the fade could run both ways. A `CircularProgressIndicator`
drives a repeating ticker for as long as it **exists**, not as long as it is visible —
so an invisible one on Home, My Plans and Diet meant three permanently animating
widgets requesting frames on a completely idle screen. It also hung every
`pumpAndSettle` in the widget suite: the same fact, reported by a different observer.
Now built only while visible.

**Verified on device:** three consecutive screenshots of an idle, settled Home are
byte-identical (`md5` 3/3) — nothing is repainting. Before the fix the same capture
produced 8 distinct frames.

**Not done, stated plainly:** I did not run a profiling pass. Each of these screens is
still one large `Obx` over the whole page, so any observable tick rebuilds the entire
list. I found no evidence of jank from it on this device and judged the refactor to be
beyond a UX-polish mission; it remains the obvious next performance item.
`MyPlansScreen.build` also schedules a post-frame callback on every build (three
`ensureFreshDay` calls) — all cheap date-key comparisons with no network unless
genuinely stale, so observed-but-benign.

---

## PART 8 — REAL USER JOURNEY (all on emulator-5554)

| Step | Result |
|---|---|
| Cold start → Home | Skeleton → content, crossfaded |
| Tab switch triggering a staleness refresh | **Content retained** + "Checking for coach updates" ✅ (was: full blank) |
| Home → Diet | Coach plan + food log, correct states |
| Add Food → search "chick" | Spinner in the bar, results faded in, no flash |
| Log a food | Logged; totals updated; recents refreshed |
| Back to Diet | 165 kcal / 1 item rendered |
| **Slow network** (EDGE, 473 kbit/s, emulator console) | Used for the whole before/after reproduction |
| **Offline** (wifi + data off) | App-wide "No Internet" takeover (pre-existing, deliberate) |
| **Reconnect** | Recovers automatically |
| **Background → resume** | My Plans re-pulls with the plan **on screen** + sync whisper ✅ `shots/R_resume_2.png` |

---

## PART 9 — TRAINERHQ

**Verified from source, not on a live coach session.** The member app writes
`client_nutrition_days/{clientId}_{dateKey}`; TrainerHQ's `ClientLogsService` reads
`FsCollections.clientNutritionDays` at `.doc('${clientId}_$key').snapshots()` and
parses with `ClientNutritionDayModel.fromMap`. Identical id convention, identical
collection, live listener — the food logged on device during this pass lands in the
document TrainerHQ watches.

⏭️ **I did not sign into TrainerHQ as a coach.** That needs credentials I do not have
and should not handle. The contract is certified from both sides' source; the
end-to-end coach view is not.

---

## 🔴 FOUND, NOT FIXED — NEEDS YOUR DECISION

### 1. The deployed Firestore rules are stale, and it breaks the flagship empty state

Live on device: `PERMISSION_DENIED` on
`client_nutrition_days/EkNg2Yux4lPAQtSpQjds_2026-08-04`.

The cause is the classic missing-document case: a rule that reads `resource.data.X`
**errors** on a document that does not exist, so no clause can return true and the
read is denied. **Every member is in that state every morning**, before their first
food of the day.

**Proven, not assumed.** I logged one food (a *create*, whose rule does not
dereference `resource`) and the very same listener immediately succeeded —
`shots/J1_diet.png` (denied) → `shots/J7_diet_recovered.png` (165 kcal rendering).

`trainershq-backend/firestore.rules:1362` **already contains the fix**
(`resource == null && signedIn()`), with a comment describing this exact defect. It
has not been deployed.

**Impact:** until it is, the premium empty state this mission asked for — 🍽️ *"Today's
nutrition hasn't started → Log First Meal"* — is **unreachable in production**. Members
see *"Couldn't load today's food"* instead, every day, until they log something.
Coach-side impact is nil (an unlogged day correctly shows nothing either way).

```bash
cd /Users/bandigowtham/flutter_works/trainershq-backend && firebase deploy --only firestore:rules
```

I have not run this — it is an outward-facing change to production and yours to make.

### 2. `client_workout_screen.dart` is unreachable dead code

269 lines, with a full-screen `CircularProgressIndicator` on every load. Nothing
navigates to it — the bottom nav is Home / My Plans / Progress / Profile, and the
workout journey lives in `today_workout_section` and `workout_session_screen`. Not a
single reference exists in `lib/`, `test/`, `integration_test/` or `tool/`.

I did **not** polish it (it is not part of the running app) and did **not** delete it
(a structural change beyond this mission). There is precedent for deletion —
`client_diet_screen.dart` was removed for exactly this reason — so it is likely the
right call, but it is your call.

### 3. Offline is an app-wide takeover

While fully offline, a branded full-screen "No Internet" screen covers every route, so
the per-screen offline and stale states are reachable only on *partial* failures. This
is a deliberate, documented decision (Section 6.4) and app-wide rather than one of the
four screens, so I left it alone. Worth revisiting if you want Part 4's
"keep the data, explain the failure" behaviour to apply while offline too.

---

## VALIDATION

| Check | Result |
|---|---|
| `flutter analyze` | **0 issues** |
| `flutter test` | **1212 passing**, 14 failing |
| Failing tests | **All 14 are the documented pre-existing golden-image failures** (missing font faces on this machine): `home_cards_golden` 8, `home_header` 4, `log_transformation` 1, `serena_foundation` 1. Baseline before this work was the same 14. |
| New tests | `test/first_load_vs_refresh_test.dart` — 6 tests pinning the skeleton rule, including that `isLoading` still spans a whole refresh so the concurrency guards keep working |
| Patrol `workout` | **18/18** |
| Patrol `my_plans` | **33/34** — the 1 failure is the file's own sacrificial `warm-up` test, which exists to absorb a documented JUnit-runner artifact on the first test of a bundle. Reproduced twice, identically. |
| Patrol `add_food` | **20/20** |
| Patrol `diet_journey` | **17/17** |
| Patrol `home_lifestyle` | **15/15** |
| Patrol `recents_isolation` | **11/11** |
| **Patrol total** | **114 of 115** on emulator-5554 — the only failure is the sacrificial `my_plans` warm-up described above |

### Tests changed, and why

Nine assertions across `diet_screen_test`, `diet_journey_patrol_test`,
`add_food_patrol_test` and `recents_isolation_patrol_test` asserted the **old empty-state
copy** and were updated to the new strings — deliberate product changes, not weakened
assertions.

Two tests were changed from `pumpAndSettle` to a fixed `pump`
(`nutrition_progress_card_test`, `home_lifestyle_patrol_test`): a loading card **never
settles by design**, because its skeleton shimmers on a repeating controller — the same
contract as `CircularProgressIndicator`. The fixed pump is the stronger assertion, since
it only passes while the animation is genuinely running.

---

## FILES CHANGED

**New:** `lib/core/widgets/serena/premium_states.dart` (`SerenaSkeleton`, `SyncWhisper`,
`StaleDataBanner`, `SerenaEmptyState`, `StateSwap`) · `test/first_load_vs_refresh_test.dart`

**Controllers:** `training_controller.dart` · `home_controller.dart` · `streak_controller.dart`

**Screens:** `home/client_home_screen.dart` · `home/nutrition_progress_card.dart` ·
`plans/my_plans_screen.dart` · `nutrition/diet_screen.dart` ·
`nutrition/food_log_section.dart` · `nutrition/add_food_screen.dart` ·
`nutrition/food_history_screen.dart`

**Evidence:** `/private/tmp/claude-501/.../scratchpad/shots/` — `stale_home_1.png`
(before), `V2_home_2.png` (after), `V4_retry.png`, `J1_diet.png`, `J3_search_busy.png`,
`J4_search_results.png`, `J7_diet_recovered.png`, `O1_offline_home.png`,
`R_resume_2.png`.
