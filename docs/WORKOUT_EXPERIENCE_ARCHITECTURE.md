# Workout Experience — Architecture (Discovery)

- **Date:** 2026-07-28
- **Status: design only. No code, no schema change, no commit.**
- **Scope:** the complete workout lifecycle — TrainerHQ builder → assignment →
  serving → AlphaSerena session → logs → coach visibility — audited end to
  end, and the guided coaching experience redesigned on paper.
- Builds on: the Prescription Engine (all five phases, certified), whose
  expectation states already gate WHEN a session is offered. This document is
  about what happens INSIDE the session.

---

## 1. Current workflow — the verified reality

**Author (TrainerHQ).** A coach builds a plan as a single flat, reorderable
exercise list. Per exercise: a library link (or freehand name) and an ordered
set list of `reps / weight / rest` — all free-text so "8-12" and "bodyweight"
work. Nothing else exists in the schema: no tempo, no supersets, no warm-up
markers, no per-exercise notes, no sections/days. The library carries
`instructions, videoUrl, thumbnailUrl, videoDurationSeconds, equipment,
difficulty`.

**Assign → serve.** Certified in Phases 2–3: single-active-per-type, per-client
customized snapshots, `getMyTraining` hydrates each item with the library
metadata and per-set `setRows`; the expectation engine decides whether today
offers a session at all.

**Train (AlphaSerena `WorkoutSessionScreen`).** One exercise at a time: video
hero → name/muscle → per-set progress dots → a red "Coach Prescription" table
(`SET | REPS | KG | REST`) → "YOUR PERFORMANCE" tiles. Sets unlock strictly in
sequence; completing one opens two numeric fields (reps done / weight used),
`Complete Set` fires an automatic full-screen rest countdown (skippable, no
sound/haptics) and a full-array Firestore upsert. Last exercise shows `Finish
Workout` → save → `Get.back()` → a snackbar. A separate `WorkoutPlayerScreen`
(misnamed) is a read-only exercise detail card — the only place instructions
render.

**Coach sees (TrainerHQ).** Member Logs day cards (completion %, per-set
actual-vs-rest rows), a Progress section (adherence trend, strength chart for
the top weighted exercise, personal bests, volume), timeline entries, and the
engagement clock. No notification fires on completion — deliberate (one
`inactivity` signal philosophy).

## 2. Problems (verified, with locations)

1. **A session cannot be resumed.** State lives in `TextEditingController`s;
   kill the app mid-workout and every actual is gone. No draft, no local
   persistence, no back-press guard — swiping back silently discards work.
2. **Every screen-open mints a new session doc** (`newSessionId()` in
   `initState`). Opening three times = three docs. The coach's session count,
   day-activity count, volume and adherence all treat each as a real session —
   a member who peeked and closed produces a scorable "low-adherence workout."
3. **No way to skip or un-complete.** Sets lock forward-only; a completed set
   can never be corrected; a skipped exercise is indistinguishable from an
   unfinished one (`completed:false` either way). The coach cannot tell "chose
   to skip" from "gave up" from "never opened".
4. **The member writes data they can never read.** Set-level actuals are
   logged richly, but AlphaSerena's ONLY read of `client_workout_sessions` is
   a day-key set for streaks. No "last time", no PRs, no progression — while
   the member-facing Strength tab says "coming soon".
5. **No session duration.** `date` = screen-open time; no start/finish/elapsed
   anywhere.
6. **Completion is an anticlimax.** Save → pop → snackbar. No summary, no
   volume, no prescription-vs-actual recap, no celebration — the emotional
   peak of the product is a toast.
7. **Dead and orphaned pieces:** instructions are loaded by the session screen
   and never rendered; `SessionEntry.note` is parsed and rendered by the coach
   app but no writer exists; `MemberLogsSessionScreen` (a finished
   prescribed-vs-actual table) is fully built and never navigated to;
   `thumbnailUrl / videoDurationSeconds / equipment / difficulty` are served
   and consumed by nothing.

## 3. UX issues

- **No briefing.** The member lands on exercise 1's video with zero framing:
  no session overview, no coach note, no muscles, no estimated time, no "why".
- **No overview during the session** — `Exercise 3 of 7` is the only map; you
  cannot see what's ahead or jump (which is also why skipping is impossible).
- **Prescription vs. input are disconnected:** the member re-types "10" and
  "40" that the coach already wrote. No prefill, no one-tap "as prescribed".
- **Rest timer is a modal wall:** blocks review of the next set, no sound or
  haptic at zero (phone in pocket = missed), no +30s, no between-exercise rest.
- **The transition between exercises is a hard cut** — no "Next up: Leg
  Press" moment, which is where a human coach talks.
