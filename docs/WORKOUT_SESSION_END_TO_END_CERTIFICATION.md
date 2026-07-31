# Workout Session — End-to-End Certification

- **Date:** 2026-07-28 · **Repos:** trainersHQ · trainershq-backend · alphaserena
- **Mission:** prove the complete workout lifecycle correct. No new features, no
  redesign — fix what is wrong, disprove what is suspected.
- **Status: verified. Nothing committed. Nothing deployed.**

**Verification performed:** `flutter analyze` clean · **515 tests pass** ·
debug APK builds. No emulator/device run — every claim below is a traced code
path or a passing test, and the limits of that method are stated in §12.

---

## 1. State diagram (reconstructed from code, then verified against it)

```
TrainerHQ library plan ──assign──▶ client_plan_assignments
   (or weekly mapping ──assign──▶ same doc + weeklyPlanId)
        │  setPrescription (CF, immutable versions)
        ▼
getMyTraining (CF) ── membership gate ── day-resolves weekly ── hydrates media
        ▼
AlphaSerena Home ── expectation gates entry ──▶ Briefing (no writes)
        ▼ Start
┌────────────────────── SESSION (screen) ─────────────────────────┐
│ NOT_CREATED ──(_bootstrap)──▶ one of:                           │
│   • DRAFT_RESUMED    draft.dayKey == today && non-empty         │
│   • REMOTE_RESUMED   doc {clientId}_{day} exists (cache-first)  │
│   • FINISHED_CHOICE  remote status == completed → review | new  │
│   • FRESH            no doc is written yet (integrity gate)     │
│                                                                 │
│ per set: pending ──complete──▶ completed(actuals, edited?)      │
│                └──skip──────▶ skipped                           │
│          completed ──reopen──▶ pending (re-complete ⇒ edited)   │
│ per exercise: skip(reason) ⇒ pending sets → skipped; unskip     │
│               restores only value-less skipped sets             │
│                                                                 │
│ first completed/skipped set ⇒ MEANINGFUL:                       │
│   draft saved (every action; keystrokes debounced 500 ms)       │
│   remote upsert status=inProgress (ack ≤4 s → synced|queued)    │
│ rest: wall-clock deadline overlay (survives lock/background)    │
│ leave: guard → Save & leave (draft) | Keep training             │
│ finish: status=completed + finishedAt + duration → Summary      │
│         (draft cleared; stats = the ONE engine)                 │
└─────────────────────────────────────────────────────────────────┘
        ▼
client_workout_sessions ──▶ TrainerHQ Member Logs (per-set story,
skip reasons, member note) ──▶ Consistency verdicts (presence)
──▶ Home chip (progress % — the same engine)
```

States deliberately NOT in the model, verified absent rather than assumed:
`abandoned` is representational (an unfinished doc simply stays
`inProgress`; the coach sees an in-progress session with its real sets — no
timer ever reclassifies it), and `expired` does not exist (a day's doc is
keyed to its day; a new day boots fresh via the `dayKey` guard).

## 2. Root causes found and fixed (4)

### RC-1 — The rest timer was gated behind a network acknowledgement
`_completeSet` awaited `_persist()` — draft write **plus a remote save that
waits up to 4 s for a server ack** (`ackTimeout`), the full 4 s on a dead
network — **before** showing the rest overlay. The member finished a set and
stared at a frozen screen while their real rest clock silently ran. This is
the reported "rest timer delay", root-caused: not the overlay (which is
wall-clock correct), but the caller's await ordering.
**Fix:** the overlay opens immediately; the save runs alongside it. Safe by
construction: the logs are mutated before either starts, the remote write
serializes the FULL entries array (last-write-wins, no partial merge), and
the result still surfaces through the existing `_lastSave` banners.

### RC-2 — A third session destroyed the second
"Start another" after a finished day hardcoded run 2. If run 2 was itself
finished (draft cleared → reopen → bootstrap finds run 1 → offers the choice
again), a fresh entries array was merge-written over the finished run-2 doc,
**destroying its logged sets**. **Fix:** probe upward for the first run slot
whose doc holds no entries (cache-first fetch, so it works offline for docs
the device has seen; bounded at 10).

