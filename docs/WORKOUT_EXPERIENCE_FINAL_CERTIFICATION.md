# Workout Experience — Final Certification

- **Date:** 2026-07-28 · **Repos:** trainersHQ · trainershq-backend · alphaserena
- **Mission:** the production certification of the complete workout ecosystem.
  Nothing authored by the trainer may disappear; nothing the member experiences
  may contradict TrainerHQ.
- **Status: certified, with the enumerated limits of §12. Nothing committed.
  Nothing deployed.**

**Verification performed:** backend `npm test` → **576 pass** (build
type-checks the serving change) · AlphaSerena `flutter analyze` clean,
**515 tests pass** · TrainerHQ analyze clean, **992 tests pass** (unchanged
this mission) · debug APK builds. No emulator/device run and no CF deploy —
§12 is explicit about what that means.

This certification stands on, and re-verified rather than re-argued, the
chain of prior certifications: session integrity → guided experience → weekly
prescription completion → session end-to-end. Everything below was re-traced
against current code; where a prior claim would have been wrong today it is
called out, and one was: three served fields and one authored field were
still disappearing (§2).

---

## 1. The complete field matrix (Phase 1 — from the models, not from memory)

Every field a trainer can author, traced TrainerHQ → Firestore → serving →
AlphaSerena → session. **A = authored · S = served · R = rendered.**

### Exercise library (`ExerciseModel`)
| Field | A | S | R (member) | Verdict |
|---|---|---|---|---|
| name | ✓ | ✓ | session, briefing, player, logs | ✓ |
| muscleGroup | ✓ | ✓ | session header, briefing chips, player | ✓ |
| equipment | ✓ | ✓ | briefing chips, player chips | ✓ (player chips added last mission) |
| difficulty | ✓ | ✓ | briefing, player chips | ✓ (ditto) |
| instructions | ✓ | ✓ | player "HOW TO" — reachable in-session | ✓ |
| videoUrl | ✓ | ✓ | player (honest 3-state: none/failed/playing) | ✓ |
| **thumbnailUrl** | ✓ | ✓ | **was rendered NOWHERE → now**: briefing list rows + player loading poster | **fixed this mission** |
| **videoDurationSeconds** | ✓ | ✓ | **was rendered NOWHERE → now**: player duration chip (only when a video exists) | **fixed this mission** |
| status (active/archived) | ✓ | gate | archived still hydrates for assigned members; retired from new plans | ✓ correct policy |
| isDeleted | ✓ | gate | deleted stops hydrating/serving | ✓ |

### Workout builder (`WorkoutItem` / `WorkoutPlanModel`)
| Field | A | S | R | Verdict |
|---|---|---|---|---|
| exerciseId | ✓ | ✓ | identity end-to-end (memory, analytics, "How to" lookup) | ✓ |
| exerciseName (freehand allowed) | ✓ | ✓ | everywhere | ✓ |
| setRows: reps/weight/rest per set | ✓ | ✓ | prescription table, prefill, rest timer seed | ✓ |
| legacy sets/reps/weight | ✓ | ✓ | synthesized fallback (tested byte-compatible) | ✓ |
| plan name | ✓ | ✓ | everywhere | ✓ |
| **plan description** | ✓ | **was NEVER served** → now served (live-plan paths) | **briefing "About this plan"** | **fixed this mission — the one authored field that disappeared entirely** |
| visibility / sharedTrainerIds / createdBy | ✓ | — | — | correctly coach-only: org scoping, not content |

### Assignment / prescription layer
weeklyPlanId · rhythm (4 shapes) · effective dates · exceptions · excused
days · coaching pause — all authored, all served via `getMyTraining`'s
expectation + prescriptionData, all rendered (Home hero, briefing week
progress, performance timeline). Verified in the weekly-prescription
certification and re-traced.

### Fields the mission lists that DO NOT EXIST anywhere
tempo · RPE · warm-up flag · superset/dropset/circuit grouping · multiple
images · secondary muscles · target time/distance · per-exercise coach notes.
**No schema, no authoring UI, no serving, in any repo.** They cannot
"disappear" — they cannot be written. They are the builder-vocabulary roadmap
(workout-experience architecture §14.6), and building them was explicitly out
of a certification mission's scope. **After this mission, zero authored
fields are dropped and zero served fields are ignored — the matrix is
closed.**

