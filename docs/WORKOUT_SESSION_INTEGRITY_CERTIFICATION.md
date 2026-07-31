# Workout Session Integrity — Certification (Workout Experience, Phase 1)

- **Date:** 2026-07-28
- **Delivered:** Phase 1 of `WORKOUT_EXPERIENCE_ARCHITECTURE.md` — sessions
  are now truthful, resumable and impossible to corrupt. No UI redesign, no
  PRs, no celebrations, no guided-flow changes beyond the integrity
  affordances themselves (skip, undo, resume, back-guard).
- **Backend and rules untouched** — the new document fields ride the existing
  member-owned write rules; all changes are AlphaSerena + TrainerHQ reading.
- **Nothing committed. Nothing deployed.**

---

## 1. Root causes found (all verified before fixing)

1. **`newSessionId()` in `initState`** — a random doc id minted on every
   screen open. Every open = a new session doc; a member who peeked and left
   produced a scorable "workout" in every coach metric. THE root cause of
   ghost and duplicate sessions.
2. **All state in `TextEditingController`s** — process death, a phone call,
   a restart or a back-swipe destroyed every actual. No draft, no guard.
3. **`completed` was a one-way bool** — no undo, no skip; a skipped exercise
   was indistinguishable from an abandoned one.
4. **No lifecycle on the wire** — no status, no start/finish, no duration;
   the coach could not tell finished from wandered-off.
5. **`await set()` with no timeout** — offline, the write's future never
   resolves; the member's save simply hung (the same defect class the diet
   logger had already solved with ack-timeout semantics).

## 2. Architecture decisions

**When does a session begin?** Challenged as ordered: screen-open (rejected —
browsing), pressing Start (rejected — intent), typing (rejected — still
intent; it persists in the local draft). **A session exists from its first
completed or skipped set** — the first FACT. The pure gate
(`hasMeaningfulActivity`) is the only creator; `hasCompletedWork` is stricter
still and is what marks the streak day (a skip-only session informs the
coach, never the streak).

**Identity.** `ws_{clientId}_{yyyy-MM-dd}` — deterministic, mirroring the
diet log's proven day-doc pattern. Same day → same document, always. A second
same-day session is `.._2`, minted only through an explicit "Start another"
choice in the finished-session dialog — deliberate, never accidental.

**Draft vs. document.** The local draft (SharedPreferences, one slot,
debounced 500 ms, corrupt-JSON-safe) is the *workbench*: it holds everything
including typed-but-uncompleted values and survives process death. The remote
doc is the *published truth*: it exists only once something happened and is
upserted on every state change with `synced / queued / failed` ack semantics
(the timeout does not cancel the write — Firestore's offline queue holds it,
and the member is told "saved on this device" — the truth).

**Recovery order on open:** today's draft (exact resume, including the active
exercise) → today's remote doc (crash-without-draft / reinstall; server then
cache, so it works offline) → fresh. A finished today-doc offers **Review &
edit** (same-day corrections are honest) or **Start another**.

**States.** Set: `pending → completed | skipped`, both reversible until
finish (undo = tap a completed/skipped tile). Exercise: skippable with a
reason (`No equipment · Pain / discomfort · Out of time · Too fatigued ·
Other`), undoable. Session: `inProgress → completed`; **abandoned is
DERIVED** (inProgress + past day) — never stored, never guessable wrong;
**cancelled never produced a document**; coach-excused stays in the
expectation layer where it belongs.

**Back protection.** No meaningful activity → leave freely, draft cleared, no
nag. Meaningful activity → one calm dialog: *Keep training / Save & leave*
(there is deliberately no "discard" once facts exist — history is not
destroyed by a thumb-slip; same-day editing is the correction path).

## 3. Integrity guarantees

- **Ghost sessions are impossible** — no code path writes a session doc
  before a completed/skipped set exists (pure-gated, unit-tested).
- **Duplicate sessions are impossible** — identity is a pure function of
  (member, day); the only second-session path is an explicit dialog choice.
- **Work cannot be lost** — every keystroke reaches the draft within 500 ms;
  every state change also reaches the remote doc or its offline queue; kill,
  restart, call, back-swipe all resume exactly.
- **History cannot be silently corrupted** — corrupt drafts parse to null
  (never into a session); resumes rebuild prescriptions from the wire; edits
  are same-day-only by construction (a new day gets a new identity).
- **Analytics become truthful** — one doc per real training day; `status`
  separates finished from abandoned; `durationSeconds` exists only when both
  ends were lived (clamped ≥ 0 against clock skew); skipped sets are on the
  wire, distinct from incomplete; the streak marks only completed WORK.

## 4. Files changed