- **Instructions/equipment/difficulty absent in-session** — the guidance
  fields exist and are served; the session ignores them.

## 4. Behavioural issues

- **All friction, no reward:** the strict set-locking adds discipline-shaped
  friction while completion — the moment to reinforce — is silent. Backwards.
- **No visible progress against the coach's ask** at the finish ("you did
  what was asked" is the adherence story, told only to the coach).
- **No memory:** nothing says "last week you pressed 35 kg" — the single most
  motivating sentence in strength training, and the data is already stored.
- **Failure states punish honesty:** with no skip-with-reason, the honest
  member who ran out of time looks identical to one who quit.

## 5. Coaching issues

- **The coach's voice is absent from the session.** No plan-level note, no
  per-exercise note (schema has none), instructions unrendered. An Indian
  coach's core value — "I am with you in the gym" — never reaches the floor.
- **The coach learns nothing back** beyond numbers: no member note ("shoulder
  hurt on set 3"), no skip reasons, no session duration, no "felt easy/hard".
- **No completion signal.** A coach who wants to react ("well done", "why
  only 2 sets?") must go looking. (The one-inactivity-signal philosophy is
  right for automation; a *digestable* completion event for the coach's
  attention surface is a different, unmet need.)
- **Adherence semantics are generous:** lower-bound parsing means a set with
  no numeric target always counts as a hit; "quality" can read high on
  bodyweight-heavy plans.

## 6. Architecture issues

1. **Session identity** (random per-open id) — the root of the inflation bug;
   no `status` (in-progress vs finished), no `startedAt/finishedAt`.
2. **The set vocabulary is three strings.** Fine as a floor; but tempo,
   warm-up flags, superset grouping, RPE — the language real programs are
   written in — have no home, so the builder cannot say them and the session
   cannot render them.
3. **No member-side read model** for own sessions (needs an
   `authorId+date`-window query — the index-free pattern already proven).
4. **Prescription Engine linkage is one-way:** the expectation gates entry,
   but the session never stamps WHICH expectation/version it satisfied — a
   future analytics gap (the verdict layer re-derives it, correctly, today).

## 7. Missed opportunities (experiences, not widgets)

- **Preparing mentally** — a 15-second briefing: today's focus, the coach's
  words, what success looks like.
- **Knowing why** — "chest + triceps today; week 3 of your strength block".
- **Seeing yesterday's self** — last-time numbers beside today's targets.
- **Progressive overload made visible** — "2.5 kg more than your best".
- **Finishing strong** — a summary that names what was done, what it means,
  and (occasionally, honestly) a record.
- **Talking back** — one optional line to the coach at the finish.

## 8. The ideal workout journey (redesign on paper)

```
HOME (expectation says: session expected)
  └─ tap Start
【1 BRIEFING】— one screen, skippable, 10 seconds
     "Push Day · 7 exercises · ~40 min* · Chest, Shoulders, Triceps"
     Coach's note (plan-level, when it exists) · last session's one-liner
     ("Wed: 6 of 7 done, 3,240 kg volume")            [Begin]
【2 GUIDED SESSION】— one exercise at a time (kept: it IS the guidance)
     + overview drawer (all exercises, states, jump/skip from here)
     Exercise view: video hero · instructions (finally) · equipment chip
       · "Last time: 3×10 @ 35 kg" line (own history)
       · prescription table (kept — it is good)
       · active set: PREFILLED with prescription → [Did as prescribed ✓]
         one tap; edit only when reality differed
       · complete / EDIT a completed set / skip set
       · skip exercise (reason chips: No equipment · Pain · No time · Other)
【3 REST】— overlay, not a wall: next-set target visible, +30s, skip,
     haptic + sound at zero; between-exercise transition card
     ("Next: Leg Press — 4 sets") with the same rest handling
【4 FINISH】— summary screen (the reward):
     duration · sets done/asked · volume · adherence vs prescription
     · records touched ("heaviest bench yet") — only when true
     · optional one-line note to coach → writes the `note` the coach
       app ALREADY renders
     [Done] → Home hero flips to "Done for today ✓"
【resume】— an in-progress session persists locally; reopening the same
     day offers "Continue where you left off" (same doc, same id)
```

**Challenged and decided:**
- *One-at-a-time vs whole list?* One-at-a-time stays — it is the coaching.
  The overview drawer gives orientation without surrendering guidance.
- *Automatic rest timers?* Yes (already right), but as an overlay with sound/
  haptics — a modal wall that mutes is a timer only for people staring at it.
- *Warm-up separate?* Not until the schema can say "warm-up set" (roadmap);
  inventing one client-side would fabricate prescription.
- *Should skipped be different from missed?* Emphatically — it is the
  difference between honesty and shame, and the coach's next conversation.
- *Should completion notify the coach?* As an attention-surface event (their
  existing notification center), not an automation trigger — preserving the
  one-inactivity-signal philosophy for nudges.

## 9. Screen hierarchy

```
WorkoutBriefingScreen        (new, skippable, no data writes)
WorkoutSessionScreen         (rebuilt in place: guided view + overview drawer)
  ├─ RestOverlay             (replaces the modal dialog)
  ├─ ExerciseDetailSheet     (absorbs WorkoutPlayerScreen: video + HOW TO +
  │                           equipment/difficulty — one detail surface)
  └─ SkipReasonSheet         (new)
WorkoutSummaryScreen         (new — the reward + note to coach)
```
`WorkoutPlayerScreen` retires into the detail sheet (its two navigators
retarget). Member history additions live on the existing Progress screen
(replacing the "coming soon" strength tab) — not new top-level navigation.

## 10. Interaction flow (states)

- Set: `pending → active → done(actual) | skipped(reason)`; done is EDITABLE
  until the session finishes; skipped is explicit, never inferred.
- Session: `inProgress → finished | abandoned(auto after day-end)`; one
  session doc per day per plan by default (deterministic id
  `{clientId}_{yyyy-MM-dd}` mirrors the diet-log pattern already proven);
  "train twice" appends a suffixed doc deliberately, never accidentally.
- Offline: actuals persist locally on every change; saves retry on
  reconnect; the summary shows "will sync" exactly like the diet logger's
  proven pattern.
- Back-press mid-session: sheet — Continue / Save & leave / Discard.

## 11. Coach experience (TrainerHQ)

- **Wire the dead screen:** Member Logs day card → `MemberLogsSessionScreen`
  (already built) for the per-set story; add duration, skip reasons, and the
  member note (its reader already exists).
- Progress section gains "sessions vs prescribed" once it consumes the
  Prescription Engine's week verdicts (the v1 caveat in
  `workout_adherence_provider` resolves exactly there).
