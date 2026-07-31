# AlphaSerena — Workout Domain Final Certification

**Date:** 2026-07-29
**Scope:** the complete workout lifecycle — assignment → prescription → card → briefing → session → rest → summary → consistency
**Result:** `flutter analyze` clean · **663 tests passing** · **Patrol 18/18 workout + 16/16 consistency on device** · debug + release APKs build
**Defects found and fixed this certification: 4** (1 privacy, 1 truthfulness, 1 UX-breaking, 1 hygiene)

> Certification stance: nothing was trusted until read from the repository,
> and nothing is claimed that was not executed. Where the environment made a
> path unexecutable (see §6), that limit is stated instead of papered over.

---

## 1. Repository Reconstruction

Every layer read from source this session:

```
TrainerHQ  exercise library (thumbnail/video/equipment/difficulty/instructions)
        →  workoutPlans {name, description, items[], setRows dual-write}
        →  clients doc assignment + prescriptions (versions/excuses/pause)
        →  getMyTraining CF (functions/lib/members.js): resolves plan,
           per-item media join, TODAY's expectation (server-side, local-day
           clamped), prescriptionData for the client-side certified engine
AlphaSerena
        →  TrainingController (Rxn workout/diet/coach/expectations/
           prescriptionData; ensureFreshDay rollover guard)
        →  Home workout card  (pure buildHomeWorkoutCard over SessionStats,
           12 modes, single completion authority)
        →  WorkoutBriefingScreen (facts, coach note verbatim, plan
           description, week verdict, draft-aware Resume CTA)
        →  WorkoutSessionScreen (guided one-set focus)
             bootstrap: draft → same-day remote doc → fresh
             identity:  ws_{clientId}_{yyyy-MM-dd} (+_run for deliberate
                        extras, free-slot probed so run-2 is never clobbered)
             creation:  LAZY — no doc until a completed/skipped set
             autosave:  500ms-debounced SharedPreferences draft
             remote:    full-entries upsert, 4s ack timeout →
                        synced / queued (offline persistence) / failed
        →  RestOverlay (wall-clock deadline — never tick-counted; pause,
           +30s, skip; haptics at T-3s)
        →  WorkoutSummaryScreen (SessionStats.isComplete is THE authority;
           member note = dedicated 2-field write so entries are untouchable)
        →  StreakController.markWorkoutToday(stats, nextUp) — Home's fraction
           and resume point ride the same save, zero extra reads
        →  Coach dashboard reads the same doc with the byte-identical engine
```

Storage: `client_workout_sessions` (rules-owned, functions-free writes),
SharedPreferences single draft slot, Firestore offline queue as the
offline-completion mechanism. Auth interaction: sign-out teardown deletes all
member controllers (and, after this certification, the draft — see D1).

## 2. Business Flow Verification (Phase 1)

Each transition's truthfulness anchor:

| Transition | Truth preserved by |
|---|---|
| Library → plan → member | Media/metadata joined per-item server-side; absent data renders absent (never placeholders) |
| Assignment → today | Expectation resolved SERVER-side against the member's clamped local day; `unknown` is disclosed, never dressed as a schedule |
| Today → Home card | One presentation function; progress only from `SessionStats`; "Logged today" abolished |
| Card → briefing | Same served items; duration is the one estimate and always wears "≈" |
| Briefing → session | `exercisesFromServedItems` shared by both — they cannot disagree |
| Session → doc | Full-entries serialization, last-write-wins; skipped ≠ incomplete ≠ pending on the wire; corrections marked `edited` |
| Doc → summary | `computeSessionStats` over the same logs; partial finish states its real % |
| Doc → consistency | Presence via day-keys; completion via the same stats object |
| Doc → coach | Byte-identical engine on both apps (parity-tested) |

## 3. Workout State Matrix (Phase 2)

Owner and verification for every reachable state; states the repository
cannot represent are listed as such rather than invented.