## 2. What this final pass found and fixed

Even after four prior certifications, the mission's re-trace found four
parity leaks — all now closed:

1. **Plan `description`** — authored in the builder since V1, loaded into the
   edit form, saved to Firestore… and served to no one. The coach's own words
   about the plan, silently discarded. Now served (single-plan and weekly
   day-plan live paths) and rendered on the briefing as "About this plan",
   distinct from the prescription note (which is time-scoped, not
   plan-scoped). Snapshot (customized) assignments carry no description —
   the library doc owns it; stated, not fudged.
2. **`thumbnailUrl`** — now the briefing rows' leading image and the player's
   loading poster (the member sees the exercise, not a grey box, while the
   video initializes). A broken thumbnail collapses silently rather than
   rendering a broken-image glyph.
3. **`videoDurationSeconds`** — now a duration chip on the player, shown only
   when a video genuinely exists.
4. (Last mission, re-verified here:) equipment/difficulty player chips,
   in-session "How to" route, honest video failure states.

## 3. Architecture verification (Phase 5 — one truth per number)

| Number | Single source | Consumers |
|---|---|---|
| set/exercise/session progress | `SessionStats` (pure, tested) | session bar (resolved — position), Home chip (completed — work), summary |
| completion ("done") | `SessionStats.isComplete` | summary headline, Home "Completed ✓" |
| expectation ("asked today") | server-resolved in `getMyTraining` | Home hero, briefing, session gate |
| consistency verdicts | prescription domain (byte-identical both apps) | member timeline, coach adherence |
| adherence per set | `setHitTarget` (same rule both apps, tested) | summary, coach logs |
| day presence ("logged") | ≥1 completed set (skips never count, tested) | streaks, timeline |

The mission's Phase 5 demand — "every percentage from one truth" — holds with
one deliberate pair, defended in the end-to-end certification §5: the
in-session bar answers *position* (resolved/total), Home answers *work done*
(completed/total). Same engine, two honest questions.

## 4. Session flow (Phase 4) & exercise card (Phase 3)

Home (expectation-gated) → Briefing (facts, coach note, plan description,
week progress, full list — skippable, zero writes) → guided session (one
set/one decision; position always visible; prefilled targets; last-time
memory; How-to; skip-with-reason; edit-with-flag) → rest overlay (instant
since RC-1; wall-clock; pause/+30s/skip; haptics) → manual next-exercise
(deliberate: member-controlled, not auto-advanced) → Finish → Summary (real
stats, truthful headline, note to coach, queued-banner when offline) → Home
(chip reflects the same stats instantly). No blank screens found; the one
loading gap that existed (rest overlay behind a 4s ack) was root-caused and
fixed in the end-to-end certification.

## 5. Media & performance audit (Phases 2 + 6)

**Correctness (verified):** three honest video states; poster-while-loading;
tap-to-pause/replay via loop; unparseable URLs fail closed; controller
disposed (no leak); thumbnails memory-cached at 38 px in lists.
**Not built, stated plainly (Phase 6 asked for stress tests this environment
cannot run):** no video pre-caching/preloading (streams on open; offline
in-session video fails honestly), no quality selection, no explicit
fullscreen/landscape mode (portrait player only), no seek bar (loop +
pause/replay only), briefing list is non-lazy (a 100-exercise plan builds
100 light rows — acceptable, not ideal), and no on-device memory-pressure
run. These are the player's premium ceiling and they are enumerated in §12
rather than certified around.

## 6. TrainerHQ parity (Phases 7 + 8 journeys)

Member → coach: every set's prescribed-vs-actual, skipped sets, skip
reasons, edited flags, duration, member note, status — rendered in Member
Logs (verified at source, lines 516–646). Coach → member: the closed matrix
of §1. The 100-journey grid from the weekly-prescription audit was re-walked
over the finished surface; no journey needs a primitive that does not exist,
and the two that had no honest expression a week ago (weekday splits;
day-resolved content) now do.

## 7. Self-challenge (Phase 9 — every listed break attempted, traced)