- Completion event in the coach's notification center (quiet kind, no push
  by default; org-configurable later).
- Builder roadmap (§14) adds the missing vocabulary — tempo, warm-up flag,
  superset group, per-exercise coach note — each one both authored and
  rendered, never one without the other.

## 12. Member experience — persona check

Beginner: briefing + instructions + prefilled targets = never lost. Advanced /
bodybuilder: edit-after-complete, "last time", records, volume — the log
becomes worth keeping. Fat-loss / women's transformation: adherence framed as
done-vs-asked, never weight-obsessed; skip-with-reason removes shame. Senior /
corporate / student: "as prescribed ✓" one-tap logging is the whole flow;
rest overlay with sound survives a pocketed phone. Online client: the note to
coach and skip reasons ARE the relationship.

## 13. Future AI opportunities (each needs only this data, honestly kept)

- Progression suggestions: actuals vs prescribed across weeks → "ready for
  37.5 kg" drafts for the COACH to approve (never auto-applied).
- Plateau/fatigue detection: falling actuals at stable prescription.
- Skip-reason patterns: "No equipment × 4 on cable rows → suggest substitute".
- Adaptive rest: actual inter-set gaps vs prescribed.
- Form review: member-recorded set videos attached to the session note.
All downstream of §10's truthful states; none require redesign later —
the same argument, and the same precondition, as the Prescription Engine's
immutable history.

## 14. Implementation roadmap (each phase independently shippable)

1. **Session integrity** — deterministic session id + resume + local draft +
   back-guard + `startedAt/finishedAt/status` + edit/skip states + skip
   reasons. (Fixes the inflation bug and the data-loss trap; schema additive.)
2. **In-session guidance** — instructions/equipment rendered, prescription
   prefill + "as prescribed" one-tap, overview drawer, rest overlay with
   haptics/sound and between-exercise transitions, detail sheet absorbing
   WorkoutPlayerScreen.
3. **The reward** — briefing screen + summary screen + member note (writes
   the field the coach already reads) + Home hero completion echo.
4. **Memory** — member-side session read model ("last time", records, the
   real Strength tab), PR detection at summary time.
5. **Coach parity** — wire MemberLogsSessionScreen, duration/skips/notes in
   Member Logs, completion event in the notification center, adherence v2 on
   week verdicts.
6. **Vocabulary** — builder + schema + session rendering for tempo, warm-up
   sets, supersets, per-exercise coach notes (authored and rendered together).
7. **AI** — §13, coach-in-the-loop only.

---

*Discovery only. No code written, no schema touched, nothing committed.*