| State | Owner | Verified by |
|---|---|---|
| No coach / not linked | Home gating (`_unlinkedCard`) | existing suite |
| No assigned plan | card `waiting` / session `_noWorkout` | Patrol `empty state` + unit |
| Plan begins tomorrow / future | expectation `notYetStarted` → card `dormant` | unit (card + expectation) |
| Plan ended / expired | `ended` → `dormant` | unit |
| Workout available (required day) | card `ready` | Patrol + golden |
| Rest day / coach excused / paused | card `rest`/`excused`/`paused`, never a demand | Patrol `rest/paused/closed` + unit |
| Flexible week | `flexible`, session-counted copy | unit |
| Loading | skeletons (card, briefing, session boot) | widget tests |
| Offline with cached plan | stale-sync banner + plan stays | unit |
| Offline, nothing cached | `unavailable` + Retry ("plan is safe") | unit (mode unreachable from Home today — debt T2) |
| Session started | lazy — exists only from first resolved set | unit (integrity suite) |
| Partially complete | card `inProgress` + exact next set | Patrol ladder 22/50/75/99 + unit |
| Resumed same day | draft → bootstrap | **Patrol `save & leave → resume`** |
| Restored after kill | same draft path (process-death equivalent) | Patrol (same code path) + store round-trip tests |
| Interrupted (back) | guarded dialog, save & leave | Patrol |
| Abandoned | derived server-side (in-progress after day end) | design (no client fabrication) |
| Restarted / multiple sessions | finished-choice dialog + free-run-slot probe | unit (run-2 overwrite regression) |
| Completed | `isComplete` = every set done | Patrol summary + unit |
| Completed by skipping | `closed` — over, never "Start" again, never 100% | Patrol + unit |
| Sync pending | `queued` banner ("saved on this device") | Patrol-adjacent unit; service contract tests |
| Sync failed | red banner + Retry; **Finish refuses to celebrate** | **Patrol `failed save`** |
| Duplicate submission | deterministic doc id — a re-save is an upsert, not a duplicate | design + id tests |
| Duplicate taps | 400ms complete-set cooldown (**fix D2**); `_finishing` guard | **Patrol double-tap** |
| Exercise/video/thumbnail unavailable | player `none` vs `failed` split; briefing rows degrade text-first | Patrol media + widget |
| Media timeout | ack-bounded fetches; player Retry rebuilds controller | widget |
| Coach note missing | section absent — never generated | Patrol briefing + unit |
| Bodyweight / no equipment | reps-only target, no "× 0 kg", volume absent not zero | **Patrol bodyweight** |
| Timed exercise ("60s") | prescription text passes verbatim, never parsed | unit (NextUp verbatim) |
| Single exercise / single set | isLast → Finish | Patrol |
| 100-exercise workout | only current exercise built; instant nav | **Patrol stress** |
| Long names / long coach note | ellipsis + verbatim scroll | Patrol |
| Rotation / small landscape | rest ring yields on shortestSide | Patrol landscape |
| Backgrounded / locked mid-rest | wall-clock deadline, resume repaints the true remaining time | code-verified design + overlay tests |
| Battery saver / slow device | no tick-counted timers anywhere in the flow | design |
| RPE | **not in the data model** — nothing fabricated | matrix note |
| Supersets / circuits | not modeled; sequential exercises only (future) | matrix note |
| Calories | **deliberately absent** — the repo holds no calorie truth to state | matrix note |

## 4. Defects Found & Fixed (Phases 3–8)

**D1 — Cross-member workout draft leak (privacy, high).**
`_teardownToLogin()` releases the call lock, push token and Google session
precisely so the next member on the device inherits nothing — but the
SharedPreferences workout draft survived sign-out. A second member signing in
the same day resumed the previous member's half-finished session: their
exercises, weights and reps shown to another person. *Fix:* draft cleared in
the teardown, best-effort like its siblings.