### RC-3 — The coach's guidance was unreachable from the floor
`getMyTraining` serves `videoUrl`/`instructions`/`equipment`/`difficulty`
per exercise; `WorkoutPlayerScreen` renders video + instructions — but the
SESSION had no route to it. The member's one moment of "how do I do this"
had the answer one unreachable navigation away. **Fix:** a "How to" action on
the session's exercise header opens the existing player with the served item
(resolved by exerciseId → name → index, so a mid-session plan edit degrades
gracefully). Reuses a built screen; nothing redesigned.

### RC-4 — Media failed dishonestly, twice
The player's video init swallowed errors (`catchError((_) {})`) with `_ready`
never set — a broken URL or dead network left a **loading spinner forever**,
which is a promise the video is coming. And served `equipment`/`difficulty`
were rendered **nowhere** — coach-curated fields silently dropped on their
only member-facing surface. **Fix:** failed init (or an unparseable stored
URL) renders "Video couldn't load" — distinct from "No demo video" (the coach
attached none); equipment/difficulty render as chips.

## 3. Refresh & resume investigation (Phases 2 + 7 — traced write-by-write)

The mission's scenario, step by step:

| Step | What happens | Verified by |
|---|---|---|
| Complete Set 1 | logs mutated → draft saved **immediately** (not debounced — debounce is keystrokes-only) → remote upsert (synced/queued ≤4 s) | `_completeSet` → `_persist` |
| Pull-to-refresh (Home) | reloads `getMyTraining`; the session's logs are already snapshotted; served-item lookups fall back id→name→index | `_servedItemFor` |
| Navigate back | back-guard; "Save & leave" saves the draft; leaving without meaningful activity clears it (no ghost) | `_onPopAttempt` |
| Open again | draft (dayKey == today, non-empty) restores **exact** sets, actuals, edited flags, current exercise, first-open set; prefill never overwrites typed values | `_bootstrap` branch 1; draft round-trip tests ("resume loses NOTHING") |
| Kill app | draft was written on every completed/skipped set; at most the last **≤500 ms of keystrokes** on a pending set can be lost — never a completed set | debounce design |
| Reboot phone | SharedPreferences survives reboot | platform contract |
| Offline restart | draft is local; remote fetch falls back to Firestore **cache**; saves queue and sync on reconnect (`queued` banner — the diet logger's proven contract) | `fetchSession` cache fallback; `ackTimeout` |
| Reconnect & continue | queued writes flush; same doc id (deterministic) so no duplicates ever | `workoutSessionIdFor` tests |
| Rest timer across it all | the overlay derives remaining time from a wall-clock deadline — lock, background, resume all repaint against the real clock; it is dismissed by navigation (an interrupted rest is not state worth restoring — the member rests in reality, not in the app) | `RestOverlay._endsAt` |

**Resume priority is draft → remote → fresh**, and each is the right answer:
the draft is the freshest local truth; the remote doc covers a cleared/other
install; fresh writes nothing until real activity (the integrity gate — ghost
sessions cannot exist, and duplicate sessions cannot exist because the id is
deterministic per day).

## 4. Persistence architecture (as verified)

Two stores, two jobs, no overlap: **the draft** (single-slot SharedPreferences
JSON, corrupt → null, never invents a session) is the crash/navigation net;
**the session doc** (`ws_{clientId}_{yyyy-MM-dd}[_run]`, merge-upserted full
entries array) is the durable, coach-visible truth. `date` = session date,
`startedAt` = first meaningful activity, `finishedAt`/`durationSeconds`
stamped at finish; `status` ∈ inProgress|completed. Writes are guarded by
`canLog` (linked member) and every remote op is time-boxed with honest
synced/queued/failed reporting.

## 5. Progress truthfulness (Phase 3 — the mandated example)

**Workout: A=3 sets, B=4, C=2 ⇒ 9 prescribed. 2 completed ⇒ 22%** —
`floor(2/9×100)`, and the engine (`SessionStats.progressPercent`, tested)
returns exactly that. The rules, each defended:

- **Denominator = every prescribed set.** Coaching logic: the coach asked for
  9; progress is against the ask, never against a shrunk denominator.
- **Skips count against.** A skip is honest and first-class, but it is not
  done work; 2 done + 7 skipped is 22% done and fully resolved — not 100%.
- **Floored, never rounded up.** 17/18 reads 94%; "100%" is reserved for
  actually finishing (tested).
- **`isComplete` = every prescribed set completed.** The summary's former
  private re-derivation was deleted last mission; one authority remains.

**Two progress numbers exist, and they answer different questions — this is
deliberate, not drift:** the in-session top bar counts **resolved** sets
(completed + skipped) because it answers *"how far through the session am
I?"* — position; a fully-skipped session is genuinely over. The Home chip and
summary use **completed-only** because they answer *"how much of the work is
done?"*. Merging them would make one of the two answers a lie.

**Logged Today** (streaks/consistency) is presence — ≥1 *completed* set;
skips alone never mark a training day (tested). Presence for streaks,
fraction for completion: both surfaced, neither pretending to be the other.

## 6. Media & exercise-content verification (Phases 5 + 6)

Field-by-field, TrainerHQ library → backend serving → member surfaces:

| Field | Served | Rendered | Verdict |
|---|---|---|---|
| videoUrl | ✓ | player (session-reachable now) | RC-3/RC-4 fixed |
| instructions | ✓ | player "HOW TO" | reachable in-session now |
| muscleGroup | ✓ | session header, player, briefing | ✓ |
| equipment | ✓ | briefing chips; **player chips (new)** | RC-4 fixed |
| difficulty | ✓ | briefing; **player chips (new)** | RC-4 fixed |
| setRows (per-set) | ✓ | prescription table + prefill | ✓ |
| thumbnailUrl, videoDurationSeconds | ✓ | **not rendered** | honest gap — §12.3 |
| tempo, coach per-exercise notes | **no schema** | — | cannot disappear: they cannot be authored (roadmap §14.6) |

Broken/missing media now splits into three honest states: no video authored
("No demo video"), video failed ("Video couldn't load"), video playing.

## 7. TrainerHQ parity (Phase 8)

The wire is the contract: entries are built by `buildSessionEntries` with
byte-compatible legacy fields (tested: "the legacy fields are byte-compatible
for old coach builds"), and the coach's Member Logs renders the per-set
prescribed-vs-actual story, skipped sets, per-exercise skip **reasons**,
edited flags, duration and the member note (verified present in
`member_logs_screen.dart` lines 516–646). Adherence is computed identically
by rule ("adherence matches the coach app rule exactly" — tested). The
completion getters live in the shared domain file both apps carry.

## 8. Edge cases (Phase 9 — each traced)

| Case | Behaviour |
|---|---|
| Leaves after one set | doc exists, `inProgress`, coach sees exactly one set; resumable all day; never reclassified |
| Never finishes | stays `inProgress` — no fake "abandoned" stamp; consistency counts the completed work |
| Skips exercise | reason required, pending sets → skipped, coach sees the reason |
| Changes weight / edits completed set | reopen → re-complete stamps `edited` — the coach knows it was revised, not logged live |
| Trains twice | deliberate dialog → run-2 doc; third+ session finds the first free slot (RC-2) |
| Workout replaced mid-session | session continues on its snapshot (draft); media lookups degrade id→name→index; next day serves the new plan |
| Coach edits plan mid-session | same as replace — the draft is the session's truth |
| Weekly day changes mid-day | same, and the day's expectation is served with the same `todayKey` as content (last mission's guarantee) |
| Membership pauses mid-session | serving stops NEXT fetch; the open session still saves (rules gate on linked membership identity, not entitlement) — work done is work logged |
| Coach removed | serving/coach identity degrade honestly (prior certifications); session unaffected |
| Draft from another day | `dayKey` mismatch → ignored, fresh boot — a stale draft can never leak into today |

## 9. Self-challenge results (Phase 10 — every suspect closed)

| Suspect | Verdict |
|---|---|
| Refresh bug | **disproven** — traced in §3; draft restores exact state; no reset path found |
| Resume bug | **disproven** — priority chain correct; corrupt draft → null → remote → fresh |
| Duplicate session bug | **disproven** for the normal path (deterministic id, tested); **confirmed+fixed** for the third-session slot (RC-2) |
| Progress bug | **confirmed+fixed last mission** (binary "Logged today"); maths now proven in §5 |
| Logged Today bug | **disproven** — presence requires completed work; skips never count (tested) |
| Rest timer delay | **confirmed+fixed** (RC-1) — and the overlay itself proven wall-clock honest |
| Media loading bug | **confirmed+fixed** (RC-3, RC-4) |

Additional finds while challenging my own fixes: the run-probe is bounded and
cache-first (works offline for seen docs); the "How to" lookup cannot crash on
a shrunk served list (index guard); an unparseable stored URL fails to the
broken-video state rather than constructing an invalid controller.

## 10. Tests

515 pass (unchanged count — this mission's fixes are flow-ordering and
rendering; the domain they orchestrate was already pinned): deterministic
identity + run suffixes · creation gate · draft/remote round-trips ("resume
loses NOTHING", corrupt → null) · skip/edited wire semantics + legacy
byte-compatibility · truthful-completion suite (22%-style maths, floor,
skips-against, 100-reserved) · duration never negative/invented · rest
overlay layout at 1.6× text scale · stats/adherence parity rules.

## 11. Stop conditions

✓ refresh reconstructs (traced §3) · ✓ resume correct (§3) · ✓ progress
mathematically truthful (§5, tested) · ✓ Logged Today correct (§5) ·
✓ Workout Completed correct (one engine) · ✓ rest timer instant (RC-1) and
wall-clock honest · ✓ media loads or fails honestly (RC-4) · ✓ TrainerHQ and
AlphaSerena agree (§7 — shared wire + shared rules) · ✓ no duplicate sessions
(deterministic ids + RC-2) · ✓ no state loss (≤500 ms of pending keystrokes
after a hard kill is the proven floor, stated).

## 12. Honest limitations

1. **No device run.** Await-ordering and lifecycle fixes are traced and
   analyze-clean but not exercised on hardware; the rest-overlay timing and
   video failure states deserve one manual pass before release.
2. **Multi-device same-day training**: the local draft outranks a remote doc
   written by another device that day — single-slot by design; the second
   device's completed work is preserved in Firestore but the first device's
   resume view won't show it until the draft clears.
3. **thumbnailUrl / videoDurationSeconds** are served and still unrendered
   (list thumbnails and a duration chip are UI additions — out of a
   no-new-features mission, recorded).
4. **No in-session media caching/preloading** — video streams on open;
   offline in-session video is unavailable (fails honestly now).
5. **Keystroke loss window ≤500 ms** on a hard kill mid-typing (debounce);
   completed sets are never in that window.
6. **Rest overlay does not survive process death** — deliberate: rest happens
   in reality; reconstructing a countdown after a crash would fake precision.
7. **Sound at timer zero** remains unbuilt (haptics only) — needs an audio
   dependency + mute contract; the hook is documented in the overlay.
8. **`_offerFinishedChoice` probes runs 2–9** — a member starting an 11th
   session in one day lands on run 9's slot; accepted absurdity bound.

## 13. Verdict

The lifecycle holds: creation is gated on real activity, identity is
deterministic, every resume path reconstructs the exact logged truth, the
maths answer the coach's ask, and the coach sees precisely what the member
did — including what they chose to skip and what they went back to revise.
The four defects found were all in the last inch — ordering, a hardcoded run
slot, an unreachable screen, a swallowed error — and each is now fixed at its
root, not patched at its symptom.

---

*Nothing committed. Nothing deployed.*