**alphaserena**
| File | Change |
|---|---|
| `lib/core/domain/workout_session.dart` | **new, pure** — id, states, draft codec, wire entries (additive), remote-resume parser, duration, the creation gates |
| `lib/core/services/workout_draft_store.dart` | **new** — one-slot SharedPreferences draft |
| `lib/core/services/workout_log_service.dart` | `WorkoutSaveResult` ack semantics, lifecycle fields, `fetchSession` (server→cache) |
| `lib/screens/dashboard/workout_session_screen.dart` | reworked internals: bootstrap (draft→doc→fresh), lazy creation, skip set/exercise + reasons, undo via tap, PopScope guard, autosave, finish stamps, offline banners; visual system unchanged |
| `test/workout_session_test.dart` | **new — 16 tests** |

**trainersHQ**
| File | Change |
|---|---|
| `lib/core/models/client_workout_session_model.dart` | parses `status/startedAt/finishedAt/durationSeconds`, per-set/exercise `skipped(+reason)`; derived `stateOn(today)` (completed / inProgress / **abandoned** / legacy) + `durationLabel`, `skippedSets` |
| `lib/features/member_logs/screens/member_logs_screen.dart` | day card: duration beside the time, lifecycle pill ("In progress" / "Not finished"), skipped-sets stat, per-set "Skipped" rows, "Skipped by member — {reason}" line |
| `test/workout_session_state_test.dart` | **new — 6 tests** |

## 5. Edge cases (decided, most pinned by test)

Open-and-leave → nothing anywhere · type-and-leave → draft only, cleared on
exit, no doc · one set then battery death → doc exists inProgress, draft
resumes exactly · same-day reinstall → remote-doc resume (cache-tolerant) ·
finished then reopened → Review & edit / deliberate `_2` · undo after
completing wrong set → tap, reopen, values intact · skip-only session → doc
exists for the coach, streak unmarked · abandoned yesterday → coach reads
"Not finished", never a completion · clock skew → duration clamps to 0 ·
legacy docs → `SessionState.legacy`, no claims invented · midnight
mid-session → the session keeps its start-day identity and date (a decided
simplification: a workout belongs to the day it began).

## 6. Offline behaviour

Draft writes are local and unconditional. Remote saves ack within 4 s or
report **queued** — Firestore's persistence holds the write across restarts
and syncs on reconnect; the banner says exactly that, in the diet logger's
proven words. Failed (non-timeout) saves keep the draft, show retry, and
never eat a finish: a finish that lands nowhere keeps the member on-screen
with everything intact. Resume-from-doc falls back to the Firestore cache, so
even draft-less recovery works offline.

## 7. Analytics guarantees (coach side)

Session count = real days trained (+ deliberate seconds) · completion % is
computed over the same doc, now stable across reopens · volume/adherence/
timeline/engagement all consume the same deduplicated docs unchanged ·
`inProgress` sessions are visible as such today and as "Not finished"
tomorrow — the empty-state promise of Member Logs ("exactly as they logged
it") is finally the truth.

## 8. Verification

| Check | Result |
|---|---|
| AlphaSerena `flutter analyze` / `flutter test` | **clean · 453/453 (16 new)** |
| TrainerHQ `flutter analyze` / `flutter test` | **clean · 992/992 (6 new)** |
| Backend / rules | untouched — 560/560 + 202/202 stand from this session |
| Debug APK | **built** |
| Process-death / restart / resume | draft round-trip pinned by test (full fidelity incl. typed-uncompleted values); live device run still owed |
| Duplicate prevention | identity determinism pinned by test |
| Offline | ack-timeout semantics + cache-fallback resume implemented per the proven diet pattern; emulator/device offline run still owed |
| Timezone | day identity from the local day key (the same convention every certified phase uses) |

**Said plainly — not machine-verified:** no human has killed the app
mid-workout on a real device and watched it resume; the screen's stateful
orchestration (bootstrap ordering, dialog flows) has no widget tests — its
rules are all pinned at the pure layer instead; multi-device same-day
concurrent sessions merge last-write-wins on the shared doc id (acceptable:
one member, one workout; documented, not defended further).

## 9. Remaining opportunities (later phases, per the architecture)

Briefing + summary screens (the reward) · member note to coach · "last time"
/ PRs (memory) · rest-overlay with haptics · overview drawer · wiring
TrainerHQ's dead `MemberLogsSessionScreen` · completion event in the coach's
notification center · builder vocabulary (tempo/supersets/warm-ups) ·
adherence v2 on week verdicts.

---

*Verified 2026-07-28: analyze clean both apps · 453/453 · 992/992 · APK
built. Nothing committed, nothing deployed.*