**D2 — Double-tap completed two sets (truthfulness, medium).**
With no prescribed rest there is no overlay barrier after "Complete Set", so
a fast double-tap landed on the next set's freshly-prefilled button and
logged work that never happened. *Fix:* 400ms wall-clock cooldown in
`_completeSet`. *Regression-locked by Patrol:* double-tap now completes
exactly one set.

**D3 — Undo skip-exercise didn't reopen anything (UX-breaking, medium).**
Found BY the Patrol suite. `_unskipExercise` only reopened sets whose
`actualReps/actualWeight` were empty — but prefill writes the coach's targets
into the inputs, the field listeners debounce a draft save, and `_saveDraft`
syncs every field into its log. So any set that had merely been *looked at*
failed the guard: Undo un-flagged the exercise while every set stayed
skipped. *Fix:* a bulk skip gets a bulk undo — every skipped set reopens
(completed sets keep their numbers). *Regression-locked by Patrol.*

**D4 — TextEditingController leak on re-restore (hygiene, low).**
`_restoreFrom` replaced `_exercises` without disposing the outgoing set
states ("Start another" path). *Fix:* dispose before replace.

Verified-sound in the same hunt (no action): rest-timer wall-clock behaviour,
back-guard/save-and-leave, failure/queued banners with Retry, lazy session
creation, run-slot probing, summary never a dead end, `_servedItemFor`
id-first matching surviving coach mid-session plan edits, spam-guarded
Finish, keyboard-safe inputs (`numberWithOptions(decimal)`).

## 5. Patrol Certification (Phase 7) — emulator-5554, Android 16

Deterministic fixtures, no manual setup: real screens over a real
`TrainingController` with the served-shape plan injected (the same `Rxn`
fields `getMyTraining` writes). Draft slot cleared per journey.

**Final run: 18/18 passed** (plus consistency regression suite 16/16 —
34/34 total on device).

Journeys: guided completion (prefill → sets → done card → advance) · rest
timer (open/pause/+30s/skip) · **double-tap = one set** · skip set · reopen →
`edited` marker · skip exercise + reason + undo · back guard → save & leave →
**draft resume restores exact position** · failed save honesty (banner,
Retry, Finish refuses to lose work) · empty plan · 100-exercise stress + long
names · single-set bodyweight · briefing facts + long coach note + draft-
aware Resume CTA · summary complete/partial (real %, em-dash duration, absent
volume) · Home-card ladder 22→50→75→99→100 · rest/paused/closed cards ·
media none-vs-broken · 1.6× accessibility · landscape rest overlay.

Iterations to green: 13/18 → 16/18 → 17/18 → **18/18**. Three failures were
test-side (wrong target string; `kg`-suffix false positive; const-widget
State reuse killing a re-mounted `initState`; a simulated-vs-wall-clock pump
race; a 1-of-1 count slip). One was the real app defect **D3**.

## 6. Honest Execution Limits

- Phone-OTP auth is externally blocked on this Firebase project (Play
  Integrity disabled), so no journey can sign in: **a successful Firestore
  save cannot execute on this emulator.** The failure/queued paths run for
  real; the success path (and finish→summary handoff) is certified by the
  663-test suite and a direct summary mount. This is stated rather than
  simulated.
- Kill-and-restore is certified at the draft layer (identical code path to
  process death); a literal `adb kill` mid-journey would tear down Patrol's
  own channel.
- Formal performance/memory *profiling* was not run (no authenticated app
  session to profile); the performance review below is code-level plus
  on-device stress behaviour.

## 7. UX Review (Phase 9)

Judged against Apple Fitness / Strong / NTC standards:

- **The session answers "what now?" in one glance** — current set, coach's
  target huge, two prefilled inputs, one button. Position always visible
  (exercise N of M, set N of M, top progress bar).
- **Prefill over data entry** — the coach said "10 × 40"; the member confirms
  or edits, never retypes.
- **"Last time" memory** appears only from real history — the sentence
  strength athletes actually want.