| Attack | Survives because |
|---|---|
| Video deleted / broken storage URL | "Video couldn't load" state; session unaffected |
| Exercise renamed | identity is exerciseId-first (memory keeps history — tested) |
| Exercise archived | still hydrates for assigned members |
| Exercise deleted | item degrades to its own snapshot, honestly |
| Workout edited/replaced mid-session | session continues on its draft; lookups degrade id→name→index |
| Weekly day changed mid-day | content + expectation share one `todayKey`; re-prescription on edit |
| Plan paused / membership paused | serving stops next fetch; open session still logs (work done is logged) |
| Coach removed | identity degrades honestly (prior certs, re-checked) |
| Offline / kill / refresh / reboot | draft→remote→fresh chain; queued writes; ≤500 ms keystroke window |
| Second / third workout | deliberate dialog; first-free-run-slot probe (fixed prior mission) |
| Old draft | dayKey guard — can never leak into today |
| Corrupted cache/draft | corrupt JSON → null → next source; never an invented session |
| Multiple devices, same day | **known limit** — local draft outranks the other device's doc (§12) |

## 8. Premium review (Phase 10 — answered straight)

**Would a premium trainer proudly use this?** For workout *execution* — yes:
their words (description, prescription note, instructions), their targets
prefilled, their week structure, honest skips, edit transparency and per-set
visibility back. **Would a beginner understand every exercise?** Yes when the
coach attached video/instructions; the gap (no media authored) is the
coach's, surfaced honestly. **Would an advanced athlete feel slowed?** The
one-tap "as prescribed" flow and edit-after-complete keep pace; no supersets
/tempo vocabulary yet is the real ceiling for advanced programming (§12).
**Outperform Strong/Trainerize for execution?** On coached execution
(prescription-driven, coach-connected, honest adherence): competitive to
ahead. On media/player polish and program vocabulary: behind — enumerated,
not hidden.

## 9. Verification

backend 576 · AlphaSerena 515 · TrainerHQ 992 · analyze clean ×2 · APK
builds. Golden/performance suites do not exist in these repos (stated — not
"passed").

## 10. Files changed this mission

`functions/src/members.ts` (serve description) ·
`workout_briefing_screen.dart` (description card, thumbnails) ·
`workout_player_screen.dart` (poster, duration chip). Three files — the
correct size for a final pass: the system was already sound; what remained
was the last of the parity debt.

## 11. Stop conditions

✓ every authored field reaches AlphaSerena (or provably has no schema —
§1) · ✓ media production-ready **within §5's stated ceiling** · ✓ session,
rest, transitions verified prior mission · ✓ progress truthful, one engine ·
✓ parity both directions · ✓ offline/refresh/resume proven · ✓ no dead
fields, no duplicate completion logic, no fabricated state found in the final
sweep.

## 12. Honest limitations — the ship/no-ship list

**Ship-blocking, in my judgement, NONE — but three musts before release:**
(1) deploy the CF (`getMyTraining` changes — weekly serving + description are
inert until then); (2) one manual device pass over the timing-sensitive fixes
(rest-overlay instancy, video failure states); (3) deploy `firestore.rules`
if weekly-plan saves misbehave in production (deploy-state suspicion,
documented).

**Known ceilings, deliberate:** builder vocabulary (tempo/RPE/warm-up/
supersets/multi-images/secondary muscles) unbuilt — roadmap, not regression;
no video preloading/caching/fullscreen/seek; briefing list non-lazy at 100
exercises; multi-device same-day draft precedence; no sound at timer zero;
thumbnails absent for coaches who never uploaded them (nothing fabricated in
their place).

## 13. Verdict

Every word, number and video a trainer authors now reaches the member or
provably cannot be authored at all; every rep the member logs reaches the
coach with its honesty intact — skips, edits, reasons, duration. The maths
have one owner. The lifecycle survives every attack this mission lists
except the multi-device draft race, which is named rather than hidden.

**Would I personally ship this to thousands of trainers and members?** Yes —
after the three release musts above, and with §12's ceilings stated in the
release notes rather than discovered by users. The Workout Experience is
COMPLETE as scoped; what remains beyond it is vocabulary and polish, not
correctness.

---

*Nothing committed. Nothing deployed.*