- **Rest is coached** — next-set context, a reminder line, member-controlled
  (+30s/pause/skip), pocket-usable via haptics; Wrap'd actions survive 1.6×
  on small phones; ring yields to `shortestSide`.
- **Skips are honest options, not accusations** — reasons the coach reads;
  summary shows skips only when they happened.
- **One-handed / gym usability** — 44pt-class targets throughout; the one
  primary action per screen sits in thumb reach; numeric keyboards.
- Copy check: no blame anywhere in the flow; the partial-finish headline
  states its real fraction instead of an unearned congratulation.

## 8. Accessibility Review

Semantics on every actionable (sets announce state + "tap to correct";
skip/how-to labelled; summary tiles readable); 1.6×/320px exercised on device
for session, briefing, cards, overlay; state never colour-alone (icons +
fills + labels); no colour-only progress. Golden + widget suites lock the
layouts.

## 9. Performance Review

- Session body builds ONLY the current exercise — 100-exercise plans confirmed
  instant on device.
- No per-frame `setState` timers: rest overlay derives from a deadline at
  200ms repaint cadence; video player subscribes the overlay only.
- Draft writes debounced (500ms); remote saves ack-bounded (4s) and never
  block the rest overlay (root-caused earlier; preserved).
- Memory: controllers disposed (D4 closed the last known leak); media decode
  capped (`memCacheWidth`).

## 10. Security & Privacy Review

- Ownership enforced by Firestore rules on `client_workout_sessions`
  (clientId/adminId/authorId stamped per write; functions-free path).
- D1 closed the cross-member device-local leak; push token/call lock/Google
  session already handled by teardown.
- Member note is a 2-field merge write — it can never erase logged entries.
- No PII in logs; media URLs are served, never member-supplied.
- Note: this certification's file writes ran with Semgrep Guardian logged
  out (explicitly authorized); the uncommitted diff remains scannable.

## 11. Screenshots

Captured from the production widgets on emulator-5554 via
`tool/workout_preview.dart` → `docs/certification/` (`workout_session.png`,
`workout_briefing.png`, `workout_rest.png`, `workout_summary.png`,
`workout_home_card.png`). Before/after for D3: prior behaviour had no visual
(Undo produced no change — that absence *was* the bug); after, Undo visibly
returns the focus card.

## 12. Remaining Technical Debt

1. **Deploy `getMyTraining`** — the media/metadata patch (thumbnails,
   equipment, difficulty, duration, plan description) is still undeployed;
   briefing chips and player posters render without it (long-standing release
   blocker, restated).
2. Card `unavailable` mode unreachable from Home (outer error branch wins).
3. Draft pollution root: prefill → listener → draft sync writes coach targets
   into pending sets' actuals. D3 removed its sharpest tooth; a cleaner model
   would keep workbench text out of `actual*` until completion.
4. `Edit Workout Log` routes via briefing (one extra tap).
5. Supersets/circuits and RPE unmodeled (future roadmap).

## 13. Self-Critique (Phase 10)

- Would Strong ship the session flow? The guided focus, prefill, memory line
  and honest skip model — yes. The gap to close is media presence on the
  floor, which is a deploy away, not a build away.
- Three of my first-run Patrol failures were my own assertions. The suite is
  only as truthful as its expected strings; each was fixed by reading the
  widget, not loosening the assert.
- The success-path save remains untestable here; I certify it on the unit
  suite plus contract, not on-device — stated, not hidden.
- The double-tap cooldown is a heuristic (400ms). A structural fix (disable
  the button until state transition completes) would be stronger.

## 14. Final Verification

```
flutter analyze                 No issues found!
flutter test                    +663: All tests passed!  (widget + golden included)
Patrol — workout                18/18   (emulator-5554)
Patrol — consistency (regress)  16/16
flutter build apk --debug       ✓ app-debug.apk
flutter build apk --release     ✓ app-release.apk (debug-signed fallback)
```

Nothing committed. Nothing deployed.
